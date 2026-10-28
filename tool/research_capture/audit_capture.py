"""Audit native Research captures without granting alignment or clearance authority.

Standard-library only. Does not convert ARCore time to elapsedRealtime, run models,
interpolate depth, infer a floor, or import the strict spatial-recording-v2 schema.
"""
from __future__ import annotations

import argparse
from array import array
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import sys

MAX_BYTES = 64 * 1024 * 1024
RECORDING_ID = re.compile(r"capture-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}")
BLOCKED = (
    "clockBindingValidated", "physicalAlignmentValidated", "metricErrorBoundsValidated",
    "floorReferenceValidated", "bodyVolumeCoverageEstablished", "promotionAllowed",
    "ordinaryCameraWired", "captureToDecisionAvailable",
)
ENCODINGS = {
    "rgb": "YUV_420_888_three_planes",
    "rawDepth": "uint16_little_endian_camera_plane_millimetres_zero_unknown",
    "confidence": "uint8_confidence_zero_unknown",
}


class CaptureError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CaptureError(message)


def integer(value, name, low=0, high=2**63 - 1):
    require(type(value) is int and low <= value <= high, f"invalid {name}")
    return value


def vector(value, length, name):
    require(isinstance(value, list) and len(value) == length, f"invalid {name}")
    require(all(type(v) in (int, float) and math.isfinite(v) for v in value), f"nonfinite {name}")
    return value


def load_json(raw):
    def reject_constant(value):
        raise CaptureError(f"nonfinite JSON constant: {value}")
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(raw, parse_constant=reject_constant, object_pairs_hook=unique)


def relative_file(root: Path, name: str):
    require(isinstance(name, str) and "\\" not in name and ":" not in name, "invalid relative path")
    parts = PurePosixPath(name)
    require(not parts.is_absolute() and len(parts.parts) > 0 and
            all(p not in ("..", ".") for p in parts.parts), "path escapes recording")
    require(parts.as_posix() == name, "noncanonical relative path")
    path = root.joinpath(*parts.parts)
    require(path.resolve().is_relative_to(root.resolve()), "path escapes recording")
    require(all(not p.is_symlink() for p in [path, *path.parents] if p != root.parent), "symlink in recording")
    require(path.is_file(), f"missing file: {name}")
    return path


def hashed_file(root, descriptor, seen, limit):
    require(isinstance(descriptor, dict), "missing file descriptor")
    name = descriptor.get("path")
    require(name not in seen, "payload reused by multiple descriptors")
    path = relative_file(root, name)
    require(path.stat().st_size <= limit, "file too large")
    raw = path.read_bytes()
    require(descriptor.get("sha256") == hashlib.sha256(raw).hexdigest(), f"hash mismatch: {name}")
    seen.add(name)
    return raw


def intrinsics(value):
    require(isinstance(value, dict), "missing intrinsics")
    dims = value.get("imageDimensions")
    require(isinstance(dims, list) and len(dims) == 2, "invalid intrinsics dimensions")
    for d in dims:
        integer(d, "intrinsics dimension", 1, 4096)
    focal = vector(value.get("focalLength"), 2, "focal length")
    require(min(focal) > 0, "invalid focal length")
    vector(value.get("principalPoint"), 2, "principal point")
    return dims


def image(root, value, kind, seen):
    if value is None:
        return None
    require(isinstance(value, dict), f"invalid {kind}")
    integer(value.get("timestampNs"), f"{kind} timestamp", 1)
    width = integer(value.get("width"), "image width", 1, 4096)
    height = integer(value.get("height"), "image height", 1, 4096)
    integer(value.get("androidImageFormat"), "image format", 1, 2**31 - 1)
    require(value.get("encoding") == ENCODINGS[kind], "unexpected encoding")
    expected_space = "arcore_cpu_image_native" if kind == "rgb" else "arcore_raw_depth_native_gpu_aspect"
    require(value.get("coordinateSpace") == expected_space, "unexpected coordinate space")
    crop = value.get("cropRect")
    require(isinstance(crop, list) and len(crop) == 4, "missing crop")
    for c in crop:
        integer(c, "crop coordinate", 0, 4096)
    require(0 <= crop[0] < crop[2] <= width and 0 <= crop[1] < crop[3] <= height, "invalid crop")
    planes = value.get("planes")
    require(isinstance(planes, list) and len(planes) == (3 if kind == "rgb" else 1), "wrong plane count")
    payloads = []
    for index, plane in enumerate(planes):
        w, h = ((width + 1) // 2, (height + 1) // 2) if kind == "rgb" and index else (width, height)
        bpp = 2 if kind == "rawDepth" else 1
        require(plane.get("width") == w and plane.get("height") == h and
                plane.get("bytesPerPixel") == bpp, "wrong packed plane dimensions")
        pixel = integer(plane.get("sourcePixelStride"), "pixel stride", bpp, 65536)
        integer(plane.get("sourceRowStride"), "row stride", (w - 1) * pixel + bpp, 2**31 - 1)
        require(plane.get("packing") == "row_major_samples_without_padding", "unexpected packing")
        require(isinstance(plane.get("path"), str) and plane["path"].startswith("payloads/"), "wrong payload path")
        data = hashed_file(root, plane, seen, MAX_BYTES)
        require(plane.get("byteLength") == len(data) == w * h * bpp, "wrong payload length")
        payloads.append(data)
    return payloads


def pair_reasons(row, dims):
    frame = row["frameTimestampNs"]
    rgb, depth, confidence = (row[k] for k in ("rgb", "rawDepth", "confidence"))
    reasons = []
    if rgb is None:
        reasons.append("rgb_unavailable")
    elif rgb["timestampNs"] != frame:
        reasons.append("rgb_frame_timestamp_mismatch")
    if depth is None:
        reasons.append("raw_depth_unavailable")
    elif depth["timestampNs"] != frame:
        reasons.append("depth_not_new_for_frame")
    if confidence is None:
        reasons.append("confidence_unavailable")
    elif depth is None or confidence["timestampNs"] != depth["timestampNs"]:
        reasons.append("confidence_timestamp_mismatch")
    if row["trackingState"] != "TRACKING":
        reasons.append("pose_not_tracking")
    if rgb is None or [rgb["width"], rgb["height"]] != dims:
        reasons.append("rgb_intrinsics_dimensions_mismatch")
    if depth is None or confidence is None or any(depth[k] != confidence[k] for k in ("width", "height")):
        reasons.append("depth_confidence_dimensions_mismatch")
    return reasons


def pixel_availability(depth_bytes, confidence_bytes, width, height):
    depth = array("H")
    depth.frombytes(depth_bytes)
    if sys.byteorder != "little":
        depth.byteswap()
    total = width * height
    observed = [d > 0 and c > 0 for d, c in zip(depth, confidence_bytes)]
    # These descriptive counts establish neither accuracy nor free body volume.
    grid = [[0 for _ in range(4)] for _ in range(4)]
    grid_total = [[0 for _ in range(4)] for _ in range(4)]
    for i, valid in enumerate(observed):
        x, y = (i % width) * 4 // width, (i // width) * 4 // height
        grid_total[y][x] += 1
        grid[y][x] += int(valid)
    return {
        "pixelCount": total,
        "zeroDepthPixels": sum(d == 0 for d in depth),
        "zeroConfidencePixels": confidence_bytes.count(0),
        "nonzeroDepthAndConfidencePixels": sum(observed),
        "unknownPixels": total - sum(observed),
        "nonzeroFraction": sum(observed) / total,
        "confidenceHistogramNonzeroDepth": {
            f"{lo}-{hi}": sum(d > 0 and lo <= c <= hi for d, c in zip(depth, confidence_bytes))
            for lo, hi in ((0, 0), (1, 63), (64, 127), (128, 191), (192, 255))
        },
        "nativeDepthGrid4x4": {"nonzeroCounts": grid, "pixelCounts": grid_total},
        "bodyVolumeCoverageEstablished": False,
    }


def audit(root: Path, *, expected_recording_id: str | None = None):
    if expected_recording_id is not None:
        require(isinstance(expected_recording_id, str) and RECORDING_ID.fullmatch(expected_recording_id),
                "invalid expected recording ID")
    root = root.resolve()
    require((root / "manifest.json").is_file(), "final manifest missing; recording is partial")
    require((root / "manifest.json").stat().st_size <= 65536, "manifest too large")
    manifest = load_json(relative_file(root, "manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("format") == "bagdar-native-capture-v1" and manifest.get("schemaVersion") == 1, "wrong schema")
    recording_id = manifest.get("recordingId")
    require(isinstance(recording_id, str) and RECORDING_ID.fullmatch(recording_id), "invalid recording ID")
    if expected_recording_id is not None:
        require(recording_id == expected_recording_id, "recording ID does not match selection")
    require(manifest.get("source") == "recorded" and manifest.get("consentConfirmed") is True, "missing recorded consent")
    require(isinstance(manifest.get("deviceModel"), str) and manifest["deviceModel"].strip(), "missing device identity")
    require(manifest.get("cameraOwner") == "native_arcore_only" and manifest.get("flutterEngineCreated") is False, "wrong camera owner")
    require(manifest.get("depthMode") == "RAW_DEPTH_ONLY", "wrong depth mode")
    require(manifest.get("sourceTimestampDomain") == "arcore_camera_ns_unverified" and
            manifest.get("receiveTimestampDomain") == "elapsedRealtimeNs", "unverified clock relabelled")
    for flag in BLOCKED:
        require(manifest.get(flag) is False, f"capture cannot grant {flag}")
    require(manifest.get("recordingStatus") in ("complete", "failed"), "recording not finalized")
    integer(manifest.get("maxFrames"), "max frames", 1, 30)
    integer(manifest.get("maxDurationNs"), "max duration", 1, 10_000_000_000)
    integer(manifest.get("sampleIntervalNs"), "sample interval", 200_000_000)
    integer(manifest.get("maxPayloadBytes"), "max bytes", 1, MAX_BYTES)
    started = integer(manifest.get("startedElapsedNs"), "started time", 1)
    stopped = integer(manifest.get("stoppedElapsedNs"), "stopped time", started)
    seen = set()
    require(manifest.get("frames", {}).get("path") == "frames.jsonl", "wrong frames path")
    raw_rows = hashed_file(root, manifest["frames"], seen, 1024 * 1024)
    rows = [load_json(line) for line in raw_rows.decode("utf-8").splitlines() if line.strip()]
    require(len(rows) == integer(manifest.get("frameCount"), "frame count", 0, manifest["maxFrames"]), "frame count mismatch")
    last_source, last_ready = 0, started
    unavailable = Counter()
    frames = []
    for index, row in enumerate(rows):
        require(row.get("frameIndex") == index and row.get("frameId") == index + 1 and
                row.get("sessionGeneration") == 1, "frame identity/order mismatch")
        last_source = integer(row.get("frameTimestampNs"), "frame time", last_source + 1)
        received = integer(row.get("receivedElapsedNs"), "received time", last_ready, stopped)
        ready = integer(row.get("payloadsReadyElapsedNs"), "payload ready time", received, stopped)
        last_ready = ready
        require(row.get("trackingState") in ("TRACKING", "PAUSED", "STOPPED"), "invalid tracking state")
        pose = row.get("cameraPose")
        require(isinstance(pose, dict) and pose.get("convention") == "arcore_world_right_up_negative_z_forward", "missing pose convention")
        vector(pose.get("translationM"), 3, "translation")
        q = vector(pose.get("rotationQuaternionXyzw"), 4, "quaternion")
        require(abs(sum(v * v for v in q) - 1) <= .01, "nonunit quaternion")
        dims = intrinsics(row.get("imageIntrinsics"))
        intrinsics(row.get("textureIntrinsics"))
        grid = row.get("imageToTextureGrid")
        require(isinstance(grid, dict) and grid.get("physicalAlignmentValidated") is False, "unvalidated mapping relabelled")
        vector(grid.get("inputImagePixels"), 18, "mapping input")
        mapping = grid.get("outputTextureNormalized")
        require(isinstance(mapping, list) and len(mapping) == 18, "invalid mapping output")
        require(all(v is None or (type(v) in (int, float) and math.isfinite(v)) for v in mapping), "nonfinite mapping")
        data = {kind: image(root, row.get(kind), kind, seen) for kind in ENCODINGS}
        reasons = pair_reasons(row, dims)
        require(row.get("pairReasons") == reasons and row.get("pairStatus") ==
                ("unavailable" if reasons else "same_frame_candidate"), "pair admission mismatch")
        unavailable.update(reasons)
        info = {"frameIndex": index, "pairStatus": row["pairStatus"], "pairReasons": reasons,
                "rgbToTextureMappingAvailable": all(v is not None for v in mapping),
                "receiveToPayloadReadyMs": (ready - received) / 1e6}
        if data["rawDepth"] and data["confidence"] and not any(
                row["rawDepth"][k] != row["confidence"][k] for k in ("width", "height", "timestampNs")):
            info["nativePixelAvailability"] = pixel_availability(data["rawDepth"][0], data["confidence"][0],
                row["rawDepth"]["width"], row["rawDepth"]["height"])
        frames.append(info)
    files = [p for p in (root / "payloads").rglob("*") if p.is_file()] if (root / "payloads").exists() else []
    require(all(not p.is_symlink() for p in files), "symlink payload")
    payload_bytes = sum(p.stat().st_size for p in files)
    require(payload_bytes <= manifest["maxPayloadBytes"] and payload_bytes == manifest.get("payloadBytes"), "payload byte total mismatch")
    orphans = sorted(p.relative_to(root).as_posix() for p in files if p.relative_to(root).as_posix() not in seen)
    require(not orphans or manifest["recordingStatus"] == "failed", "unreferenced payloads in complete capture")
    complete = manifest["recordingStatus"] == "complete" and len(rows) > 0
    return {
        "schema": "bagdar-native-capture-audit-v1", "integrityPassed": True,
        "finalizedNonemptyCapture": complete,
        "recordingId": manifest["recordingId"], "sourceProvenance": "manifest_self_report_only",
        # A matching selection prevents accidental association; it does not authenticate capture origin.
        "expectedRecordingId": expected_recording_id,
        "recordingSelectionMatched": expected_recording_id is not None,
        "deviceModel": manifest["deviceModel"], "recordingStatus": manifest["recordingStatus"],
        "terminationReason": manifest.get("terminationReason"), "frames": frames, "frameCount": len(rows),
        "sameFrameCandidates": sum(f["pairStatus"] == "same_frame_candidate" for f in frames),
        "unavailableReasons": dict(sorted(unavailable.items())), "orphanPayloads": orphans,
        "elapsedSessionMs": (stopped - started) / 1e6,
        "captureAgeMs": None, "captureToDecisionMs": None,
        "pixelAvailabilityMeaning": "native depth pixels only; not RGB alignment, accuracy or free body volume",
        **{flag: False for flag in BLOCKED},
        "spatialRecordingV2Ready": False, "safetyReplayReady": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("recording", type=Path)
    parser.add_argument("--expected-recording-id", help="compare with an independently selected capture ID")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.is_relative_to(args.recording.resolve()) and output != args.recording.resolve() / "audit.json":
        parser.error("inside the recording, --output may only name audit.json; raw inputs cannot be overwritten")
    try:
        receipt = audit(args.recording, expected_recording_id=args.expected_recording_id)
    except (CaptureError, OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        receipt = {"integrityPassed": False, "error": str(error), "promotionAllowed": False, "safetyReplayReady": False}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({k: receipt.get(k) for k in ("integrityPassed", "frameCount", "sameFrameCandidates", "error")}, ensure_ascii=False))
    return 0 if receipt.get("finalizedNonemptyCapture") else 2


if __name__ == "__main__":
    sys.exit(main())

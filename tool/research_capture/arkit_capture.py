"""Strict, offline ARKit recording import. No sensor or clearance authority.

The ARCore v1 reader is deliberately independent. sceneDepth is SDK-estimated
camera-axis depth, not raw LiDAR and not whole-pixel free-space bounds.
"""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import shutil
import struct
import sys
import zipfile

FORMAT = "bagdar-arkit-capture-v1"
MAX_PAYLOAD = 512 * 1024 * 1024
MAX_ARCHIVE = MAX_PAYLOAD + 8 * 1024 * 1024
AUTHORITY = {
    "physicalAlignmentValidated": False, "metricErrorBoundsValidated": False,
    "floorReferenceValidated": False, "clockBindingValidated": False,
    "bodyVolumeCoverageEstablished": False, "safetyReplayReady": False,
    "ordinaryCameraWired": False, "promotionAllowed": False,
}
ENCODINGS = {
    "rgb": "apple_ycbcr_biplanar_native",
    "depth": "float32_little_endian_camera_axis_metres_sdk_estimate",
    "confidence": "uint8_arkit_low0_medium1_high2",
    "validity": "uint8_finite_positive_depth_0_or_1",
}
POSE = "arkit_world_right_up_negative_z_forward_column_major"


class CaptureError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise CaptureError(message)


def integer(value, name, minimum=0, maximum=2**63 - 1):
    require(type(value) is int and minimum <= value <= maximum, f"invalid {name}")
    return value


def load_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, f"duplicate key: {key}")
            result[key] = value
        return result
    def reject(value):
        raise CaptureError(f"nonfinite JSON: {value}")
    result = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=pairs,
                        parse_constant=reject)
    require(isinstance(result, dict), "JSON root must be an object")
    return result


def canonical_path(name):
    require(isinstance(name, str) and name and "\\" not in name and ":" not in name,
            "invalid archive path")
    parts = PurePosixPath(name)
    require(not parts.is_absolute() and parts.as_posix() == name and
            all(p not in (".", "..", "") for p in name.split("/")), "unsafe archive path")
    return parts


def local_file(root, name):
    parts = canonical_path(name)
    path = root.joinpath(*parts.parts)
    require(path.resolve().is_relative_to(root.resolve()), "path escapes recording")
    require(all(not p.is_symlink() for p in (path, *path.parents)), "symlink in recording")
    require(path.is_file(), f"missing file: {name}")
    return path


def hashed(root, descriptor, used, limit=MAX_PAYLOAD):
    require(isinstance(descriptor, dict), "missing file descriptor")
    name = descriptor.get("path")
    require(isinstance(name, str), "missing payload path")
    require(name not in used, "reused payload")
    path = local_file(root, name)
    require(path.stat().st_size <= limit, "payload too large")
    raw = path.read_bytes()
    require(integer(descriptor.get("byteLength"), "byte length", 0, limit) == len(raw), "wrong byte length")
    require(descriptor.get("sha256") == hashlib.sha256(raw).hexdigest(), "hash mismatch")
    used.add(name)
    return raw


def vector(value, n, name):
    require(isinstance(value, list) and len(value) == n and
            all(type(v) in (int, float) and math.isfinite(v) for v in value), f"invalid {name}")
    return value


def pose_matrix(value):
    a = vector(value, 16, "camera transform")
    require(all(abs(a[i] - v) < 1e-5 for i, v in zip((3, 7, 11, 15), (0, 0, 0, 1))),
            "invalid affine pose")
    for i in range(3):
        for j in range(3):
            require(abs(sum(a[4*i+k]*a[4*j+k] for k in range(3)) - (i == j)) < 1e-4,
                    "pose not orthonormal")
    det = a[0]*(a[5]*a[10]-a[9]*a[6])-a[4]*(a[1]*a[10]-a[9]*a[2])+a[8]*(a[1]*a[6]-a[5]*a[2])
    require(abs(det - 1) < 1e-4, "reflected pose")


def image(root, descriptor, kind, row, used):
    if descriptor is None:
        return None
    require(isinstance(descriptor, dict), "invalid image")
    require(descriptor.get("encoding") == ENCODINGS[kind], "wrong encoding")
    require(descriptor.get("frameId") == row["frameId"] and
            descriptor.get("sourceTimestampUs") == row["sourceTimestampUs"], "image frame mismatch")
    w = integer(descriptor.get("width"), "width", 1, 4096)
    h = integer(descriptor.get("height"), "height", 1, 4096)
    require(w * h <= 16_777_216, "image too large")
    planes = descriptor.get("planes")
    require(isinstance(planes, list) and len(planes) == (2 if kind == "rgb" else 1),
            "wrong plane count")
    result = []
    for index, plane in enumerate(planes):
        require(isinstance(plane, dict), "invalid plane descriptor")
        pw, ph, bpp = w, h, 4 if kind == "depth" else 1
        if kind == "rgb" and index == 1:
            pw, ph, bpp = (w+1)//2, (h+1)//2, 2
        require(plane.get("width") == pw and plane.get("height") == ph and
                plane.get("bytesPerPixel") == bpp, "wrong plane shape")
        require(plane.get("sourceRowStride", 0) >= pw*bpp and
                plane.get("packing") == "row_major_samples_without_padding", "wrong stride/packing")
        require(isinstance(plane.get("path"), str) and plane["path"].startswith("payloads/"),
                "wrong payload directory")
        raw = hashed(root, plane, used)
        require(len(raw) == pw*ph*bpp, "wrong packed length")
        result.append(raw)
    return (w, h, result)


def audit(root: Path, expected_recording_id: str):
    root = root.absolute()
    manifest_file = local_file(root, "manifest.json")
    require(manifest_file.stat().st_size <= 65536, "manifest too large")
    manifest = load_json(manifest_file)
    require(manifest.get("format") == FORMAT and manifest.get("schemaVersion") == 1, "wrong schema")
    import re
    rid = manifest.get("recordingId")
    require(isinstance(rid, str) and re.fullmatch(r"capture-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}", rid),
            "invalid recording ID")
    require(rid == expected_recording_id, "recording ID does not match selection")
    require(manifest.get("recordingStatus") == "complete", "partial/failed recording is not complete")
    require(manifest.get("source") == "recorded" and manifest.get("consentConfirmed") is True,
            "missing source/consent assertion")
    for key in ("deviceModel", "osVersion", "recorderVersion"):
        require(isinstance(manifest.get(key), str) and manifest[key].strip(), f"missing {key}")
    build_tag = manifest.get("recorderSourceId")
    require(isinstance(build_tag, str) and (build_tag == "unfrozen-development" or
            re.fullmatch(r"[0-9a-f]{64}", build_tag)), "invalid recorder source identity")
    require(manifest.get("cameraOwner") == "native_arkit_only" and
            manifest.get("depthMode") == "ARKIT_SCENE_DEPTH_ESTIMATE" and
            manifest.get("flutterEngineCreated") is False, "wrong camera/depth source")
    require(manifest.get("sourceTimestampDomain") == "arkit_frame_seconds_unverified" and
            manifest.get("receiveTimestampDomain") == "dispatch_uptime_ns", "clock relabelled")
    require(manifest.get("poseConvention") == POSE, "wrong axes")
    for key, value in AUTHORITY.items():
        require(manifest.get(key) is value, f"capture cannot grant {key}")
    require(manifest.get("maxFrames") == 300 and manifest.get("maxDurationNs") == 10_000_000_000 and
            manifest.get("maxPayloadBytes") == MAX_PAYLOAD, "limits changed")
    start = integer(manifest.get("startedUptimeNs"), "start", 1)
    stop = integer(manifest.get("stoppedUptimeNs"), "stop", start)
    used = set()
    require(isinstance(manifest.get("frames"), dict) and manifest["frames"].get("path") == "frames.jsonl",
            "wrong rows path")
    raw_rows = hashed(root, manifest["frames"], used, 4*1024*1024)
    # Reuse the strict JSON decoder for rows, including duplicate-key rejection.
    def parse_row(raw):
        def pairs(items):
            d = {}
            for k, v in items:
                require(k not in d, "duplicate frame key")
                d[k] = v
            return d
        def reject(_):
            raise CaptureError("nonfinite JSON frame")
        result = json.loads(raw, object_pairs_hook=pairs, parse_constant=reject)
        require(isinstance(result, dict), "frame must be a JSON object")
        return result
    rows = [parse_row(line) for line in raw_rows.decode("utf-8").splitlines() if line.strip()]
    require(len(rows) == integer(manifest.get("frameCount"), "frame count", 1, 300), "wrong frame count")
    dropped = manifest.get("droppedFrames")
    require(isinstance(dropped, dict), "missing drop counters")
    drops = sum(integer(n, "drop counter") for n in dropped.values())
    require(integer(manifest.get("receivedFrames"), "received frame count") == len(rows) + drops,
            "capture/drop accounting mismatch")
    report_rows, last_id, last_stamp, last_receive = [], 0, -1, start
    session = manifest.get("sessionId")
    require(isinstance(session, str) and session == rid, "invalid session")
    dimensions = None
    for index, row in enumerate(rows):
        require(row.get("frameIndex") == index and row.get("sessionId") == session and
                row.get("sessionGeneration") == 1, "mixed session/index")
        last_id = integer(row.get("frameId"), "frame ID", last_id+1)
        stamp = row.get("sourceTimestampSeconds")
        require(type(stamp) in (int, float) and math.isfinite(stamp) and stamp >= 0,
                "invalid source timestamp")
        require(row.get("sourceTimestampBits") == struct.pack(">d", float(stamp)).hex(), "timestamp bits mismatch")
        last_stamp = integer(row.get("sourceTimestampUs"), "source timestamp", last_stamp+1)
        require(last_stamp == int(stamp*1_000_000), "source timestamp conversion")
        last_receive = integer(row.get("receivedUptimeNs"), "receive timestamp", last_receive, stop)
        integer(row.get("payloadsReadyUptimeNs"), "ready timestamp", last_receive, stop)
        require(row.get("poseConvention") == POSE, "frame axes changed")
        pose_matrix(row.get("cameraTransform"))
        k = vector(row.get("intrinsics"), 9, "intrinsics")
        require(k[0] > 0 and k[4] > 0 and k[8] == 1 and
                all(abs(k[i]) < 1e-8 for i in (1, 2, 3, 5)), "invalid intrinsics")
        require(row.get("trackingState") in ("normal", "limited", "notAvailable"), "unknown tracking state")
        require(row.get("orientation") in ("portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight"),
                "unknown orientation")
        images = {kind: image(root, row.get(kind), kind, row, used) for kind in ENCODINGS}
        rgb, depth, confidence, validity = (images[k] for k in ENCODINGS)
        require(rgb is not None, "missing captured image")
        require(row.get("rgbPixelFormat") in (875704422, 875704438), "unknown RGB pixel format")
        require(row.get("rgbColorRange") == ("full" if row["rgbPixelFormat"] == 875704422 else "video"),
                "RGB range mismatch")
        require(isinstance(row.get("rgbYCbCrMatrix"), str) and row["rgbYCbCrMatrix"], "missing colour matrix metadata")
        require(row.get("imageResolution") == list(rgb[:2]), "RGB intrinsics resolution mismatch")
        dims = tuple(rgb[:2]) + (() if depth is None else tuple(depth[:2]))
        if dimensions is None and depth is not None:
            dimensions = dims
        if depth is not None:
            require(dims == dimensions, "dimensions changed within session")
            require(rgb[0]*depth[1] == rgb[1]*depth[0], "depth/RGB aspect mismatch")
            require(validity is not None and validity[:2] == depth[:2], "missing/mismatched validity")
            if confidence is not None:
                require(confidence[:2] == depth[:2], "confidence dimensions mismatch")
                require(all(c <= 2 for c in confidence[2][0]), "invalid ARKit confidence")
            values = [v[0] for v in struct.iter_unpack("<f", depth[2][0])]
            valid = validity[2][0]
            require(all(v == int(math.isfinite(z) and z > 0) for z, v in zip(values, valid)),
                    "validity does not preserve invalid depth")
            high = [bool(v) and confidence is not None and confidence[2][0][i] == 2
                    for i, v in enumerate(valid)]
            grid = [[0]*8 for _ in range(6)]
            totals = [[0]*8 for _ in range(6)]
            for i, available in enumerate(high):
                x, y = (i % depth[0])*8//depth[0], (i//depth[0])*6//depth[1]
                totals[y][x] += 1
                grid[y][x] += int(available)
            availability = {"pixelCount": len(valid), "finitePositivePixels": sum(valid),
                            "highConfidencePixels": sum(high), "grid8x6Counts": grid,
                            "grid8x6Totals": totals, "wholePixelBoundsAvailable": False}
        else:
            require(confidence is None and validity is None, "orphan depth auxiliary data")
            availability = None
        reasons = []
        if depth is None:
            reasons.append("depth_unavailable")
        if confidence is None:
            reasons.append("confidence_unavailable")
        if row["trackingState"] != "normal":
            reasons.append("tracking_unavailable")
        report_rows.append({"frameId": last_id, "sourceTimestampUs": last_stamp,
                            "sameFrameCandidate": not reasons, "unavailableReasons": reasons,
                            "nativePixelAvailability": availability})
    total = sum(local_file(root, name).stat().st_size for name in used if name.startswith("payloads/"))
    require(total == manifest.get("payloadBytes") and total <= MAX_PAYLOAD, "payload accounting mismatch")
    require({p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file()} == used | {"manifest.json"},
            "unreferenced files in capture")
    return {"format": FORMAT, "recordingId": rid, "integrityPassed": True,
            "manifestSha256": hashlib.sha256((root/"manifest.json").read_bytes()).hexdigest(),
            "frameCount": len(rows), "frames": report_rows, "droppedFrames": dropped,
            "sameFrameCandidates": sum(r["sameFrameCandidate"] for r in report_rows),
            "captureToDecisionMs": None, "captureToDecisionStatus": "not_established",
            "recorderSourceId": build_tag, "recorderBuildTagAuthenticated": False,
            "humanOriginAuthenticated": False, "genericObstacleDelivery": "shadow", **AUTHORITY}


def import_archive(archive: Path, output: Path, expected_recording_id: str):
    """Exclusive extraction. Rejected material is retained for investigation."""
    require(not output.exists(), "output already exists")
    resolved = output.resolve()
    require(not any((parent/".git").exists() for parent in (resolved, *resolved.parents)),
            "raw recorded media must stay outside Git repositories")
    require(archive.stat().st_size <= MAX_ARCHIVE, "archive too large")
    with zipfile.ZipFile(archive) as z:
        members = z.infolist()
        require(0 < len(members) <= 2500, "wrong archive entry count")
        seen, total = set(), 0
        for member in members:
            name = member.filename.rstrip("/") if member.is_dir() else member.filename
            canonical_path(name)
            require(name not in seen, "duplicate archive entry")
            seen.add(name)
            require(((member.external_attr >> 16) & 0o170000) in (0, 0o100000, 0o040000),
                    "archive link/special file")
            require(not member.flag_bits & 1, "encrypted archive")
            total += member.file_size
            require(total <= MAX_ARCHIVE, "expanded archive too large")
        output.mkdir(parents=True, exist_ok=False)
        for member in members:
            target = output.joinpath(*PurePosixPath(member.filename).parts)
            if member.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with z.open(member) as src, target.open("xb") as dst:
                    shutil.copyfileobj(src, dst)
    return audit(output, expected_recording_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture", type=Path)
    parser.add_argument("--expected-recording-id", required=True)
    parser.add_argument("--extract-to", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        if args.extract_to:
            result = import_archive(args.capture, args.extract_to, args.expected_recording_id)
        else:
            result = audit(args.capture, args.expected_recording_id)
        rendered = json.dumps(result, indent=2, allow_nan=False)+"\n"
        if args.output:
            root = (args.extract_to or args.capture).resolve()
            require(not args.output.resolve().is_relative_to(root), "report must be outside immutable capture")
            with args.output.open("x", encoding="utf-8") as f:
                f.write(rendered)
        else:
            print(rendered, end="")
    except (CaptureError, OSError, ValueError, KeyError, TypeError, zipfile.BadZipFile) as e:
        print(f"ARKit import rejected: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

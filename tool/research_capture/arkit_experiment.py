"""Preregistered iPhone feasibility protocol and declared offline metric scorer.

This module does not run models or the runtime. A user-supplied decision is not
proof that Bagdar produced it. Scoring never promotes a sensor or the product.
"""
from __future__ import annotations
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

from arkit_capture import AUTHORITY, CaptureError, audit, require, load_json, local_file

SCENARIOS = (
    ("wide-corridor", "passable"), ("wide-doorway", "passable"),
    ("obstacle-outside-path", "passable"), ("plain-floor", "passable"),
    ("dark-floor", "passable"), ("open-space-no-near-return", "passable"),
    ("box-in-path", "hazard"), ("thin-pole", "hazard"),
    ("low-beam", "hazard"), ("narrow-doorway", "hazard"),
    ("floor-discontinuity", "hazard"), ("crossing-object", "hazard"),
)


def protocol():
    return {"schemaVersion": 1, "protocolId": "iphone-spatial-feasibility-v1",
        "scope": "stationary-operator-recorded-offline-research",
        "targetDevice": "iPhone 13 Pro Max", "cameraOwner": "native_arkit_only",
        "source": "ARKIT_SCENE_DEPTH_ESTIMATE", "humanCollectionStatus": "not_run",
        "request": {"widthM": .9, "headroomM": 1.85, "forwardStartM": .2,
                    "forwardEndM": 3.5, "maximumFloorRiseM": .05, "maximumFloorDropM": .05},
        "maximumAgeUs": 100000, "minimumConfidence": .99,
        "calibrationDistancesM": [.25, .5, 1, 2, 3.5],
        "calibrationRegions": ["centre", "left-edge", "right-edge"],
        "collectionPrecondition": "physical-provider-feasibility-gates-pass-before-behavioural-collection",
        "holdoutPolicy": "freeze-candidate-before-session-2; no-retuning-after-unblinding",
        "acceptance": {"maximumUnsafeContinues": 0, "maximumHazardNonStops": 0,
                       "minimumRelativeFalseStopReduction": .5,
                       "allContinuesRequireCurrentWholeVolumeProof": True},
        "recordings": [{"planId": f"s{session}-{scenario}-r{repeat}", "session": session,
                        "split": "development" if session == 1 else "holdout",
                        "scenario": scenario, "plannedClass": label, "repeat": repeat}
                       for session in (1, 2) for scenario, label in SCENARIOS for repeat in (1, 2, 3)],
        "genericObstacleDelivery": "shadow", **AUTHORITY}


def calibration_report(root, recording_id, measurements):
    receipt = audit(root, recording_id)
    require(measurements.get("recordingId") == recording_id and
            measurements.get("captureManifestSha256") == receipt["manifestSha256"],
            "calibration belongs to different capture")
    require(measurements.get("scope") == "calibration-only" and
            measurements.get("independentReferenceAssertion") is True,
            "separate independent reference required")
    rows = {r["frameId"]: r for r in [json.loads(line) for line in
            (root/"frames.jsonl").read_text(encoding="utf-8").splitlines() if line.strip()]}
    errors, observed, alignment = [], set(), []
    for item in measurements.get("samples", []):
        row = rows.get(item.get("frameId"))
        require(row is not None and row.get("depth") is not None, "unknown calibration frame")
        depth = row["depth"]
        x, y = item.get("x"), item.get("y")
        require(type(x) is int and type(y) is int and 0 <= x < depth["width"] and 0 <= y < depth["height"],
                "invalid reference pixel")
        target, tolerance = item.get("referenceCameraAxisM"), item.get("referenceToleranceM")
        require(type(target) in (int, float) and math.isfinite(target) and target > 0 and
                type(tolerance) in (int, float) and math.isfinite(tolerance) and tolerance > 0,
                "invalid independent reference")
        require(item.get("targetDistanceM") in (.25, .5, 1, 2, 3.5) and
                item.get("region") in ("centre", "left-edge", "right-edge"), "unknown calibration condition")
        raw = local_file(root, depth["planes"][0]["path"]).read_bytes()
        z = struct.unpack_from("<f", raw, 4*(y*depth["width"]+x))[0]
        require(math.isfinite(z) and z > 0, "reference point has no depth")
        confidence = row.get("confidence")
        c = None if confidence is None else local_file(root, confidence["planes"][0]["path"]).read_bytes()[y*depth["width"]+x]
        error = abs(z-target)
        errors.append({"frameId": row["frameId"], "x": x, "y": y, "axisDepthM": z,
                       "referenceCameraAxisM": target, "referenceToleranceM": tolerance,
                       "absoluteSampleErrorM": error, "sampleErrorPlusReferenceToleranceM": error+tolerance,
                       "confidence": c, "region": item["region"], "targetDistanceM": item["targetDistanceM"]})
        observed.add((item["targetDistanceM"], item["region"]))
        if "independentRgbFeaturePixel" in item:
            pixel = item["independentRgbFeaturePixel"]
            require(isinstance(pixel, list) and len(pixel) == 2 and
                    all(type(v) in (int, float) and math.isfinite(v) for v in pixel), "invalid RGB reference pixel")
            predicted = [(x+.5)*row["rgb"]["width"]/depth["width"],
                         (y+.5)*row["rgb"]["height"]/depth["height"]]
            residual = math.hypot(predicted[0]-pixel[0], predicted[1]-pixel[1])
            alignment.append({"frameId": row["frameId"], "depthPixel": [x, y],
                              "independentRgbFeaturePixel": pixel, "projectedRgbPixel": predicted,
                              "residualPixels": residual})
    require(errors, "no independent calibration samples")
    placement = measurements.get("diagnosticWorldToWalkingRowMajor")
    floor = []
    if placement is not None:
        from arkit_capture import pose_matrix
        require(isinstance(placement, list) and len(placement) == 16, "invalid diagnostic placement")
        pose_matrix([placement[r*4+c] for c in range(4) for r in range(4)])
    for item in measurements.get("floorReferenceSamples", []):
        require(placement is not None, "floor reference needs independent placement")
        row = rows.get(item.get("frameId"))
        require(row is not None and row.get("depth") is not None, "unknown floor reference frame")
        x, y = item.get("x"), item.get("y")
        d = row["depth"]
        require(type(x) is int and type(y) is int and 0 <= x < d["width"] and 0 <= y < d["height"],
                "invalid floor pixel")
        reference, tolerance = item.get("referenceHeightM"), item.get("referenceToleranceM")
        require(type(reference) in (int, float) and math.isfinite(reference) and
                type(tolerance) in (int, float) and math.isfinite(tolerance) and tolerance > 0,
                "invalid floor reference")
        z = struct.unpack_from("<f", local_file(root, d["planes"][0]["path"]).read_bytes(), 4*(y*d["width"]+x))[0]
        require(math.isfinite(z) and z > 0, "missing floor depth")
        k = row["intrinsics"]
        sx, sy = d["width"]/row["rgb"]["width"], d["height"]/row["rgb"]["height"]
        camera = [(x+.5-k[6]*sx)/(k[0]*sx)*z, -(y+.5-k[7]*sy)/(k[4]*sy)*z, -z, 1]
        t = row["cameraTransform"]
        world = [sum(t[c*4+r]*camera[c] for c in range(4)) for r in range(4)]
        height = sum(placement[8+c]*world[c] for c in range(4))
        floor.append({"frameId": row["frameId"], "x": x, "y": y, "sampleHeightM": height,
                      "referenceHeightM": reference, "absoluteHeightErrorM": abs(height-reference),
                      "referenceToleranceM": tolerance})
    return {"format": "bagdar-physical-evidence-profile-v1", "schemaVersion": 1,
            "id": "empirical-"+hashlib.sha256(json.dumps(measurements, sort_keys=True, allow_nan=False).encode()).hexdigest(),
            "recordingId": recording_id,
            "captureManifestSha256": receipt["manifestSha256"],
            "scope": "empirical-centre-depth-samples-only", "samples": errors,
            "requiredDistanceRegionPairs": 15, "observedDistanceRegionPairs": len(observed),
            "empiricalSampleErrorM": max(e["sampleErrorPlusReferenceToleranceM"] for e in errors),
            "alignmentSamples": alignment, "floorReferenceSamples": floor,
            "diagnosticWorldToWalkingRowMajor": placement,
            "alignmentStatus": "empirical-residuals-only" if alignment else "not_established",
            "floorReferenceStatus": "empirical-residuals-only" if floor else "not_established",
            "referenceMeasurementsAuthenticated": False,
            "wholePixelBoundsAvailable": False, "supportsPassageClearance": False, **AUTHORITY}


def score(labels, decisions):
    """All labelled free frames remain in denominators, including unavailable."""
    require(labels.get("schemaVersion") == 1 and decisions.get("schemaVersion") == 1, "wrong metric schema")
    require(labels.get("split") == "holdout" and decisions.get("split") == "holdout", "holdout required")
    require(labels.get("candidateFreezeSha256") == decisions.get("candidateFreezeSha256") and
            isinstance(labels.get("candidateFreezeSha256"), str) and
            len(labels["candidateFreezeSha256"]) == 64, "candidate freeze mismatch")
    label_rows = labels.get("frames", [])
    decision_rows = decisions.get("frames", [])
    def keyed(rows):
        result = {}
        for row in rows:
            key = (row.get("recordingId"), row.get("frameId"))
            require(isinstance(key[0], str) and key[0] and type(key[1]) is int and key[1] > 0, "invalid metric frame")
            require(key not in result, "duplicate metric frame")
            result[key] = row
        return result
    truth, outputs = keyed(label_rows), keyed(decision_rows)
    require(truth and truth.keys() == outputs.keys(), "missing/extra metric decision")
    arms = ("baseline", "candidate")
    totals = {a: Counter() for a in arms}
    recordings = {}
    scenarios = {}
    unproved = 0
    for key, label in truth.items():
        require(label.get("class") in ("passable", "hazard", "unlabelled") and
                label.get("scenario") in {s[0] for s in SCENARIOS}, "invalid label/scenario")
        out = outputs[key]
        for arm in arms:
            decision = out.get(arm)
            require(isinstance(decision, dict) and decision.get("action") in ("stopNow", "continueForward", "wait"),
                    "unknown/missing action")
            counts = Counter(frames=1)
            category = label["class"]
            counts[category+"Frames"] += 1
            if category == "passable" and decision["action"] == "stopNow":
                counts["falseStopFrames"] += 1
            if category == "passable" and decision["action"] == "continueForward":
                counts["passableContinueFrames"] += 1
            if category == "hazard":
                counts["hazardNonStopFrames"] += int(decision["action"] != "stopNow")
                counts["unsafeContinueFrames"] += int(decision["action"] == "continueForward")
            counts["unavailableFrames"] += int(decision.get("providerStatus") == "unavailable")
            counts["staleFrames"] += int(decision.get("stale") is True)
            if arm == "candidate" and decision["action"] == "continueForward":
                # Do not accept a declared measuredClear status as physical proof.
                # Current SDK adapter cannot issue the required evidence.
                unproved += 1
            totals[arm].update(counts)
            recordings.setdefault(key[0], {a: Counter() for a in arms})[arm].update(counts)
            scenarios.setdefault(label["scenario"], {a: Counter() for a in arms})[arm].update(counts)
    def render(counts):
        d = {k: counts[k] for k in ("frames", "passableFrames", "hazardFrames", "unlabelledFrames",
             "falseStopFrames", "passableContinueFrames", "hazardNonStopFrames", "unsafeContinueFrames", "unavailableFrames", "staleFrames")}
        d["falseStopRate"] = counts["falseStopFrames"]/counts["passableFrames"] if counts["passableFrames"] else None
        return d
    result = {a: render(totals[a]) for a in arms}
    base, candidate = result["baseline"]["falseStopRate"], result["candidate"]["falseStopRate"]
    reduction = None if base in (None, 0) else (base-candidate)/base
    return {"schemaVersion": 1, "scope": "declared-offline-decisions-not-runtime-execution-proof",
            "candidateFreezeSha256": labels["candidateFreezeSha256"], "summary": result,
            "perRecording": {k: {a: render(v[a]) for a in arms} for k, v in recordings.items()},
            "perScenario": {k: {a: render(v[a]) for a in arms} for k, v in scenarios.items()},
            "relativeFalseStopReduction": reduction, "unprovedCandidateContinues": unproved,
            "numericGatePassed": bool(reduction is not None and reduction >= .5 and
                result["candidate"]["unsafeContinueFrames"] == 0 and
                result["candidate"]["hazardNonStopFrames"] == 0 and unproved == 0 and
                result["candidate"]["passableContinueFrames"] > 0 and
                result["candidate"]["hazardFrames"] > 0),
            "physicalGatePassed": False, "falseStopReductionEstablished": False,
            "runtimeExecutionAuthenticated": False, "genericObstacleDelivery": "shadow", **AUTHORITY}


def freeze(root, output):
    require(not output.exists(), "freeze already exists")
    paths = []
    for directory in ("lib", "tool/research_capture", "tool/model_benchmark"):
        paths += [p for p in (root/directory).rglob("*") if p.is_file() and
                  p.suffix in (".dart", ".py", ".swift", ".plist", ".pbxproj", ".json", ".ps1", ".sh", ".xcscheme") and
                  "__pycache__" not in p.parts]
    paths += [root/p for p in ("assets/midas_small.ncnn.bin", "assets/midas_small.ncnn.param",
                              "assets/yolov8n_int8.tflite", "pubspec.lock")]
    result = {"schemaVersion": 1, "status": "implementation-freeze-not-holdout-release",
              "files": {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in sorted(set(paths))}, "protocol": protocol(), **AUTHORITY}
    write(output, result)
    return result


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as f:
        json.dump(value, f, indent=2, allow_nan=False)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("protocol"); p.add_argument("--output", type=Path)
    p = sub.add_parser("status"); p.add_argument("--output", type=Path)
    p = sub.add_parser("freeze"); p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("calibrate"); p.add_argument("capture", type=Path)
    p.add_argument("--recording-id", required=True); p.add_argument("--measurements", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("score"); p.add_argument("--labels", type=Path, required=True)
    p.add_argument("--decisions", type=Path, required=True); p.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "protocol":
            result = protocol()
        elif args.command == "status":
            result = {"schemaVersion": 1, "collectionStatus": "not_run", "importedRecordings": 0,
              "plannedRecordings": 72, "calibrationStatus": "not_run", "runtimeComparisonStatus": "not_run",
              "xcodeBuild": "not_run", "iphoneLifecycle": "not_run", "android": "not_run",
              "hazardNonStops": None, "unsafeContinues": None, "falseStopRate": None,
              "staleFrames": None, "captureToDecisionMs": None, "falseStopReductionEstablished": False,
              "statusScope": "empty-initial-project-receipt-not-an-inventory-of-external-recordings",
              "genericObstacleDelivery": "shadow", **AUTHORITY}
        elif args.command == "freeze":
            result = freeze(Path(__file__).resolve().parents[2], args.output)
            print(f"Frozen {len(result['files'])} files; no holdout release.")
            return 0
        elif args.command == "calibrate":
            result = calibration_report(args.capture, args.recording_id, load_json(args.measurements))
        else:
            result = score(load_json(args.labels), load_json(args.decisions))
        if args.output:
            write(args.output, result)
        else:
            print(json.dumps(result, indent=2, allow_nan=False))
        return 0 if args.command == "protocol" else 2
    except (CaptureError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"ARKit experiment rejected: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

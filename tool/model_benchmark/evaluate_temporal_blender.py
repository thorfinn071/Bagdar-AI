"""Measure detector outputs and frame-to-frame gaps on Blender temporal v2.

The replay annotations use synthetic scene-state sectors. Detector boxes are
reported separately and never converted into Bagdar clearance or user alerts.
"""

from __future__ import annotations

import argparse
import json
import platform
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, __version__ as pillow_version

from evaluate_blender_detectors import (
    CONFIDENCE,
    HAZARD_MASK_CLASSES,
    MODEL_MANIFEST,
    NMS_IOU,
    REPO_ROOT,
    Detector,
    checked_file,
    checked_output_path,
    evaluate_scene,
    sha256,
)


CORPUS_BASE = REPO_ROOT / "test/fixtures/spatial_safety"
SUPPORTED_CORPORA = ("blender-temporal-v2", "blender-context-v3")


def load_sequences(corpus_id: str = "blender-temporal-v2") -> tuple[str, list[dict[str, object]]]:
    if corpus_id not in SUPPORTED_CORPORA:
        raise ValueError(f"unsupported temporal corpus: {corpus_id}")
    corpus_root = CORPUS_BASE / corpus_id
    corpus_manifest = corpus_root / "corpus-manifest.json"
    manifest = json.loads(corpus_manifest.read_text(encoding="utf-8"))
    if manifest["schemaVersion"] != 2 or manifest["corpusId"] != corpus_id:
        raise ValueError("unexpected temporal Blender corpus identity")
    for key, path in (
        ("generatorSha256", REPO_ROOT / manifest["generator"]),
        ("baseGeometryGeneratorSha256", REPO_ROOT / "tool/blender/generate_spatial_corpus.py"),
    ):
        if sha256(path) != manifest[key]:
            raise ValueError(f"temporal corpus generator drift: {key}")
    if corpus_id == "blender-context-v3":
        if sha256(REPO_ROOT / "tool/blender/generate_spatial_temporal_corpus.py") != manifest["parentTemporalGeneratorSha256"]:
            raise ValueError("context corpus parent generator drift")
    checked_file(corpus_root, manifest["scene"]["path"], manifest["scene"]["sha256"])
    replay_path = checked_file(
        corpus_root,
        manifest["replayManifest"]["path"],
        manifest["replayManifest"]["sha256"],
    )
    replay = json.loads(replay_path.read_text(encoding="utf-8"))
    replay_scenes = {scene["id"]: scene for scene in replay["scenes"]}
    assets = manifest["assets"]
    if len(assets) != len(replay_scenes) or len({a["sceneId"] for a in assets}) != len(assets):
        raise ValueError("temporal asset/replay scene sets differ")
    sequences: list[dict[str, object]] = []
    for asset in sorted(assets, key=lambda item: item["sceneId"]):
        scene_id = asset["sceneId"]
        if scene_id not in replay_scenes:
            raise ValueError(f"missing replay scene: {scene_id}")
        replay_scene = replay_scenes[scene_id]
        replay_frames_path = checked_file(
            corpus_root, replay_scene["frames"], replay_scene["sha256"]["frames"]
        )
        annotation_path = checked_file(
            corpus_root, replay_scene["annotations"], replay_scene["sha256"]["annotations"]
        )
        replay_frames = [json.loads(line) for line in replay_frames_path.read_text(encoding="utf-8").splitlines()]
        annotations = json.loads(annotation_path.read_text(encoding="utf-8"))
        if annotations["sceneId"] != scene_id or len(replay_frames) != manifest["frameCountPerScene"]:
            raise ValueError(f"temporal replay count/identity drift: {scene_id}")
        source_frames = sorted(asset["frames"], key=lambda frame: frame["frameIndex"])
        if len(source_frames) != len(replay_frames):
            raise ValueError(f"temporal source count mismatch: {scene_id}")
        state = asset["state"]
        compatible_classes = asset.get("compatibleCocoClassIds")
        if corpus_id == "blender-context-v3":
            if not isinstance(compatible_classes, list) or any(
                not isinstance(value, int) or value < 0 or value >= 80
                for value in compatible_classes
            ):
                raise ValueError(f"invalid compatible COCO classes: {scene_id}")
        category = (
            "object_like" if state in ("blocked", "moving")
            else "traversable" if state == "safe" else "other"
        )
        frame_inputs: list[dict[str, object]] = []
        rgb_hashes: set[str] = set()
        for index, (source, replay_frame) in enumerate(zip(source_frames, replay_frames)):
            if source["frameIndex"] != index or replay_frame["frameIndex"] != index:
                raise ValueError(f"temporal frame index mismatch: {scene_id}")
            if source["capturedOffsetMs"] != replay_frame["capturedOffsetMs"]:
                raise ValueError(f"temporal frame timestamp mismatch: {scene_id}/{index}")
            paths = {
                kind: checked_file(corpus_root, source[kind]["path"], source[kind]["sha256"])
                for kind in ("rgb", "depth", "semantic")
            }
            rgb_hash = source["rgb"]["sha256"]
            if rgb_hash in rgb_hashes:
                raise ValueError(f"duplicate temporal RGB frame: {scene_id}")
            rgb_hashes.add(rgb_hash)
            expected_action = annotations["timeline"][index]["expectedActions"]
            if len(expected_action) != 1:
                raise ValueError(f"ambiguous temporal action: {scene_id}/{index}")
            frame_inputs.append({
                "sceneId": scene_id,
                "frameIndex": index,
                "capturedOffsetMs": source["capturedOffsetMs"],
                "state": state,
                "category": category,
                "expectedAction": expected_action[0],
                "rgbPath": paths["rgb"],
                "semanticPath": paths["semantic"],
                "rgbSha256": rgb_hash,
                **({"compatibleCocoClassIds": compatible_classes}
                   if corpus_id == "blender-context-v3" else {}),
            })
        sequences.append({"sceneId": scene_id, "state": state, "category": category, "frames": frame_inputs})
    return sha256(corpus_manifest), sequences


def evaluate_sequence(detector: Detector, sequence: dict[str, object]) -> dict[str, object]:
    frames: list[dict[str, object]] = []
    for source in sequence["frames"]:
        result = evaluate_scene(detector, source)
        if "compatibleCocoClassIds" in source:
            compatible = source["compatibleCocoClassIds"]
            result["compatibleCocoClassIds"] = compatible
            result["classCompatibleForwardMaskOverlapPresent"] = any(
                detection["forward"]
                and detection["forwardHazardMaskOverlapPixels"] > 0
                and detection["classId"] in compatible
                for detection in result["detections"]
            )
        result["frameIndex"] = source["frameIndex"]
        result["capturedOffsetMs"] = source["capturedOffsetMs"]
        frames.append(result)
    presence = [bool(frame["forwardMaskOverlapPresent"]) for frame in frames]
    return {
        "sceneId": sequence["sceneId"],
        "state": sequence["state"],
        "category": sequence["category"],
        "forwardMaskOverlapFrames": sum(presence),
        "presenceTransitions": sum(left != right for left, right in zip(presence, presence[1:])),
        "frames": frames,
    }


def summarize(results: list[dict[str, object]]) -> dict[str, object]:
    objects = [result for result in results if result["category"] == "object_like"]
    safe = [result for result in results if result["category"] == "traversable"]
    object_frames = [frame for result in objects for frame in result["frames"]]
    safe_frames = [frame for result in safe for frame in result["frames"]]
    scorable = [frame for frame in object_frames if frame["forwardHazardMaskPixels"] > 0]
    summary = {
        "objectSequences": len(objects),
        "objectFrames": len(object_frames),
        "objectMaskScorableFrames": len(scorable),
        "objectFramesWithForwardMaskOverlap": sum(
            bool(frame["forwardMaskOverlapPresent"]) for frame in scorable
        ),
        "objectSequencesWithAnyForwardMaskOverlap": sum(
            result["forwardMaskOverlapFrames"] > 0 for result in objects
        ),
        "objectPresenceTransitions": sum(result["presenceTransitions"] for result in objects),
        "traversableFrames": len(safe_frames),
        "traversableFramesWithForwardBox": sum(
            bool(frame["forwardBoxPresent"]) for frame in safe_frames
        ),
        "totalDetections": sum(
            len(frame["detections"]) for result in results for frame in result["frames"]
        ),
    }
    if any("compatibleCocoClassIds" in frame for frame in object_frames):
        class_scorable = [frame for frame in object_frames if frame["compatibleCocoClassIds"]]
        summary["classCompatibleScorableFrames"] = len(class_scorable)
        summary["classCompatibleForwardMaskOverlapFrames"] = sum(
            bool(frame["classCompatibleForwardMaskOverlapPresent"])
            for frame in class_scorable
        )
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", choices=SUPPORTED_CORPORA, default="blender-temporal-v2")
    parser.add_argument("--output", help="Write the report to this repo-relative path.")
    parser.add_argument("--check", help="Compare with this report without writing.")
    args = parser.parse_args()
    if args.output and args.check:
        parser.error("choose --output or --check")
    corpus_hash, sequences = load_sequences(args.corpus)
    manifest = json.loads(MODEL_MANIFEST.read_text(encoding="utf-8"))
    control = next(s for s in manifest["controls"] if s["modelId"] == "yolov8n-int8-control-416")
    specs = [(control, "tflite"), *((s, "onnx") for s in manifest["candidates"])]
    models: list[dict[str, object]] = []
    for spec, runtime in specs:
        detector = Detector(spec, runtime)
        results = [evaluate_sequence(detector, sequence) for sequence in sequences]
        models.append({
            "modelId": spec["modelId"],
            "artifactSha256": spec["artifactSha256"],
            "artifactLicense": spec["license"],
            "runtime": runtime,
            "inputSize": detector.size,
            "summary": summarize(results),
            "sequences": results,
        })
    import tensorflow as tf

    report = {
        "schemaVersion": 1,
        "benchmarkId": (
            "bagdar-blender-temporal-detector-diagnostic-v2"
            if args.corpus == "blender-temporal-v2"
            else "bagdar-blender-context-detector-diagnostic-v3"
        ),
        "scope": "desktop synthetic frame-by-frame detector diagnostic; not camera or user-alert evidence",
        "toolSha256": sha256(Path(__file__)),
        "baseEvaluatorSha256": sha256(REPO_ROOT / "tool/model_benchmark/evaluate_blender_detectors.py"),
        "corpusId": args.corpus,
        "corpusManifestSha256": corpus_hash,
        "modelManifestSha256": sha256(MODEL_MANIFEST),
        "sequenceCount": len(sequences),
        "frameCount": sum(len(sequence["frames"]) for sequence in sequences),
        "protocol": {
            "preprocess": "PIL bilinear aspect-preserving letterbox RGB/255; TFLite NHWC, ONNX NCHW",
            "confidenceThreshold": CONFIDENCE,
            "classAwareNmsIou": NMS_IOU,
            "forwardRule": "box center in middle image third",
            "maskOverlapRule": "at least one overlapping central hazard-mask pixel; diagnostic only",
            "temporalRule": "presence transition between successive 300 ms frames",
        },
        "environment": {
            "python": platform.python_version(),
            "numpy": np.__version__,
            "pillow": pillow_version,
            "onnxruntime": ort.__version__,
            "tensorflow": tf.__version__,
            "platform": platform.platform(),
        },
        "models": models,
        "promotionAllowed": False,
        "blockingReasons": [
            (
                "synthetic primitive RGB cannot establish real-camera recall or false-alert rate"
                if args.corpus == "blender-temporal-v2"
                else "synthetic contextual RGB cannot establish real-camera recall or false-alert rate"
            ),
            "replay uses synthetic scene-state sectors, not model depth or detector-derived occupancy",
            "three frames are too few for temporal reliability or moving-direction validation",
            "model license/provenance and named-device gates remain open",
        ],
    }
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        path = checked_output_path(args.check)
        if path.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"temporal Blender report drift: {args.check}")
        print(f"Temporal Blender report matches: {args.check}")
    elif args.output:
        path = checked_output_path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")
        print(f"Wrote {path.relative_to(REPO_ROOT)}")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()

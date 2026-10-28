"""Compare pinned detector artifacts on the synthetic Bagdar obstacle corpus.

This is a detector diagnostic, not an assistive or phone-runtime gate. The
ground-truth spatial replay remains separate: semantic detections do not create
free-space or override geometry in Bagdar.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
from pathlib import Path

import numpy as np
import onnxruntime as ort
from PIL import Image, __version__ as pillow_version


REPO_ROOT = Path(__file__).resolve().parents[2]
CORPUS_ROOT = REPO_ROOT / "test/fixtures/spatial_safety/blender-egocentric-v1"
CORPUS_MANIFEST = CORPUS_ROOT / "corpus-manifest.json"
MODEL_MANIFEST = REPO_ROOT / "model_export/candidates/manifest.json"
CONFIDENCE = 0.25
NMS_IOU = 0.45
MAX_DETECTIONS = 300
HAZARD_MASK_CLASSES = frozenset({2, 3, 4, 5, 7, 9, 10})


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def checked_file(root: Path, relative: str, expected_hash: str) -> Path:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError(f"unsafe corpus path: {relative!r}")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"missing or escaping corpus path: {relative}")
    if sha256(path) != expected_hash:
        raise ValueError(f"corpus hash mismatch: {relative}")
    return path


def load_scenes() -> tuple[str, list[dict[str, object]]]:
    manifest = json.loads(CORPUS_MANIFEST.read_text(encoding="utf-8"))
    if manifest["schemaVersion"] != 1 or manifest["corpusId"] != "blender-egocentric-v1":
        raise ValueError("unexpected Blender corpus identity")
    replay_path = checked_file(
        CORPUS_ROOT,
        manifest["replayManifest"]["path"],
        manifest["replayManifest"]["sha256"],
    )
    replay = json.loads(replay_path.read_text(encoding="utf-8"))
    replay_scenes = {scene["id"]: scene for scene in replay["scenes"]}
    assets = manifest["assets"]
    if len(assets) != len(replay_scenes) or len({a["sceneId"] for a in assets}) != len(assets):
        raise ValueError("Blender asset and replay scene sets differ")
    scenes: list[dict[str, object]] = []
    for asset in sorted(assets, key=lambda item: item["sceneId"]):
        scene_id = asset["sceneId"]
        if scene_id not in replay_scenes:
            raise ValueError(f"missing replay scene: {scene_id}")
        replay_scene = replay_scenes[scene_id]
        paths = {
            kind: checked_file(CORPUS_ROOT, asset[kind]["path"], asset[kind]["sha256"])
            for kind in ("rgb", "depth", "semantic")
        }
        frame_path = checked_file(
            CORPUS_ROOT, replay_scene["frames"], replay_scene["sha256"]["frames"]
        )
        annotation_path = checked_file(
            CORPUS_ROOT,
            replay_scene["annotations"],
            replay_scene["sha256"]["annotations"],
        )
        frames = frame_path.read_text(encoding="utf-8").splitlines()
        if len(frames) != 1:
            raise ValueError(f"single-image benchmark requires one frame: {scene_id}")
        frame = json.loads(frames[0])
        annotation = json.loads(annotation_path.read_text(encoding="utf-8"))
        if frame["sceneId"] != scene_id or annotation["sceneId"] != scene_id:
            raise ValueError(f"replay scene identity mismatch: {scene_id}")
        expected_actions = annotation["timeline"][0]["expectedActions"]
        if len(expected_actions) != 1:
            raise ValueError(f"ambiguous expected action: {scene_id}")
        state = asset["state"]
        category = (
            "object_like" if state in ("blocked", "moving")
            else "traversable" if state == "safe"
            else "geometry_only" if state == "drop"
            else "quality_gate"
        )
        if category == "object_like" and expected_actions[0] != "stopNow":
            raise ValueError(f"object scene annotation drift: {scene_id}")
        if category == "traversable" and expected_actions[0] != "continueForward":
            raise ValueError(f"traversable scene annotation drift: {scene_id}")
        scenes.append({
            "sceneId": scene_id,
            "state": state,
            "category": category,
            "expectedAction": expected_actions[0],
            "rgbPath": paths["rgb"],
            "semanticPath": paths["semantic"],
            "rgbSha256": asset["rgb"]["sha256"],
        })
    return sha256(CORPUS_MANIFEST), scenes


def letterbox(image: Image.Image, size: int) -> tuple[np.ndarray, float, int, int]:
    width, height = image.size
    scale = min(size / width, size / height)
    resized_width = round(width * scale)
    resized_height = round(height * scale)
    pad_x = (size - resized_width) // 2
    pad_y = (size - resized_height) // 2
    canvas = Image.new("RGB", (size, size), (114, 114, 114))
    canvas.paste(
        image.resize((resized_width, resized_height), Image.Resampling.BILINEAR),
        (pad_x, pad_y),
    )
    return np.asarray(canvas, dtype=np.float32) / 255.0, scale, pad_x, pad_y


def decode(output: np.ndarray, decoder_id: str) -> tuple[np.ndarray, np.ndarray, np.ndarray, float]:
    if decoder_id == "yolo26-end2end-bnc-v1":
        if output.shape != (1, 300, 6):
            raise ValueError(f"YOLO26 output shape drift: {output.shape}")
        raw = output[0]
        boxes = raw[:, :4].copy()
        scores = raw[:, 4]
        classes = raw[:, 5]
        if not np.allclose(classes, np.round(classes)):
            raise ValueError("YOLO26 returned fractional class IDs")
        classes = classes.astype(np.int32)
    else:
        if output.ndim != 3 or output.shape[0] != 1 or output.shape[1] != 84:
            raise ValueError(f"BCN output shape drift: {output.shape}")
        raw = output[0]
        classes = np.argmax(raw[4:84], axis=0).astype(np.int32)
        scores = np.max(raw[4:84], axis=0)
        center_x, center_y, width, height = raw[:4]
        boxes = np.stack(
            (center_x - width / 2, center_y - height / 2,
             center_x + width / 2, center_y + height / 2), axis=1
        )
    if not np.isfinite(output).all() or np.any(scores < 0) or np.any(scores > 1):
        raise ValueError("nonfinite or out-of-range detector output")
    if np.any(classes < 0) or np.any(classes >= 80):
        raise ValueError("COCO class ID outside 0..79")
    max_raw_score = float(np.max(scores))
    kept = scores >= CONFIDENCE
    return boxes[kept], scores[kept], classes[kept], max_raw_score


def box_iou(box: np.ndarray, others: np.ndarray) -> np.ndarray:
    xy1 = np.maximum(box[:2], others[:, :2])
    xy2 = np.minimum(box[2:], others[:, 2:])
    intersection = np.prod(np.maximum(xy2 - xy1, 0), axis=1)
    area_box = np.prod(np.maximum(box[2:] - box[:2], 0))
    area_others = np.prod(np.maximum(others[:, 2:] - others[:, :2], 0), axis=1)
    return intersection / np.maximum(area_box + area_others - intersection, 1e-9)


def nms(boxes: np.ndarray, scores: np.ndarray, classes: np.ndarray) -> list[int]:
    # Stable score and source-index order makes the report independent of sort ties.
    order = np.lexsort((np.arange(len(scores)), -scores))
    selected: list[int] = []
    for index in order:
        if len(selected) >= MAX_DETECTIONS:
            break
        if any(
            classes[index] == classes[prior]
            and box_iou(boxes[index], boxes[prior:prior + 1])[0] > NMS_IOU
            for prior in selected
        ):
            continue
        selected.append(int(index))
    return selected


def project_boxes(
    boxes: np.ndarray,
    *,
    input_size: int,
    scale: float,
    pad_x: int,
    pad_y: int,
    width: int,
    height: int,
    normalized_input: bool,
) -> np.ndarray:
    projected = boxes.copy()
    if normalized_input:
        projected *= input_size
    projected[:, (0, 2)] = (projected[:, (0, 2)] - pad_x) / scale
    projected[:, (1, 3)] = (projected[:, (1, 3)] - pad_y) / scale
    projected[:, (0, 2)] = np.clip(projected[:, (0, 2)], 0, width)
    projected[:, (1, 3)] = np.clip(projected[:, (1, 3)], 0, height)
    return projected


class Detector:
    def __init__(self, spec: dict[str, object], runtime: str):
        self.spec = spec
        self.runtime = runtime
        self.size = int(spec["input"]["shape"][2])
        self.decoder_id = str(spec["decoderId"])
        self.path = REPO_ROOT / str(spec["artifactPath"])
        if sha256(self.path) != spec["artifactSha256"]:
            raise ValueError(f"model hash mismatch: {self.path}")
        if runtime == "tflite":
            import tensorflow as tf

            self.interpreter = tf.lite.Interpreter(model_path=str(self.path), num_threads=1)
            self.interpreter.allocate_tensors()
            self.input = self.interpreter.get_input_details()[0]
            self.output = self.interpreter.get_output_details()[0]
            if list(self.input["shape"]) != spec["input"]["shape"] or list(self.output["shape"]) != spec["output"]["shape"]:
                raise ValueError("TFLite tensor contract drift")
            if self.input["dtype"] != np.float32 or self.output["dtype"] != np.float32:
                raise ValueError("TFLite float I/O contract drift")
        else:
            options = ort.SessionOptions()
            options.intra_op_num_threads = 1
            options.inter_op_num_threads = 1
            self.session = ort.InferenceSession(
                str(self.path), sess_options=options, providers=["CPUExecutionProvider"]
            )
            self.input = self.session.get_inputs()[0]
            self.output = self.session.get_outputs()[0]
            if list(self.input.shape) != spec["input"]["shape"] or list(self.output.shape) != spec["output"]["shape"]:
                raise ValueError("ONNX tensor contract drift")

    def infer(self, image: Image.Image) -> tuple[list[dict[str, object]], float]:
        tensor, scale, pad_x, pad_y = letterbox(image, self.size)
        if self.runtime == "tflite":
            self.interpreter.set_tensor(self.input["index"], tensor[None])
            self.interpreter.invoke()
            output = self.interpreter.get_tensor(self.output["index"])
        else:
            output = self.session.run(
                [self.output.name], {self.input.name: np.transpose(tensor, (2, 0, 1))[None]}
            )[0]
        boxes, scores, classes, max_raw_score = decode(output, self.decoder_id)
        if len(boxes) == 0:
            return [], max_raw_score
        # This pinned TFLite export reports normalized boxes; ONNX reports
        # input-pixel boxes. Confusing the two silently drops control results.
        width, height = image.size
        boxes = project_boxes(
            boxes, input_size=self.size, scale=scale, pad_x=pad_x,
            pad_y=pad_y, width=width, height=height,
            normalized_input=self.runtime == "tflite",
        )
        valid = (boxes[:, 2] > boxes[:, 0]) & (boxes[:, 3] > boxes[:, 1])
        boxes, scores, classes = boxes[valid], scores[valid], classes[valid]
        detections: list[dict[str, object]] = []
        for index in nms(boxes, scores, classes):
            box = boxes[index]
            detections.append({
                "classId": int(classes[index]),
                "score": round(float(scores[index]), 6),
                "boxNormalized": [round(float(box[j] / (width if j % 2 == 0 else height)), 6) for j in range(4)],
                "forward": bool(width / 3 <= (box[0] + box[2]) / 2 <= width * 2 / 3),
            })
        return detections, max_raw_score


def evaluate_scene(detector: Detector, scene: dict[str, object]) -> dict[str, object]:
    with Image.open(scene["rgbPath"]) as source:
        image = source.convert("RGB")
    with Image.open(scene["semanticPath"]) as source:
        semantic = np.asarray(source, dtype=np.uint8)
    if semantic.shape != (image.height, image.width):
        raise ValueError(f"RGB/semantic alignment mismatch: {scene['sceneId']}")
    hazard_mask = np.isin(semantic, list(HAZARD_MASK_CLASSES))
    center_x1, center_x2 = image.width // 3, image.width * 2 // 3
    forward_mask_pixels = int(hazard_mask[:, center_x1:center_x2].sum())
    detections, max_raw_score = detector.infer(image)
    for detection in detections:
        x1, y1, x2, y2 = detection["boxNormalized"]
        left = max(0, int(np.floor(x1 * image.width)))
        top = max(0, int(np.floor(y1 * image.height)))
        right = min(image.width, int(np.ceil(x2 * image.width)))
        bottom = min(image.height, int(np.ceil(y2 * image.height)))
        detection["hazardMaskOverlapPixels"] = int(
            hazard_mask[top:bottom, left:right].sum()
        )
        detection["forwardHazardMaskOverlapPixels"] = int(
            hazard_mask[top:bottom, max(left, center_x1):min(right, center_x2)].sum()
        ) if min(right, center_x2) > max(left, center_x1) else 0
    forward_detections = [d for d in detections if d["forward"]]
    return {
        "sceneId": scene["sceneId"],
        "rgbSha256": scene["rgbSha256"],
        "state": scene["state"],
        "category": scene["category"],
        "groundTruthAction": scene["expectedAction"],
        "forwardHazardMaskPixels": forward_mask_pixels,
        "maxRawScore": round(max_raw_score, 6),
        "forwardBoxPresent": bool(forward_detections),
        "forwardMaskOverlapPresent": any(
            d["forwardHazardMaskOverlapPixels"] > 0 for d in forward_detections
        ),
        "detections": detections,
    }


def summarize(results: list[dict[str, object]]) -> dict[str, object]:
    objects = [r for r in results if r["category"] == "object_like"]
    mask_scorable = [r for r in objects if r["forwardHazardMaskPixels"] > 0]
    traversable = [r for r in results if r["category"] == "traversable"]
    return {
        "objectLikeScenes": len(objects),
        "objectLikeForwardBoxes": sum(bool(r["forwardBoxPresent"]) for r in objects),
        "objectLikeMaskScorableScenes": len(mask_scorable),
        "objectLikeForwardMaskOverlap": sum(
            bool(r["forwardMaskOverlapPresent"]) for r in mask_scorable
        ),
        "objectLikeWithoutForwardMaskOverlap": [
            r["sceneId"] for r in mask_scorable if not r["forwardMaskOverlapPresent"]
        ],
        "traversableScenes": len(traversable),
        "traversableForwardBoxes": [
            r["sceneId"] for r in traversable if r["forwardBoxPresent"]
        ],
        "geometryOnlyScenes": sum(r["category"] == "geometry_only" for r in results),
        "qualityGateScenes": sum(r["category"] == "quality_gate" for r in results),
        "objectScenesWithoutForwardSemanticMask": [
            r["sceneId"] for r in objects if r["forwardHazardMaskPixels"] == 0
        ],
        "totalDetections": sum(len(r["detections"]) for r in results),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", help="Write the report to this repo-relative path.")
    parser.add_argument("--check", help="Compare with this report without writing.")
    args = parser.parse_args()
    if args.output and args.check:
        parser.error("choose --output or --check")
    corpus_hash, scenes = load_scenes()
    manifest = json.loads(MODEL_MANIFEST.read_text(encoding="utf-8"))
    control = next(s for s in manifest["controls"] if s["modelId"] == "yolov8n-int8-control-416")
    specs = [(control, "tflite"), *((s, "onnx") for s in manifest["candidates"])]
    models: list[dict[str, object]] = []
    for spec, runtime in specs:
        detector = Detector(spec, runtime)
        results = [evaluate_scene(detector, scene) for scene in scenes]
        models.append({
            "modelId": spec["modelId"],
            "artifactSha256": spec["artifactSha256"],
            "artifactLicense": spec["license"],
            "runtime": runtime,
            "decoderId": spec["decoderId"],
            "inputSize": detector.size,
            "summary": summarize(results),
            "scenes": results,
        })
    import tensorflow as tf

    report = {
        "schemaVersion": 1,
        "benchmarkId": "bagdar-blender-detector-diagnostic-v1",
        "scope": "desktop synthetic single-frame class-agnostic forward-box diagnostic",
        "toolSha256": sha256(Path(__file__)),
        "corpusId": "blender-egocentric-v1",
        "corpusManifestSha256": corpus_hash,
        "modelManifestSha256": sha256(MODEL_MANIFEST),
        "sceneCount": len(scenes),
        "protocol": {
            "preprocess": "PIL bilinear aspect-preserving letterbox, RGB/255, padding 114; NHWC for TFLite, NCHW for ONNX",
            "confidenceThreshold": CONFIDENCE,
            "classAwareNmsIou": NMS_IOU,
            "forwardRule": "box center in middle image third",
            "maskOverlapRule": "reported if a box intersects central hazard-mask pixels; no class correctness implied",
            "interpretation": "forward box is detector evidence only, not a Bagdar alert or clearance decision",
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
            "synthetic 96x72 primitive RGB is not representative camera validation",
            "single images cannot establish temporal stability or moving-threat direction",
            "forward boxes are not production geometry or actual user alerts",
            "model license/provenance and named-device gates remain open",
        ],
    }
    rendered = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.check:
        path = checked_output_path(args.check)
        if path.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"Blender detector report drift: {args.check}")
        print(f"Blender detector report matches: {args.check}")
    elif args.output:
        path = checked_output_path(args.output)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8")
        print(f"Wrote {path.relative_to(REPO_ROOT)}")
    else:
        print(rendered, end="")


def checked_output_path(relative: str) -> Path:
    path = (REPO_ROOT / relative).resolve()
    if Path(relative).is_absolute() or not path.is_relative_to(REPO_ROOT):
        raise ValueError(f"output must stay inside repository: {relative}")
    return path


if __name__ == "__main__":
    main()

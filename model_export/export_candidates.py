from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

import onnx
import tflite
import ultralytics
from ultralytics import YOLO


REPO_ROOT = Path(__file__).resolve().parent.parent
EXPORT_ROOT = REPO_ROOT / "model_export"
CANDIDATE_ROOT = EXPORT_ROOT / "candidates"


@dataclass(frozen=True)
class ExportSpec:
    model_id: str
    source: str
    output: str
    image_size: int
    expected_output: tuple[int, ...]
    decoder_id: str


SPECS = (
    ExportSpec(
        "yolo11n-onnx-320-experiment",
        "model_export/yolo11n.pt",
        "model_export/candidates/yolo11n_320.onnx",
        320,
        (1, 84, 2100),
        "yolov8-v11-bcn-v1",
    ),
    ExportSpec(
        "yolo11n-onnx-416-experiment",
        "model_export/yolo11n.pt",
        "model_export/candidates/yolo11n_416.onnx",
        416,
        (1, 84, 3549),
        "yolov8-v11-bcn-v1",
    ),
    ExportSpec(
        "yolo26n-onnx-416-experiment",
        "model_export/yolo26n.pt",
        "model_export/candidates/yolo26n_416.onnx",
        416,
        (1, 300, 6),
        "yolo26-end2end-bnc-v1",
    ),
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tensor_shape(value) -> list[int]:
    return [dimension.dim_value for dimension in value.type.tensor_type.shape.dim]


def export(spec: ExportSpec) -> None:
    source = REPO_ROOT / spec.source
    target = REPO_ROOT / spec.output
    if not source.is_file():
        raise FileNotFoundError(source)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="bagdar-export-", dir=EXPORT_ROOT) as raw:
        temp_dir = Path(raw)
        temp_source = temp_dir / f"{target.stem}.pt"
        shutil.copy2(source, temp_source)
        generated = Path(
            YOLO(str(temp_source)).export(
                format="onnx",
                imgsz=spec.image_size,
                opset=17,
                simplify=True,
                dynamic=False,
                nms=False,
                device="cpu",
            )
        )
        shutil.copy2(generated, target)


def inspect_onnx(spec: ExportSpec) -> dict[str, object]:
    source = REPO_ROOT / spec.source
    artifact = REPO_ROOT / spec.output
    if not artifact.is_file():
        raise FileNotFoundError(artifact)
    model = onnx.load(artifact)
    onnx.checker.check_model(model)
    if len(model.graph.input) != 1 or len(model.graph.output) != 1:
        raise ValueError(f"{spec.model_id}: expected one input and one output")
    input_shape = tensor_shape(model.graph.input[0])
    output_shape = tensor_shape(model.graph.output[0])
    expected_input = [1, 3, spec.image_size, spec.image_size]
    if input_shape != expected_input:
        raise ValueError(f"{spec.model_id}: input {input_shape} != {expected_input}")
    if output_shape != list(spec.expected_output):
        raise ValueError(
            f"{spec.model_id}: output {output_shape} != {spec.expected_output}"
        )
    metadata = {item.key: item.value for item in model.metadata_props}
    if "AGPL-3.0" not in metadata.get("license", ""):
        raise ValueError(f"{spec.model_id}: missing pinned AGPL metadata")
    return {
        "modelId": spec.model_id,
        "status": "exportedExperiment",
        "sourcePath": spec.source,
        "sourceSha256": sha256(source),
        "artifactPath": spec.output,
        "artifactSha256": sha256(artifact),
        "artifactBytes": artifact.stat().st_size,
        "format": "onnx",
        "opset": max(item.version for item in model.opset_import),
        "input": {"name": model.graph.input[0].name, "shape": input_shape},
        "output": {"name": model.graph.output[0].name, "shape": output_shape},
        "decoderId": spec.decoder_id,
        "license": metadata.get("license"),
        "exportCommand": (
            f"yolo export model={spec.source} format=onnx "
            f"imgsz={spec.image_size} opset=17 simplify=True "
            "dynamic=False nms=False device=cpu"
        ),
        "ultralyticsVersion": metadata.get("version"),
    }


def inspect_tflite_control() -> dict[str, object]:
    path = REPO_ROOT / "assets/yolov8n_int8.tflite"
    model = tflite.Model.GetRootAsModel(path.read_bytes(), 0)
    graph = model.Subgraphs(0)
    input_tensor = graph.Tensors(graph.Inputs(0))
    output_tensor = graph.Tensors(graph.Outputs(0))
    input_shape = [input_tensor.Shape(i) for i in range(input_tensor.ShapeLength())]
    output_shape = [
        output_tensor.Shape(i) for i in range(output_tensor.ShapeLength())
    ]
    if input_shape != [1, 416, 416, 3] or output_shape != [1, 84, 3549]:
        raise ValueError(
            f"YOLOv8 control tensor drift: input={input_shape}, output={output_shape}"
        )
    return {
        "modelId": "yolov8n-int8-control-416",
        "status": "productionControl",
        "artifactPath": "assets/yolov8n_int8.tflite",
        "artifactSha256": sha256(path),
        "artifactBytes": path.stat().st_size,
        "format": "tflite-float-io-int8-weights",
        "input": {"name": "images", "shape": input_shape},
        "output": {"name": "Identity", "shape": output_shape},
        "decoderId": "flutter-vision-yolov8-bcn-v1",
        "license": "provenance-review-required",
    }


def inspect_depth_control() -> dict[str, object]:
    param = REPO_ROOT / "assets/midas_small.ncnn.param"
    weights = REPO_ROOT / "assets/midas_small.ncnn.bin"
    return {
        "modelId": "midas-small-ncnn",
        "status": "productionControl",
        "artifactPaths": [
            "assets/midas_small.ncnn.param",
            "assets/midas_small.ncnn.bin",
        ],
        "artifactSha256": {
            "param": sha256(param),
            "bin": sha256(weights),
        },
        "input": {"name": "0", "shape": [1, 3, 256, 256]},
        "output": {"name": "797", "shape": [256, 256]},
        "semantics": "relativeProximity",
        "preprocessId": "yuv420-rgb01-chw-256-rotate-mirror-crop-stretch-v1",
        "license": "checkpoint-provenance-review-required",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--export", action="store_true")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify that the committed manifest matches without writing it.",
    )
    parser.add_argument(
        "--output",
        default="model_export/candidates/manifest.json",
    )
    args = parser.parse_args()

    if args.export:
        for spec in SPECS:
            export(spec)

    manifest = {
        "schemaVersion": 1,
        "generator": "model_export/export_candidates.py",
        "environment": {
            "ultralytics": ultralytics.__version__,
            "onnx": onnx.__version__,
        },
        "controls": [inspect_tflite_control(), inspect_depth_control()],
        "candidates": [inspect_onnx(spec) for spec in SPECS],
    }
    rendered = json.dumps(manifest, indent=2) + "\n"
    output = REPO_ROOT / args.output
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != rendered:
            raise SystemExit(
                f"Candidate manifest drift: {output.relative_to(REPO_ROOT)}"
            )
        print(
            f"Verified {len(SPECS)} candidates; manifest matches "
            f"{output.relative_to(REPO_ROOT)}"
        )
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    print(f"Verified {len(SPECS)} candidates; wrote {output.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()

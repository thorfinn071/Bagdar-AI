from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import ultralytics
from ultralytics import YOLO
from ultralytics.utils import ASSETS


REPO_ROOT = Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_candidate(candidate: dict[str, object], sources: list[Path]) -> dict[str, object]:
    artifact = REPO_ROOT / str(candidate["artifactPath"])
    actual_hash = sha256(artifact)
    if actual_hash != candidate["artifactSha256"]:
        raise ValueError(f"artifact hash mismatch: {artifact}")
    input_size = int(candidate["input"]["shape"][2])
    model = YOLO(str(artifact), task="detect")
    predictions: list[dict[str, object]] = []
    for source in sources:
        result = model.predict(
            source=str(source),
            imgsz=input_size,
            conf=0.25,
            iou=0.45,
            save=False,
            verbose=False,
            device="cpu",
        )[0]
        boxes: list[dict[str, object]] = []
        if result.boxes is not None:
            xyxyn = result.boxes.xyxyn.cpu().tolist()
            classes = result.boxes.cls.cpu().tolist()
            scores = result.boxes.conf.cpu().tolist()
            order = sorted(range(len(scores)), key=lambda index: (-scores[index], index))
            for index in order:
                x1, y1, x2, y2 = (round(float(value), 7) for value in xyxyn[index])
                center_x = (x1 + x2) / 2
                sector = "left" if center_x < 1 / 3 else "right" if center_x > 2 / 3 else "forward"
                boxes.append(
                    {
                        "classId": int(classes[index]),
                        "score": round(float(scores[index]), 7),
                        "boxNormalized": [x1, y1, x2, y2],
                        "sector": sector,
                    }
                )
        predictions.append(
            {
                "sourceId": source.name.removesuffix(source.suffix),
                "sourceSha256": sha256(source),
                "sourceLicenseStatus": "blocked_pending_asset_provenance_review",
                "detections": boxes,
            }
        )
    return {
        "modelId": candidate["modelId"],
        "artifactSha256": actual_hash,
        "decoderId": candidate["decoderId"],
        "preprocessId": f"ultralytics-letterbox-rgb01-{input_size}-v1",
        "inputSize": input_size,
        "licenseStatus": "blocked_pending_distribution_review",
        "predictions": predictions,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="model_export/candidates/manifest.json")
    parser.add_argument(
        "--output",
        default=None,
        help="Write JSON only when an explicit path is supplied.",
    )
    parser.add_argument(
        "--check",
        default=None,
        help="Compare generated JSON with a committed fixture without writing.",
    )
    args = parser.parse_args()
    manifest_path = REPO_ROOT / args.manifest
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    sources = [Path(ASSETS) / "bus.jpg", Path(ASSETS) / "zidane.jpg"]
    for source in sources:
        if not source.exists():
            raise FileNotFoundError(source)
    report = {
        "schemaVersion": 1,
        "corpusId": "ultralytics-installed-assets-derived-v1",
        "scope": "real-onnx-output-correctness-and-downstream-shadow-replay",
        "sourceHandling": "derived-boxes-only-no-rgb-committed",
        "sourcePackage": {
            "name": "ultralytics",
            "version": ultralytics.__version__,
            "assetDirectory": str(Path(ASSETS)),
            "licenseStatus": "blocked_pending_asset_provenance_review",
        },
        "environment": {
            "runtime": "ultralytics-onnxruntime-cpu",
            "manifestSha256": sha256(manifest_path),
        },
        "models": [run_candidate(candidate, sources) for candidate in manifest["candidates"]],
        "promotionAllowed": False,
        "blockingReasons": [
            "source asset provenance/license review",
            "no Blender RGB/depth ground truth corpus",
            "no production YOLOv8 control predictions in the same runtime",
            "no named-device latency/thermal evidence",
        ],
    }
    rendered = json.dumps(report, indent=2) + "\n"
    if args.check:
        expected = (REPO_ROOT / args.check).read_text(encoding="utf-8")
        if expected != rendered:
            raise SystemExit(f"Prediction fixture drift: {args.check}")
        print(f"Prediction fixture matches: {args.check}")
    elif args.output:
        output = REPO_ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {output.relative_to(REPO_ROOT)}")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()

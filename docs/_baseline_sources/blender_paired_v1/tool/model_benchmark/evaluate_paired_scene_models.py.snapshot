"""Real pinned production-control inference on new RGB; truth is scoring-only."""
from __future__ import annotations

import argparse
import gzip
import json
import time
from pathlib import Path
import numpy as np
from PIL import Image
from verify_paired_scene_corpus import CORPUS, ROOT, checked, load_corpus, read_json, sha

OUT = ROOT / "docs/_baseline_logs"


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def finalize(name, report, samples, check):
    path = OUT / f"blender_paired_{name}.json"
    if check:
        if read_json(path) != report:
            raise ValueError(f"Pinned inference/report drift: {name}")
    else:
        if path.exists():
            raise ValueError("Never replace an existing baseline; use --check or a new version")
        save(path, report)
        timings = [r["totalMs"] for r in samples]
        save(OUT / f"blender_paired_{name}_timing.json", {
            "scope": "desktop CPU, one inference thread; includes file decode/preprocess/inference; excludes real capture/rendering/runtime/audio",
            "sourceManifestSha256": sha(CORPUS / "corpus-manifest.json"), "warmupInferences": 3,
            "p50Ms": float(np.percentile(timings, 50)), "p95Ms": float(np.percentile(timings, 95)), "frames": samples})


def evaluate_detector(check):
    import tensorflow as tf
    from evaluate_blender_detectors import MODEL_MANIFEST, Detector, evaluate_scene
    manifest, sequences = load_corpus()
    spec = next(s for s in read_json(MODEL_MANIFEST)["controls"] if s["modelId"] == "yolov8n-int8-control-416")
    detector = Detector(spec, "tflite")
    with Image.open(sequences[0]["frames"][0]["paths"]["rgb"]) as image:
        for _ in range(3):
            detector.infer(image.convert("RGB"))
    results, timings = [], []
    for seq in sequences:
        rows = []
        label = seq["labels"]
        for frame in seq["frames"]:
            start = time.perf_counter_ns()
            result = evaluate_scene(detector, {"sceneId": seq["sceneId"], "rgbPath": frame["paths"]["rgb"],
                "semanticPath": frame["paths"]["semantic"], "rgbSha256": frame["rgb"]["sha256"],
                "state": "blocked" if label["physicalHazard"] else "safe",
                "category": "object_like" if label["physicalHazard"] else "traversable",
                "expectedAction": "stopNow" if label["physicalHazard"] else "continueForward"})
            timings.append({"sceneId": seq["sceneId"], "frameIndex": frame["frameIndex"], "totalMs": (time.perf_counter_ns() - start) / 1e6})
            result.update({"frameIndex": frame["frameIndex"], "capturedOffsetMs": frame["capturedOffsetMs"],
                "compatibleCocoClassIds": label["compatibleCocoClassIds"],
                "classCompatibleVisiblePersonOverlap": any(d["classId"] in label["compatibleCocoClassIds"] and d["hazardMaskOverlapPixels"] > 0 for d in result["detections"])})
            rows.append(result)
        results.append({"sceneId": seq["sceneId"], "pair": seq["pair"], "frames": rows})
        print("PAIRED_YOLO " + seq["sceneId"], flush=True)
    report = {"schemaVersion": 1, "corpusId": manifest["corpusId"], "corpusManifestSha256": sha(CORPUS / "corpus-manifest.json"),
        "toolSha256": sha(__file__), "helperSha256": sha(ROOT / "tool/model_benchmark/evaluate_blender_detectors.py"),
        "modelManifestSha256": sha(MODEL_MANIFEST), "modelId": spec["modelId"], "artifactSha256": spec["artifactSha256"],
        "runtime": "desktop TFLite CPU (TensorFlow " + tf.__version__ + ")", "preprocessId": "pinned-PIL-bilinear-letterbox-RGB01-NHWC-416-v1",
        "maskAuthority": "scoring only; semantic overlap is not a stop decision", "promotionAllowed": False, "sequences": results}
    finalize("yolo", report, timings, check)


def evaluate_depth(check):
    import ncnn
    from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names
    manifest, sequences = load_corpus()
    controls = read_json(ROOT / "model_export/candidates/manifest.json")["controls"]
    model = next(s for s in controls if s["modelId"] == "midas-small-ncnn")
    if sha(PARAM) != model["artifactSha256"]["param"] or sha(BIN) != model["artifactSha256"]["bin"]:
        raise ValueError("MiDaS model drift")
    net = ncnn.Net()
    net.opt.use_vulkan_compute, net.opt.num_threads = False, 1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):
        raise RuntimeError("Pinned MiDaS load failed")
    inp, out = ncnn_blob_names(PARAM)
    def pixels(path):
        with Image.open(path) as image:
            a = np.asarray(image.convert("RGB"), dtype=np.float32) / 255
        ys, xs = np.arange(256) * a.shape[0] // 256, np.arange(256) * a.shape[1] // 256
        return a[ys[:, None], xs[None, :]]
    for _ in range(3):
        infer(net, inp, out, pixels(sequences[0]["frames"][0]["paths"]["rgb"]))
    folder = CORPUS / "ncnn"
    folder.mkdir(exist_ok=True)
    rows, timings = [], []
    for seq in sequences:
        for frame in seq["frames"]:
            start = time.perf_counter_ns()
            rgb = pixels(frame["paths"]["rgb"])
            prepared = time.perf_counter_ns()
            raw = infer(net, inp, out, rgb).astype("<f4").tobytes()
            finished = time.perf_counter_ns()
            path = folder / f"{seq['sceneId']}-{frame['frameIndex']:02d}.f32.gz"
            if check:
                if gzip.decompress(path.read_bytes()) != raw:
                    raise ValueError("NCNN output drift: " + path.name)
            else:
                path.write_bytes(gzip.compress(raw, mtime=0))
            rows.append({"sceneId": seq["sceneId"], "frameIndex": frame["frameIndex"], "rgbSha256": frame["rgb"]["sha256"],
                "asset": {"path": path.relative_to(CORPUS).as_posix(), "sha256": sha(path)}})
            timings.append({"sceneId": seq["sceneId"], "frameIndex": frame["frameIndex"],
                "preprocessingMs": (prepared - start) / 1e6, "inferenceMs": (finished - prepared) / 1e6, "totalMs": (finished - start) / 1e6})
        print("PAIRED_MIDAS " + seq["sceneId"], flush=True)
    report = {"schemaVersion": 1, "corpusId": manifest["corpusId"], "corpusManifestSha256": sha(CORPUS / "corpus-manifest.json"),
        "toolSha256": sha(__file__), "helperSha256": sha(ROOT / "tool/model_benchmark/generate_context_ncnn_depth.py"),
        "modelId": model["modelId"], "modelParamSha256": sha(PARAM), "modelBinSha256": sha(BIN),
        "runtime": "desktop NCNN CPU, one thread, Vulkan disabled", "preprocessId": "pinned-RGB01-CHW-256-nearest-stretch-v1",
        "mapWidth": 256, "mapHeight": 256, "mapEncoding": "little-endian-float32-row-major",
        "valueSemantics": "raw relative inverse depth; not metres", "newMetricFit": False, "promotionAllowed": False, "frames": rows}
    finalize("ncnn", report, timings, check)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["detector", "depth"])
    p.add_argument("--check", action="store_true")
    args = p.parse_args()
    (evaluate_detector if args.mode == "detector" else evaluate_depth)(args.check)

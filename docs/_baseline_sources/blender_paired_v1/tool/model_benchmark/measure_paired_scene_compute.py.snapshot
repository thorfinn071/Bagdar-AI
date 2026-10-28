"""Separate serial desktop timing with scoring/hash checks outside timed regions."""
import argparse
import gzip
import json
import time
import numpy as np
from PIL import Image
from verify_paired_scene_corpus import CORPUS, ROOT, load_corpus, read_json, sha


def main(mode):
    _, sequences = load_corpus()
    if mode == "detector":
        from evaluate_blender_detectors import MODEL_MANIFEST, Detector
        spec = next(s for s in read_json(MODEL_MANIFEST)["controls"] if s["modelId"] == "yolov8n-int8-control-416")
        detector = Detector(spec, "tflite")
        frozen = read_json(ROOT / "docs/_baseline_logs/blender_paired_yolo.json")
        records = {(s["sceneId"], f["frameIndex"]): f for s in frozen["sequences"] for f in s["frames"]}
        def compute(image):
            return detector.infer(image)
        def check(result, seq, frame):
            predicted, maximum = result
            row = records[(seq["sceneId"], frame["frameIndex"])]
            expected = [{k: d[k] for k in ("classId", "score", "boxNormalized", "forward")} for d in row["detections"]]
            if expected != predicted or row["maxRawScore"] != round(maximum, 6):
                raise ValueError("Timed detector output differs from frozen baseline")
        stage = "PIL bilinear letterbox + pinned TFLite CPU + decode/NMS"
    else:
        import ncnn
        from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names
        net = ncnn.Net()
        net.opt.use_vulkan_compute, net.opt.num_threads = False, 1
        if net.load_param(str(PARAM)) or net.load_model(str(BIN)):
            raise RuntimeError("MiDaS load failed")
        inp, out = ncnn_blob_names(PARAM)
        frozen = read_json(ROOT / "docs/_baseline_logs/blender_paired_ncnn.json")
        if sha(PARAM) != frozen["modelParamSha256"] or sha(BIN) != frozen["modelBinSha256"]:
            raise ValueError("Timed model differs from frozen baseline")
        records = {(r["sceneId"], r["frameIndex"]): r for r in frozen["frames"]}
        def compute(image):
            a = np.asarray(image, dtype=np.float32) / 255
            ys, xs = np.arange(256) * a.shape[0] // 256, np.arange(256) * a.shape[1] // 256
            return infer(net, inp, out, a[ys[:, None], xs[None, :]])
        def check(result, seq, frame):
            row = records[(seq["sceneId"], frame["frameIndex"])]
            if gzip.decompress((CORPUS / row["asset"]["path"]).read_bytes()) != result.astype("<f4").tobytes():
                raise ValueError("Timed NCNN output differs from frozen baseline")
        stage = "RGB01 nearest stretch + pinned one-thread NCNN CPU; Vulkan disabled"
    with Image.open(sequences[0]["frames"][0]["paths"]["rgb"]) as source:
        image = source.convert("RGB")
        for _ in range(5):
            compute(image)
    samples = []
    for round_id in range(2):
        for seq in sequences:
            for frame in seq["frames"]:
                start = time.perf_counter_ns()
                with Image.open(frame["paths"]["rgb"]) as source:
                    image = source.convert("RGB")
                decoded = time.perf_counter_ns()
                result = compute(image)
                finish = time.perf_counter_ns()
                check(result, seq, frame)
                samples.append({"round": round_id, "sceneId": seq["sceneId"], "frameIndex": frame["frameIndex"],
                    "decodeMs": (decoded - start) / 1e6, "computeMs": (finish - decoded) / 1e6, "decodeAndComputeMs": (finish - start) / 1e6})
        print(f"COMPUTE_ROUND {mode} {round_id}", flush=True)
    values = [r["computeMs"] for r in samples]
    report = {"scope": "serial desktop CPU stage timing; masks, annotations and output verification outside timed regions; not capture-to-alert or concurrent-load evidence",
        "stage": stage, "mode": mode, "toolSha256": sha(__file__), "corpusManifestSha256": sha(CORPUS / "corpus-manifest.json"),
        "warmupInferences": 5, "rounds": 2, "samples": len(samples), "outputsMatchFrozen": True,
        "computeP50Ms": float(np.percentile(values, 50)), "computeP95Ms": float(np.percentile(values, 95)), "computeMaxMs": max(values), "frames": samples}
    path = ROOT / f"docs/_baseline_logs/blender_paired_{mode}_compute_timing.json"
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: report[k] for k in ("mode", "samples", "computeP50Ms", "computeP95Ms", "outputsMatchFrozen")}))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["detector", "depth"])
    main(p.parse_args().mode)

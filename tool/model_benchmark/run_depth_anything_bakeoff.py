"""Real DA-V2 Small / MiDaS desktop inference, mobile exports and parity.

No camera, runtime model selection, source corpus, or old receipt is modified.
Ground-truth depth is opened only by the scoring helper after inference.
"""
from __future__ import annotations

import argparse
import copy
import importlib.metadata
import os
import platform
import subprocess
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import onnx
import onnxruntime as ort
import torch
import torch.nn.functional as functional

from depth_candidate_common import (CORPUS, EXPERIMENT, MODEL_ROOT, ROOT, load_frames,
                                    nearest_grid, normalize, parity, percentile, read, save, score, sha)

sys.path.insert(0, str(MODEL_ROOT / "upstream"))
sys.path.insert(0, str(MODEL_ROOT / "conversion_env/Lib/site-packages"))
from depth_anything_v2.dpt import DepthAnythingV2  # noqa: E402
import ncnn  # noqa: E402

SIZES = (280, 336, 518)
NCNN_RECIPE = 'explicit-MHA-folded-LayerScale-equivalent-v2'
PARAM = ROOT / "assets/midas_small.ncnn.param"
BIN = ROOT / "assets/midas_small.ncnn.bin"
PNNX = MODEL_ROOT / "conversion_env/Lib/site-packages/pnnx/pnnx.exe"
PREPROCESS = "official-RGB-ImageNet-aspect-preserving-cubic-multiple14-full-FOV-alignCornersTrue-v1"


class ExportableAttention(torch.nn.Module):
    """Equivalent eval-only attention expressed as an NCNN-supported module."""
    def __init__(self, original):
        super().__init__()
        dim = original.qkv.in_features
        self.attention = torch.nn.MultiheadAttention(dim, original.num_heads,
                                                    dropout=0, batch_first=True,
                                                    bias=original.qkv.bias is not None)
        with torch.no_grad():
            self.attention.in_proj_weight.copy_(original.qkv.weight)
            self.attention.in_proj_bias.copy_(original.qkv.bias)
            self.attention.out_proj.weight.copy_(original.proj.weight)
            self.attention.out_proj.bias.copy_(original.proj.bias)

    def forward(self, x):
        return self.attention(x, x, x, need_weights=False)[0]


def exportable_model(reference):
    model = copy.deepcopy(reference)
    for block in model.pretrained.blocks:
        block.attn = ExportableAttention(block.attn)
        # Fold per-output-channel LayerScale into the preceding linear layer.
        # gamma * (W x + b) == (gamma W) x + gamma b. This avoids a PNNX
        # broadcast across its implicit batch axis without changing inference.
        for scale_name, linear in (("ls1", block.attn.attention.out_proj),
                                   ("ls2", block.mlp.fc2)):
            scale = getattr(block, scale_name)
            if not hasattr(scale, "gamma"):
                raise ValueError("unexpected LayerScale contract")
            with torch.no_grad():
                linear.weight.mul_(scale.gamma[:, None])
                if linear.bias is not None:
                    linear.bias.mul_(scale.gamma)
            setattr(block, scale_name, torch.nn.Identity())
    # Force the traceable public MHA path rather than torch's native fast-path.
    torch.backends.mha.set_fastpath_enabled(False)
    return model.eval()


def load_model() -> DepthAnythingV2:
    source = read(MODEL_ROOT / "source-manifest.json")
    for relative, digest in source["files"].items():
        if sha(MODEL_ROOT / relative) != digest:
            raise ValueError("source/checkpoint drift: " + relative)
    model = DepthAnythingV2(encoder="vits", features=64, out_channels=[48, 96, 192, 384])
    model.load_state_dict(torch.load(MODEL_ROOT / "depth_anything_v2_vits.pth",
                                    map_location="cpu", weights_only=True))
    return model.eval()


def prepare(model, path: Path, size: int) -> tuple[torch.Tensor, tuple[int, int]]:
    image = cv2.imread(str(path))
    if image is None:
        raise ValueError("cannot decode corpus RGB")
    tensor, original_size = model.image2tensor(image, input_size=size)
    if tensor.shape[-2] % 14 or tensor.shape[-1] % 14:
        raise ValueError("DINOv2 dimensions must be multiples of 14")
    return tensor.contiguous(), original_size


def aligned_grid(raw: np.ndarray, original_size: tuple[int, int]) -> np.ndarray:
    if raw.ndim != 3 or raw.shape[0] != 1 or not np.isfinite(raw).all():
        raise ValueError("invalid DA-V2 output shape or numeric values")
    # Restore the original image before the common 256x256 scoring grid.
    full = functional.interpolate(torch.from_numpy(raw)[:, None], original_size,
                                  mode="bilinear", align_corners=True)[0, 0].numpy()
    return nearest_grid(full).astype("<f4")


def blob_names(param: Path) -> tuple[str, str]:
    lines = param.read_text(encoding="utf-8").splitlines()[2:]
    produced, consumed, inputs = [], set(), []
    for line in lines:
        parts = line.split()
        if len(parts) < 4:
            continue
        bottom, top = int(parts[2]), int(parts[3])
        consumed.update(parts[4:4 + bottom])
        outputs = parts[4 + bottom:4 + bottom + top]
        produced.extend(outputs)
        if parts[0] == "Input":
            inputs.extend(outputs)
    outputs = [name for name in produced if name not in consumed]
    if len(inputs) != 1 or len(outputs) != 1:
        raise ValueError("expected single input/output NCNN graph")
    return inputs[0], outputs[0]


def ncnn_net(param: Path, weights: Path):
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.opt.num_threads = 1
    # CPU conversion parity: same FP32 execution for both FP32/FP16 weight files.
    net.opt.use_fp16_packed = False
    net.opt.use_fp16_storage = False
    net.opt.use_fp16_arithmetic = False
    if net.load_param(str(param)) or net.load_model(str(weights)):
        raise RuntimeError("NCNN model initialization failed")
    return net, blob_names(param)


def ncnn_infer(net, names, chw: np.ndarray) -> np.ndarray:
    channels, height, width = chw.shape
    mat = ncnn.Mat(width, height, channels)
    for channel in range(channels):
        np.copyto(np.array(mat.channel(channel), copy=False), chw[channel])
    extractor = net.create_extractor()
    if extractor.input(names[0], mat):
        raise RuntimeError("NCNN input rejected")
    code, output = extractor.extract(names[1])
    if code:
        raise RuntimeError("NCNN inference failed: " + str(code))
    return np.array(output, copy=True).astype(np.float32).reshape(1, output.h, output.w)


def exports(model, frames) -> dict:
    records = {}
    portable_model = exportable_model(model)
    log_dir = EXPERIMENT / "conversion_logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    with torch.inference_mode():
        for size in SIZES[:2]:
            tensor, _ = prepare(model, frames[0]["paths"]["rgb"], size)
            base = MODEL_ROOT / f"dav2_small_short{size}"
            onnx_path = base.with_suffix(".onnx")
            trace_path = MODEL_ROOT / f"dav2_small_short{size}_mha_ls_v2.pt"
            print(f"Exporting DA-V2 {size}, input {list(tensor.shape)}", flush=True)
            if not onnx_path.exists():
                torch.onnx.export(model, tensor, str(onnx_path), input_names=["images"],
                                  output_names=["relative_inverse_depth"], opset_version=17,
                                  dynamo=False, do_constant_folding=True)
            graph = onnx.load(str(onnx_path))
            onnx.checker.check_model(graph)
            equivalence = parity(aligned_grid(model(tensor).numpy(), (192, 256)),
                                 aligned_grid(portable_model(tensor).numpy(), (192, 256)))
            if not equivalence['passed']:
                raise ValueError('MHA export adapter is not equivalent to official reference')
            if not trace_path.exists():
                torch.jit.trace(portable_model, tensor, check_trace=False).save(str(trace_path))
            for fp16 in (0, 1):
                stem = f"dav2_small_short{size}_mha_ls_v2_weights{'fp16' if fp16 else 'fp32'}"
                param, weights = MODEL_ROOT / f"{stem}.param", MODEL_ROOT / f"{stem}.bin"
                command = [str(PNNX), str(trace_path),
                           "inputshape=[" + ",".join(map(str, tensor.shape)) + "]",
                           f"fp16={fp16}", f"ncnnparam={param}", f"ncnnbin={weights}",
                           f"pnnxparam={MODEL_ROOT / (stem + '.pnnx.param')}",
                           f"pnnxbin={MODEL_ROOT / (stem + '.pnnx.bin')}",
                           f"pnnxpy={MODEL_ROOT / (stem + '_pnnx.py')}",
                           f"ncnnpy={MODEL_ROOT / (stem + '_ncnn.py')}"]
                log = log_dir / f"{stem}.txt"
                if not param.exists() or not weights.exists():
                    with log.open("w", encoding="utf-8") as output:
                        result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                                cwd=MODEL_ROOT, timeout=600)
                    if result.returncode:
                        raise RuntimeError("pnnx conversion failed; see " + str(log))
                if not param.exists() or not weights.exists():
                    raise RuntimeError("pnnx produced no NCNN artifact")
                if any(text in log.read_text(encoding='utf-8') for text in
                       ('not supported', 'not implemented', 'unsupported operator')):
                    raise RuntimeError('PNNX reported unsupported operations; see ' + str(log))
                key = f"dav2_small_short{size}_weights{'fp16' if fp16 else 'fp32'}"
                records[key] = {"paramPath": param.relative_to(ROOT).as_posix(), "paramSha256": sha(param),
                                 "binPath": weights.relative_to(ROOT).as_posix(), "binSha256": sha(weights),
                                 "binBytes": weights.stat().st_size, "command": command,
                                 "conversionLogSha256": sha(log), "inputShape": list(tensor.shape),
                                 "outputShape": [1, int(tensor.shape[-2]), int(tensor.shape[-1])],
                                 "fp16Weights": bool(fp16), "mobileRuntimeValidated": False,
                                 "conversionRecipe": NCNN_RECIPE, "attentionAdapterParity": equivalence}
            records[f"dav2_small_short{size}_onnx"] = {
                "path": onnx_path.relative_to(ROOT).as_posix(), "sha256": sha(onnx_path),
                "bytes": onnx_path.stat().st_size, "inputShape": list(tensor.shape),
                "opset": 17, "mobileRuntimeValidated": False}
    manifest = {"schemaVersion": 1, "checkpointSha256": sha(MODEL_ROOT / "depth_anything_v2_vits.pth"),
                "sourceManifestSha256": sha(MODEL_ROOT / "source-manifest.json"),
                "versions": {name: importlib.metadata.version(name) for name in
                             ("torch", "onnx", "onnxruntime", "pnnx", "ncnn")},
                "preprocessId": PREPROCESS, "conversionRecipe": NCNN_RECIPE,
                "artifacts": records, "promotionAllowed": False}
    save(MODEL_ROOT / "export-manifest.json", manifest)
    return manifest


def run_variant(model, frames, variant: str, backend: str, size: int, artifacts: dict) -> dict:
    init_start = time.perf_counter_ns()
    if backend == "onnx":
        options = ort.SessionOptions()
        options.intra_op_num_threads = options.inter_op_num_threads = 1
        session = ort.InferenceSession(str(MODEL_ROOT / f"dav2_small_short{size}.onnx"),
                                      options, providers=["CPUExecutionProvider"])
        expected_shape = artifacts[f"dav2_small_short{size}_onnx"]["inputShape"]
        if session.get_inputs()[0].shape != expected_shape:
            raise ValueError("ONNX input contract drift")
        def call(tensor):
            return session.run(None, {"images": tensor.numpy()})[0]
    elif backend.startswith("ncnn"):
        stem = f"dav2_small_short{size}_weights{'fp16' if backend.endswith('fp16') else 'fp32'}"
        artifact = artifacts[stem]
        net, names = ncnn_net(ROOT / artifact['paramPath'], ROOT / artifact['binPath'])
        def call(tensor):
            return ncnn_infer(net, names, tensor.numpy()[0])
    elif backend == "midas":
        net, names = ncnn_net(PARAM, BIN)
        def call(tensor):
            return ncnn_infer(net, names, tensor.numpy()[0])
    else:
        def call(tensor):
            return model(tensor).numpy()
    init_ms = (time.perf_counter_ns() - init_start) / 1e6

    def input_for(frame):
        if backend == "midas":
            image = cv2.imread(str(frame["paths"]["rgb"]))
            rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB).astype(np.float32) / 255
            chw = np.transpose(nearest_grid(rgb), (2, 0, 1)).copy()
            return torch.from_numpy(chw)[None], (192, 256)
        return prepare(model, frame["paths"]["rgb"], size)

    with torch.inference_mode():
        first, original_size = input_for(frames[0])
        for _ in range(3):
            call(first)
        rows, previous = [], {}
        for frame in frames:
            start = time.perf_counter_ns()
            tensor, original_size = input_for(frame)
            prepared = time.perf_counter_ns()
            prediction = call(tensor)
            inferred = time.perf_counter_ns()
            raw = prediction[0].astype("<f4") if backend == "midas" else aligned_grid(prediction, original_size)
            relative = normalize(raw)
            ended = time.perf_counter_ns()
            filename = f"maps/{variant}/{frame['sceneId']}_f{frame['frameIndex']}.f32"
            path = EXPERIMENT / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw.tobytes())
            row = {"sceneId": frame["sceneId"], "frameIndex": frame["frameIndex"],
                   "capturedOffsetMs": frame["capturedOffsetMs"], "expectedAction": frame["expectedAction"],
                   "rgbSha256": frame["rgb"]["sha256"], "mapPath": filename, "mapSha256": sha(path),
                   "preprocessMs": (prepared - start) / 1e6, "inferenceMs": (inferred - prepared) / 1e6,
                   "alignmentNormalizeMs": (ended - inferred) / 1e6, "imageToMapMs": (ended - start) / 1e6,
                   "rawMin": float(raw.min()), "rawMax": float(raw.max()), **score(raw, frame)}
            # Camera moves; this is screen-grid variation, not motion-compensated flicker.
            earlier = previous.get(frame["sceneId"])
            row["screenGridTemporalMeanAbsDelta"] = None if earlier is None else float(np.abs(relative - earlier).mean())
            previous[frame["sceneId"]] = relative.copy()
            if backend not in {"torch", "midas"}:
                reference_path = EXPERIMENT / f"maps/dav2_torch_short{size}/{path.name}"
                reference = np.fromfile(reference_path, dtype="<f4").reshape(256, 256)
                row["conversionParity"] = parity(reference, raw)
            rows.append(row)
        print(f"Completed {variant}: {len(rows)} real RGB frames", flush=True)
    ranks = [row["rankRhoToOracleInverseDepth"] for row in rows if row["rankRhoToOracleInverseDepth"] is not None]
    correct = sum(row["boundaryOrderingCorrectPairs"] for row in rows)
    pairs = sum(row["boundaryOrderingPairs"] for row in rows)
    if backend == 'midas':
        model_hash = f"sha256:param:{sha(PARAM)};bin:{sha(BIN)}"
    elif backend.startswith('ncnn'):
        artifact = artifacts[f"dav2_small_short{size}_weights{'fp16' if backend.endswith('fp16') else 'fp32'}"]
        model_hash = f"sha256:param:{artifact['paramSha256']};bin:{artifact['binSha256']}"
    elif backend == 'onnx':
        model_hash = 'sha256:onnx:' + artifacts[f'dav2_small_short{size}_onnx']['sha256']
    else:
        model_hash = 'sha256:checkpoint:' + sha(MODEL_ROOT / 'depth_anything_v2_vits.pth')
    return {"variantId": variant, "backend": backend, "shortSide": size,
            "modelId": "midas-small-ncnn" if backend == "midas" else "depth-anything-v2-small-relative-experiment",
            "preprocessId": "RGB01-nearest-stretch256-full-FOV-normalization-inside-MiDaS-v1" if backend == "midas" else PREPROCESS + f"-short{size}",
            "inputShape": list(first.shape), "mapWidth": 256, "mapHeight": 256,
            "modelHash": model_hash,
            "initializationMs": init_ms, "warmupInferences": 3, "frames": rows,
            "summary": {"completedFrames": len(rows), "failedFrames": 0,
                        "meanFrameRankRho": float(np.mean(ranks)) if ranks else None,
                        "boundaryOrderingAccuracy": correct / pairs if pairs else None,
                        "imageToMapP50Ms": percentile([row["imageToMapMs"] for row in rows], 0.5),
                        "imageToMapP95Ms": percentile([row["imageToMapMs"] for row in rows], 0.95),
                        "inferenceP50Ms": percentile([row["inferenceMs"] for row in rows], 0.5),
                        "inferenceP95Ms": percentile([row["inferenceMs"] for row in rows], 0.95),
                        "conversionParityPassed": all(row.get("conversionParity", {"passed": True})["passed"] for row in rows)}}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--exports-only", action="store_true")
    args = parser.parse_args()
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    cv2.setNumThreads(1)
    corpus, frames = load_frames()
    model = load_model()
    EXPERIMENT.mkdir(parents=True, exist_ok=True)
    controls = [PARAM, BIN, ROOT / "assets/yolov8n_int8.tflite", ROOT / "pubspec.yaml",
                ROOT / "lib/services/model_service.dart"]
    baseline = {path.relative_to(ROOT).as_posix(): sha(path) for path in controls}
    baseline_path = EXPERIMENT / "production-controls-before.json"
    if baseline_path.exists() and read(baseline_path) != baseline:
        raise ValueError("production controls changed during experiment")
    save(baseline_path, baseline)
    export_manifest = exports(model, frames)
    if args.exports_only:
        return
    report = {"schemaVersion": 1, "experimentId": "dav2-vs-midas-context-desktop-v1",
              "corpusId": corpus["corpusId"], "corpusManifestSha256": sha(CORPUS / "corpus-manifest.json"),
              "sourceManifestSha256": sha(MODEL_ROOT / "source-manifest.json"),
              "exportManifestSha256": sha(MODEL_ROOT / "export-manifest.json"),
              "scriptSha256": sha(Path(__file__)), "helperSha256": sha(ROOT / "tool/model_benchmark/depth_candidate_common.py"),
              "machine": {"platform": platform.platform(), "processor": platform.processor(),
                          "python": platform.python_version(), "inferenceThreads": 1,
                          "versions": export_manifest["versions"]},
              "scope": "desktop CPU real RGB inference, full-FOV; no Android YUV/camera/GPU/device/alerts",
              "mapSemantics": "raw relative inverse depth, larger nearer; all variants aligned to 256x256 for replay",
              "timingOrigin": "file decode -> preprocess -> inference -> image alignment -> percentile normalization",
              "timingExcludes": ["camera", "scheduler", "transport", "Bagdar geometry", "TTS", "device thermals"],
              "temporalDiagnostic": "screen-grid delta includes real camera motion; not a flicker accuracy metric",
              "promotionAllowed": False, "variants": []}
    variants = [("midas_ncnn_control", "midas", 256)]
    variants += [(f"dav2_torch_short{size}", "torch", size) for size in SIZES]
    variants += [(f"dav2_onnx_short{size}", "onnx", size) for size in SIZES[:2]]
    variants += [(f"dav2_ncnn_short{size}_{precision}", "ncnn-" + precision, size)
                 for size in SIZES[:2] for precision in ("fp32", "fp16")]
    for variant, backend, size in variants:
        try:
            report["variants"].append(run_variant(model, frames, variant, backend, size, export_manifest["artifacts"]))
        except Exception as error:
            report["failedVariant"] = {"variantId": variant, "error": repr(error)}
            save(EXPERIMENT / "inference-report.json", report)
            raise
        save(EXPERIMENT / "inference-report.json", report)
    report["allConversionParityPassed"] = all(v["summary"]["conversionParityPassed"] for v in report["variants"])
    save(EXPERIMENT / "inference-report.json", report)
    print("Wrote inference/parity report to " + str(EXPERIMENT), flush=True)


if __name__ == "__main__":
    main()

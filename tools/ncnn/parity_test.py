"""Parity test: TFLite vs NCNN MiDaS Small.

Generates 5 synthetic inputs (256x256x3 normalized to [0,1]) and compares
inference outputs from both runtimes. Pass condition:
    mean abs diff < 0.03 over each output map (output values are normalized depths).

Run from repo root after `convert_midas.py`:
    python tools/ncnn/parity_test.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS = REPO_ROOT / "assets"
TOOLS = REPO_ROOT / "tools" / "ncnn"

TFLITE_PATH = ASSETS / "midas_small_int8.tflite"
NCNN_PARAM = ASSETS / "midas_small.ncnn.param"
NCNN_BIN = ASSETS / "midas_small.ncnn.bin"
REPORT = TOOLS / "parity_report.json"

INPUT_SIZE = 256
N_SAMPLES = 5
PASS_THRESHOLD = 0.03


def make_inputs(rng: np.random.Generator) -> list[np.ndarray]:
    """Synthetic but plausible inputs: gradients + noise + structured patterns."""
    samples = []
    
    g = np.linspace(0, 1, INPUT_SIZE, dtype=np.float32)
    samples.append(np.tile(g[None, :, None], (INPUT_SIZE, 1, 3)))
    
    g = np.linspace(0, 1, INPUT_SIZE, dtype=np.float32)
    samples.append(np.tile(g[:, None, None], (1, INPUT_SIZE, 3)))
    
    cb = np.indices((INPUT_SIZE, INPUT_SIZE)).sum(0) % 32 < 16
    samples.append(np.repeat(cb.astype(np.float32)[..., None], 3, axis=-1))
    
    samples.append(rng.random((INPUT_SIZE, INPUT_SIZE, 3), dtype=np.float32))
    
    yy, xx = np.mgrid[0:INPUT_SIZE, 0:INPUT_SIZE].astype(np.float32)
    dist = np.sqrt((yy - INPUT_SIZE / 2) ** 2 + (xx - INPUT_SIZE / 2) ** 2)
    disk = np.clip(1.0 - dist / (INPUT_SIZE / 2), 0.0, 1.0)
    samples.append(np.repeat(disk[..., None], 3, axis=-1))
    return samples


def run_tflite(inputs: list[np.ndarray]) -> list[np.ndarray]:
    try:
        import tensorflow as tf  
    except ImportError:
        pass
    try:
        from tflite_runtime.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite.python.interpreter import Interpreter

    interp = Interpreter(model_path=str(TFLITE_PATH))
    interp.allocate_tensors()
    in_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]

    outputs: list[np.ndarray] = []
    for arr in inputs:
        x = arr.astype(np.float32)[None, ...]
        if in_det["dtype"] == np.uint8:
            scale, zp = in_det["quantization"]
            x_q = np.clip(np.round(x / scale + zp), 0, 255).astype(np.uint8)
            interp.set_tensor(in_det["index"], x_q)
        else:
            interp.set_tensor(in_det["index"], x)
        interp.invoke()
        out = interp.get_tensor(out_det["index"])
        if out_det["dtype"] == np.uint8:
            scale, zp = out_det["quantization"]
            out = (out.astype(np.float32) - zp) * scale
        outputs.append(np.squeeze(out).astype(np.float32))
    return outputs


def run_ncnn(inputs: list[np.ndarray]) -> list[np.ndarray]:
    try:
        import ncnn
    except ImportError:
        sys.exit(
            "Python ncnn package missing. Install via:\n"
            "    pip install ncnn  # (may require building from source on Windows)\n"
            "If unavailable, use the on-device parity check (run app + log outputs)."
        )

    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.load_param(str(NCNN_PARAM))
    net.load_model(str(NCNN_BIN))

    
    param_text = NCNN_PARAM.read_text()
    in_name = None
    out_name = None
    for line in param_text.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "Input" and in_name is None:
            in_name = parts[-1] if parts[-1].isidentifier() else parts[2]
    
    last_layer = [ln for ln in param_text.splitlines() if ln.strip()][-1]
    out_name = last_layer.split()[-1]

    if in_name is None or out_name is None:
        sys.exit(f"Could not parse blob names from {NCNN_PARAM}")

    outputs: list[np.ndarray] = []
    for arr in inputs:
        
        chw = np.transpose(arr, (2, 0, 1)).astype(np.float32)
        mat_in = ncnn.Mat(chw.shape[2], chw.shape[1], chw.shape[0])
        for c in range(chw.shape[0]):
            np.copyto(np.array(mat_in.channel(c), copy=False), chw[c])
        ex = net.create_extractor()
        ex.input(in_name, mat_in)
        ret, mat_out = ex.extract(out_name)
        if ret != 0:
            sys.exit(f"ncnn extract failed: ret={ret}")
        h, w = mat_out.h, mat_out.w
        out_np = np.array(mat_out, copy=True).reshape(h, w)
        outputs.append(out_np.astype(np.float32))
    return outputs


def compare(a: np.ndarray, b: np.ndarray) -> dict:
    a_n = (a - a.min()) / (a.max() - a.min() + 1e-9)
    b_n = (b - b.min()) / (b.max() - b.min() + 1e-9)
    diff = np.abs(a_n - b_n)
    return {
        "mean_abs_diff": float(diff.mean()),
        "max_abs_diff": float(diff.max()),
        "p99_diff": float(np.percentile(diff, 99)),
        "shape_a": list(a.shape),
        "shape_b": list(b.shape),
    }


def main() -> None:
    if not NCNN_PARAM.exists() or not NCNN_BIN.exists():
        sys.exit(f"Missing NCNN model. Run convert_midas.py first.\n  {NCNN_PARAM}\n  {NCNN_BIN}")

    rng = np.random.default_rng(42)
    inputs = make_inputs(rng)

    print("Running TFLite ...")
    tfl_out = run_tflite(inputs)
    print(f"  outputs: {[o.shape for o in tfl_out]}")

    print("Running NCNN ...")
    ncnn_out = run_ncnn(inputs)
    print(f"  outputs: {[o.shape for o in ncnn_out]}")

    results = []
    failures = 0
    for i, (a, b) in enumerate(zip(tfl_out, ncnn_out)):
        cmp = compare(a, b)
        cmp["sample"] = i
        cmp["pass"] = cmp["mean_abs_diff"] < PASS_THRESHOLD
        if not cmp["pass"]:
            failures += 1
        results.append(cmp)
        flag = "OK" if cmp["pass"] else "FAIL"
        print(
            f"  sample {i}: {flag}  mean={cmp['mean_abs_diff']:.4f}  "
            f"max={cmp['max_abs_diff']:.4f}  p99={cmp['p99_diff']:.4f}"
        )

    REPORT.write_text(json.dumps({
        "threshold": PASS_THRESHOLD,
        "failures": failures,
        "samples": results,
    }, indent=2))
    print(f"\nReport: {REPORT}")

    if failures:
        sys.exit(f"\nFAILED: {failures}/{len(results)} samples exceeded threshold {PASS_THRESHOLD}")
    print("\nPASS: NCNN parity acceptable.")


if __name__ == "__main__":
    main()

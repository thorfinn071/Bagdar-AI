"""TFLite -> ONNX -> NCNN FP16 conversion for MiDaS Small.

Run from repo root:
    python tools/ncnn/convert_midas.py

Pipeline:
    midas_small_int8.tflite (INT8)
        ↓ tflite2onnx (dequant to FP32)
    midas_small_fp32.onnx
        ↓ onnx2ncnn
    midas_small.ncnn.param + midas_small.ncnn.bin (FP32)
        ↓ ncnnoptimize -fp16
    midas_small.ncnn.param + midas_small.ncnn.bin (FP16, final)
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS = REPO_ROOT / "assets"
TOOLS = REPO_ROOT / "tools" / "ncnn"
BIN = TOOLS / "bin"

TFLITE_IN = ASSETS / "midas_small_int8.tflite"
ONNX_FP32 = TOOLS / "build" / "midas_small_fp32.onnx"
NCNN_FP32_PARAM = TOOLS / "build" / "midas_small_fp32.ncnn.param"
NCNN_FP32_BIN = TOOLS / "build" / "midas_small_fp32.ncnn.bin"
NCNN_OUT_PARAM = ASSETS / "midas_small.ncnn.param"
NCNN_OUT_BIN = ASSETS / "midas_small.ncnn.bin"


def find_binary(name: str) -> Path:
    """Locate ncnn CLI binary (onnx2ncnn / ncnnoptimize)."""
    suffix = ".exe" if os.name == "nt" else ""
    candidates = [
        BIN / f"{name}{suffix}",
        BIN / name,
    ]
    for c in candidates:
        if c.exists():
            return c
    in_path = shutil.which(name)
    if in_path:
        return Path(in_path)
    raise FileNotFoundError(
        f"Cannot find '{name}'. Place it in {BIN} or ensure it is on PATH.\n"
        f"Download from https://github.com/Tencent/ncnn/releases"
    )


def step(label: str) -> None:
    print(f"\n=== {label} ===", flush=True)


def run(cmd: list[str]) -> None:
    print("$ " + " ".join(str(c) for c in cmd), flush=True)
    result = subprocess.run(cmd, check=False)
    if result.returncode != 0:
        sys.exit(f"FAILED ({result.returncode}): {cmd[0]}")


def convert_tflite_to_onnx() -> None:
    step("1/3 TFLite → ONNX FP32 (tflite2onnx)")
    if not TFLITE_IN.exists():
        sys.exit(f"Missing input: {TFLITE_IN}")
    ONNX_FP32.parent.mkdir(parents=True, exist_ok=True)
    import tflite2onnx
    tflite2onnx.convert(str(TFLITE_IN), str(ONNX_FP32))
    print(f"OK: {ONNX_FP32} ({ONNX_FP32.stat().st_size / 1e6:.1f} MB)")


def convert_onnx_to_ncnn() -> None:
    step("2/3 ONNX → NCNN FP32 (onnx2ncnn)")
    onnx2ncnn = find_binary("onnx2ncnn")
    NCNN_FP32_PARAM.parent.mkdir(parents=True, exist_ok=True)
    run([
        str(onnx2ncnn),
        str(ONNX_FP32),
        str(NCNN_FP32_PARAM),
        str(NCNN_FP32_BIN),
    ])
    if not NCNN_FP32_PARAM.exists() or not NCNN_FP32_BIN.exists():
        sys.exit("onnx2ncnn did not produce output")
    print(f"OK: {NCNN_FP32_PARAM} ({NCNN_FP32_PARAM.stat().st_size / 1e3:.0f} KB)")
    print(f"OK: {NCNN_FP32_BIN} ({NCNN_FP32_BIN.stat().st_size / 1e6:.1f} MB)")


def optimize_to_fp16() -> None:
    step("3/3 NCNN FP32 → NCNN FP16 (ncnnoptimize)")
    ncnnoptimize = find_binary("ncnnoptimize")
    NCNN_OUT_PARAM.parent.mkdir(parents=True, exist_ok=True)
    run([
        str(ncnnoptimize),
        str(NCNN_FP32_PARAM),
        str(NCNN_FP32_BIN),
        str(NCNN_OUT_PARAM),
        str(NCNN_OUT_BIN),
        "65536",
    ])
    if not NCNN_OUT_PARAM.exists() or not NCNN_OUT_BIN.exists():
        sys.exit("ncnnoptimize did not produce output")
    print(f"OK: {NCNN_OUT_PARAM} ({NCNN_OUT_PARAM.stat().st_size / 1e3:.0f} KB)")
    print(f"OK: {NCNN_OUT_BIN} ({NCNN_OUT_BIN.stat().st_size / 1e6:.1f} MB)")


def main() -> None:
    convert_tflite_to_onnx()
    convert_onnx_to_ncnn()
    optimize_to_fp16()
    print("\n=== DONE ===")
    print(f"Final assets:\n  {NCNN_OUT_PARAM}\n  {NCNN_OUT_BIN}")
    print("\nNext: run `python tools/ncnn/parity_test.py` to verify outputs match TFLite.")


if __name__ == "__main__":
    main()

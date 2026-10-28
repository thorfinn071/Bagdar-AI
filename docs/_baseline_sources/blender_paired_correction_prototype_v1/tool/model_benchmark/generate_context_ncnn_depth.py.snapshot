"""Pin desktop NCNN MiDaS outputs for the contextual Blender shadow replay.

The RGB path matches the model's RGB01/CHW and nearest stretch contract, but
does not emulate Android YUV conversion or camera timing. Outputs are raw
inverse-depth float32, not metres or a claim of device parity.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import ncnn
import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-context-v3"
OUTPUT = ROOT / "test/fixtures/spatial_safety/blender-context-ncnn-depth-v1"
PARAM = ROOT / "assets/midas_small.ncnn.param"
BIN = ROOT / "assets/midas_small.ncnn.bin"
sys.path.insert(0, str(ROOT / "tools/ncnn"))
from parity_test import ncnn_blob_names  # noqa: E402


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def checked_asset(relative: str, expected: str) -> Path:
    if Path(relative).is_absolute() or ".." in Path(relative).parts or "\\" in relative:
        raise ValueError(f"unsafe corpus path: {relative}")
    path = (CORPUS / relative).resolve()
    if not path.is_relative_to(CORPUS.resolve()) or sha256_file(path) != expected:
        raise ValueError(f"corpus asset hash/path mismatch: {relative}")
    return path


def nearest_rgb(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        rgb = np.asarray(image.convert("RGB"), dtype=np.float32) / 255.0
    height, width = rgb.shape[:2]
    ys = np.arange(256) * height // 256
    xs = np.arange(256) * width // 256
    return rgb[ys[:, None], xs[None, :], :]


def depth_mm(path: Path) -> np.ndarray:
    with path.open("rb") as stream:
        magic = stream.readline().strip()
        dimensions = stream.readline().strip()
        maximum = stream.readline().strip()
        if magic != b"P5" or maximum != b"65535":
            raise ValueError(f"invalid oracle PGM: {path}")
        width, height = map(int, dimensions.split())
        payload = stream.read()
    if len(payload) != width * height * 2:
        raise ValueError(f"invalid oracle PGM size: {path}")
    return np.frombuffer(payload, dtype=">u2").reshape(height, width)


def rank_correlation(raw: np.ndarray, oracle_mm: np.ndarray) -> float | None:
    height, width = oracle_mm.shape
    ys = np.arange(256) * height // 256
    xs = np.arange(256) * width // 256
    oracle = oracle_mm[ys[:, None], xs[None, :]].astype(np.float64)
    valid = (oracle > 0) & np.isfinite(raw)
    if valid.sum() < 100:
        return None
    inverse_m = 1000.0 / oracle[valid]
    predicted = raw[valid].astype(np.float64)
    a = np.argsort(np.argsort(inverse_m, kind="stable"), kind="stable")
    b = np.argsort(np.argsort(predicted, kind="stable"), kind="stable")
    rho = float(np.corrcoef(a, b)[0, 1])
    return rho if np.isfinite(rho) else None


def infer(net: ncnn.Net, input_name: str, output_name: str, rgb: np.ndarray) -> np.ndarray:
    chw = np.transpose(rgb, (2, 0, 1)).astype(np.float32)
    mat = ncnn.Mat(256, 256, 3)
    for channel in range(3):
        np.copyto(np.array(mat.channel(channel), copy=False), chw[channel])
    extractor = net.create_extractor()
    if extractor.input(input_name, mat) != 0:
        raise RuntimeError("NCNN input failed")
    result, output = extractor.extract(output_name)
    if result != 0 or output.w != 256 or output.h != 256:
        raise RuntimeError(f"NCNN output failed: {result}, {output.w}x{output.h}")
    raw = np.array(output, copy=True).reshape(256, 256).astype("<f4")
    if not np.isfinite(raw).all() or float(np.ptp(raw)) < 1e-3:
        raise ValueError("invalid or degenerate NCNN depth output")
    return raw


def build(check: bool) -> None:
    corpus_path = CORPUS / "corpus-manifest.json"
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    if corpus["corpusId"] != "blender-context-v3" or corpus["schemaVersion"] != 2:
        raise ValueError("unexpected source corpus")
    if sha256_file(PARAM) != "d618bb98777ff7e7adeeef1c8cf50ede79c97c754876681d6a0b26330708e8d3":
        raise ValueError("NCNN param drift")
    if sha256_file(BIN) != "324412b094f3309c0c7acd506a06ccdc60296749ac382dc58431efdde0f13242":
        raise ValueError("NCNN bin drift")
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    if net.load_param(str(PARAM)) != 0 or net.load_model(str(BIN)) != 0:
        raise RuntimeError("NCNN model load failed")
    input_name, output_name = ncnn_blob_names(PARAM)
    frames = []
    for asset in sorted(corpus["assets"], key=lambda item: item["sceneId"]):
        for frame in sorted(asset["frames"], key=lambda item: item["frameIndex"]):
            rgb_path = checked_asset(frame["rgb"]["path"], frame["rgb"]["sha256"])
            oracle_path = checked_asset(frame["depth"]["path"], frame["depth"]["sha256"])
            raw = infer(net, input_name, output_name, nearest_rgb(rgb_path))
            relative = f"maps/{asset['sceneId']}_f{frame['frameIndex']}.f32"
            content = raw.tobytes(order="C")
            output_path = OUTPUT / relative
            if check:
                if not output_path.exists() or output_path.read_bytes() != content:
                    raise ValueError(f"NCNN depth map drift: {relative}")
            else:
                output_path.parent.mkdir(parents=True, exist_ok=True)
                output_path.write_bytes(content)
            frames.append({
                "sceneId": asset["sceneId"],
                "frameIndex": frame["frameIndex"],
                "rgbSha256": frame["rgb"]["sha256"],
                "oracleDepthSha256": frame["depth"]["sha256"],
                "mapPath": relative,
                "mapSha256": sha256_bytes(content),
                "rawMin": float(raw.min()),
                "rawMax": float(raw.max()),
                "rankRhoToOracleInverseMetres": rank_correlation(raw, depth_mm(oracle_path)),
            })
    manifest = {
        "schemaVersion": 1,
        "id": "blender-context-ncnn-depth-v1",
        "scope": "desktop NCNN CPU MiDaS output; no Android YUV, camera, or device evidence",
        "generatorSha256": sha256_file(Path(__file__)),
        "sourceCorpusId": corpus["corpusId"],
        "sourceCorpusManifestSha256": sha256_file(corpus_path),
        "modelId": "midas-small-ncnn",
        "modelParamSha256": sha256_file(PARAM),
        "modelBinSha256": sha256_file(BIN),
        "preprocessId": "rgb01-chw-256-nearest-stretch-no-crop-v1",
        "valueSemantics": "rawRelativeInverseDepthLargerNearer",
        "mapWidth": 256,
        "mapHeight": 256,
        "mapEncoding": "little-endian-float32-row-major",
        "runtime": f"ncnn-python-{getattr(ncnn, '__version__', 'unknown')}-cpu",
        "frames": frames,
    }
    rendered = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    manifest_path = OUTPUT / "manifest.json"
    if check:
        if not manifest_path.exists() or manifest_path.read_text(encoding="utf-8") != rendered:
            raise ValueError("NCNN depth manifest drift")
        print(f"NCNN depth maps match: {len(frames)} frames")
    else:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(rendered, encoding="utf-8")
        print(f"Wrote NCNN depth maps: {len(frames)} frames to {OUTPUT}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)

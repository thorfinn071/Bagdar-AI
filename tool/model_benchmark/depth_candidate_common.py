"""Hash-checked synthetic depth experiment helpers; ground truth is scoring only."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / "test/fixtures/spatial_safety/blender-context-v3"
EXPERIMENT = ROOT / "scratch/depth-anything-v2-bakeoff-2026-10-05"
MODEL_ROOT = ROOT / "model_export/depth_anything_v2"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, allow_nan=False) + "\n", encoding="utf-8")


def checked(root: Path, relative: str, digest: str) -> Path:
    if Path(relative).is_absolute() or ".." in Path(relative).parts or "\\" in relative:
        raise ValueError("unsafe relative asset path")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()) or sha(path) != digest:
        raise ValueError("asset path/hash mismatch: " + relative)
    return path


def load_frames() -> tuple[dict, list[dict]]:
    corpus = read(CORPUS / "corpus-manifest.json")
    if corpus["corpusId"] != "blender-context-v3" or corpus["schemaVersion"] != 2:
        raise ValueError("unexpected contextual corpus")
    frames = []
    keys = set()
    for scene in sorted(corpus["assets"], key=lambda row: row["sceneId"]):
        if scene["state"] not in {"safe", "blocked", "moving"}:
            raise ValueError("unlabelled scene state")
        for frame in sorted(scene["frames"], key=lambda row: row["frameIndex"]):
            key = (scene["sceneId"], frame["frameIndex"])
            if key in keys:
                raise ValueError("duplicate frame")
            keys.add(key)
            paths = {name: checked(CORPUS, frame[name]["path"], frame[name]["sha256"])
                     for name in ("rgb", "depth", "semantic")}
            frames.append({**frame, "sceneId": scene["sceneId"], "state": scene["state"],
                           "expectedAction": "continueForward" if scene["state"] == "safe" else "stopNow",
                           "paths": paths})
    if len(frames) != 18 or len({f["sceneId"] for f in frames}) != 6:
        raise ValueError("expected complete 6-scene / 18-frame corpus")
    return corpus, frames


def nearest_grid(array: np.ndarray, size: int = 256) -> np.ndarray:
    h, w = array.shape[:2]
    return array[(np.arange(size) * h // size)[:, None], (np.arange(size) * w // size)[None, :]]


def normalize(raw: np.ndarray) -> np.ndarray:
    raw = np.asarray(raw, dtype=np.float32)
    if raw.shape != (256, 256) or not np.isfinite(raw).all():
        raise ValueError("invalid aligned 256x256 relative-depth output")
    low, high = np.quantile(raw, [0.05, 0.95], method="linear")
    if high - low < 1e-3:
        raise ValueError("degenerate relative-depth output")
    return np.clip((raw - low) / (high - low), 0, 1).astype(np.float32)


def average_ranks(values: np.ndarray) -> np.ndarray:
    _, inverse, counts = np.unique(values, return_inverse=True, return_counts=True)
    ends = np.cumsum(counts)
    return (ends - (counts + 1) / 2.0)[inverse]


def rank_rho(a: np.ndarray, b: np.ndarray) -> float | None:
    valid = np.isfinite(a) & np.isfinite(b)
    if valid.sum() < 100:
        return None
    ra, rb = average_ranks(a[valid]), average_ranks(b[valid])
    if np.ptp(ra) == 0 or np.ptp(rb) == 0:
        return None
    value = float(np.corrcoef(ra, rb)[0, 1])
    return value if math.isfinite(value) else None


def score(raw: np.ndarray, frame: dict) -> dict:
    with Image.open(frame["paths"]["depth"]) as image:
        mm = nearest_grid(np.asarray(image, dtype=np.float32))
    inverse = np.full_like(mm, np.nan)
    valid = mm > 0
    inverse[valid] = 1000.0 / mm[valid]
    # Boundary ordering uses labelled adjacent pixels. It does not infer free space.
    predicted_correct = significant_pairs = 0
    for axis in (0, 1):
        a = np.take(inverse, np.arange(252), axis=axis)
        b = np.take(inverse, np.arange(4, 256), axis=axis)
        pa = np.take(raw, np.arange(252), axis=axis)
        pb = np.take(raw, np.arange(4, 256), axis=axis)
        eligible = np.isfinite(a) & np.isfinite(b) & (np.abs(a - b) > 0.2 * np.maximum(a, b))
        significant_pairs += int(eligible.sum())
        predicted_correct += int(((pa - pb) * (a - b) > 0)[eligible].sum())
    return {"rankRhoToOracleInverseDepth": rank_rho(raw, inverse),
            "boundaryOrderingCorrectPairs": predicted_correct,
            "boundaryOrderingPairs": significant_pairs,
            "boundaryOrderingAccuracy": predicted_correct / significant_pairs if significant_pairs else None,
            "oracleUse": "scoring only; no oracle pixels supplied to inference or planner"}


def percentile(values: list[float], p: float) -> float | None:
    return float(np.quantile(values, p, method="inverted_cdf")) if values else None


def parity(reference: np.ndarray, candidate: np.ndarray) -> dict:
    a, b = normalize(reference), normalize(candidate)
    error = np.abs(a - b)
    rho = rank_rho(reference, candidate)
    return {"rankRho": rho, "normalizedMeanAbsoluteError": float(error.mean()),
            "normalizedP99AbsoluteError": float(np.quantile(error, 0.99)),
            "normalizedMaxAbsoluteError": float(error.max()),
            "passed": rho is not None and rho >= 0.999 and float(error.mean()) <= 0.002
                      and float(np.quantile(error, 0.99)) <= 0.01}

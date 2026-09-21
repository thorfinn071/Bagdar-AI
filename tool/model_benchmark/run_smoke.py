from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import statistics
import time
from pathlib import Path

import numpy as np
import onnxruntime as ort
import psutil


REPO_ROOT = Path(__file__).resolve().parents[2]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    position = (len(ordered) - 1) * fraction
    low = int(position)
    high = min(low + 1, len(ordered) - 1)
    weight = position - low
    return ordered[low] * (1 - weight) + ordered[high] * weight


def benchmark(candidate: dict[str, object], iterations: int) -> dict[str, object]:
    path = REPO_ROOT / str(candidate["artifactPath"])
    actual_hash = sha256(path)
    if actual_hash != candidate["artifactSha256"]:
        raise ValueError(f"hash mismatch for {path}")

    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(
        str(path),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    input_meta = session.get_inputs()[0]
    output_meta = session.get_outputs()[0]
    expected_input = candidate["input"]["shape"]
    expected_output = candidate["output"]["shape"]
    if list(input_meta.shape) != expected_input:
        raise ValueError(f"input contract drift for {candidate['modelId']}")
    if list(output_meta.shape) != expected_output:
        raise ValueError(f"output contract drift for {candidate['modelId']}")

    seed = 20260920
    rng = np.random.default_rng(seed)
    sample = rng.random(expected_input, dtype=np.float32)
    process = psutil.Process(os.getpid())
    rss_before = process.memory_info().rss
    for _ in range(3):
        session.run(None, {input_meta.name: sample})

    timings_ms: list[float] = []
    output = None
    for _ in range(iterations):
        started = time.perf_counter_ns()
        output = session.run(None, {input_meta.name: sample})[0]
        timings_ms.append((time.perf_counter_ns() - started) / 1_000_000)
    rss_after = process.memory_info().rss
    assert output is not None
    finite = bool(np.isfinite(output).all())
    checks: dict[str, object] = {
        "shapeMatches": list(output.shape) == expected_output,
        "allFinite": finite,
    }
    if candidate["decoderId"] == "yolo26-end2end-bnc-v1":
        scores = output[0, :, 4]
        classes = output[0, :, 5]
        checks.update(
            {
                "scoresIn01": bool(((scores >= 0) & (scores <= 1)).all()),
                "classesIntegral": bool(np.allclose(classes, np.round(classes))),
                "classesInCocoRange": bool(((classes >= 0) & (classes < 80)).all()),
            }
        )
    passed = all(bool(value) for value in checks.values())
    return {
        "modelId": candidate["modelId"],
        "artifactSha256": actual_hash,
        "seed": seed,
        "warmupIterations": 3,
        "measuredIterations": iterations,
        "latencyMs": {
            "p50": round(statistics.median(timings_ms), 3),
            "p95": round(percentile(timings_ms, 0.95), 3),
            "min": round(min(timings_ms), 3),
            "max": round(max(timings_ms), 3),
        },
        "processRssDeltaBytes": rss_after - rss_before,
        "checks": checks,
        "passed": passed,
        "correctnessScope": "synthetic tensor smoke only",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=20)
    parser.add_argument(
        "--manifest",
        default="model_export/candidates/manifest.json",
    )
    parser.add_argument(
        "--output",
        default=None,
        help="Write JSON only when an explicit path is supplied.",
    )
    parser.add_argument(
        "--spatial-report",
        default=None,
        help="Optional current spatial report; omitted reports no replay evidence.",
    )
    args = parser.parse_args()
    if args.iterations < 5:
        raise ValueError("at least five measured iterations are required")

    manifest = json.loads((REPO_ROOT / args.manifest).read_text(encoding="utf-8"))
    results = [benchmark(candidate, args.iterations) for candidate in manifest["candidates"]]
    replay = None
    if args.spatial_report:
        replay_path = REPO_ROOT / args.spatial_report
        replay = json.loads(replay_path.read_text(encoding="utf-8"))
    report = {
        "schemaVersion": 1,
        "scope": "desktop-synthetic-smoke",
        "host": {
            "system": platform.system(),
            "machine": platform.machine(),
            "processor": os.environ.get("PROCESSOR_IDENTIFIER") or platform.processor(),
            "python": platform.python_version(),
            "onnxruntime": ort.__version__,
            "executionProvider": "CPUExecutionProvider",
            "threads": 1,
        },
        "models": results,
        "productionReplay": {
            "selection": "YOLOv8n control + MiDaS control",
            "evaluated": replay is not None,
            "passed": replay["passed"] if replay is not None else False,
            "metrics": replay["metrics"] if replay is not None else None,
            "candidatePredictionsUsed": False,
        },
        "blockedGates": [
            "recorded detector correctness corpus",
            "candidate downstream replay using real predictions",
            "native/reference MiDaS parity fixture",
            "Depth Anything V2 converted checkpoints",
            "traversability artifacts and boundary-labelled corpus",
            "named-device latency, memory, battery and thermal",
            "candidate license/provenance approval",
        ],
        "selectionDecision": {
            "detector": "keep yolov8n-int8-control-416",
            "relativeDepth": "keep midas-small-ncnn",
            "traversability": "deferred",
            "candidatePromotion": False,
        },
        "passed": all(result["passed"] for result in results),
        "correctnessPassed": False,
    }
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        output = REPO_ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {output.relative_to(REPO_ROOT)}; smoke passed={report['passed']}")
    else:
        print(rendered, end="")


if __name__ == "__main__":
    main()

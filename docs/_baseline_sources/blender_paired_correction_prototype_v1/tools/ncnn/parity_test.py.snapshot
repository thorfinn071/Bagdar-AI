"""ONNX reference vs NCNN MiDaS Small parity.

The default run is read-only and prints a JSON report. Use --output for a
report file and --fixture to explicitly refresh the compact Dart fixture.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import ncnn
import numpy as np
import onnxruntime as ort


REPO_ROOT = Path(__file__).resolve().parents[2]
ASSETS = REPO_ROOT / "assets"
TOOLS = REPO_ROOT / "tools" / "ncnn"
ONNX_REFERENCE = TOOLS / "build" / "midas_small_fp32.onnx"
NCNN_PARAM = ASSETS / "midas_small.ncnn.param"
NCNN_BIN = ASSETS / "midas_small.ncnn.bin"
INPUT_SIZE = 256
PASS_MEAN_ABS_THRESHOLD = 0.10
PASS_SPEARMAN_THRESHOLD = 0.90


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def make_inputs(rng: np.random.Generator) -> list[tuple[str, np.ndarray]]:
    """Deterministic gradients, edges, texture, and radial structure."""
    samples: list[tuple[str, np.ndarray]] = []
    gradient = np.linspace(0, 1, INPUT_SIZE, dtype=np.float32)
    samples.append(
        (
            "horizontal-gradient",
            np.tile(gradient[None, :, None], (INPUT_SIZE, 1, 3)),
        )
    )
    samples.append(
        (
            "vertical-gradient",
            np.tile(gradient[:, None, None], (1, INPUT_SIZE, 3)),
        )
    )
    edge = np.tile(
        np.linspace(0.15, 0.85, INPUT_SIZE, dtype=np.float32)[:, None],
        (1, INPUT_SIZE),
    )
    edge[90:220, 92:164] = 0.95
    samples.append(
        (
            "central-obstacle-edge",
            np.repeat(edge[..., None], 3, axis=-1),
        )
    )
    samples.append(
        (
            "seeded-texture",
            rng.random((INPUT_SIZE, INPUT_SIZE, 3), dtype=np.float32),
        )
    )
    yy, xx = np.mgrid[0:INPUT_SIZE, 0:INPUT_SIZE].astype(np.float32)
    distance = np.sqrt((yy - INPUT_SIZE / 2) ** 2 + (xx - INPUT_SIZE / 2) ** 2)
    disk = np.clip(1.0 - distance / (INPUT_SIZE / 2), 0.0, 1.0)
    samples.append(("radial-edge", np.repeat(disk[..., None], 3, axis=-1)))
    return samples


def chw(sample: np.ndarray) -> np.ndarray:
    return np.transpose(sample, (2, 0, 1)).astype(np.float32)


def run_reference(inputs: list[tuple[str, np.ndarray]]) -> list[np.ndarray]:
    options = ort.SessionOptions()
    options.intra_op_num_threads = 1
    options.inter_op_num_threads = 1
    session = ort.InferenceSession(
        str(ONNX_REFERENCE),
        sess_options=options,
        providers=["CPUExecutionProvider"],
    )
    input_meta = session.get_inputs()[0]
    output_meta = session.get_outputs()[0]
    if list(input_meta.shape) != [1, 3, INPUT_SIZE, INPUT_SIZE]:
        raise ValueError(f"reference input drift: {input_meta.shape}")
    if list(output_meta.shape) != [1, INPUT_SIZE, INPUT_SIZE]:
        raise ValueError(f"reference output drift: {output_meta.shape}")
    return [
        np.squeeze(session.run(None, {input_meta.name: chw(sample)[None]})[0]).astype(
            np.float32
        )
        for _, sample in inputs
    ]


def ncnn_blob_names(param_path: Path) -> tuple[str, str]:
    layers: list[tuple[str, list[str]]] = []
    for line in param_path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) < 4 or not parts[2].isdigit() or not parts[3].isdigit():
            continue
        bottom_count = int(parts[2])
        top_count = int(parts[3])
        top_start = 4 + bottom_count
        if top_count < 1 or len(parts) < top_start + top_count:
            continue
        layers.append((parts[0], parts[top_start : top_start + top_count]))
    if not layers or layers[0][0] != "Input":
        raise ValueError("NCNN param has no leading Input layer")
    return layers[0][1][0], layers[-1][1][-1]


def run_ncnn(inputs: list[tuple[str, np.ndarray]]) -> list[np.ndarray]:
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    if net.load_param(str(NCNN_PARAM)) != 0:
        raise RuntimeError("NCNN param load failed")
    if net.load_model(str(NCNN_BIN)) != 0:
        raise RuntimeError("NCNN model load failed")
    input_name, output_name = ncnn_blob_names(NCNN_PARAM)
    outputs: list[np.ndarray] = []
    for _, sample in inputs:
        source = chw(sample)
        mat = ncnn.Mat(source.shape[2], source.shape[1], source.shape[0])
        for channel in range(source.shape[0]):
            np.copyto(np.array(mat.channel(channel), copy=False), source[channel])
        extractor = net.create_extractor()
        if extractor.input(input_name, mat) != 0:
            raise RuntimeError("NCNN input failed")
        result, output = extractor.extract(output_name)
        if result != 0:
            raise RuntimeError(f"NCNN extract failed: {result}")
        outputs.append(
            np.array(output, copy=True)
            .reshape(output.h, output.w)
            .astype(np.float32)
        )
    return outputs


def normalize(value: np.ndarray) -> np.ndarray:
    if not np.isfinite(value).all():
        raise ValueError("non-finite depth output")
    span = float(value.max() - value.min())
    if span <= 1e-9:
        raise ValueError("degenerate depth output")
    return (value - value.min()) / span


def compare(reference: np.ndarray, candidate: np.ndarray) -> dict[str, object]:
    reference_normalized = normalize(reference)
    candidate_normalized = normalize(candidate)
    difference = np.abs(reference_normalized - candidate_normalized)
    reference_rank = np.argsort(np.argsort(reference_normalized.reshape(-1)))
    candidate_rank = np.argsort(np.argsort(candidate_normalized.reshape(-1)))
    return {
        "meanAbsDiff": float(difference.mean()),
        "maxAbsDiff": float(difference.max()),
        "p99Diff": float(np.percentile(difference, 99)),
        "spearman": float(np.corrcoef(reference_rank, candidate_rank)[0, 1]),
        "referenceShape": list(reference.shape),
        "candidateShape": list(candidate.shape),
    }


def compact_samples(value: np.ndarray) -> list[float]:
    normalized = normalize(value)
    return [
        round(float(item), 7) for item in normalized[::16, ::16].reshape(-1)
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=None)
    parser.add_argument("--fixture", default=None)
    parser.add_argument("--check-fixture", default=None)
    args = parser.parse_args()
    for required in (ONNX_REFERENCE, NCNN_PARAM, NCNN_BIN):
        if not required.exists():
            raise FileNotFoundError(required)

    inputs = make_inputs(np.random.default_rng(42))
    reference_outputs = run_reference(inputs)
    ncnn_outputs = run_ncnn(inputs)
    cases: list[dict[str, object]] = []
    failures = 0
    for (name, _), reference, candidate in zip(
        inputs, reference_outputs, ncnn_outputs
    ):
        metrics = compare(reference, candidate)
        passed = (
            float(metrics["meanAbsDiff"]) < PASS_MEAN_ABS_THRESHOLD
            and float(metrics["spearman"]) >= PASS_SPEARMAN_THRESHOLD
        )
        failures += 0 if passed else 1
        cases.append(
            {
                "name": name,
                "reference": compact_samples(reference),
                "native": compact_samples(candidate),
                "metrics": metrics,
                "passed": passed,
            }
        )
    report = {
        "schemaVersion": 1,
        "referenceRuntime": f"onnxruntime-{ort.__version__}-cpu",
        "candidateRuntime": "ncnn-python-cpu",
        "preprocessId": "rgb01-chw-256-no-extra-normalization-v1",
        "seed": 42,
        "thresholds": {
            "normalizedMeanAbsDiffMax": PASS_MEAN_ABS_THRESHOLD,
            "spearmanMin": PASS_SPEARMAN_THRESHOLD,
        },
        "artifacts": {
            "referenceOnnxSha256": sha256(ONNX_REFERENCE),
            "ncnnParamSha256": sha256(NCNN_PARAM),
            "ncnnBinSha256": sha256(NCNN_BIN),
        },
        "cases": cases,
        "failures": failures,
        "passed": failures == 0,
        "scope": "desktop inference parity; Android bridge/device parity remains R8",
    }
    rendered = json.dumps(report, indent=2) + "\n"
    if args.check_fixture:
        fixture = REPO_ROOT / args.check_fixture
        if fixture.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"NCNN reference fixture drift: {args.check_fixture}")
        print(f"NCNN reference fixture matches: {fixture.relative_to(REPO_ROOT)}")
    elif args.output:
        output = REPO_ROOT / args.output
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8")
        print(f"Wrote {output.relative_to(REPO_ROOT)}")
    else:
        print(rendered, end="")
    if args.fixture:
        fixture = REPO_ROOT / args.fixture
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(rendered, encoding="utf-8")
        print(f"Wrote {fixture.relative_to(REPO_ROOT)}")
    if failures:
        raise SystemExit(f"NCNN parity failed: {failures}/{len(cases)}")


if __name__ == "__main__":
    main()

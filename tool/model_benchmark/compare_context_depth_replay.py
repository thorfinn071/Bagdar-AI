"""Compare identical shadow timelines with Blender oracle and desktop NCNN depth."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOGS = ROOT / "docs/_baseline_logs"
ORACLE = LOGS / "blender_context_shadow_replay.json"
NCNN = LOGS / "blender_context_ncnn_shadow_replay.json"
DEPTH = ROOT / "test/fixtures/spatial_safety/blender-context-ncnn-depth-v1/manifest.json"
DEFAULT_OUTPUT = LOGS / "blender_context_depth_comparison.json"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frames_by_key(model: dict) -> dict[tuple[str, int], dict]:
    frames = {
        (sequence["sceneId"], frame["frameIndex"]): frame
        for sequence in model["sequences"]
        for frame in sequence["frames"]
    }
    if len(frames) != 18:
        raise ValueError("expected exactly 18 unique contextual frames")
    return frames


def build() -> dict:
    oracle = json.loads(ORACLE.read_text(encoding="utf-8"))
    ncnn = json.loads(NCNN.read_text(encoding="utf-8"))
    depth = json.loads(DEPTH.read_text(encoding="utf-8"))
    if oracle["corpusManifestSha256"] != ncnn["corpusManifestSha256"]:
        raise ValueError("shadow reports refer to different corpora")
    if oracle["detectorDiagnosticSha256"] != ncnn["detectorDiagnosticSha256"]:
        raise ValueError("shadow reports refer to different detector predictions")
    if ncnn["ncnnDepthManifestSha256"] != sha256(DEPTH):
        raise ValueError("pinned NCNN depth manifest drift")
    if depth["sourceCorpusManifestSha256"] != oracle["corpusManifestSha256"]:
        raise ValueError("NCNN depth output refers to a different corpus")
    oracle_models = {model["modelId"]: model for model in oracle["models"]}
    ncnn_models = {model["modelId"]: model for model in ncnn["models"]}
    if len(oracle_models) != 4 or oracle_models.keys() != ncnn_models.keys():
        raise ValueError("model sets differ")
    comparisons = []
    for model_id, oracle_model in oracle_models.items():
        ncnn_model = ncnn_models[model_id]
        a = frames_by_key(oracle_model)
        b = frames_by_key(ncnn_model)
        if a.keys() != b.keys():
            raise ValueError("frame sets differ")
        changed = []
        for scene_id, frame_index in sorted(a):
            left, right = a[(scene_id, frame_index)], b[(scene_id, frame_index)]
            if left["expectedAction"] != right["expectedAction"]:
                raise ValueError("ground truth changed between depth runs")
            if left["plannedAction"] != right["plannedAction"] or left["plannedRuleId"] != right["plannedRuleId"]:
                changed.append({
                    "sceneId": scene_id,
                    "frameIndex": frame_index,
                    "expectedAction": left["expectedAction"],
                    "oracleAction": left["plannedAction"],
                    "oracleRuleId": left["plannedRuleId"],
                    "oracleGeometry": [item["geometry"] for item in left["geometryComponents"]],
                    "ncnnAction": right["plannedAction"],
                    "ncnnRuleId": right["plannedRuleId"],
                    "ncnnGeometry": [item["geometry"] for item in right["geometryComponents"]],
                    "ncnnGroundConfidence": right["groundConfidence"],
                    "ncnnForwardUnknown": right["forwardUnknown"],
                })
        comparisons.append({
            "modelId": model_id,
            "oracleSummary": oracle_model["summary"],
            "ncnnSummary": ncnn_model["summary"],
            "changedActionCount": sum(
                row["oracleAction"] != row["ncnnAction"] for row in changed
            ),
            "changedRuleCount": len(changed),
            "changedFrames": changed,
        })
    ranks = {}
    for scene_id in sorted({frame["sceneId"] for frame in depth["frames"]}):
        values = [
            frame["rankRhoToOracleInverseMetres"]
            for frame in depth["frames"]
            if frame["sceneId"] == scene_id
        ]
        ranks[scene_id] = sum(values) / len(values)
    return {
        "schemaVersion": 1,
        "benchmarkId": "blender-context-oracle-vs-desktop-ncnn-shadow-v1",
        "toolSha256": sha256(Path(__file__)),
        "oracleReportSha256": sha256(ORACLE),
        "ncnnReportSha256": sha256(NCNN),
        "ncnnDepthManifestSha256": sha256(DEPTH),
        "sceneMeanFramewideDepthRankRho": ranks,
        "models": comparisons,
        "interpretationLimit": "framewide depth rank and synthetic shadow action agreement are diagnostics, not phone hazard recall or assistive authorization",
        "promotionAllowed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    if args.output and args.check:
        parser.error("choose --output or --check")
    rendered = json.dumps(build(), indent=2, ensure_ascii=False) + "\n"
    target = args.output or args.check or DEFAULT_OUTPUT
    if not target.is_absolute():
        target = ROOT / target
    if args.check:
        if target.read_text(encoding="utf-8") != rendered:
            raise SystemExit(f"comparison report drift: {target}")
        print(f"Comparison report matches: {target}")
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(rendered, encoding="utf-8")
        print(f"Wrote comparison report: {target}")


if __name__ == "__main__":
    main()

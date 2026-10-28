"""First-run receipt: pin source closure, outputs and source-labelled previews."""
import argparse
import json
import re
from pathlib import Path
from verify_paired_scene_corpus import CORPUS, ROOT, checked, load_corpus, read_json, sha

RECEIPT = ROOT / "docs/_baseline_logs/blender_paired_baseline_contract_v1.json"


def source_closure():
    files = {ROOT / "docs/blender-paired-scenes-protocol-2026-10-04.md", ROOT / "tool/blender/paired_scene_spec_v1.json"}
    files.update(ROOT / p for p in (
        "tool/blender/generate_paired_scene_corpus.py", "tool/blender/check_paired_scene_projection.py",
        "tool/model_benchmark/verify_paired_scene_corpus.py", "tool/model_benchmark/evaluate_paired_scene_models.py",
        "tool/model_benchmark/test_paired_scene_corpus.py", "tool/model_benchmark/verify_paired_scene_baseline.py",
        "tool/model_benchmark/measure_paired_scene_compute.py", "tools/ncnn/parity_test.py",
        "tool/model_benchmark/check_paired_scene_quality.py",
        "tool/model_benchmark/evaluate_blender_detectors.py", "tool/model_benchmark/generate_context_ncnn_depth.py"))
    queue = [ROOT / "test/blender_paired_scene_shadow_replay_test.dart"]
    while queue:
        path = queue.pop().resolve()
        if path in files:
            continue
        files.add(path)
        for name in re.findall(r"(?:import|export)\s+['\"]([^'\"]+)['\"]", path.read_text(encoding="utf-8")):
            if name.startswith("package:bagdar/"):
                child = ROOT / "lib" / name.removeprefix("package:bagdar/")
            elif ":" not in name:
                child = (path.parent / name).resolve()
            else:
                continue
            if child.is_file() and child.is_relative_to(ROOT):
                queue.append(child)
    return {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)}


def build():
    manifest, sequences = load_corpus()
    prefix = "docs/_baseline_logs/blender_paired_"
    reports = [ROOT / (prefix + name + ".json") for name in ("yolo", "ncnn", "shadow", "quality")]
    source_hash = sha(CORPUS / "corpus-manifest.json")
    for path in reports:
        report = read_json(path)
        if report["corpusManifestSha256"] != source_hash or report["promotionAllowed"] is not False:
            raise ValueError("Report source/scope mismatch")
    for row in read_json(reports[1])["frames"]:
        checked(CORPUS, row["asset"])
    preview = read_json(CORPUS / "previews/manifest.json")
    if preview["sourceManifestSha256"] != source_hash or len(preview["assets"]) != 13:
        raise ValueError("Incomplete or stale previews")
    for asset in preview["assets"]:
        checked(CORPUS, asset)
    return {"schemaVersion": 1, "corpusId": manifest["corpusId"], "corpusManifestSha256": source_hash,
        "scope": "first-use independent synthetic expansion; after evaluation this becomes a known regression corpus",
        "sources": source_closure(), "reports": {p.relative_to(ROOT).as_posix(): sha(p) for p in reports},
        "previewsManifestSha256": sha(CORPUS / "previews/manifest.json"),
        "sceneCount": len(sequences), "frameCount": sum(len(s["frames"]) for s in sequences),
        "promotionAllowed": False, "deviceRuntime": "not_run", "modelRetraining": "not_run", "thresholdTuning": "not_run"}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--write", action="store_true")
    args = p.parse_args()
    current = build()
    if args.write:
        if RECEIPT.exists():
            raise ValueError("The first-run receipt is write-once")
        RECEIPT.write_text(json.dumps(current, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    elif read_json(RECEIPT) != current:
        raise ValueError("First-run paired baseline drift")
    print(f"Paired scene baseline: {current['sceneCount']} scenes, {current['frameCount']} frames, pinned source/output closure passed")

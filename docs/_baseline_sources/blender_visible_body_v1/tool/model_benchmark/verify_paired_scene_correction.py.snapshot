"""Verify the immutable first baseline and a separately versioned correction."""
import argparse
import json
from pathlib import Path
from check_paired_scene_quality import evaluate
from verify_paired_scene_baseline import RECEIPT as FIRST, source_closure
from verify_paired_scene_corpus import CORPUS, ROOT, checked, load_corpus, read_json, sha

ARCHIVE = ROOT / "docs/_baseline_sources/blender_paired_v1"
REPORT = ROOT / "docs/_baseline_logs/blender_paired_correction_shadow_v3.json"
RECEIPT = ROOT / "docs/_baseline_logs/blender_paired_correction_contract_v4.json"


def verify_first():
    original = read_json(FIRST)
    manifest, sequences = load_corpus()
    if original["corpusManifestSha256"] != sha(CORPUS / "corpus-manifest.json"):
        raise ValueError("Changed first corpus")
    for path, expected in original["sources"].items():
        snapshot = ARCHIVE / (path + ".snapshot")
        if not snapshot.resolve().is_relative_to(ARCHIVE.resolve()) or sha(snapshot) != expected:
            raise ValueError("Changed first source snapshot: " + path)
    for path, expected in original["reports"].items():
        if sha(ROOT / path) != expected:
            raise ValueError("Changed first report: " + path)
    preview = read_json(CORPUS / "previews/manifest.json")
    if sha(CORPUS / "previews/manifest.json") != original["previewsManifestSha256"]:
        raise ValueError("Changed first previews")
    for asset in preview["assets"]:
        checked(CORPUS, asset)
    for row in read_json(ROOT / "docs/_baseline_logs/blender_paired_ncnn.json")["frames"]:
        checked(CORPUS, row["asset"])
    return original


def build():
    first = verify_first()
    report = read_json(REPORT)
    if report["promotionAllowed"] is not False or report["conservativeConfidenceAuthority"] is not True:
        raise ValueError("Invalid correction authority/delivery scope")
    if report["policyId"] != "confidence-authority-v3":
        raise ValueError("Unexpected correction implementation")
    if report["corpusManifestSha256"] != first["corpusManifestSha256"]:
        raise ValueError("Correction used another corpus")
    if report["firstBaselineSha256"] != first["reports"]["docs/_baseline_logs/blender_paired_shadow.json"]:
        raise ValueError("Correction lost original reference")
    for mode in report["modes"]:
        if any(row["delivery"] != "shadow" or row["passageApplied"] for seq in mode["sequences"] for row in seq["frames"]):
            raise ValueError("Unexpected delivery or oracle clearance")
    sources = source_closure()
    for path in ("test/blender_paired_scene_correction_replay_test.dart",
                 "lib/safety/runtime/confidence_authority_spatial_runtime.dart",
                 "test/generic_geometry_confidence_authority_test.dart",
                 "lib/viewmodels/camera_view_model.dart",
                 "tool/model_benchmark/verify_paired_scene_correction.py",
                 "docs/blender-paired-correction-protocol-2026-10-04.md"):
        sources[path] = sha(ROOT / path)
    return {"schemaVersion": 1, "firstReceiptSha256": sha(FIRST),
            "corpusManifestSha256": first["corpusManifestSha256"],
            "correctionReportSha256": sha(REPORT), "sources": sources,
            "scope": "known synthetic correction regression; legacy control preserved; camera shadow wiring; no field accuracy",
            "promotionAllowed": False, "deviceRuntime": "not_run", **evaluate(report)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-only", action="store_true")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    if args.baseline_only:
        first = verify_first()
        print(f"First paired baseline preserved: {len(first['sources'])} source snapshots and all pinned outputs")
    else:
        current = build()
        if args.write:
            if RECEIPT.exists():
                raise ValueError("Correction receipt is write-once")
            RECEIPT.write_text(json.dumps(current, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        elif read_json(RECEIPT) != current:
            raise ValueError("Correction source/report drift")
        print(json.dumps({k: v for k, v in current.items() if k != "sources"}, indent=2))
        raise SystemExit(0 if current["passed"] else 1)

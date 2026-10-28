"""Fail the quality gate on hazardous continues, late stops or false imminence.

Integrity/reproducibility passing does not make these safety checks pass.
False stops due to unknown space are reported but never removed by this gate.
"""
import argparse
import json
from verify_paired_scene_corpus import CORPUS, ROOT, read_json, sha

REPORT = ROOT / "docs/_baseline_logs/blender_paired_shadow.json"
OUTPUT = ROOT / "docs/_baseline_logs/blender_paired_quality.json"


def evaluate(report):
    failures = []
    for mode in report["modes"]:
        summary = mode["summary"]
        for metric, limit in (("unsafeContinues", 0), ("lateStopSequences", 0), ("missedStopSequences", 0), ("falseImminentFrames", 0)):
            if summary[metric] > limit:
                failures.append({"mode": mode["mode"], "metric": metric, "actual": summary[metric], "maximumAllowed": limit})
    return {"passed": not failures, "failures": failures}


def build():
    report = read_json(REPORT)
    assert report["promotionAllowed"] is False
    assert report["corpusManifestSha256"] == sha(CORPUS / "corpus-manifest.json")
    return {"schemaVersion": 1, "corpusManifestSha256": report["corpusManifestSha256"],
        "shadowReportSha256": sha(REPORT), "toolSha256": sha(__file__),
        "scope": "synthetic shadow quality gate, independent of hash/report reproducibility; not field accuracy",
        "promotionAllowed": False, **evaluate(report)}


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--write", action="store_true")
    args = p.parse_args()
    report = build()
    if args.write:
        if OUTPUT.exists():
            raise ValueError("First quality result is write-once")
        OUTPUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    elif read_json(OUTPUT) != report:
        raise ValueError("Quality report drift")
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report["passed"] else 1)

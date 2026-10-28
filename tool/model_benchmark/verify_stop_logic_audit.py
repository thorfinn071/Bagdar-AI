"""Independently check and summarize known-scene STOP state interventions.

This audits replay receipts; it does not validate physical sensing or grant
movement authority. All state-reset lanes remain diagnostic interventions.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path


LANES = (
    "appContinuous", "appFreshRuntime", "appFreshStationary",
    "calibratedContinuous", "calibratedFreshRuntime", "calibratedFreshStationary",
)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(audit, baseline, root):
    require(audit["schemaVersion"] == 1, "Unsupported audit schema")
    for field in ("promotionAllowed", "ordinaryCameraWired",
                  "falseStopReductionEstablished", "newHoldout", "newNeuralInference"):
        require(audit[field] is False, f"Invalid authority claim: {field}")
    for field in ("namedDeviceRuntime", "controlledWalking"):
        require(audit[field] == "not_run", f"Unmeasured physical claim: {field}")
    require(audit["captureToDecisionMs"] is None, "Replay is not phone timing")
    require(audit["freshnessPolicyUs"] == 100000, "Freshness changed")
    for path, expected in audit["preservedSourceHashes"].items():
        require(digest(root / path) == expected, f"Changed source/receipt: {path}")

    old_rows = {(r["sceneId"], r["frameId"]): r for r in baseline["frames"]
                if r["corpus"] == "paired-visible-body-v1"
                and r["sampleKind"] == "knownSyntheticReplay"}
    require(len(old_rows) == 132, "Incomplete baseline")
    by_frame = defaultdict(dict)
    groups = {lane: {"clear": Counter(), "hazard": Counter()} for lane in LANES}
    for row in audit["frames"]:
        key = (row["sceneId"], row["frameId"])
        lane = row["variant"]
        require(lane in LANES and key in old_rows, "Foreign frame/lane")
        require(lane not in by_frame[key], "Duplicate lane/frame")
        by_frame[key][lane] = row
        require(row["runtimeAccepted"] is True, "Rejected input scored as admitted")
        require(row["delivery"] == "shadow", "Non-shadow result")
        require(row["captureToDecisionMs"] is None, "Invented phone timing")
        require(row["replayAgeUs"] == 2000, "Intervention changed input age")
        require(row["trackerHistoryReset"] is False, "Tracker reset invalidates isolation")
        require(row["runtimeHistoryReset"] == ("Fresh" in lane), "Wrong reset arm")
        require(row["userMoving"] == (not lane.endswith("Stationary")), "Wrong movement arm")
        require(row["calibratedSourceSupplied"] == lane.startswith("calibrated"), "Wrong source arm")
        expected_label = old_rows[key]["scoringOnly"]
        require(row["scoringOnly"]["referencePassable"] == expected_label["referencePassable"]
                and row["scoringOnly"]["physicalHazard"] == expected_label["physicalHazard"],
                "Changed scene label")
        if expected_label["referencePassable"] is True:
            groups[lane]["clear"][row["action"]] += 1
        elif expected_label["physicalHazard"] is True:
            groups[lane]["hazard"][row["action"]] += 1
        else:
            raise ValueError("Unknown label must remain unscored")
        if lane == "calibratedContinuous":
            for field in ("action", "ruleId", "passageStatus", "passageApplied", "corridorRejections"):
                require(row[field] == old_rows[key][field], f"Baseline mismatch: {key}/{field}")
        if lane.startswith("app"):
            require(row["passageStatus"] is None and row["producerPassageStatus"] is None,
                    "Absent source presented as a measured result")

    require(len(by_frame) == 132 and len(audit["frames"]) == 792, "Incomplete intervention matrix")
    comparisons = {}
    for prefix in ("app", "calibrated"):
        counts = Counter({label + "_" + field: 0 for label in ("clear", "hazard")
                          for field in ("plannerHistoryActionChanges", "combinedRuntimeHistoryActionChanges",
                                        "sceneStateActionChangesWithFreshPlanners", "runtimeRuleChanges",
                                        "runtimeUnknownChanges", "runtimeCollisionRiskChanges",
                                        "runtimeCorridorRejectionChanges")})
        examples = []
        for key, arms in by_frame.items():
            require(set(arms) == set(LANES), "Missing arm")
            require(len({r["rawTracksSha256"] for r in arms.values()}) == 1,
                    "Tracks changed between arms")
            require(len({r["headerSha256"] for r in arms.values()}) == 1,
                    "Header changed between arms")
            current, fresh = arms[prefix + "Continuous"], arms[prefix + "FreshRuntime"]
            same_scene = current["sameSnapshotFreshPlanner"]
            fresh_scene = fresh["sameSnapshotFreshPlanner"]
            label = "clear" if current["scoringOnly"]["referencePassable"] else "hazard"
            if current["action"] != same_scene["action"]:
                counts[label + "_plannerHistoryActionChanges"] += 1
            if current["action"] != fresh["action"]:
                counts[label + "_combinedRuntimeHistoryActionChanges"] += 1
                examples.append({"sceneId": key[0], "frameId": key[1],
                                 "continuous": current["action"], "freshRuntime": fresh["action"],
                                 "freshPlannerSameScene": same_scene["action"]})
            if same_scene["action"] != fresh_scene["action"]:
                counts[label + "_sceneStateActionChangesWithFreshPlanners"] += 1
            for field, name in (("ruleId", "runtimeRuleChanges"),
                                ("forwardUnknownRisk", "runtimeUnknownChanges"),
                                ("forwardCollisionRisk", "runtimeCollisionRiskChanges"),
                                ("corridorRejections", "runtimeCorridorRejectionChanges")):
                if current[field] != fresh[field]:
                    counts[label + "_" + name] += 1
        comparisons[prefix] = {"counts": dict(counts), "changedFrameExamples": examples}

    details = {}
    for lane in LANES:
        lane_rows = [r for r in audit["frames"] if r["variant"] == lane]
        details[lane] = {}
        for label in ("clear", "hazard"):
            selected = [r for r in lane_rows if r["scoringOnly"][
                "referencePassable" if label == "clear" else "physicalHazard"]]
            details[lane][label] = {
                "rules": dict(Counter(r["ruleId"] for r in selected)),
                "corridorRejections": dict(Counter(reason for r in selected for reason in r["corridorRejections"])),
                "associationRelations": dict(Counter(a["relation"] for r in selected
                                                       for a in r["cameraTrackAssociations"].values())),
                "associationReasons": dict(Counter(a["reason"] for r in selected
                                                     for a in r["cameraTrackAssociations"].values())),
                "positiveCorridorFrames": sum(r["positiveCorridor"] is True for r in selected),
                "framesWithForwardHazards": sum(bool(r["forwardHazardIds"]) for r in selected),
            }

    probes = audit["relativeCeilingProbes"]
    require(len(probes) == 2 and {p["moving"] for p in probes} == {True, False}, "Missing ceiling probe")
    for probe in probes:
        require(probe["unknown"] >= .65 and probe["occupancy"] == 0 and probe["drop"] == 0,
                "Ceiling probe is not isolated uncertainty")
        require(probe["positiveCorridor"] is False and probe["physicalMeasurement"] is False,
                "Ceiling probe misrepresented")
        require(probe["action"] == ("stopNow" if probe["moving"] else "holdAndScan"),
                "Unexpected relative ceiling action")
        require(probe["delivery"] == "shadow" and probe["arbiterActive"] is False,
                "Ceiling probe issued authority")

    return {
        "schemaVersion": 1, "independentReceiptChecksPassed": True,
        "uniqueKnownFrames": len(by_frame), "interventionRows": len(audit["frames"]),
        "groups": groups, "historyComparisons": comparisons, "details": details,
        "baselineComparisons": len(old_rows), "preservedFiles": len(audit["preservedSourceHashes"]),
        "relativeCeilingProbes": probes,
        "scope": audit["scope"], "captureToDecisionMs": None,
        "newHoldout": False, "falseStopReductionEstablished": False,
        "ordinaryCameraWired": False, "promotionAllowed": False,
        "namedDeviceRuntime": "not_run", "controlledWalking": "not_run",
    }


def render(summary):
    lines = ["# STOP logic audit — known synthetic scenes", "",
             "State resets and stationary substitutions below are diagnostic interventions.",
             "They are not candidate recovery policies or independent scene observations.", "",
             "| Lane | Clear: STOP | Clear: HOLD | Clear: CONTINUE | Hazard: STOP | Hazard: HOLD | Hazard: CONTINUE |",
             "| --- | ---: | ---: | ---: | ---: | ---: | ---: |"]
    for lane, group in summary["groups"].items():
        values = [group[label].get(action, 0) for label in ("clear", "hazard")
                  for action in ("stopNow", "holdAndScan", "continueForward")]
        lines.append("| " + lane + " | " + " | ".join(map(str, values)) + " |")
    lines += ["", "Counts cover 132 unique already-known frames, repeated in six lanes.",
              "The tracker and detector retain identical inputs across each frame's six lanes.",
              "App lanes match the absent passage configuration, not the full Android pipeline.",
              "Stationary lanes change only the runtime movement input; detector motion remains walking.", "",
              "## History comparisons", ""]
    for prefix, result in summary["historyComparisons"].items():
        counts = result["counts"]
        lines.append(f"- {prefix}, clear-labelled frames: action changes after a fresh planner on the same scene "
                     f"{counts['clear_plannerHistoryActionChanges']}; after a fresh runtime "
                     f"{counts['clear_combinedRuntimeHistoryActionChanges']}; rule changes "
                     f"{counts['clear_runtimeRuleChanges']}; collision-score changes "
                     f"{counts['clear_runtimeCollisionRiskChanges']}.")
    lines += ["", "A fresh planner on the same fused snapshot isolates planner history.",
              "A fresh runtime resets the scene model and planner, retaining original tracker history.",
              "Equal STOP actions do not mean that history has no effect on scores or explanations.",
              "Neither reset is a proposed runtime fix.", "",
              "## Relative-only ceiling probe", "",
              "Constructed perfect relative coverage and ground, with no obstacle tracks, still produce",
              "forward uncertainty >=0.65: moving gives STOP; stationary gives HOLD.",
              "These constructed values are not physical measurements.", "",
              "## Evidence limits", "",
              "No new model inference, holdout, real capture, phone timing, user trial or walking test.",
              "No production behavior, clearance dimensions, freshness limit or stop release policy changed.",
              "All runtime actions remain shadow. No false-stop reduction or promotion is established.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    audit = json.loads(args.audit.read_text(encoding="utf-8-sig"))
    baseline = json.loads(args.baseline.read_text(encoding="utf-8-sig"))
    require(audit["baselineSha256"] == digest(args.baseline), "Changed baseline receipt")
    summary = verify(audit, baseline, root)
    summary["auditSha256"] = digest(args.audit)
    summary["baselineSha256"] = digest(args.baseline)
    summary["verifierSha256"] = digest(__file__)
    # Exercise rejection of authority and label corruption in memory only.
    for field in ("promotionAllowed", "ordinaryCameraWired"):
        altered = dict(audit, **{field: True})
        try:
            verify(altered, baseline, root)
        except ValueError:
            continue
        raise ValueError(f"Tampered {field} was accepted")
    summary["tamperedAuthorityCopiesRejected"] = 2
    altered = dict(audit, frames=list(audit["frames"]))
    altered["frames"][1] = altered["frames"][0]
    try:
        verify(altered, baseline, root)
    except ValueError:
        summary["tamperedDuplicateMatrixRejected"] = True
    else:
        raise ValueError("Duplicate intervention matrix accepted")
    for name, content in (("summary.json", json.dumps(summary, indent=2) + "\n"),
                          ("report.md", render(summary))):
        with (args.audit.parent / name).open("x", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
    print(json.dumps({"checked": summary["interventionRows"], "baseline": summary["baselineComparisons"],
                      "groups": summary["groups"], "history": summary["historyComparisons"]}, indent=2))


if __name__ == "__main__":
    main()

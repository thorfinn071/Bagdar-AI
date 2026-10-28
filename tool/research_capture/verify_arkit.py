"""Serial software verification; no implicit iPhone or Android readiness."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--baseline", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("Choose a new verification directory.")
    output.mkdir(parents=True)
    flutter = "flutter.bat" if os.name == "nt" else "flutter"
    env = dict(os.environ, BAGDAR_TEST_ARKIT_DART="1")
    stages = [
      ("python-contracts", [sys.executable, "-m", "unittest", "discover", "-s", "tool/research_capture", "-p", "test_*.py", "-v"]),
      ("recorded-rgbd-tests", [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "test/recorded_rgbd_test.dart"]),
      ("positive-producer", [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "--dart-define=BAGDAR_CLOSED_AUDIT=true", "--dart-define=BAGDAR_CHECK_CLOSED_AUDIT=true", "test/closed_volume_control_source_audit_test.dart"]),
      ("positive-runtime-and-faults", [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "--dart-define=BAGDAR_CLOSED_CONTROL=true", "--dart-define=BAGDAR_CHECK_CLOSED=true", "test/closed_volume_control_test.dart"]),
      ("original-unavailable-control", [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "--dart-define=BAGDAR_HOLDOUT_AUDIT=true", "--dart-define=BAGDAR_CHECK_HOLDOUT_AUDIT=true", "test/volume_holdout_source_audit_test.dart"]),
      ("analysis", [flutter, "analyze", "--no-pub"]),
      ("full-flutter", [flutter, "test", "--no-pub", "--concurrency=1", "--reporter", "expanded", "--dart-define=BAGDAR_RC=true"]),
    ]
    result = {"schemaVersion": 1, "scope": "host-software-and-known-synthetic-regressions",
      "startedAtUtc": datetime.now(timezone.utc).isoformat(), "stages": [],
      "xcodeBuild": "not_run", "nativeXCTest": "not_run", "iphoneLifecycle": "not_run",
      "realCaptures": "not_run", "physicalCalibration": "not_run", "android": "not_run",
      "controlledWalking": "not_run", "genericObstacleDelivery": "shadow",
      "falseStopReductionEstablished": False, "ordinaryCameraWired": False, "promotionAllowed": False}
    success = True
    try:
        info = ROOT/"tool/research_capture/ios/BagdarCapture/Info.plist"
        plistlib.load(info.open("rb"))
        ET.parse(ROOT/"tool/research_capture/ios/BagdarCapture.xcodeproj/xcshareddata/xcschemes/BagdarCapture.xcscheme")
        from arkit_experiment import protocol
        if json.loads((ROOT/"tool/research_capture/arkit_protocol.json").read_text()) != protocol():
            raise ValueError("Checked-in protocol does not match generator")
        for name, command in stages:
            log = output/(name+".log")
            with log.open("w", encoding="utf-8") as stream:
                run = subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                                     stderr=subprocess.STDOUT, text=True)
            text = log.read_text(encoding="utf-8")
            stage = {"name": name, "command": command, "exitCode": run.returncode,
                     "log": log.name, "logSha256": sha(log)}
            matches = re.findall(r"\+(\d+)(?: ~(\d+))?(?: -(\d+))?: All tests passed!", text)
            if matches:
                passed, skipped, failed = matches[-1]
                stage.update(passed=int(passed), skipped=int(skipped or 0), failed=int(failed or 0))
            if name == "python-contracts":
                match = re.search(r"Ran (\d+) tests", text)
                if match: stage["tests"] = int(match[1])
            result["stages"].append(stage)
            print(f"{name}: exit={run.returncode}", flush=True)
            print("\n".join(text.splitlines()[-3:]), flush=True)
            if run.returncode:
                success = False
                break
        if args.baseline:
            baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
            drift = [path for path, fingerprint in baseline["files"].items()
                     if not (ROOT/path).is_file() or sha(ROOT/path) != fingerprint]
            result["preExistingSourceAndReceiptPreservation"] = {
                "files": len(baseline["files"]), "changedOrMissing": drift,
                "baselineSha256": sha(args.baseline)}
            success = success and not drift
        paths = [p for directory in ("lib/research", "tool/research_capture")
                 for p in (ROOT/directory).rglob("*") if p.is_file() and
                 p.suffix in (".dart", ".py", ".swift", ".plist", ".pbxproj", ".json", ".sh", ".md", ".xcscheme")]
        paths.append(ROOT/"test/recorded_rgbd_test.dart")
        result["taskSourceSha256"] = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(paths)}
    except Exception as error:
        success = False
        result["error"] = str(error)
    result.update(softwareChecksPassed=success, finishedAtUtc=datetime.now(timezone.utc).isoformat())
    (output/"verification.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
    print(f"Software receipt: {output/'verification.json'}", flush=True)
    return 0 if success else 1


if __name__ == "__main__":
    raise SystemExit(main())

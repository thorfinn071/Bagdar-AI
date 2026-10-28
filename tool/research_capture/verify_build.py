"""Check flavor isolation and saved Research test/build evidence on this checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

from audit_capture import require

REPO = Path(__file__).resolve().parents[2]
ANDROID = "{http://schemas.android.com/apk/res/android}"
CLASS = "com.example.bagdar.capture.SingleOwnerCaptureActivity"
DEX_PACKAGE = b"com/example/bagdar/capture/"


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for data in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def verify():
    receipts = {}
    for flavor, expected in (("research", True), ("core", False)):
        manifest = REPO / f"build/app/intermediates/merged_manifests/{flavor}Debug/process{flavor.title()}DebugManifest/AndroidManifest.xml"
        activities = ET.parse(manifest).getroot().findall("application/activity")
        matches = [a for a in activities if a.get(ANDROID + "name") == CLASS]
        require(bool(matches) == expected, f"{flavor}: capture manifest boundary broken")
        if expected:
            require(len(matches) == 1 and matches[0].get(ANDROID + "process") == ":capture", "capture must use separate process")
        apk = REPO / f"build/app/outputs/apk/{flavor}/debug/app-{flavor}-debug.apk"
        with zipfile.ZipFile(apk) as package:
            dex = [n for n in package.namelist() if n.startswith("classes") and n.endswith(".dex")]
            require(dex, "APK has no dex")
            included = any(DEX_PACKAGE in package.read(n) for n in dex)
            require(included == expected, f"{flavor}: capture dex boundary broken")
            abis = sorted({n.split("/")[1] for n in package.namelist() if n.startswith("lib/") and n.endswith(".so")})
        receipts[flavor] = {"apk": str(apk), "sha256": sha(apk), "bytes": apk.stat().st_size,
                            "nativeLibraryAbis": abis, "captureEntryPresent": expected}
    suites = []
    for name, count in (("CapturePairContractTest", 10), ("CapturePlanePackerTest", 6)):
        report = REPO / f"build/app/test-results/testResearchDebugUnitTest/TEST-com.example.bagdar.capture.{name}.xml"
        suite = ET.parse(report).getroot()
        require(int(suite.get("tests", "0")) == count and all(int(suite.get(k, "0")) == 0 for k in ("failures", "errors", "skipped")), "Research unit tests did not pass")
        suites.append({"name": name, "passed": count, "timestamp": suite.get("timestamp"), "reportSha256": sha(report)})
    sources = {}
    for source in sorted((REPO / "android/app/src/research/kotlin/com/example/bagdar/capture").glob("*.kt")):
        sources[source.relative_to(REPO).as_posix()] = sha(source)
    for source in sorted((REPO / "android/app/src/testResearch/kotlin/com/example/bagdar/capture").glob("*.kt")):
        sources[source.relative_to(REPO).as_posix()] = sha(source)
    for source in sorted((REPO / "tool/research_capture").glob("*.py")):
        sources[source.relative_to(REPO).as_posix()] = sha(source)
    for name in ("android/app/src/research/AndroidManifest.xml", "android/app/build.gradle.kts"):
        sources[name] = sha(REPO / name)
    return {"schema": "bagdar-research-capture-build-v1", "softwareBuildPassed": True,
            "flavorIsolationPassed": True, "apks": receipts, "newKotlinTestsPassed": 16,
            "testSuites": suites, "sourceHashes": sources, "deviceRuntime": "not_run",
            "physicalAlignmentValidated": False, "clockBindingValidated": False,
            "safetyReplayReady": False, "promotionAllowed": False, "ordinaryCameraWired": False}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = verify()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: receipt[k] for k in ("softwareBuildPassed", "flavorIsolationPassed", "newKotlinTestsPassed", "deviceRuntime", "promotionAllowed")}))

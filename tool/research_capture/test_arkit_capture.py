import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

from arkit_capture import (AUTHORITY, ENCODINGS, FORMAT, MAX_PAYLOAD, POSE,
                           CaptureError, audit, import_archive)
from arkit_experiment import calibration_report, protocol, score


class ArkitCaptureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base/"capture"
        self.root.mkdir()
        self.rid = "capture-00000000-0000-0000-0000-000000000001"
        self.manifest = {"format": FORMAT, "schemaVersion": 1, "recordingId": self.rid,
          "sessionId": self.rid, "source": "recorded", "consentConfirmed": True,
          "deviceModel": "SYNTHETIC CONTRACT FIXTURE", "osVersion": "fixture", "recorderVersion": "1.0.0",
          "recorderSourceId": "unfrozen-development",
          "cameraOwner": "native_arkit_only", "depthMode": "ARKIT_SCENE_DEPTH_ESTIMATE",
          "flutterEngineCreated": False, "poseConvention": POSE,
          "sourceTimestampDomain": "arkit_frame_seconds_unverified", "receiveTimestampDomain": "dispatch_uptime_ns",
          "recordingStatus": "complete", "maxFrames": 300, "maxDurationNs": 10_000_000_000,
          "maxPayloadBytes": MAX_PAYLOAD, "startedUptimeNs": 100, "stoppedUptimeNs": 900,
          "droppedFrames": {}, "receivedFrames": 1, **AUTHORITY}
        self.row = {"frameIndex": 0, "frameId": 1, "sessionId": self.rid, "sessionGeneration": 1,
          "sourceTimestampSeconds": 1., "sourceTimestampBits": "3ff0000000000000", "sourceTimestampUs": 1000000,
          "receivedUptimeNs": 200, "payloadsReadyUptimeNs": 300,
          "poseConvention": POSE, "cameraTransform": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1],
          "intrinsics": [2, 0, 0, 0, 2, 0, 1, 1, 1], "imageResolution": [2, 2],
          "trackingState": "normal", "orientation": "portrait", "rgbPixelFormat": 875704422,
          "rgbColorRange": "full", "rgbYCbCrMatrix": "ITU_R_601_4"}
        self.row["rgb"] = self.image("rgb", [b"\x10"*4, b"\x80\x80"])
        self.row["depth"] = self.image("depth", [struct.pack("<ffff", 1, 0, float("nan"), 3)])
        self.row["confidence"] = self.image("confidence", [bytes([2, 2, 2, 1])])
        self.row["validity"] = self.image("validity", [bytes([1, 0, 0, 1])])

    def image(self, kind, payloads):
        descriptors = []
        for i, raw in enumerate(payloads):
            w = h = 1 if kind == "rgb" and i == 1 else 2
            bpp = 4 if kind == "depth" else 2 if kind == "rgb" and i == 1 else 1
            path = f"payloads/1-{kind}-{i}.bin"
            (self.root/"payloads").mkdir(exist_ok=True)
            (self.root/path).write_bytes(raw)
            descriptors.append({"path": path, "sha256": hashlib.sha256(raw).hexdigest(), "byteLength": len(raw),
              "width": w, "height": h, "bytesPerPixel": bpp, "sourceRowStride": w*bpp+8,
              "packing": "row_major_samples_without_padding"})
        return {"encoding": ENCODINGS[kind], "frameId": 1, "sourceTimestampUs": 1000000,
                "width": 2, "height": 2, "planes": descriptors}

    def seal(self, rows=None):
        rows = [self.row] if rows is None else rows
        raw = ("\n".join(json.dumps(row, allow_nan=False) for row in rows)+"\n").encode()
        (self.root/"frames.jsonl").write_bytes(raw)
        self.manifest.update(frameCount=len(rows), frames={"path": "frames.jsonl",
          "sha256": hashlib.sha256(raw).hexdigest(), "byteLength": len(raw)},
          payloadBytes=sum(p.stat().st_size for p in (self.root/"payloads").iterdir()))
        (self.root/"manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def run_audit(self):
        self.seal()
        return audit(self.root, self.rid)

    def test_native_invalid_depth_and_confidence_preserved(self):
        r = self.run_audit()
        self.assertEqual(r["sameFrameCandidates"], 1)
        pixels = r["frames"][0]["nativePixelAvailability"]
        self.assertEqual(pixels["finitePositivePixels"], 2)
        self.assertEqual(pixels["highConfidencePixels"], 1)
        self.assertFalse(pixels["wholePixelBoundsAvailable"])
        self.assertTrue(all(r[k] is False for k in AUTHORITY))
        self.assertIsNone(r["captureToDecisionMs"])

    def test_recording_selection(self):
        self.seal()
        with self.assertRaisesRegex(CaptureError, "selection"):
            audit(self.root, self.rid[:-1]+"2")

    def test_partial_and_failed_are_rejected(self):
        for status in ("partial", "failed"):
            with self.subTest(status=status):
                self.manifest["recordingStatus"] = status
                with self.assertRaisesRegex(CaptureError, "partial/failed"):
                    self.run_audit()

    def test_clock_relabelling_and_claims_rejected(self):
        for key, value in [("sourceTimestampDomain", "utc"), ("cameraOwner", "flutter_and_arkit"),
                           ("depthMode", "RAW_LIDAR"), *[(k, True) for k in AUTHORITY]]:
            with self.subTest(key=key):
                saved = self.manifest[key]
                self.manifest[key] = value
                with self.assertRaises(CaptureError):
                    self.run_audit()
                self.manifest[key] = saved

    def test_hash_corruption(self):
        self.seal()
        (self.root/self.row["depth"]["planes"][0]["path"]).write_bytes(b"\x00"*16)
        with self.assertRaisesRegex(CaptureError, "hash"):
            audit(self.root, self.rid)

    def test_malformed_json_root_and_plane_descriptor(self):
        self.seal()
        (self.root/"manifest.json").write_text("[]", encoding="utf-8")
        with self.assertRaisesRegex(CaptureError, "root"):
            audit(self.root, self.rid)
        self.row["depth"]["planes"] = [None]
        with self.assertRaisesRegex(CaptureError, "plane descriptor"):
            self.run_audit()

    def test_short_stride(self):
        self.row["depth"]["planes"][0]["sourceRowStride"] = 1
        with self.assertRaisesRegex(CaptureError, "stride"):
            self.run_audit()

    def test_mismatched_payload_frame_and_timestamp(self):
        for key, value in (("frameId", 2), ("sourceTimestampUs", 1000001)):
            original = self.row["depth"][key]
            self.row["depth"][key] = value
            with self.assertRaisesRegex(CaptureError, "frame mismatch"):
                self.run_audit()
            self.row["depth"][key] = original

    def test_session_and_axes(self):
        for key, value in (("sessionId", "foreign"), ("poseConvention", "left_handed")):
            original = self.row[key]; self.row[key] = value
            with self.assertRaises(CaptureError): self.run_audit()
            self.row[key] = original

    def test_reflected_or_scaled_pose(self):
        for value in (-1, 2):
            self.row["cameraTransform"][0] = value
            with self.assertRaises(CaptureError): self.run_audit()

    def test_invalid_mask_cannot_fill_nan(self):
        self.row["validity"] = self.image("validity", [bytes([1, 0, 1, 1])])
        with self.assertRaisesRegex(CaptureError, "validity"):
            self.run_audit()

    def test_missing_confidence_is_not_a_candidate(self):
        (self.root/self.row["confidence"]["planes"][0]["path"]).unlink()
        self.row["confidence"] = None
        r = self.run_audit()
        self.assertEqual(r["sameFrameCandidates"], 0)
        self.assertIn("confidence_unavailable", r["frames"][0]["unavailableReasons"])

    def test_confidence_code_is_not_probability(self):
        self.row["confidence"] = self.image("confidence", [bytes([255]*4)])
        with self.assertRaisesRegex(CaptureError, "confidence"):
            self.run_audit()

    def test_received_after_stop_and_timestamp_bits(self):
        for key, value in (("receivedUptimeNs", 901), ("sourceTimestampBits", "0"*16),
                           ("sourceTimestampUs", 999999)):
            original = self.row[key]; self.row[key] = value
            with self.assertRaises(CaptureError): self.run_audit()
            self.row[key] = original

    def test_unreferenced_payload_rejected(self):
        (self.root/"payloads/extra.bin").write_bytes(b"extra")
        with self.assertRaises(CaptureError): self.run_audit()

    def test_duplicate_or_rolled_back_source_frame(self):
        for stamp in (1000000, 999999):
            row = copy.deepcopy(self.row)
            row.update(frameIndex=1, frameId=2, sourceTimestampUs=stamp,
                       sourceTimestampSeconds=stamp/1000000,
                       sourceTimestampBits=struct.pack(">d", stamp/1000000).hex())
            self.manifest["receivedFrames"] = 2
            self.seal([self.row, row])
            with self.assertRaisesRegex(CaptureError, "source timestamp"):
                audit(self.root, self.rid)

    def test_rgb_resolution_and_count_accounting(self):
        self.row["imageResolution"] = [3, 2]
        with self.assertRaisesRegex(CaptureError, "resolution"):
            self.run_audit()
        self.row["imageResolution"] = [2, 2]
        self.manifest["receivedFrames"] = True
        with self.assertRaisesRegex(CaptureError, "received frame count"):
            self.run_audit()

    def archive(self, name="capture.zip"):
        path = self.base/name
        with zipfile.ZipFile(path, "w") as z:
            for p in self.root.rglob("*"):
                if p.is_file(): z.write(p, p.relative_to(self.root).as_posix())
        return path

    def test_archive_roundtrip_and_no_overwrite(self):
        self.seal(); path = self.archive(); output = self.base/"imported"
        self.assertTrue(import_archive(path, output, self.rid)["integrityPassed"])
        with self.assertRaisesRegex(CaptureError, "already exists"):
            import_archive(path, output, self.rid)

    def test_zip_traversal_link_duplicate(self):
        for mode in ("traversal", "link", "duplicate"):
            path = self.base/f"{mode}.zip"
            with zipfile.ZipFile(path, "w") as z:
                if mode == "traversal": z.writestr("../escape", b"bad")
                elif mode == "link":
                    info = zipfile.ZipInfo("link"); info.external_attr = 0o120777 << 16
                    z.writestr(info, "../bad")
                else:
                    import warnings
                    with warnings.catch_warnings():
                        warnings.simplefilter("ignore")
                        z.writestr("manifest.json", b"a"); z.writestr("manifest.json", b"b")
            with self.assertRaises(CaptureError):
                import_archive(path, self.base/f"out-{mode}", self.rid)

    def test_recorded_media_cannot_be_imported_into_git(self):
        self.seal(); path = self.archive()
        repo = self.base/"another-repository"
        (repo/".git").mkdir(parents=True)
        with self.assertRaisesRegex(CaptureError, "outside Git"):
            import_archive(path, repo/"capture", self.rid)
        self.assertFalse((repo/"capture").exists())

    def test_calibration_does_not_promote_samples(self):
        receipt = self.run_audit()
        result = calibration_report(self.root, self.rid, {"recordingId": self.rid,
          "captureManifestSha256": receipt["manifestSha256"], "scope": "calibration-only",
          "independentReferenceAssertion": True, "samples": [{"frameId": 1, "x": 0, "y": 0,
          "referenceCameraAxisM": .99, "referenceToleranceM": .005, "targetDistanceM": 1,
          "region": "centre"}]})
        self.assertAlmostEqual(result["empiricalSampleErrorM"], .015)
        self.assertFalse(result["supportsPassageClearance"])
        self.assertFalse(result["metricErrorBoundsValidated"])

    def test_empirical_alignment_and_floor_are_separate_from_authority(self):
        receipt = self.run_audit()
        result = calibration_report(self.root, self.rid, {"recordingId": self.rid,
          "captureManifestSha256": receipt["manifestSha256"], "scope": "calibration-only",
          "independentReferenceAssertion": True,
          "diagnosticWorldToWalkingRowMajor": [1,0,0,0,0,0,-1,0,0,1,0,1.42,0,0,0,1],
          "samples": [{"frameId": 1, "x": 0, "y": 0, "referenceCameraAxisM": 1,
          "referenceToleranceM": .005, "targetDistanceM": 1, "region": "centre",
          "independentRgbFeaturePixel": [.5, .5]}],
          "floorReferenceSamples": [{"frameId": 1, "x": 0, "y": 0,
            "referenceHeightM": 0, "referenceToleranceM": .005}]})
        self.assertEqual(result["alignmentSamples"][0]["residualPixels"], 0)
        self.assertAlmostEqual(result["floorReferenceSamples"][0]["absoluteHeightErrorM"], 1.67)
        self.assertEqual(result["alignmentStatus"], "empirical-residuals-only")
        self.assertFalse(result["physicalAlignmentValidated"])
        self.assertFalse(result["floorReferenceValidated"])

    def test_dart_feasibility_end_to_end_if_enabled(self):
        import os
        if os.environ.get("BAGDAR_TEST_ARKIT_DART") != "1":
            self.skipTest("opt-in Dart process (run with BAGDAR_TEST_ARKIT_DART=1)")
        receipt = self.run_audit()
        audit_path = self.base/"audit.json"
        audit_path.write_text(json.dumps(receipt), encoding="utf-8")
        command = ["dart.bat" if sys.platform == "win32" else "dart", "run",
                   "tool/research_capture/analyze_arkit.dart", str(self.root), str(audit_path), str(self.base/"analysis")]
        run = subprocess.run(command, capture_output=True, text=True, timeout=90)
        self.assertEqual(run.returncode, 2, run.stdout+run.stderr)
        report = json.loads((self.base/"analysis/feasibility.json").read_text())
        self.assertEqual(report["measuredClearFrames"], 0)
        self.assertEqual(report["frames"][0]["runtimeDecisionStatus"], "not_run")
        self.assertTrue((self.base/"analysis/coverage.svg").exists())
        profile = {"format": "bagdar-physical-evidence-profile-v1", "schemaVersion": 1,
          "id": "empirical", "recordingId": self.rid, "captureManifestSha256": receipt["manifestSha256"],
          "diagnosticWorldToWalkingRowMajor": [1,0,0,0,0,0,-1,0,0,1,0,1.42,0,0,0,1],
          "empiricalSampleErrorM": .01}
        profile_path = self.base/"profile.json"
        profile_path.write_text(json.dumps(profile), encoding="utf-8")
        placed_command = command[:-1]+[str(self.base/"analysis-placed"), str(profile_path)]
        run = subprocess.run(placed_command, capture_output=True, text=True, timeout=90)
        self.assertEqual(run.returncode, 2, run.stdout+run.stderr)
        placed = json.loads((self.base/"analysis-placed/feasibility.json").read_text())
        self.assertGreater(placed["frames"][0]["geometry"]["nearGapM"], 0)
        profile["wholePixelBoundsValidated"] = True
        profile_path.write_text(json.dumps(profile), encoding="utf-8")
        run = subprocess.run(command[:-1]+[str(self.base/"analysis-fake-proof"), str(profile_path)],
                             capture_output=True, text=True, timeout=90)
        self.assertEqual(run.returncode, 1)
        self.assertFalse((self.base/"analysis-fake-proof").exists())


class ProtocolMetricTest(unittest.TestCase):
    def test_plan_is_not_a_corpus(self):
        p = protocol()
        self.assertEqual(len(p["recordings"]), 72)
        self.assertEqual(len({r["planId"] for r in p["recordings"]}), 72)
        self.assertEqual(sum(r["split"] == "holdout" for r in p["recordings"]), 36)
        self.assertEqual(p["humanCollectionStatus"], "not_run")

    def inputs(self):
        labels = {"schemaVersion": 1, "split": "holdout", "candidateFreezeSha256": "a"*64,
          "frames": [{"recordingId": "one", "frameId": i, "scenario": "wide-corridor" if i < 3 else "box-in-path",
          "class": "passable" if i < 3 else "hazard"} for i in (1, 2, 3)]}
        decisions = {"schemaVersion": 1, "split": "holdout", "candidateFreezeSha256": "a"*64,
          "frames": [{"recordingId": "one", "frameId": i,
          "baseline": {"action": "stopNow"}, "candidate": {"action": "stopNow", "providerStatus": "unavailable"}}
          for i in (1, 2, 3)]}
        return labels, decisions

    def test_unknown_free_frames_remain_in_denominator(self):
        labels, decisions = self.inputs(); r = score(labels, decisions)
        self.assertEqual(r["summary"]["candidate"]["falseStopRate"], 1)
        self.assertEqual(r["summary"]["candidate"]["unavailableFrames"], 3)
        self.assertFalse(r["physicalGatePassed"])

    def test_dangerous_continue_and_fake_proof_rejected_as_success(self):
        labels, decisions = self.inputs()
        decisions["frames"][2]["candidate"] = {"action": "continueForward", "proofStatus": "measuredClear"}
        r = score(labels, decisions)
        self.assertEqual(r["summary"]["candidate"]["unsafeContinueFrames"], 1)
        self.assertEqual(r["unprovedCandidateContinues"], 1)
        self.assertFalse(r["numericGatePassed"])

    def test_missing_duplicate_and_foreign_freeze(self):
        labels, original = self.inputs()
        for variant in ("missing", "duplicate", "freeze"):
            decisions = copy.deepcopy(original)
            if variant == "missing": decisions["frames"].pop()
            if variant == "duplicate": decisions["frames"].append(decisions["frames"][0])
            if variant == "freeze": decisions["candidateFreezeSha256"] = "b"*64
            with self.assertRaises(CaptureError): score(labels, decisions)

    def test_wait_only_is_not_useful_false_stop_reduction(self):
        labels, decisions = self.inputs()
        for frame in decisions["frames"][:2]: frame["candidate"]["action"] = "wait"
        result = score(labels, decisions)
        self.assertEqual(result["relativeFalseStopReduction"], 1)
        self.assertEqual(result["summary"]["candidate"]["passableContinueFrames"], 0)
        self.assertFalse(result["numericGatePassed"])


if __name__ == "__main__":
    unittest.main()

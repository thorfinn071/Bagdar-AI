import copy
from contextlib import redirect_stdout
import hashlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from audit_capture import audit, CaptureError, BLOCKED, ENCODINGS
import pull_capture


class CaptureAuditTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.manifest = {
            "format": "bagdar-native-capture-v1", "schemaVersion": 1,
            "recordingId": "capture-00000000-0000-0000-0000-000000000001",
            "source": "recorded", "consentConfirmed": True, "deviceModel": "SYNTHETIC CONTRACT FIXTURE",
            "cameraOwner": "native_arcore_only", "flutterEngineCreated": False,
            "depthMode": "RAW_DEPTH_ONLY", "sourceTimestampDomain": "arcore_camera_ns_unverified",
            "receiveTimestampDomain": "elapsedRealtimeNs", "recordingStatus": "complete",
            "maxFrames": 30, "maxDurationNs": 10_000_000_000,
            "sampleIntervalNs": 200_000_000, "maxPayloadBytes": 64 * 1024 * 1024,
            "startedElapsedNs": 100, "stoppedElapsedNs": 900,
            **{k: False for k in BLOCKED},
        }
        self.row = {
            "frameIndex": 0, "frameId": 1, "sessionGeneration": 1, "frameTimestampNs": 12345,
            "receivedElapsedNs": 200, "payloadsReadyElapsedNs": 300, "trackingState": "TRACKING",
            "cameraPose": {"convention": "arcore_world_right_up_negative_z_forward",
                           "translationM": [0, 0, 0], "rotationQuaternionXyzw": [0, 0, 0, 1]},
            "imageIntrinsics": {"imageDimensions": [2, 2], "focalLength": [2, 2], "principalPoint": [1, 1]},
            "textureIntrinsics": {"imageDimensions": [2, 2], "focalLength": [2, 2], "principalPoint": [1, 1]},
            "imageToTextureGrid": {"physicalAlignmentValidated": False,
                                   "inputImagePixels": [0] * 18, "outputTextureNormalized": [0] * 18},
            "pairStatus": "same_frame_candidate", "pairReasons": [],
        }
        self.row["rgb"] = self.image("rgb", [bytes([16] * 4), b"\x80", b"\x80"])
        self.row["rawDepth"] = self.image("rawDepth", [b"\x00\x00\xe8\x03\xd0\x07\xb8\x0b"])
        self.row["confidence"] = self.image("confidence", [bytes([0, 255, 64, 0])])

    def image(self, kind, payloads):
        planes = []
        for index, data in enumerate(payloads):
            w = h = 1 if kind == "rgb" and index > 0 else 2
            bpp = 2 if kind == "rawDepth" else 1
            native_kind = "depth" if kind == "rawDepth" else kind
            path = f"payloads/0000-{native_kind}-{index}.bin"
            target = self.root / path
            target.parent.mkdir(exist_ok=True)
            target.write_bytes(data)
            planes.append({"path": path, "sha256": hashlib.sha256(data).hexdigest(),
                           "width": w, "height": h, "bytesPerPixel": bpp, "byteLength": len(data),
                           "sourcePixelStride": bpp, "sourceRowStride": w * bpp,
                           "packing": "row_major_samples_without_padding"})
        return {"width": 2, "height": 2, "timestampNs": 12345, "androidImageFormat": 35,
                "encoding": ENCODINGS[kind], "cropRect": [0, 0, 2, 2], "planes": planes,
                "coordinateSpace": "arcore_cpu_image_native" if kind == "rgb" else "arcore_raw_depth_native_gpu_aspect"}

    def seal(self, rows=None):
        rows = [self.row] if rows is None else rows
        data = "".join(json.dumps(r, allow_nan=True) + "\n" for r in rows).encode()
        (self.root / "frames.jsonl").write_bytes(data)
        self.manifest.update(frameCount=len(rows), payloadBytes=sum(p.stat().st_size for p in (self.root / "payloads").glob("*")),
                             frames={"path": "frames.jsonl", "sha256": hashlib.sha256(data).hexdigest()})
        (self.root / "manifest.json").write_text(json.dumps(self.manifest), encoding="utf-8")

    def result(self):
        self.seal()
        return audit(self.root)

    def test_exact_pair_reports_availability_without_promoting(self):
        result = self.result()
        self.assertEqual(result["sameFrameCandidates"], 1)
        pixels = result["frames"][0]["nativePixelAvailability"]
        self.assertEqual((pixels["nonzeroDepthAndConfidencePixels"], pixels["unknownPixels"]), (2, 2))
        self.assertEqual(pixels["zeroDepthPixels"], 1)
        self.assertEqual(pixels["confidenceHistogramNonzeroDepth"]["192-255"], 1)
        self.assertFalse(result["safetyReplayReady"])
        self.assertFalse(result["spatialRecordingV2Ready"])
        self.assertIsNone(result["captureAgeMs"])
        self.assertTrue(all(result[k] is False for k in BLOCKED))

    def test_zero_depth_with_high_confidence_stays_unknown(self):
        self.row["rawDepth"] = self.image("rawDepth", [b"\x00" * 8])
        self.row["confidence"] = self.image("confidence", [b"\xff" * 4])
        self.assertEqual(self.result()["frames"][0]["nativePixelAvailability"]["unknownPixels"], 4)

    def test_reprojected_depth_is_retained_but_unavailable(self):
        for kind in ("rawDepth", "confidence"):
            self.row[kind]["timestampNs"] -= 1
        self.row.update(pairStatus="unavailable", pairReasons=["depth_not_new_for_frame"])
        self.assertEqual(self.result()["sameFrameCandidates"], 0)

    def test_future_depth_cannot_be_self_declared_candidate(self):
        self.row["rawDepth"]["timestampNs"] += 1
        with self.assertRaisesRegex(CaptureError, "pair admission"):
            self.result()

    def test_paused_pose_and_missing_depth_are_explicit(self):
        for kind in ("rawDepth", "confidence"):
            for plane in self.row[kind]["planes"]:
                (self.root / plane["path"]).unlink()
            self.row[kind] = None
        self.row.update(trackingState="PAUSED", pairStatus="unavailable", pairReasons=[
            "raw_depth_unavailable", "confidence_unavailable", "pose_not_tracking", "depth_confidence_dimensions_mismatch"])
        result = self.result()
        self.assertEqual(result["sameFrameCandidates"], 0)
        self.assertEqual(result["unavailableReasons"]["pose_not_tracking"], 1)

    def test_clock_domains_cannot_be_relabelled(self):
        self.manifest["sourceTimestampDomain"] = "elapsedRealtimeNs"
        with self.assertRaisesRegex(CaptureError, "clock relabelled"):
            self.result()

    def test_all_promotion_flags_are_guarded(self):
        for flag in BLOCKED:
            with self.subTest(flag=flag):
                self.manifest[flag] = True
                with self.assertRaisesRegex(CaptureError, "cannot grant"):
                    self.result()
                self.manifest[flag] = False

    def test_payload_hash_detects_corruption(self):
        (self.root / self.row["rawDepth"]["planes"][0]["path"]).write_bytes(b"\xff" * 8)
        with self.assertRaisesRegex(CaptureError, "hash mismatch"):
            self.result()

    def test_relative_path_cannot_escape(self):
        self.row["rawDepth"]["planes"][0]["path"] = "payloads/../../secret.bin"
        with self.assertRaisesRegex(CaptureError, "escapes"):
            self.result()

    def test_truncated_plane_is_rejected_even_with_matching_hash(self):
        self.row["rawDepth"] = self.image("rawDepth", [b"\x00" * 7])
        with self.assertRaisesRegex(CaptureError, "payload length"):
            self.result()

    def test_nonfinite_pose_is_rejected(self):
        self.row["cameraPose"]["translationM"][0] = float("nan")
        with self.assertRaisesRegex(CaptureError, "nonfinite"):
            self.result()

    def test_missing_pose_is_rejected(self):
        self.row.pop("cameraPose")
        with self.assertRaisesRegex(CaptureError, "pose"):
            self.result()

    def test_intrinsics_mismatch_is_not_admitted(self):
        self.row["imageIntrinsics"]["imageDimensions"][0] = 3
        with self.assertRaisesRegex(CaptureError, "admission"):
            self.result()

    def test_receive_clock_rollback_is_rejected(self):
        self.row["payloadsReadyElapsedNs"] = 199
        with self.assertRaisesRegex(CaptureError, "ready time"):
            self.result()

    def test_frame_identity_and_source_clock_are_guarded(self):
        for field, value in (("sessionGeneration", 2), ("frameId", 2), ("frameTimestampNs", 0)):
            with self.subTest(field=field):
                original = self.row[field]
                self.row[field] = value
                with self.assertRaises(CaptureError):
                    self.result()
                self.row[field] = original

    def test_partial_recording_has_no_final_receipt(self):
        with self.assertRaisesRegex(CaptureError, "partial"):
            audit(self.root)

    def test_failed_capture_retains_orphan_diagnostic_without_admission(self):
        (self.root / "payloads/orphan.bin").write_bytes(b"\x01")
        self.manifest["recordingStatus"] = "failed"
        result = self.result()
        self.assertFalse(result["finalizedNonemptyCapture"])
        self.assertEqual(result["orphanPayloads"], ["payloads/orphan.bin"])

    def test_complete_capture_cannot_hide_orphan_payload(self):
        (self.root / "payloads/orphan.bin").write_bytes(b"\x01")
        with self.assertRaisesRegex(CaptureError, "unreferenced"):
            self.result()

    def test_empty_capture_never_becomes_data_evidence(self):
        for path in (self.root / "payloads").glob("*"):
            path.unlink()
        self.seal([])
        result = audit(self.root)
        self.assertFalse(result["finalizedNonemptyCapture"])
        self.assertEqual(result["sameFrameCandidates"], 0)

    def test_duplicate_source_frames_rejected_before_payload_reuse(self):
        second = copy.deepcopy(self.row)
        second.update(frameIndex=1, frameId=2, receivedElapsedNs=400, payloadsReadyElapsedNs=500)
        self.seal([self.row, second])
        with self.assertRaisesRegex(CaptureError, "frame time"):
            audit(self.root)

    def test_manifest_only_audit_does_not_claim_selection_binding(self):
        result = self.result()
        self.assertIsNone(result["expectedRecordingId"])
        self.assertFalse(result["recordingSelectionMatched"])
        self.assertEqual(result["sourceProvenance"], "manifest_self_report_only")

    def test_matching_selection_preserves_manifest_provenance_and_blocked_flags(self):
        self.seal()
        result = audit(self.root, expected_recording_id=self.manifest["recordingId"])
        self.assertEqual(result["expectedRecordingId"], self.manifest["recordingId"])
        self.assertTrue(result["recordingSelectionMatched"])
        self.assertEqual(result["sourceProvenance"], "manifest_self_report_only")
        self.assertTrue(all(result[k] is False for k in BLOCKED))
        self.assertFalse(result["safetyReplayReady"])

    def test_selected_recording_cannot_be_replaced_by_another_manifest(self):
        self.seal()
        other = "capture-00000000-0000-0000-0000-000000000002"
        with self.assertRaisesRegex(CaptureError, "recording ID does not match selection"):
            audit(self.root, expected_recording_id=other)

    def test_invalid_selection_is_rejected(self):
        self.seal()
        for invalid in ("", "capture-other", "../capture", 1, True):
            with self.subTest(invalid=invalid), self.assertRaisesRegex(CaptureError, "invalid expected recording ID"):
                audit(self.root, expected_recording_id=invalid)

    def test_cli_selection_mismatch_writes_failure_receipt_and_keeps_inputs(self):
        self.seal()
        before = {p: p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        output = self.root / "audit.json"
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("audit_capture.py")),
            str(self.root), "--expected-recording-id", "capture-00000000-0000-0000-0000-000000000002",
            "--output", str(output)], capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 2, result.stderr)
        review = json.loads(output.read_text(encoding="utf-8"))
        self.assertFalse(review["integrityPassed"])
        self.assertIn("recording ID does not match selection", review["error"])
        self.assertFalse(review["promotionAllowed"])
        self.assertTrue(all(p.read_bytes() == data for p, data in before.items()))

    def export_with_mock_adb(self, selected_id):
        self.seal()
        archive = self.root / "device.tar"
        inputs = [self.root / "manifest.json", self.root / "frames.jsonl", *sorted((self.root / "payloads").glob("*"))]
        with tarfile.open(archive, "w") as tar:
            for path in inputs:
                tar.add(path, arcname=f"{selected_id}/{path.relative_to(self.root).as_posix()}")
        output = self.root / "export"
        receipt = self.root / "export-receipt.json"

        def fake_adb(command, **kwargs):
            if command[1:] == ["devices", "-l"]:
                return subprocess.CompletedProcess(command, 0, "List of devices attached\nTEST_PHONE device\n", "")
            if command[1:] == ["-s", "TEST_PHONE", "shell", "getprop", "ro.kernel.qemu"]:
                return subprocess.CompletedProcess(command, 0, "0\n", "")
            self.assertEqual(command[1:], ["-s", "TEST_PHONE", "exec-out", "run-as", pull_capture.PACKAGE,
                "tar", "-C", "files/research-captures", "-cf", "-", selected_id])
            kwargs["stdout"].write(archive.read_bytes())
            return subprocess.CompletedProcess(command, 0, None, b"")

        args = ["pull_capture.py", "--adb", "TEST_ADB", "--serial", "TEST_PHONE", "--recording", selected_id,
                "--output", str(output), "--receipt", str(receipt)]
        with patch.object(sys, "argv", args), patch.object(pull_capture.subprocess, "run", side_effect=fake_adb), redirect_stdout(io.StringIO()):
            status = pull_capture.main()
        return status, json.loads(receipt.read_text(encoding="utf-8")), output

    def test_export_binds_selected_id_to_manifest(self):
        status, receipt, output = self.export_with_mock_adb(self.manifest["recordingId"])
        self.assertEqual(status, 0, receipt)
        self.assertTrue(receipt["recordingSelectionMatched"])
        review = json.loads((output / "audit.json").read_text(encoding="utf-8"))
        self.assertTrue(review["recordingSelectionMatched"])
        self.assertEqual(review["expectedRecordingId"], receipt["recordingId"])
        self.assertFalse(receipt["promotionAllowed"])

    def test_export_rejects_renamed_directory_containing_another_capture(self):
        selected = "capture-00000000-0000-0000-0000-000000000002"
        status, receipt, output = self.export_with_mock_adb(selected)
        self.assertEqual(status, 2, receipt)
        self.assertIn("recording ID does not match selection", receipt["error"])
        self.assertNotIn("finalizedNonemptyCapture", receipt)
        self.assertFalse(receipt["promotionAllowed"])
        self.assertFalse(receipt["safetyReplayReady"])
        # Failed exports stay available for diagnosis, without a successful audit.
        self.assertTrue((output / "manifest.json").is_file())
        self.assertFalse((output / "audit.json").exists())


if __name__ == "__main__":
    unittest.main()

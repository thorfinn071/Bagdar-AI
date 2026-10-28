"""Admission failures must reject corrupted or relabelled evaluation inputs."""
import copy
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import verify_paired_scene_corpus as v


class PairedCorpusAdmissionTest(unittest.TestCase):
    def altered_manifest(self, change):
        original = v.read_json
        manifest = copy.deepcopy(original(v.CORPUS / "corpus-manifest.json"))
        change(manifest)
        def read(path):
            return manifest if Path(path) == v.CORPUS / "corpus-manifest.json" else original(path)
        return patch.object(v, "read_json", side_effect=read)

    def test_complete_new_pairs_and_visible_hazards(self):
        _, sequences = v.load_corpus()
        self.assertEqual(len(sequences), 12)
        self.assertEqual(sum(len(s["frames"]) for s in sequences), 132)
        self.assertEqual(sum(s["labels"]["physicalHazard"] for s in sequences), 6)
        self.assertEqual(sum(s["labels"]["referencePassable"] and s["labels"]["userMoving"] for s in sequences), 5)

    def test_asset_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "sample.bin").write_bytes(b"modified")
            with self.assertRaisesRegex(ValueError, "modified asset"):
                v.checked(root, {"path": "sample.bin", "sha256": hashlib.sha256(b"original").hexdigest()})

    def test_escaping_and_windows_absolute_paths_are_rejected(self):
        for path in ("../elsewhere.png", "C:/outside.png", "/outside.png", "a\\b.png"):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "Unsafe asset path"):
                v.checked(v.CORPUS, {"path": path, "sha256": "0" * 64})

    def test_missing_scene_rejects_the_entire_set(self):
        with self.altered_manifest(lambda m: m["sequences"].pop()), self.assertRaisesRegex(ValueError, "Incomplete or reordered"):
            v.load_corpus()

    def test_missing_frame_is_not_an_empty_safe_scene(self):
        with self.altered_manifest(lambda m: m["sequences"][0]["frames"].pop()), self.assertRaisesRegex(ValueError, "Incomplete frame"):
            v.load_corpus()

    def test_clock_drift_is_rejected(self):
        def change(m):
            m["sequences"][0]["frames"][0]["capturedOffsetMs"] = 100
        with self.altered_manifest(change), self.assertRaisesRegex(ValueError, "Timestamp drift"):
            v.load_corpus()

    def test_post_result_relabelling_is_rejected(self):
        original = v.read_json
        def read(path):
            result = original(path)
            if Path(path).name == "annotations.json":
                result["physicalHazard"] = not result["physicalHazard"]
            return result
        with patch.object(v, "read_json", side_effect=read), self.assertRaisesRegex(ValueError, "Annotation drift"):
            v.load_corpus()

    def test_old_rgb_cannot_be_called_new_holdout(self):
        manifest = v.read_json(v.CORPUS / "corpus-manifest.json")
        used = manifest["sequences"][0]["frames"][0]["rgb"]["sha256"]
        with patch.object(v, "old_rgb_hashes", return_value={used}), self.assertRaisesRegex(ValueError, "Reused old-corpus RGB"):
            v.load_corpus()

    def test_fov_mismatch_is_rejected(self):
        def change(m):
            m["sequences"][0]["frames"][0]["cameraPose"]["fy"] *= 1.2
        with self.altered_manifest(change), self.assertRaisesRegex(ValueError, "Invalid camera projection"):
            v.load_corpus()

    def test_quality_gate_rejects_hazard_continue_even_with_valid_report(self):
        from check_paired_scene_quality import evaluate
        summary = {k: 0 for k in ("unsafeContinues", "lateStopSequences", "missedStopSequences", "falseImminentFrames")}
        summary["unsafeContinues"] = 1
        result = evaluate({"modes": [{"mode": "synthetic-negative", "summary": summary}]})
        self.assertFalse(result["passed"])
        self.assertEqual(result["failures"][0]["metric"], "unsafeContinues")


if __name__ == "__main__":
    unittest.main()

"""Regression checks for detector benchmark coordinates and source integrity."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from evaluate_blender_detectors import checked_file, project_boxes, sha256


class DetectorBenchmarkContractTest(unittest.TestCase):
    def test_normalized_tflite_and_pixel_onnx_boxes_map_to_same_image(self) -> None:
        # 96x72 -> 416x312 with 52px top and bottom padding.
        normalized = np.array([[0.375, 0.375, 0.625, 0.625]], dtype=np.float32)
        pixels = normalized * 416
        arguments = dict(
            input_size=416, scale=416 / 96, pad_x=0, pad_y=52,
            width=96, height=72,
        )
        control = project_boxes(normalized, **arguments, normalized_input=True)
        candidate = project_boxes(pixels, **arguments, normalized_input=False)
        np.testing.assert_allclose(control, candidate, atol=1e-5)
        self.assertGreater(float(control[0, 2] - control[0, 0]), 0)
        self.assertGreater(float(control[0, 3] - control[0, 1]), 0)
        self.assertAlmostEqual(float((control[0, 0] + control[0, 2]) / 2), 48)

    def test_changed_corpus_asset_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "scene.png"
            source.write_bytes(b"known bytes")
            expected = sha256(source)
            source.write_bytes(b"changed bytes")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                checked_file(root, "scene.png", expected)
            with self.assertRaisesRegex(ValueError, "escaping corpus path"):
                checked_file(root, "../outside.png", expected)


if __name__ == "__main__":
    unittest.main()

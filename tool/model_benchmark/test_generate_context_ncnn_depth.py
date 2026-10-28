"""Small contract checks for the desktop RGB-to-NCNN diagnostic path."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from generate_context_ncnn_depth import nearest_rgb, rank_correlation


class ContextNcnnDepthTest(unittest.TestCase):
    def test_nearest_stretch_uses_integer_source_pixels(self) -> None:
        pixels = np.array(
            [
                [[255, 0, 0], [0, 255, 0]],
                [[0, 0, 255], [255, 255, 255]],
            ],
            dtype=np.uint8,
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "rgb.png"
            Image.fromarray(pixels, mode="RGB").save(path)
            result = nearest_rgb(path)
        self.assertEqual(result.shape, (256, 256, 3))
        np.testing.assert_array_equal(result[0, 0], [1.0, 0.0, 0.0])
        np.testing.assert_array_equal(result[127, 128], [0.0, 1.0, 0.0])
        np.testing.assert_array_equal(result[128, 127], [0.0, 0.0, 1.0])
        np.testing.assert_array_equal(result[255, 255], [1.0, 1.0, 1.0])

    def test_rank_correlation_keeps_larger_nearer(self) -> None:
        mm = np.tile(np.arange(1000, 1256, dtype=np.uint16), (256, 1))
        inverse = 1000.0 / mm.astype(np.float32)
        self.assertGreater(rank_correlation(inverse, mm), 0.99)
        self.assertLess(rank_correlation(-inverse, mm), -0.99)


if __name__ == "__main__":
    unittest.main()

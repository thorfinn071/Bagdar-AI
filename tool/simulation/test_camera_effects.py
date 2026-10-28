import hashlib
import unittest

import numpy as np
from PIL import Image

from camera_effects import apply, to_i420


class CameraEffectsTest(unittest.TestCase):
    def setUp(self):
        a = np.indices((96, 64)).sum(axis=0)%2*220+20
        self.image = Image.fromarray(np.repeat(a[..., None], 3, axis=2).astype(np.uint8))

    def test_seeded_conditions_are_repeatable_and_distinct(self):
        hashes = set()
        for condition in ('clean', 'shake', 'lowlight', 'defocus', 'rain', 'mixed'):
            first = apply(self.image, condition, 10, 2).tobytes()
            self.assertEqual(first, apply(self.image, condition, 10, 2).tobytes())
            hashes.add(hashlib.sha256(first).hexdigest())
        self.assertEqual(len(hashes), 6)

    def test_defocus_reduces_edge_contrast(self):
        before = np.asarray(self.image).astype(float)
        after = np.asarray(apply(self.image, 'defocus', 10, 0)).astype(float)
        self.assertLess(np.abs(np.diff(after, axis=1)).mean(), np.abs(np.diff(before, axis=1)).mean()/2)

    def test_i420_plane_lengths_and_limited_range_endpoints(self):
        black = to_i420(Image.new('RGB', (4, 2), 'black'))
        white = to_i420(Image.new('RGB', (4, 2), 'white'))
        self.assertEqual(len(black), 12)
        self.assertEqual(black[:8], bytes([16]*8))
        self.assertEqual(white[:8], bytes([235]*8))
        self.assertEqual(black[8:], bytes([128]*4))
        with self.assertRaises(ValueError):
            to_i420(Image.new('RGB', (3, 2)))

    def test_rejects_unknown_conditions(self):
        with self.assertRaises(ValueError):
            apply(self.image, 'invented', 0, 0)


if __name__ == '__main__':
    unittest.main()

"""Negative checks for evidence admission and relative-depth scoring."""
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

from depth_candidate_common import checked, normalize, parity, rank_rho, score, sha


class DepthCandidateEvidenceTests(unittest.TestCase):
    def test_hash_and_path_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'frame.f32'
            path.write_bytes(b'unchanged')
            self.assertEqual(checked(root, path.name, sha(path)), path.resolve())
            for relative, digest in (('../frame.f32', sha(path)),
                                     (str(path.resolve()), sha(path)),
                                     (path.name, '0' * 64)):
                with self.assertRaises(ValueError):
                    checked(root, relative, digest)

    def test_invalid_maps_are_not_an_empty_scene(self):
        for raw in (np.ones((256, 256)), np.zeros((1, 256)),
                    np.full((256, 256), np.nan), np.full((256, 256), np.inf)):
            with self.assertRaises(ValueError):
                normalize(raw)

    def test_rank_ties_and_depth_direction(self):
        raw = np.repeat(np.arange(10), 100).astype(np.float32)
        self.assertAlmostEqual(rank_rho(raw, raw * 3 + 5), 1)
        self.assertAlmostEqual(rank_rho(raw, -raw), -1)
        self.assertIsNone(rank_rho(raw, np.ones_like(raw)))
        self.assertIsNone(rank_rho(raw[:99], raw[:99]))

    def test_parity_rejects_reversed_or_distorted_map(self):
        raw = np.arange(256 * 256, dtype=np.float32).reshape(256, 256)
        self.assertTrue(parity(raw, raw * 2 + 17)['passed'])
        self.assertFalse(parity(raw, -raw)['passed'])
        self.assertFalse(parity(raw, np.flip(raw, axis=0))['passed'])

    def test_oracle_boundary_order_requires_larger_nearer(self):
        mm = np.full((256, 256), 4000, dtype=np.uint16)
        mm[:, :128] = 1000
        raw = 1000.0 / mm
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'oracle.png'
            Image.fromarray(mm).save(path)
            frame = {'paths': {'depth': path}}
            correct, reversed_map = score(raw, frame), score(-raw, frame)
            self.assertGreater(correct['boundaryOrderingPairs'], 0)
            self.assertEqual(correct['boundaryOrderingAccuracy'], 1)
            self.assertEqual(reversed_map['boundaryOrderingAccuracy'], 0)


if __name__ == '__main__':
    unittest.main()

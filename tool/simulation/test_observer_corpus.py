import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from build_observer_corpus import PROTOCOL, build, chart, transform, validate


class ObserverCorpusTest(unittest.TestCase):
    def test_split_leakage_and_unknown_noise_rejected(self):
        p = json.loads(PROTOCOL.read_text()); validate(p)
        for field, value in [('families', p['splits']['development']['families'][0]),
                             ('seeds', p['splits']['development']['seeds'][0])]:
            bad = copy.deepcopy(p); bad['splits']['holdout'][field].append(value)
            with self.assertRaises(ValueError): validate(bad)
        p['conditions'][0]['noise'] = 'invented'
        with self.assertRaises(ValueError): validate(p)

    def test_noise_models_deterministic_distinct_and_do_not_mutate_source(self):
        im = chart('triangles', 18, 64, 96, 1)
        original = np.asarray(im).copy()
        p = json.loads(PROTOCOL.read_text())
        outputs = []
        for c in p['conditions']:
            a = transform(im, c, 117)
            np.testing.assert_array_equal(a, transform(im, c, 117))
            outputs.append(a.tobytes())
        self.assertEqual(len(set(outputs)), len(outputs))
        np.testing.assert_array_equal(np.asarray(im), original)

    def test_frozen_identity_pixels_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); p = json.loads(PROTOCOL.read_text())
            p['sizes'] = [[64, 96]]; p['contrasts'] = [1]
            p['splits'] = {'development': {'families': ['sparse-polylines'], 'seeds': [7]},
                           'holdout': {'families': ['sparse-arcs'], 'seeds': [8]}}
            p['phaseCells'] = [7]; p['phaseOffsets'] = [0]
            protocol = root/'p.json'; protocol.write_text(json.dumps(p))
            m = build(root/'corpus', protocol)
            self.assertEqual(len(m['images']), 29)
            self.assertEqual(m['candidateSourceSha256'], hashlib.sha256((root/'corpus/candidate-frozen.dart.txt').read_bytes()).hexdigest())
            for row in m['images']:
                raw = (root/'corpus'/row['asset']['path']).read_bytes()
                self.assertEqual(len(raw), row['width']*row['height'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row['asset']['sha256'])
            with self.assertRaises(FileExistsError): build(root/'corpus', protocol)


if __name__ == '__main__': unittest.main()

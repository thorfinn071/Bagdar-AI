import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from build_quality_corpus import PROTOCOL, build, make_chart, transform, validate_protocol


class QualityCorpusTest(unittest.TestCase):
    def test_paired_transforms_preserve_source_and_noise_does_not_restore_edges(self):
        image = make_chart('doorway', 31, 96, 128, 1)
        original = np.asarray(image).copy()
        blur = {'blurSigmaPx': 5, 'motionPx': 1, 'gain': 1, 'noiseSigmaLuma': 0}
        blurred = transform(image, blur, 1)
        noisy = transform(image, {**blur, 'noiseSigmaLuma': 8}, 77)
        np.testing.assert_array_equal(np.asarray(image), original)
        self.assertTrue(np.any((blurred > 50) & (blurred < 128)))
        self.assertGreater(np.std(noisy.astype(float)-blurred), 6)
        np.testing.assert_array_equal(noisy, transform(image, {**blur, 'noiseSigmaLuma': 8}, 77))
        self.assertFalse(np.array_equal(noisy, transform(image, {**blur, 'noiseSigmaLuma': 8}, 78)))

    def test_rejects_leakage_between_development_and_holdout(self):
        protocol = json.loads(PROTOCOL.read_text())
        validate_protocol(protocol)
        leaked = copy.deepcopy(protocol)
        leaked['splits']['holdout']['families'].append('panel')
        with self.assertRaises(ValueError):
            validate_protocol(leaked)
        leaked = copy.deepcopy(protocol)
        leaked['splits']['holdout']['seeds'].append(271010)
        with self.assertRaises(ValueError):
            validate_protocol(leaked)

    def test_corpus_identity_pairing_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            protocol = json.loads(PROTOCOL.read_text())
            protocol['sizes'] = [[64, 64]]
            protocol['contrasts'] = [1]
            protocol['splits'] = {'development': {'families': ['panel'], 'seeds': [1]},
                                  'holdout': {'families': ['doorway'], 'seeds': [2]}}
            protocol['phaseProbe']['xOffsets'] = [0]
            protocol['phaseProbe']['yOffsets'] = [0]
            protocol_path = base/'protocol.json'
            protocol_path.write_text(json.dumps(protocol))
            manifest = build(base/'corpus', protocol_path)
            self.assertEqual(len(manifest['images']), 31)
            self.assertEqual(manifest['protocolSha256'], hashlib.sha256(protocol_path.read_bytes()).hexdigest())
            for row in manifest['images']:
                raw = (base/'corpus'/row['asset']['path']).read_bytes()
                self.assertEqual(len(raw), row['width']*row['height'])
                self.assertEqual(hashlib.sha256(raw).hexdigest(), row['asset']['sha256'])
            before = (base/'corpus/manifest.json').read_bytes()
            with self.assertRaises(FileExistsError):
                build(base/'corpus', protocol_path)
            self.assertEqual((base/'corpus/manifest.json').read_bytes(), before)


if __name__ == '__main__':
    unittest.main()

import copy
import json
from pathlib import Path
import tempfile
import unittest

from summarize_observer import summarize, digest


class ObserverSummaryTest(unittest.TestCase):
    def fixture(self, root):
        (root/'sample.y8').write_bytes(bytes([128])*32*32)
        (root/'protocol.json').write_text('{}')
        (root/'candidate-frozen.dart.txt').write_text('frozen diagnostic candidate')
        rows = [{'id': str(i), 'baseId': 'one', 'width': 32, 'height': 32, 'rowStride': 32,
                 'family': 'sparse-polylines', 'split': 'development', 'condition': c,
                 'asset': {'path': 'sample.y8', 'sha256': digest(root/'sample.y8')}}
                for i, c in enumerate(['sharp', 'defocus-6', 'defocus-6-white-8', 'defocus-6-correlated-8', 'defocus-6-shot-64'])]
        manifest = {'promotionAllowed': False, 'candidateSourceSha256': digest(root/'candidate-frozen.dart.txt'), 'images': rows}
        (root/'manifest.json').write_text(json.dumps(manifest))
        baseline = {'images': [{**r, 'rejected': True} for r in rows]}
        (root/'baseline.json').write_text(json.dumps(baseline))
        result = {'promotionAllowed': False, 'corpusManifestSha256': digest(root/'manifest.json'),
                  'baselineSha256': digest(root/'baseline.json'), 'protocolSha256': digest(root/'protocol.json'),
                  'candidateSourceSha256': digest(root/'candidate-frozen.dart.txt'), 'timingScope': 'test-only fixture',
                  'images': [{**r, 'observerElapsedUs': 1, 'observer': {'evidence': 'unknown',
                    'promotionAllowed': False, 'residualProxy': None, 'structureFraction': None,
                    'edgeConcentration': None, 'clippedFraction': None}} for r in baseline['images']]}
        (root/'observer.json').write_text(json.dumps(result))
        return result

    def test_unknown_is_preserved_and_summary_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); self.fixture(root)
            result = summarize(root, root/'report.md')
            self.assertEqual(result['pairs'][0]['noisyEvidence'], 'unknown')
            self.assertEqual(result['physicalDeviceValidation'], 'not_run')
            self.assertFalse(result['promotionAllowed'])
            with self.assertRaises(FileExistsError): summarize(root, root/'report.md')

    def test_tampered_inputs_identity_duplicates_and_nonfinite_results_fail(self):
        for change in ('pixels', 'source', 'protocol', 'baseline', 'duplicate', 'nonfinite', 'metadata'):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as folder:
                root = Path(folder); r = self.fixture(root)
                if change == 'pixels': (root/'sample.y8').write_bytes(b'wrong')
                elif change == 'source': (root/'candidate-frozen.dart.txt').write_text('changed')
                elif change == 'protocol': (root/'protocol.json').write_text('{"changed":true}')
                elif change == 'baseline': (root/'baseline.json').write_text('{}')
                elif change == 'duplicate': r['images'][1] = copy.deepcopy(r['images'][0])
                elif change == 'nonfinite': r['images'][0]['observer']['residualProxy'] = float('nan')
                elif change == 'metadata': r['images'][0]['condition'] = 'foreign'
                (root/'observer.json').write_text(json.dumps(r))
                with self.assertRaises((ValueError, KeyError)): summarize(root, root/'report.md')
                self.assertFalse((root/'observer-summary.json').exists())


if __name__ == '__main__': unittest.main()

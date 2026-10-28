import json
from pathlib import Path
import tempfile
import unittest

from quality_app_probe import package, evaluate, sha, write


class QualityAppProbeTest(unittest.TestCase):
    def prepare(self, base):
        source = base/'source'
        source.mkdir()
        (source/'manifest.json').write_text('{}')
        luma = bytes(range(256))*20
        (source/'source.y8').write_bytes(luma)
        rows = [{'id': f'{family}-{condition}', 'family': family, 'condition': condition,
                 'seed': 927201, 'width': 320, 'height': 16, 'contrast': 1,
                 'asset': {'path': 'source.y8', 'sha256': sha(luma)},
                 'rejected': condition == 'defocus-5', 'score': 0 if condition == 'defocus-5' else 200}
                for family in ('doorway', 'bricks') for condition in ('sharp', 'defocus-5', 'defocus-5-noise-8')]
        write(source/'baseline.json', {'corpusManifestSha256': sha(b'{}'), 'images': rows,
                                     'productionSourceSha256': 'a'*64})
        target = base/'probe'
        package(source, target)
        return target, luma

    def test_packaging_preserves_exact_y_bytes_and_keeps_labels_outside_runtime(self):
        with tempfile.TemporaryDirectory() as folder:
            root, original = self.prepare(Path(folder))
            manifest = json.loads((root/'runtime/manifest.json').read_text())
            for sequence in manifest['sequences']:
                self.assertEqual(len(sequence['frames']), 31)
                raw = (root/'runtime'/sequence['frames'][0]['yuv']['path']).read_bytes()
                self.assertEqual(raw[:len(original)], original)
                self.assertEqual(set(raw[len(original):]), {128})
            self.assertNotIn('expectedSharpnessScore', (root/'runtime/manifest.json').read_text())
            self.assertTrue((root/'probe-annotations.json').exists())

    def test_app_evaluation_requires_current_complete_native_receipts(self):
        with tempfile.TemporaryDirectory() as folder:
            root, _ = self.prepare(Path(folder))
            digest = sha((root/'runtime/manifest.json').read_bytes())
            annotations = json.loads((root/'probe-annotations.json').read_text())
            write(root/'runtime/control.json', {'runId': 'new-run'})
            (root/'app-reports').mkdir()
            write(root/'app-reports/process-batch-complete.json', {'runId': 'new-run',
                'manifestSha256': digest, 'completed': True,
                'episodes': [{'sequenceId': row['sequenceId'], 'status': 'recorded'} for row in annotations['sequences']]})
            for row in annotations['sequences']:
                events = [{'type': 'models_loaded', 'liveYolo': True, 'liveDepth': True, 'depthTier': 'ncnnCpu'}]
                for i in range(31):
                    events.append({'type': 'frame_delivered', 'frameId': i+1})
                    if row['expectedBlurRejected']:
                        events.append({'type': 'quality_skip', 'reason': 'blur', 'sharpness': row['expectedSharpnessScore']})
                write(root/f'app-reports/run-{row["sequenceId"]}.json', {'runId': 'new-run',
                    'sequenceId': row['sequenceId'], 'manifestSha256': digest, 'promotionAllowed': False,
                    'completedInput': True, 'events': events})
            report = Path(folder)/'report.md'
            result = evaluate(root, report)
            self.assertTrue(result['allReceiptsComplete'])
            self.assertTrue(result['allBlurSkipDecisionsMatchBaseline'])
            path = root/'app-reports/run-q-doorway-sharp.json'
            bad = json.loads(path.read_text())
            bad['events'][0]['depthTier'] = 'focalLength'
            write(path, bad)
            self.assertFalse(evaluate(root, report)['allReceiptsComplete'])
            bad['runId'] = 'old-run'
            write(path, bad)
            with self.assertRaises(ValueError):
                evaluate(root, report)


if __name__ == '__main__':
    unittest.main()

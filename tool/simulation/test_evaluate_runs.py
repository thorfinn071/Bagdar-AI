import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from evaluate_runs import evaluate, percentiles


class EvaluationTest(unittest.TestCase):
    def test_small_latency_samples_use_nearest_rank_percentiles(self):
        self.assertEqual(percentiles([1000, 9000])['p95Ms'], 9)
        self.assertEqual(percentiles([1000, 9000])['p50Ms'], 1)
        self.assertIsNone(percentiles([])['p95Ms'])

    def test_distinguishes_passable_stops_hazardous_continues_and_missing_runs(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root/'runtime').mkdir()
            (root/'app-reports').mkdir()
            sequences = [{'id': identifier, 'frames': [{'drop': False}]} for identifier in ('free', 'hazard', 'missing')]
            raw = json.dumps({'sequences': sequences}).encode()
            (root/'runtime/manifest.json').write_bytes(raw)
            digest = hashlib.sha256(raw).hexdigest()
            (root/'annotations.json').write_text(json.dumps({'runtimeManifestSha256': digest,
                'sequences': [{'sequenceId': s['id'], 'layout': 'test', 'condition': 'clean',
                  'physicalHazard': s['id'] != 'free', 'frames': [{'frameId': 1, 'visibleHazardWitnesses': 10}]} for s in sequences]}))
            for identifier, action in (('free', 'stopNow'), ('hazard', 'continueForward')):
                report = {'manifestSha256': digest, 'sequenceId': identifier, 'promotionAllowed': False,
                    'completedInput': True, 'events': [
                        {'type': 'models_loaded', 'liveYolo': True, 'liveDepth': True, 'depthTier': 'ncnnCpu', 'modelHashes': {}},
                        {'type': 'frame_delivered', 'captureTimestampUs': 100, 'frameId': 1},
                        {'type': 'spatial_result', 'sourceTimestampUs': 100, 'plannedAction': action,
                         'plannedRuleId': 'SPATIAL-P0-DEGRADED-MOVING'}]}
                (root/f'app-reports/run-{identifier}.json').write_text(json.dumps(report))
            summary = evaluate(root)
            self.assertEqual(summary['execution'], {'completed': 2, 'not_run': 1})
            self.assertEqual(summary['hazardousContinueFrames'], 1)
            self.assertEqual(summary['framesWithSpatialDecision'], 2)
            self.assertEqual(summary['framesWithHazardWitness'], 1)
            self.assertEqual(summary['hazardFramesWithDecision'], 1)
            self.assertEqual(summary['hazardFramesWithoutDecision'], 0)
            self.assertEqual(summary['sequences'][0]['passableStopFrames'], 1)
            self.assertEqual(summary['sequences'][0]['passableImminentFrames'], 0)
            self.assertFalse(summary['promotionAllowed'])
            # Loaded assets must not make a heuristic depth fallback count as NCNN.
            fallback = json.loads((root/'app-reports/run-free.json').read_text())
            fallback['events'][0]['depthTier'] = 'focalLength'
            (root/'app-reports/run-free.json').write_text(json.dumps(fallback))
            self.assertEqual(evaluate(root)['sequences'][0]['execution'], 'incomplete')
            # A previous receipt must not fill a missing result in a new run.
            (root/'runtime/control.json').write_text(json.dumps({'runId': 'new-run'}))
            self.assertEqual(evaluate(root)['execution'], {'not_run': 3})
            # A current timeout wins over a leftover receipt from the old run.
            (root/'app-reports/process-batch-complete.json').write_text(json.dumps({
                'runId': 'new-run', 'manifestSha256': digest,
                'episodes': [{'sequenceId': 'free', 'status': 'timeout', 'error': 'deadline'}]}))
            self.assertEqual(evaluate(root)['execution'], {'failed': 1, 'not_run': 2})


if __name__ == '__main__':
    unittest.main()

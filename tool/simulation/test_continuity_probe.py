import copy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess
from types import SimpleNamespace

from continuity_probe import ContinuityDevice, matches, package, sha, summarize_episode, PROTOCOL
from experiment_spec import validate_spec


class ContinuityTest(unittest.TestCase):
    def test_adb_timeout_is_recorded_and_later_poll_can_recover(self):
        d = ContinuityDevice('adb', 'emulator-5554')
        with patch('subprocess.run', side_effect=[subprocess.TimeoutExpired('adb', 15),
                   SimpleNamespace(returncode=0, stdout=b'{"runId":"current"}')]):
            self.assertIsNone(d.read_json('batch-complete.json'))
            self.assertEqual(d.read_json('batch-complete.json'), {'runId': 'current'})
        self.assertEqual(d.transport_errors, [{'file': 'batch-complete.json', 'error': 'adb_read_timeout_15s'}])
    def test_foreign_progress_cannot_trigger_lifecycle_actions(self):
        value = {'runId': 'current', 'manifestSha256': 'digest', 'sequenceId': 'one', 'promotionAllowed': False}
        self.assertTrue(matches(value, 'current', 'digest', 'one'))
        self.assertFalse(matches(value, 'old', 'digest', 'one'))
        self.assertFalse(matches(value, 'current', 'wrong', 'one'))
        self.assertFalse(matches(value, 'current', 'digest', 'two'))
        self.assertFalse(matches(None, 'current', 'digest'))

    def test_missing_lifecycle_and_disposal_are_not_success(self):
        seq = {'id': 'one', 'frames': [{'frameId': 1, 'drop': False}]}
        report = {'completedInput': True, 'events': [
            {'type': 'frame_delivered', 'frameId': 1, 'deliveryAgeUs': 123, 'elapsedUs': 123}]}
        r = summarize_episode(seq, report, None, resumed_expected=True)
        self.assertFalse(r['pauseResumeObserved']); self.assertFalse(r['postResumeDelivery'])
        self.assertFalse(r['disposalObserved']); self.assertFalse(r['liveModels'])
        not_host = summarize_episode(seq, report, {'routeCompleted': True, 'disposed': True,
                                                  'hostDisposalAcknowledged': False})
        self.assertFalse(not_host['disposalObserved'])
        self.assertIsNone(r['yoloCaptureToResultUs']['p95'])
        report['events'] += [{'type': 'lifecycle_state', 'state': 'paused', 'elapsedUs': 10},
                             {'type': 'lifecycle_state', 'state': 'resumed', 'elapsedUs': 100}]
        r = summarize_episode(seq, report, {'routeCompleted': True, 'disposed': True, 'hostDisposalAcknowledged': True}, resumed_expected=True)
        self.assertTrue(r['pauseResumeObserved']); self.assertTrue(r['postResumeDelivery']); self.assertTrue(r['disposalObserved'])

    def test_versioned_continuity_keeps_assets_and_labels_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); source = root/'source'; (source/'runtime').mkdir(parents=True)
            (source/'runtime/frame').write_bytes(b'pixels')
            asset = {'path': 'frame', 'sha256': sha(b'pixels')}
            seq = {'id': 'one', 'width': 2, 'height': 2, 'frames': [{'frameId': 1, 'offsetUs': 0,
                'yuv': asset, 'preview': asset, 'deliveryDelayUs': 0, 'drop': False}],
                'sensors': [{'offsetUs': 0, 'accelerometer': [0, 8, 5], 'gyroscope': [0, 0, 0]}]}
            (source/'runtime/manifest.json').write_text(json.dumps({'promotionAllowed': False, 'sequences': [seq]}))
            p = json.loads(PROTOCOL.read_text()); p.update(sourceSequenceIds=['one'], durationSeconds=5, fps=1)
            protocol = root/'protocol.json'; protocol.write_text(json.dumps(p))
            package(source, root/'out', protocol)
            m = json.loads((root/'out/runtime/manifest.json').read_text())
            self.assertEqual([f['offsetUs'] for f in m['sequences'][0]['frames']], list(range(0, 5000001, 1000000)))
            self.assertFalse(m['promotionAllowed']); self.assertNotIn('annotations', m)
            with self.assertRaises(FileExistsError): package(source, root/'out', protocol)
            (source/'runtime/frame').write_bytes(b'changed')
            with self.assertRaises(ValueError): package(source, root/'tampered', protocol)

    def test_camera_material_and_geometry_controls_reject_invalid_values(self):
        spec = json.loads(Path(__file__).with_name('lab_breadth_v1.json').read_text()); validate_spec(spec)
        for section, name, value in [('camera', 'lensMm', 0), ('camera', 'heightM', float('nan')),
                                     ('geometry', 'crossTrackScale', -1), ('materials', 'bumpStrength', 9)]:
            bad = copy.deepcopy(spec); bad[section][name] = value
            with self.assertRaises(ValueError): validate_spec(bad)


if __name__ == '__main__': unittest.main()

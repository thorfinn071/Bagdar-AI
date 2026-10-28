import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from process_batch import run_batch


class Device:
    def __init__(self, digest, *, timeout=False):
        self.digest, self.timeout = digest, timeout
        self.actions = []
        self.current = None

    def stop(self): self.actions.append('stop')
    def select(self, identifier, run_id):
        self.current = (identifier, run_id)
        self.actions.append(f'select-{identifier}')
    def start(self): self.actions.append('start')
    def diagnostics(self): return 'test transport log'
    def input_identity(self): return self.digest
    def has_anr(self): return False
    def receipt(self, identifier):
        if self.timeout:
            return {'runId': 'old-run'}
        return {'sequenceId': identifier, 'runId': self.current[1],
            'manifestSha256': self.digest, 'completedInput': True, 'events': []}


class ProcessBatchTest(unittest.TestCase):
    def prepare(self, root):
        (root/'runtime').mkdir()
        raw = json.dumps({'sequences': [{'id': 'one'}, {'id': 'two'}]}).encode()
        (root/'runtime/manifest.json').write_bytes(raw)
        (root/'runtime/control.json').write_text(json.dumps({'runId': 'current-run'}))
        return hashlib.sha256(raw).hexdigest()

    def test_two_episodes_use_independent_processes_and_matching_receipts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            device = Device(self.prepare(root))
            run_batch(root, device)
            self.assertEqual(device.actions, ['stop', 'select-one', 'start', 'stop',
                                             'stop', 'select-two', 'start', 'stop', 'stop'])
            marker = json.loads((root/'app-reports/process-batch-complete.json').read_text())
            self.assertTrue(marker['completed'])
            self.assertEqual(len(marker['episodes']), 2)
            self.assertEqual(json.loads((root/'app-reports/run-two.json').read_text())['runId'], 'current-run')

    def test_stale_receipts_timeout_without_fabricating_app_results(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            device = Device(self.prepare(root), timeout=True)
            elapsed = [0]
            results = run_batch(root, device, timeout=1, poll=.5,
                now=lambda: elapsed[0], sleep=lambda delay: elapsed.__setitem__(0, elapsed[0]+delay))
            self.assertEqual([r['status'] for r in results], ['timeout', 'timeout'])
            self.assertFalse((root/'app-reports/run-one.json').exists())
            self.assertEqual(device.actions[-1], 'stop')


if __name__ == '__main__':
    unittest.main()

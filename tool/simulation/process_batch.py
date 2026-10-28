"""Independent cold-start app episodes; no dependency on Flutter route disposal."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

PACKAGE = 'com.example.bagdar.simulation'


def write_json(path, data):
    temporary = path.with_suffix(path.suffix+'.tmp')
    temporary.write_text(json.dumps(data, indent=2, allow_nan=False)+'\n', encoding='utf-8')
    temporary.replace(path)


class AdbDevice:
    def __init__(self, adb, serial):
        self.base = [str(adb), '-s', serial]

    def call(self, *args):
        return subprocess.run(self.base+list(args), check=True, capture_output=True, timeout=60)

    def stop(self):
        self.call('shell', 'am', 'force-stop', PACKAGE)

    def select(self, sequence_id, run_id):
        with tempfile.TemporaryDirectory(prefix='bagdar-control-') as folder:
            path = Path(folder)/'control.json'
            write_json(path, {'sequenceId': sequence_id, 'runId': run_id, 'autoClose': False})
            remote = '/data/local/tmp/bagdar-simulation-control.json'
            self.call('push', str(path), remote)
            self.call('shell', 'run-as', PACKAGE, 'cp', remote, 'files/simulation/control.json')
            copied = self.call('shell', '-T', 'run-as', PACKAGE, 'cat', 'files/simulation/control.json').stdout
            if json.loads(copied) != json.loads(path.read_text()):
                raise ValueError('Control transport mismatch')

    def start(self):
        self.call('shell', 'am', 'start', '-n', f'{PACKAGE}/com.example.bagdar.MainActivity')

    def input_identity(self):
        return self.call('shell', '-T', 'run-as', PACKAGE, 'sha256sum',
                         'files/simulation/manifest.json').stdout.decode().split()[0]

    def has_anr(self):
        window = self.call('shell', 'dumpsys', 'window').stdout.decode('utf-8', errors='replace')
        return f'Application Not Responding: {PACKAGE}' in window

    def receipt(self, identifier):
        result = subprocess.run(self.base+['shell', '-T', 'run-as', PACKAGE,
            'cat', f'files/simulation/run-{identifier}.json'], capture_output=True, timeout=15)
        if result.returncode:
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None  # The app may still be writing its receipt.

    def diagnostics(self):
        return self.call('logcat', '-d', '-s', 'flutter', 'AndroidRuntime').stdout.decode('utf-8', errors='replace')


def run_batch(corpus, device, *, timeout=90, poll=.75, now=time.monotonic, sleep=time.sleep):
    runtime = corpus/'runtime'
    raw = (runtime/'manifest.json').read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    manifest = json.loads(raw)
    control = json.loads((runtime/'control.json').read_text(encoding='utf-8-sig'))
    run_id = control['runId']
    ids = [s['id'] for s in manifest['sequences']]
    requested = control.get('sequenceIds', ids)
    if not requested or len(set(requested)) != len(requested) or not set(requested) <= set(ids):
        raise ValueError('Invalid process batch selection')
    ids = [identifier for identifier in ids if identifier in requested]
    output = corpus/'app-reports'
    output.mkdir(exist_ok=True)
    common = {'schemaVersion': 1, 'runId': run_id, 'manifestSha256': digest,
              'controller': 'adb-isolated-processes', 'promotionAllowed': False}
    results = []
    marker = output/'process-batch-complete.json'
    try:
        if device.input_identity() != digest:
            raise ValueError('Emulator input manifest differs from the selected corpus')
        for index, identifier in enumerate(ids):
            if not identifier or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in identifier):
                raise ValueError('Unsafe sequence identifier')
            write_json(output/'process-batch-progress.json', {**common, 'phase': 'running',
                'sequenceId': identifier, 'completedEpisodes': index, 'selectedEpisodes': len(ids)})
            device.stop()
            device.select(identifier, run_id)
            device.start()
            deadline = now()+timeout
            report = None
            while now() < deadline:
                candidate = device.receipt(identifier)
                if candidate and candidate.get('runId') == run_id:
                    if candidate.get('sequenceId') != identifier or candidate.get('manifestSha256') != digest:
                        raise ValueError('Foreign application receipt')
                    report = candidate
                    break
                sleep(poll)
            if report is None:
                status = {'sequenceId': identifier, 'status': 'timeout', 'error': 'No matching app receipt within deadline'}
            else:
                write_json(output/f'run-{identifier}.json', report)
                errors = [e for e in report['events'] if e['type'] in ('startup_error', 'callback_error')]
                status = {'sequenceId': identifier, 'status': 'recorded',
                          'completedInput': report['completedInput'], 'errors': errors}
            status['androidAnrObserved'] = device.has_anr()
            (output/f'logcat-{identifier}.txt').write_text(device.diagnostics(), encoding='utf-8')
            device.stop()
            results.append(status)
            write_json(output/'process-batch-progress.json', {**common, 'phase': status['status'],
                'sequenceId': identifier, 'completedEpisodes': index+1, 'selectedEpisodes': len(ids)})
            print(f"SIMULATION_EPISODE {index+1}/{len(ids)} {identifier}: {status['status']}", flush=True)
        write_json(marker, {**common, 'phase': 'completed', 'completed': True,
            'sequences': len(ids), 'episodes': results})
        return results
    except Exception as error:
        write_json(marker, {**common, 'phase': 'failed', 'completed': False,
            'error': str(error), 'episodes': results})
        raise
    finally:
        device.stop()


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('corpus', type=Path)
    p.add_argument('--adb', required=True, type=Path)
    p.add_argument('--serial', default='emulator-5554')
    p.add_argument('--timeout', type=float, default=90)
    a = p.parse_args()
    run_batch(a.corpus.resolve(), AdbDevice(a.adb, a.serial), timeout=a.timeout)

"""Versioned sustained-input and actual Android lifecycle/disposal experiment."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import shutil
import time
import uuid

from device_io import push
from process_batch import AdbDevice, PACKAGE, write_json

PROTOCOL = Path(__file__).with_name('continuity_protocol_v1.json')


def sha(raw): return hashlib.sha256(raw).hexdigest()


def package(source, target, protocol_path=PROTOCOL):
    protocol_raw = protocol_path.read_bytes(); p = json.loads(protocol_raw)
    raw = (source/'runtime/manifest.json').read_bytes(); original = json.loads(raw)
    if p['schemaVersion'] != 1 or p['promotionAllowed'] is not False or original['promotionAllowed'] is not False:
        raise ValueError('Research-only continuity inputs required')
    seconds, fps = p['durationSeconds'], p['fps']
    if not 5 <= seconds <= 60 or not 1 <= fps <= 20:
        raise ValueError('Invalid duration/cadence')
    requested = p['sourceSequenceIds']
    if not requested or len(set(requested)) != len(requested): raise ValueError('Duplicate/empty sequences')
    sources = {s['id']: s for s in original['sequences']}
    if not set(requested) <= set(sources): raise ValueError('Missing source sequence')
    target.mkdir(parents=True, exist_ok=False); runtime = target/'runtime'; runtime.mkdir()
    copied = set(); sequences = []
    for identifier in requested:
        s = sources[identifier]
        frames = []
        for i in range(round(seconds*fps)+1):
            frame = s['frames'][i % len(s['frames'])]
            for key in ('yuv', 'preview'):
                asset = frame[key]; relative = asset['path']
                path = (source/'runtime'/relative).resolve()
                if not path.is_relative_to((source/'runtime').resolve()) or sha(path.read_bytes()) != asset['sha256']:
                    raise ValueError('Changed or escaped source pixels')
                if relative not in copied:
                    destination = runtime/relative; destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, destination); copied.add(relative)
            frames.append({**frame, 'frameId': i+1, 'offsetUs': round(i*1e6/fps),
                           'deliveryDelayUs': 0, 'drop': False})
        sensors = [{**s['sensors'][i % len(s['sensors'])], 'offsetUs': round(i*1e6/60)}
                   for i in range(round(seconds*60)+1)]
        sequences.append({**s, 'id': f'continuous-{identifier}', 'frames': frames, 'sensors': sensors})
    write_json(runtime/'manifest.json', {'schemaVersion': 1, 'synthetic': True,
        'promotionAllowed': False, 'corpusId': p['experimentId'], 'scope': p['scope'], 'sequences': sequences})
    (target/'protocol.json').write_bytes(protocol_raw)
    write_json(target/'continuity-provenance.json', {
        'sourceManifestSha256': sha(raw), 'runtimeManifestSha256': sha((runtime/'manifest.json').read_bytes()),
        'protocolSha256': sha(protocol_raw), 'packagerSha256': sha(Path(__file__).read_bytes()),
        'sourceSequenceIds': requested, 'repeatedSourceFrames': True,
        'newGeometry': False, 'calibratedSensorModel': False, 'promotionAllowed': False})
    print(f'CONTINUITY_CORPUS {len(sequences)} continuous episodes, {sum(len(s["frames"]) for s in sequences)} frames')


class ContinuityDevice(AdbDevice):
    def __init__(self, adb, serial):
        super().__init__(adb, serial)
        self.transport_errors = []

    def read_json(self, filename):
        # Every filename is constructed from a validated manifest sequence ID.
        import subprocess
        try:
            r = subprocess.run(self.base+['shell', '-T', 'run-as', PACKAGE, 'cat', f'files/simulation/{filename}'],
                               capture_output=True, timeout=15)
        except subprocess.TimeoutExpired:
            self.transport_errors.append({'file': filename, 'error': 'adb_read_timeout_15s'})
            return None  # A later bounded poll may recover; never invent JSON.
        if r.returncode: return None
        try: return json.loads(r.stdout)
        except json.JSONDecodeError: return None


def matches(value, run_id, digest, identifier=None):
    return bool(value and value.get('runId') == run_id and value.get('manifestSha256') == digest
                and value.get('promotionAllowed') is False
                and (identifier is None or value.get('sequenceId') == identifier))


def summarize_episode(sequence, receipt, disposal, *, resumed_expected=False):
    events = receipt['events']; counts = Counter(e['type'] for e in events)
    delivered = [e for e in events if e['type'] == 'frame_delivered']
    expected = [f['frameId'] for f in sequence['frames'] if not f['drop']]
    lifecycle = [e for e in events if e['type'] == 'lifecycle_state']
    resumes = [e for e in lifecycle if e['state'] == 'resumed']
    pauses = [e for e in lifecycle if e['state'] in ('paused', 'hidden')]
    errors = [e for e in events if e['type'] in ('startup_error', 'callback_error', 'progress_error')]
    models = [e for e in events if e['type'] == 'models_loaded']
    samples = [e for e in events if e['type'] == 'resource_sample']
    scheduler = [e['scheduler'] for e in samples if 'scheduler' in e]
    def stats(values):
        v = sorted(values)
        return {'count': len(v), 'p50': v[math.ceil(len(v)*.5)-1] if v else None,
                'p95': v[math.ceil(len(v)*.95)-1] if v else None, 'maximum': max(v) if v else None}
    lifecycle_seen = bool(pauses and resumes and any(r['elapsedUs'] > pauses[0]['elapsedUs'] for r in resumes))
    post_resume = bool(resumes and any(e['elapsedUs'] >= resumes[-1]['elapsedUs'] for e in delivered))
    return {
        'sequenceId': sequence['id'], 'completedInput': receipt['completedInput'],
        'exactDeliveredIds': [e['frameId'] for e in delivered] == expected,
        'deliveredFrames': len(delivered), 'eventsByType': dict(counts), 'errors': errors,
        'liveModels': bool(models and models[-1]['liveYolo'] and models[-1]['liveDepth']),
        'actualLifecycle': lifecycle, 'pauseResumeObserved': lifecycle_seen,
        'postResumeDelivery': post_resume, 'pauseResumeRequired': resumed_expected,
        'deliveryAgeUs': stats([e['deliveryAgeUs'] for e in delivered]),
        'yoloCaptureToResultUs': stats([e['captureToResultUs'] for e in events if e['type'] == 'yolo_result']),
        'callbackDiagnostics': receipt.get('diagnostics'),
        'schedulerSamples': {'count': len(scheduler),
            'maximumObservedActiveModelLanes': max((s['activeModelLanes'] for s in scheduler), default=None),
            'maximumObservedQueuedCameraFrames': max((s['queuedCameraFrames'] for s in scheduler), default=None),
            'atReport': receipt.get('schedulerAtReport')},
        'rssBytes': {'samples': len(samples), 'first': samples[0]['currentRssBytes'] if samples else None,
                     'last': samples[-1]['currentRssBytes'] if samples else None,
                     'maximum': max((e['currentRssBytes'] for e in samples), default=None)},
        'disposalObserved': bool(disposal and disposal['routeCompleted'] and disposal['disposed']
                                 and disposal.get('hostDisposalAcknowledged') is True),
        'disposalDiagnostics': disposal,
        'inferenceQueueDepth': 'not_instrumented; callback concurrency is not native inference queue depth',
    }


def run(root, adb, serial):
    if not serial.startswith('emulator-'): raise ValueError('Emulator-only probe')
    device = ContinuityDevice(adb, serial)
    if device.call('shell', 'getprop', 'ro.kernel.qemu').stdout.strip() != b'1':
        raise ValueError('Selected target is not an emulator')
    raw = (root/'runtime/manifest.json').read_bytes(); digest = sha(raw); manifest = json.loads(raw)
    p = json.loads((root/'protocol.json').read_text()); provenance = json.loads((root/'continuity-provenance.json').read_text())
    if provenance['runtimeManifestSha256'] != digest or provenance['protocolSha256'] != sha((root/'protocol.json').read_bytes()):
        raise ValueError('Foreign continuity input identity')
    run_id = str(uuid.uuid4()); output = root/'app-reports'; output.mkdir(exist_ok=False)
    write_json(root/'runtime/control.json', {'sequenceId': 'all', 'autoClose': True, 'runId': run_id})
    device.stop(); push(adb, serial, root/'runtime')
    device.call('logcat', '-c')
    device.start()
    start = time.monotonic(); deadline = start+p['controllerDeadlineSeconds']
    first = manifest['sequences'][0]['id']; ready_at = None; background_at = None; resume_at = None
    receipts, disposals, actions, anr = {}, {}, [], False
    terminal = None
    try:
        while time.monotonic() < deadline:
            now = time.monotonic()
            progress = device.read_json(f'run-{first}.json.progress.json')
            if ready_at is None and matches(progress, run_id, digest, first): ready_at = now
            if ready_at is not None and background_at is None and now-ready_at >= p['backgroundAfterSeconds']:
                device.call('shell', 'input', 'keyevent', 'KEYCODE_HOME'); background_at = time.monotonic()
                actions.append({'action': 'home', 'controllerElapsedSeconds': background_at-start})
            if background_at is not None and resume_at is None and now-background_at >= p['backgroundSeconds']:
                device.start(); resume_at = time.monotonic()
                actions.append({'action': 'resume_activity', 'controllerElapsedSeconds': resume_at-start})
            for s in manifest['sequences']:
                identifier = s['id']
                for suffix, bucket in [('', receipts), ('.disposal.json', disposals)]:
                    if identifier in bucket: continue
                    name = f'run-{identifier}.json{suffix}'
                    value = device.read_json(name)
                    if matches(value, run_id, digest, identifier):
                        bucket[identifier] = value; write_json(output/name, value)
            anr = anr or device.has_anr()
            terminal = device.read_json('batch-complete.json')
            if matches(terminal, run_id, digest):
                write_json(output/'batch-complete.json', terminal)
                break
            time.sleep(1)
        # A terminal marker can appear between the last per-file read and the
        # marker read. Collect final acknowledgements again before evaluating.
        for s in manifest['sequences']:
            identifier = s['id']
            for suffix, bucket in [('', receipts), ('.disposal.json', disposals)]:
                name = f'run-{identifier}.json{suffix}'
                value = device.read_json(name)
                if matches(value, run_id, digest, identifier):
                    bucket[identifier] = value; write_json(output/name, value)
        framework = device.read_json('framework-errors.json')
        framework_errors = framework['errors'] if matches(framework, run_id, digest) else []
        if framework_errors: write_json(output/'framework-errors.json', framework)
        rows = [summarize_episode(s, receipts[s['id']], disposals.get(s['id']), resumed_expected=i == 0)
                for i, s in enumerate(manifest['sequences']) if s['id'] in receipts]
        complete = bool(terminal and matches(terminal, run_id, digest) and terminal.get('completed') is True
                        and len(rows) == len(manifest['sequences']))
        checks = bool(complete and not anr and not framework_errors and all(r['completedInput'] and r['exactDeliveredIds'] and r['liveModels']
                      and r['disposalObserved'] and not r['errors'] and r['callbackDiagnostics']['omittedEvents'] == 0
                      and (not r['pauseResumeRequired'] or r['pauseResumeObserved'] and r['postResumeDelivery']) for r in rows))
        result = {'schemaVersion': 1, 'runId': run_id, 'manifestSha256': digest,
                  'promotionAllowed': False, 'completedBatch': complete, 'softwareProbeChecksPassed': checks,
                  'controllerTimedOut': not matches(terminal, run_id, digest), 'androidAnrObserved': anr,
                  'controllerActions': actions, 'episodes': rows,
                  'frameworkErrors': framework_errors,
                  'transportErrors': device.transport_errors,
                  'physicalDeviceValidation': 'not_run', 'controlledWalking': 'not_run',
                  'scope': p['scope'], 'nativeInferenceQueueMeasured': False}
        write_json(root/'continuity-evaluation.json', result)
        print(json.dumps(result, indent=2), flush=True)
        return result
    finally:
        (output/'logcat.txt').write_text(device.diagnostics(), encoding='utf-8')
        (output/'window.txt').write_text(device.call('shell', 'dumpsys', 'window').stdout.decode(errors='replace'), encoding='utf-8')
        device.stop()


def recover(root, adb, serial):
    """Recover only matching native receipts; retain the controller failure."""
    device = ContinuityDevice(adb, serial)
    raw = (root/'runtime/manifest.json').read_bytes(); digest = sha(raw)
    manifest = json.loads(raw); control = json.loads((root/'runtime/control.json').read_text())
    run_id = control['runId']; output = root/'app-reports'
    marker = device.read_json('batch-complete.json')
    if not matches(marker, run_id, digest) or marker.get('completed') is not True:
        raise ValueError('No completed native batch with this exact identity')
    rows = []
    for i, s in enumerate(manifest['sequences']):
        name = f'run-{s["id"]}.json'; r = device.read_json(name); d = device.read_json(name+'.disposal.json')
        if not matches(r, run_id, digest, s['id']) or not matches(d, run_id, digest, s['id']):
            raise ValueError('Missing or foreign recovered native receipt')
        write_json(output/name, r); write_json(output/(name+'.disposal.json'), d)
        rows.append(summarize_episode(s, r, d, resumed_expected=i == 0))
    write_json(output/'batch-complete.json', marker)
    result = {'schemaVersion': 1, 'runId': run_id, 'manifestSha256': digest, 'promotionAllowed': False,
        'completedBatch': True, 'softwareProbeChecksPassed': False,
        'controllerCollectionFailed': True, 'collectionMode': 'recovered_native_receipts_after_controller_transport_timeout',
        'episodes': rows, 'physicalDeviceValidation': 'not_run', 'controlledWalking': 'not_run',
        'scope': 'Actual matching app evidence recovered; the original controller run still failed.'}
    write_json(root/'recovered-evaluation.json', result)
    print(json.dumps({'runId': run_id, 'recoveredEpisodes': len(rows), 'originalControllerPassed': False}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('package'); p.add_argument('source', type=Path); p.add_argument('target', type=Path)
    p.add_argument('--protocol', type=Path, default=PROTOCOL)
    p = sub.add_parser('run'); p.add_argument('root', type=Path); p.add_argument('--adb', type=Path, required=True)
    p.add_argument('--serial', default='emulator-5554')
    p = sub.add_parser('recover'); p.add_argument('root', type=Path); p.add_argument('--adb', type=Path, required=True)
    p.add_argument('--serial', default='emulator-5554')
    a = parser.parse_args()
    if a.action == 'package': package(a.source, a.target, a.protocol)
    elif a.action == 'recover': recover(a.root.resolve(), a.adb, a.serial)
    else:
        result = run(a.root.resolve(), a.adb, a.serial)
        if not result['softwareProbeChecksPassed']: raise SystemExit(2)

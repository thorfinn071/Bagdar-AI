"""Write-once software contract; timings are deliberately not reproducibility data."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/camera_processing_age_contract.json'
SOURCES = [
    'lib/safety/perception/camera_cached_scale_metric_motion.dart',
    'lib/safety/runtime/camera_processing_age_gate.dart',
    'test/camera_processing_age_gate_test.dart',
    'test/camera_processing_parity_test.dart',
    'test/camera_processing_age_replay_test.dart',
    'test/harness/camera_processing_age_benchmark.dart',
    'tool/model_benchmark/profile_camera_processing.dart',
    'tool/model_benchmark/camera_processing_ncnn_worker.py',
    'tool/model_benchmark/evaluate_camera_processing_age.dart',
    'tool/model_benchmark/verify_camera_processing_age.py',
    'docs/camera-processing-age-protocol-2026-10-03.md',
]
REPORTS = [
    'docs/_baseline_logs/camera_processing_parity.json',
    'docs/_baseline_logs/camera_processing_age_functional.json',
    'docs/_baseline_logs/camera_processing_age_overload.json',
    'docs/_baseline_logs/camera_processing_age_runtime-overrun.json',
]


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def verify(check):
    old_path = 'docs/_baseline_logs/camera_scale_motion_development_freeze.json'
    for path, expected in read(old_path)['sourceSha256'].items():
        if sha(path) != expected:
            raise ValueError('Previous frozen source drift: ' + path)
    parity = read(REPORTS[0])
    if len(parity['frames']) != 109 or not all(f['equal'] for f in parity['frames']):
        raise ValueError('Matcher parity incomplete')
    approach = [f for f in parity['frames'] if f['layoutId'] in (
        'test-scale-motion-approach-slow-06', 'test-scale-motion-approach-fast-07',
        'test-scale-motion-approach-small-08')]
    if sum(f['addsMotionRisk'] for f in approach) != 18:
        raise ValueError('Known approach motion regression')
    for path in REPORTS[1:]:
        report = read(path)
        summary = report['summary']
        if report['promotionAllowed'] or report['currentAgeLimitUs'] != 100000:
            raise ValueError('Promotion or age policy changed')
        if any(summary[k] for k in ('staleApplications', 'unsafeContinueSteps', 'unjustifiedClearances')):
            raise ValueError('Safety regression')
        if report['mode'] == 'functional' and (
                summary['identityMatches'] != 67 or summary['onTimeStops'] != 9
                or summary['falseStopSequences'] != 0):
            raise ValueError('Frozen functional behavior changed')
        if report['mode'] == 'overload' and (
                summary['motionAppliedFrames'] or not summary['queueReplaced']
                or summary['falseStopSequences'] + summary['falseHoldSequences'] != 1):
            raise ValueError('Overload is not explicitly unavailable')
        if report['mode'] == 'runtime-overrun' and not summary['discardedClearDecisions']:
            raise ValueError('Late clear did not exercise the release guard')
        for sequence in report['sequences']:
            for frame in sequence['frames']:
                if frame['motionApplied'] and frame['ageAtReleaseUs'] > 100000:
                    raise ValueError('Stale motion application')
                if frame['rejection'] != 'none' and frame['passageApplied']:
                    raise ValueError('Unavailable data cleared passage')
    for path in SOURCES[:2]:
        text = (ROOT / path).read_text(encoding='utf-8')
        for forbidden in ('dart:io', 'annotations.json', 'visibleObjectMask', 'expectedDecision', 'mesh'):
            if forbidden in text:
                raise ValueError('Producer/gate reads external or hidden data: ' + path)
    receipt = {
        'scope': 'known-regression software parity and processing-age contract; no device promotion',
        'sourceSha256': {p: sha(p) for p in SOURCES},
        'reportSha256': {p: sha(p) for p in REPORTS},
        'previousFreezeSha256': sha(old_path),
        'priorTestIsKnownRegression': True, 'newIndependentHoldout': False,
        'promotionAllowed': False, 'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if OUT.read_text(encoding='utf-8') != rendered:
            raise ValueError('Processing-age contract drift')
    else:
        if OUT.exists():
            raise ValueError('Do not overwrite the processing-age contract')
        OUT.write_text(rendered, encoding='utf-8')
    print('Processing-age integrity: exact parity 109/109, approach 18/18, functional runtime 67/67, no stale application')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

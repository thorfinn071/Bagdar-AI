"""Write-once independent fast-motion regression contract; timings excluded."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/camera_fast_motion_contract_v2.json'
SOURCES = [
    'lib/safety/perception/camera_fast_motion_types.dart',
    'lib/safety/perception/camera_fast_metric_motion.dart',
    'lib/safety/runtime/camera_fast_motion_worker.dart',
    'lib/safety/runtime/camera_fast_motion_shadow_adapter.dart',
    'tool/model_benchmark/fast_camera_motion_fixture.dart',
    'tool/model_benchmark/profile_fast_camera_motion.dart',
    'tool/model_benchmark/replay_fast_camera_motion.dart',
    'tool/model_benchmark/evaluate_fast_camera_motion.dart',
    'tool/model_benchmark/verify_fast_camera_motion.py',
    'test/camera_fast_motion_test.dart',
    'test/camera_fast_motion_shadow_replay_test.dart',
    'test/harness/camera_fast_motion_shadow_benchmark.dart',
    'docs/camera-fast-motion-protocol-2026-10-03.md',
]
REPORTS = [
    'docs/_baseline_logs/camera_fast_motion_parity.json',
    'docs/_baseline_logs/camera_fast_motion_functional.json',
    'docs/_baseline_logs/camera_fast_motion_shadow.json',
]


def read(path):
    return json.loads((ROOT / path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify(check):
    old = 'docs/_baseline_logs/camera_processing_age_contract.json'
    for group in ('sourceSha256', 'reportSha256'):
        for path, expected in read(old)[group].items():
            if sha(path) != expected:
                raise ValueError('Previous frozen contract drift: ' + path)
    for path, expected in read('docs/_baseline_logs/camera_scale_motion_development_freeze.json')['sourceSha256'].items():
        if sha(path) != expected:
            raise ValueError('Original scale-motion freeze drift: ' + path)
    parity, functional, shadow = [read(path) for path in REPORTS]
    if len(parity['frames']) != 109 or not all(r['equal'] for r in parity['frames']):
        raise ValueError('Exact full-diagnostic AOT parity incomplete')
    f = functional['summary']
    if f['frames'] != 109 or f['admitted'] != 109 or f['approachRiskPairs'] != 18:
        raise ValueError('Functional independent worker regression')
    if f['staleReleases'] or f['freeSpaceCertifiedFrames']:
        raise ValueError('Stale release or clearance authority')
    s = shadow['summary']
    if s['frames'] != 67 or s['diagnosticMatches'] != 67 or s['freshMotionAppliedFrames'] != 30:
        raise ValueError('Real shadow runtime integration incomplete')
    if s['staleApplications'] or s['unsafeContinues'] or s['clearances'] or s['unknownRetainedFrames'] != 67:
        raise ValueError('Unknown or safety contract weakened')
    if s['sufficientPassableSequences'] != 1 or s['falseStopSequences'] + s['falseHoldSequences'] != 1:
        raise ValueError('Risk-only branch falsely declares useful clearance')
    for report in (parity, functional, shadow):
        if report['promotionAllowed'] or report['newIndependentHoldout']:
            raise ValueError('Experimental/known regression boundary changed')
    for path in SOURCES[:3]:
        text = (ROOT / path).read_text()
        for forbidden in ('dart:io', 'annotations.json', 'visibleObjectMask', 'expectedDecision', 'relativeModelHash', 'midas-small'):
            if forbidden in text:
                raise ValueError('Producer awaits NN or reads hidden data: ' + path)
    receipt = {
        'scope': 'known synthetic AOT parity and additive independent shadow worker; no phone promotion',
        'sourceSha256': {path: sha(path) for path in SOURCES},
        'reportSha256': {path: sha(path) for path in REPORTS},
        'previousProcessingContractSha256': sha(old),
        'initialFastContractSha256': sha('docs/_baseline_logs/camera_fast_motion_contract.json'),
        'promotionAllowed': False, 'newIndependentHoldout': False,
        'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if OUT.read_text() != rendered:
            raise ValueError('Independent fast-motion contract drift')
    else:
        if OUT.exists():
            raise ValueError('Never overwrite the fast-motion contract')
        OUT.write_text(rendered)
    print('Fast motion: AOT full parity 109/109, approach 18/18, shadow integration 67/67; unknown retained, no stale/unsafe/clearance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

"""Write-once versioned load experiment; preserve every earlier v2 source."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/camera_fast_motion_load_contract_v2.json'
INITIAL = 'docs/_baseline_logs/camera_fast_motion_load_contract.json'
SOURCES = [
    'lib/safety/perception/camera_fast_metric_motion_load.dart',
    'lib/safety/perception/camera_fast_motion_native_match.dart',
    'lib/safety/runtime/camera_fast_motion_load_worker.dart',
    'lib/safety/runtime/camera_fast_motion_load_shadow_adapter.dart',
    'tool/model_benchmark/native/fast_motion_match.c',
    'tool/model_benchmark/build_fast_motion_native.ps1',
    'tool/model_benchmark/profile_fast_camera_motion_load.dart',
    'tool/model_benchmark/replay_fast_camera_motion_load.dart',
    'tool/model_benchmark/evaluate_fast_camera_motion_load.dart',
    'tool/model_benchmark/summarize_fast_camera_motion_load.py',
    'tool/model_benchmark/verify_fast_camera_motion_load.py',
    'test/camera_fast_motion_load_test.dart',
    'test/camera_fast_motion_load_shadow_replay_test.dart',
    'test/harness/camera_fast_motion_load_shadow_benchmark.dart',
    'docs/camera-fast-motion-load-protocol-2026-10-04.md',
]
REPORT = 'docs/_baseline_logs/camera_fast_motion_load_shadow.json'
PREVIOUS = 'docs/_baseline_logs/camera_fast_motion_contract_v2.json'


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def verify(check):
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_fast_camera_motion.py',
                    '--check'], cwd=ROOT, check=True)
    initial = json.loads((ROOT / INITIAL).read_text())
    snapshot = ROOT / 'scratch/fast-motion-load-first-freeze'
    for path, expected in initial['sourceSha256'].items():
        if hashlib.sha256((snapshot / path).read_bytes()).hexdigest() != expected:
            raise ValueError('Initial load-source snapshot drift: ' + path)
    report = json.loads((ROOT / REPORT).read_text())
    old = json.loads((ROOT / 'docs/_baseline_logs/camera_fast_motion_shadow.json').read_text())
    if report != old:
        raise ValueError('Native shadow runtime differs from frozen v2 behavior')
    for path in SOURCES[:4] + [SOURCES[4]]:
        text = (ROOT / path).read_text()
        for forbidden in ('annotations.json', 'visibleObjectMask', 'expectedDecision',
                          'midas-small', 'relativeModelHash'):
            if forbidden in text:
                raise ValueError('Producer reads model/hidden scoring inputs: ' + path)
    receipt = {
        'scope': 'versioned Windows x64 native/RGB allocation experiment; known shadow regression',
        'sourceSha256': {path: sha(path) for path in SOURCES},
        'reportSha256': {REPORT: sha(REPORT)},
        'previousFastContractSha256': sha(PREVIOUS),
        'initialLoadContractSha256': sha(INITIAL),
        'frozenParityReferenceSha256': sha('docs/_baseline_logs/camera_fast_motion_parity.json'),
        'frozenFunctionalReferenceSha256': sha('docs/_baseline_logs/camera_fast_motion_functional.json'),
        'promotionAllowed': False, 'newIndependentHoldout': False,
        'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if OUT.read_text() != rendered:
            raise ValueError('Load experiment contract drift')
    else:
        if OUT.exists():
            raise ValueError('Never overwrite the load experiment receipt')
        OUT.write_text(rendered)
    print('Load experiment integrity: earlier v2 unchanged; shadow 67/67; no stale/unsafe/clearance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

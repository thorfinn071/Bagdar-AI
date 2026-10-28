"""Write-once source receipt for the transport/allocation correction."""
import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RECEIPT = ROOT / 'docs/_baseline_logs/camera_fast_motion_packed_contract_v1.json'
SOURCES = [
    'lib/safety/perception/camera_fast_metric_motion_packed.dart',
    'lib/safety/perception/camera_fast_motion_bulk_native_match.dart',
    'lib/safety/runtime/camera_fast_motion_packed_transport.dart',
    'lib/safety/runtime/camera_fast_motion_packed_worker.dart',
    'lib/safety/runtime/camera_fast_motion_packed_shadow_adapter.dart',
    'tool/model_benchmark/profile_fast_camera_motion_packed.dart',
    'tool/model_benchmark/replay_fast_camera_motion_packed.dart',
    'tool/model_benchmark/evaluate_fast_camera_motion_packed.dart',
    'tool/model_benchmark/verify_fast_camera_motion_packed.py',
    'test/camera_fast_motion_packed_worker_test.dart',
    'test/camera_fast_motion_packed_shadow_replay_test.dart',
    'test/harness/camera_fast_motion_packed_shadow_benchmark.dart',
    'docs/camera-fast-motion-packed-protocol-2026-10-07.md',
]


def sha(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def canonical(text):
    # These versioned Dart modules contain no comment delimiters in strings.
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
    return re.sub(r'\s+', '', text)


def verify(check):
    subprocess.run([sys.executable,
                    'tool/model_benchmark/verify_fast_camera_motion_load.py',
                    '--check'], cwd=ROOT, check=True)
    old = (ROOT / 'lib/safety/perception/camera_fast_metric_motion_load.dart').read_text()
    expected = old.replace('camera_fast_motion_native_match.dart',
                           'camera_fast_motion_bulk_native_match.dart')
    expected = expected.replace('CameraFastMotionNativeMatch',
                                'CameraFastMotionBulkNativeMatch')
    expected = expected.replace('CameraFastMetricMotionLoadSource',
                                'CameraFastMetricMotionPackedSource')
    if canonical(expected) != canonical((ROOT / SOURCES[0]).read_text()):
        raise ValueError('Numeric source changed beyond the native copy adapter')
    old = (ROOT / 'lib/safety/perception/camera_fast_motion_native_match.dart').read_text()
    expected = old.replace('CameraFastMotionNativeMatch',
                           'CameraFastMotionBulkNativeMatch')
    expected = expected.replace('numbers = calloc<Double>(',
                                'numbers = malloc<Double>(')
    expected = expected.replace('calloc.free(numbers);', 'malloc.free(numbers);')
    expected = expected.replace('pointer.asTypedList(values.length).setAll(0, values);',
                                'pointer.asTypedList(values.length).setRange(0, values.length, values);')
    if canonical(expected) != canonical((ROOT / SOURCES[1]).read_text()):
        raise ValueError('Native adapter changed beyond owned copy allocation')
    for path in SOURCES[:5]:
        text = (ROOT / path).read_text()
        for forbidden in ('annotations.json', 'visibleObjectMask',
                          'expectedDecision', 'midas-small', 'relativeModelHash'):
            if forbidden in text:
                raise ValueError('Producer reads model or hidden scoring inputs: ' + path)
    receipt = {
        'scope': 'Windows x64 owned transport/allocation correction; known synthetic regression',
        'sourceSha256': {path: sha(path) for path in SOURCES},
        'previousLoadContractSha256': sha(
            'docs/_baseline_logs/camera_fast_motion_load_contract_v2.json'),
        'frozenReferencesSha256': {
            f'docs/_baseline_logs/camera_fast_motion_{name}.json': sha(
                f'docs/_baseline_logs/camera_fast_motion_{name}.json')
            for name in ('parity', 'functional', 'load_shadow')
        },
        'numericSourceUnchanged': True,
        'currentAgeLimitUs': 100000,
        'promotionAllowed': False,
        'ordinaryCameraWired': False,
        'newIndependentHoldout': False,
        'captureToCommandMeasured': False,
        'timingsAreReproducibilityData': False,
    }
    rendered = json.dumps(receipt, indent=2) + '\n'
    if check:
        if RECEIPT.read_text() != rendered:
            raise ValueError('Packed correction source receipt drift')
    else:
        if RECEIPT.exists():
            raise ValueError('Never overwrite the packed correction receipt')
        RECEIPT.write_text(rendered)
    print('Packed integrity: earlier receipts unchanged; numeric source unchanged; shadow only')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    verify(parser.parse_args().check)

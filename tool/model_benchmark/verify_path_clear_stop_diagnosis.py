"""Pin a cause-only correction and the known paired-scene causal probe."""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'docs/_baseline_logs/path_clear_stop_diagnosis_contract_v1.json'
REPORT = ROOT / 'scratch/path-clear-diagnosis-2026-10-07/replay.json'
SOURCES = [
    'lib/safety/planning/coverage_aware_stop_guidance.dart',
    'test/coverage_aware_stop_guidance_test.dart',
    'test/harness/path_clear_stop_diagnosis.dart',
    'test/path_clear_stop_diagnosis_test.dart',
    'tool/model_benchmark/verify_path_clear_stop_diagnosis.py',
    'docs/path-clear-stop-diagnosis-protocol-2026-10-07.md',
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def build():
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_visible_body.py'],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    data = read(REPORT)
    expected = dict(frames=22, passableFrames=11, hazardFrames=11,
                    baselineFalseStops=11, correctedFalseStops=11,
                    hazardStops=11, hazardUnsafeContinues=0, reasonCorrections=1,
                    passableWithoutLatchStops=11,
                    passableWithoutTracksMovingStops=11,
                    passableWithoutTracksStationaryHolds=11)
    if data['summary'] != expected or data['failures']:
        raise ValueError('Selected scene diagnosis or protected decisions drift')
    for key in ('promotionAllowed', 'ordinaryCameraWired',
                'falseStopReductionEstablished', 'captureToCommandMeasured'):
        if data[key] is not False:
            raise ValueError('Unexpected claimed authority: ' + key)
    for row in data['frames']:
        before, after = row['baseline'], row['correctedCause']
        for key in ('action', 'passageApplied', 'forwardUnknown',
                    'forwardOccupancy', 'positiveCorridor',
                    'rejectionReasons', 'passage', 'associations'):
            if before[key] != after[key]:
                raise ValueError('Cause correction changed sensing/decision: ' + key)
        if after['action'] != 'stopNow' or after['passageApplied']:
            raise ValueError('Unjustified clearance in selected scene')
    first = next(r for r in data['frames'] if r['sceneId'] == 'path-clear')
    for fault in ('holes', 'relativeUnits', 'staleMetricObservation'):
        value = first['testOnlyAblations'][fault]
        if value['action'] != 'stopNow' or value['passageApplied'] or value['passage']['status'] != 'unavailable':
            raise ValueError('Invalid input gained clearance: ' + fault)
    return {
        'scope': 'known paired causal diagnosis and opt-in cause-only shadow correction',
        'sourceSha256': {path: sha(ROOT / path) for path in SOURCES},
        'reportSha256': sha(REPORT),
        'priorVisibleBodyContractSha256': sha(ROOT / 'docs/_baseline_logs/blender_visible_body_contract_v2.json'),
        'priorVisibleBodyReportSha256': sha(ROOT / 'docs/_baseline_logs/blender_visible_body_shadow_v2.json'),
        'summary': expected,
        'metricPassageAgeLimitUs': 100000,
        'falseStopReductionEstablished': False,
        'promotionAllowed': False,
        'ordinaryCameraWired': False,
        'newIndependentHoldout': False,
        'namedDeviceRuntime': 'not_run',
        'captureToCommandMeasured': False,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    rendered = json.dumps(build(), indent=2) + '\n'
    if args.write:
        if OUT.exists():
            raise ValueError('Never overwrite the diagnosis contract')
        OUT.write_text(rendered, encoding='utf-8')
    elif OUT.read_text(encoding='utf-8') != rendered:
        raise ValueError('Diagnosis source/output contract drift')
    print('Path-clear: frozen sources intact; 22-frame cause-only correction; false-stop reduction not established')

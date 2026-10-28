"""Audit the actual ordinary-camera objective, not software proxy completion."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/typed-scan-transport-2026-10-11'


def read(relative):
    return json.loads((ROOT / relative).read_bytes())


def sha(relative):
    return hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()


frozen = read('scratch/typed-scan-transport-2026-10-11/preregistration.json')
for p, digest in frozen['sources'].items():
    assert sha(p) == digest, p
baselines = ['scratch/closed-volume-control-2026-10-11/replay.json',
             'scratch/volume-holdout-2026-10-10/replay.json']
for p in baselines:
    assert sha(p) == frozen['sources'][p]
closed, holdout = map(read, baselines)
single = closed['summary']['runtime']['frameStable/fixedSingleView']
independent = holdout['summary']['runtime']['frameStable/fixedSingleView']
assert single['falseStops'] == 14 and single['passableContinues'] == 0
assert independent['falseStops'] == 34 and independent['hazardStops'] == 50
assert independent['hazardMisses'] == 0
observability_path = 'scratch/single-camera-observability-2026-10-11/validation.json'
observability = read(observability_path)
ordinary = [v for v in observability['views'] if v['viewId'] != 'ideal-wide-control']
assert all(v['entireRequestInView'] is False for v in ordinary)
assert all(v['fullMeasurementStatuses']['measuredClear'] == 0 for v in ordinary)
elapsed_path = 'scratch/typed-scan-transport-2026-10-11/elapsed-validation.json'
elapsed = read(elapsed_path)
assert elapsed['elapsedAuditPassed'] and elapsed['samples'] == 108
assert all(s['ageStatuses'] == {'expiredAfterCompute': 36}
           for s in elapsed['summaries'].values())
parity = read('scratch/typed-scan-transport-2026-10-11/parity-validation.json')
assert parity['parityAuditPassed'] and parity['corpusPairs'] == 48
adb = Path(os.environ['LOCALAPPDATA']) / 'Android/Sdk/platform-tools/adb.exe'
state = subprocess.run([str(adb), 'devices', '-l'], capture_output=True, text=True,
                       check=True, timeout=20)
devices = [line.strip() for line in state.stdout.splitlines()
           if line.strip() and not line.startswith('List of devices attached')]
assert not devices, 'Device state changed; reassess instead of declaring an impasse'
consumers = []
for p in (ROOT / 'lib').rglob('*.dart'):
    code = p.read_text(encoding='utf-8')
    if 'camera_typed_height_envelope_frame.dart' in code or 'camera_scalar_height_envelope_passage_source.dart' in code:
        consumers.append(p.relative_to(ROOT).as_posix())
assert not consumers, consumers
result = {
    'objectiveComplete': False,
    'blocker': 'No available justified current ordinary-camera metric/body-volume measurement source; phone unavailable',
    'requirements': {
        'ordinarySingleViewFalseStopsReduced': {'status': 'not_met', 'falseStops': 14, 'passableFrames': 14},
        'independentFalseStopsReduced': {'status': 'not_met', 'falseStops': 34, 'passableFrames': 34},
        'frozenHazardStopsPreserved': {'status': 'old_receipt_only', 'hazardStops': 50, 'hazards': 50},
        'invalidStaleRelativeMismatchSoftwareControls': {'status': 'passed_targeted_tests_only'},
        'strictCurrentMetricCameraProof': {'status': 'missing_real_capture_and_validated_bounds'},
        'ordinaryFrustumComplete': {'status': 'not_met', 'ordinaryViews': len(ordinary)},
        'strictElapsedDeadline': {'status': 'not_met', 'expiredSamples': 108, 'samples': 108},
        'shadowBoundary': {'status': 'preserved', 'ordinaryConsumers': consumers},
    },
    'freshAdbDevices': devices,
    'runtimeReceiptsReplayedThisTurn': False,
    'consecutiveGoalTurnsWithSameExternalBlocker': 3,
    'turnEvidence': ['single-camera-minimal-scan-2026-10-11',
                     'scalar-scan-processing-2026-10-11', 'typed-scan-transport-2026-10-11'],
    'userConfirmedPhoneUnavailable': True,
    'impasseAssessment': 'More arithmetic/transport changes cannot supply the absent near/body-volume observations or establish real metric calibration. Keep ordinary unknown STOP; require a new measurement source/capture to advance the false-stop objective.',
    'requiredExternalChange': 'Provide real paired RGB/depth/pose/intrinsics capture with independent metric/alignment/error evidence; phone connection alone does not prove these.',
    'evidenceSha256': {p: sha(p) for p in [*baselines, observability_path, elapsed_path]},
    'promotionAllowed': False, 'ordinaryCameraWired': False,
    'falseStopReductionEstablished': False,
}
with (OUT / 'goal-audit.json').open('x', encoding='utf-8') as f:
    f.write(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))

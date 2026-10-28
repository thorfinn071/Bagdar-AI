"""Freeze/audit the metadata-selected scan; never infer phone capabilities."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/single-camera-minimal-scan-2026-10-11'
PRIOR = ROOT / 'scratch/single-camera-fresh-scan-2026-10-11'
MANIFEST = ROOT / 'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1/manifest.json'
NEW = [
    'docs/single-camera-minimal-scan-protocol-2026-10-11.md',
    'test/single_camera_minimal_scan_experiment_test.dart',
    'tool/model_benchmark/plan_camera_scan_geometry.py',
    'tool/model_benchmark/single_camera_minimal_scan.py',
    'tool/model_benchmark/profile_minimal_scan.dart',
    'scratch/single-camera-minimal-scan-2026-10-11/geometry-plan.json',
]
SCHEDULES = {'original': (0, 0), '30fps': (30, 0), '60fps': (60, 0),
             '90fps': (90, 0), '120fps': (120, 0),
             '120fps-compute15ms': (120, 15000),
             '120fps-compute25ms': (120, 25000)}
FAULTS = {'relative', 'invalidPixels', 'missingHeight', 'missingFirstReturn',
          'badPose', 'wrongModel', 'mixedSessions'}


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def freeze():
    prior = read(PRIOR / 'preregistration.json')
    paths = set(prior['sources'])
    for p, digest in prior['sources'].items():
        assert sha(ROOT / p) == digest, p
    paths.update(NEW)
    paths.update((PRIOR / p).relative_to(ROOT).as_posix() for p in
                 ['preregistration.json', 'experiment.json', 'validation.json'])
    result = {'scope': 'finite-pose known static synthetic diagnostic only',
              'promotionAllowed': False,
              'sources': {p: sha(ROOT / p) for p in sorted(paths)}}
    with (OUT / 'preregistration.json').open('x', encoding='utf-8') as f:
        f.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'frozenFiles': len(paths)}))


def audit_plan():
    plan = read(OUT / 'geometry-plan.json')
    assert plan['sourceSha256'] == sha(ROOT / 'tool/model_benchmark/plan_camera_scan_geometry.py')
    assert plan['manifestSha256'] == sha(MANIFEST)
    layouts = {l['sceneId']: l for l in read(MANIFEST)['layouts']}
    by_key = {p['geometrySha256']: p for p in plan['plans']}
    selected = {}
    for l in plan['layouts']:
        p = by_key[l['geometrySha256']]
        geometry = [{k: f['axisPacket'][k] for k in
                     ('width', 'height', 'fx', 'fy', 'cx', 'cy',
                      'cameraToWalkingRotation', 'cameraOriginM')}
                    for f in layouts[l['sceneId']]['frames']]
        assert p['views'] == geometry
        digest = hashlib.sha256(json.dumps(geometry, sort_keys=True).encode()).hexdigest()
        assert p['geometrySha256'] == digest
        constraints = p['terminalViewMasks']
        feasible = [m for m in range(1, 1 << len(geometry)) if all(m & c for c in constraints)]
        n = min(m.bit_count() for m in feasible)
        masks = [m for m in feasible if m.bit_count() == n]
        assert p['minimumViews'] == n and p['minimumViewMasks'] == masks
        indices = [i for i in range(len(geometry)) if masks[0] & (1 << i)]
        assert p['selectedIndices'] == indices
        assert not p['canCertifyFreeSpace'] and not p['canAuthorizeMovement']
        selected[l['sceneId']] = indices
    return layouts, selected


def verify():
    frozen = read(OUT / 'preregistration.json')
    for p, digest in frozen['sources'].items():
        assert sha(ROOT / p) == digest, p
    layouts, selected = audit_plan()
    data = read(OUT / 'experiment.json')
    assert data['maximumAgeUs'] == 100000
    for key in ['promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished',
                'latencyMeasured', 'sceneMotionValidated', 'singleCameraDynamicsValidated',
                'canAuthorizeMovement']:
        assert data[key] is False
    labels = {r['sceneId']: r['physicalHazard'] for r in
              read(ROOT / 'docs/_baseline_logs/blender_scan_complete_replay_v1.json')['scans']}
    seen, checks = set(), 0
    base = int(datetime(2026, 10, 4, tzinfo=timezone.utc).timestamp()) * 1000000
    for r in data['rows']:
        key = r['sceneId'], r['selection'], r['scheduleId']
        assert key not in seen
        seen.add(key)
        packets = [f['axisPacket'] for f in layouts[r['sceneId']]['frames']]
        indices = list(range(12)) if r['selection'] == 'full' else selected[r['sceneId']]
        fps, compute = SCHEDULES[r['scheduleId']]
        assert r['selectedOriginalIndices'] == indices
        assert (r['fps'], r['simulatedComputeUs']) == (fps, compute)
        times = ([base + packets[i]['capturedOffsetMs'] * 1000 for i in indices] if fps == 0 else
                 [base + (i * 1000000 + fps // 2) // fps for i in range(len(indices))])
        assert r['assignedCaptureTimesUs'] == times
        assert r['counterfactualClock'] == (fps != 0)
        start, finish = times[-1] + 2000, times[-1] + 2000 + compute
        retained = [i for i, t in enumerate(times) if start - t <= 100000]
        assert r['retainedOriginalIndices'] == [indices[i] for i in retained]
        oldest = times[retained[0]]
        snapshot = r['snapshot']
        assert snapshot['captureTimesUs'] == [times[i] for i in retained]
        assert snapshot['frameIds'] == [packets[indices[i]]['frameId'] for i in retained]
        assert snapshot['oldestCaptureUs'] == oldest and snapshot['inspectedAtUs'] == start
        assert snapshot['canAuthorizeMovement'] is False
        assert r['oldestAgeAtStartUs'] == start - oldest
        assert r['oldestAgeAtCompletionUs'] == finish - oldest
        o, before, released = r['observation'], r['preCompletionMeasurement'], r['releasedMeasurement']
        assert o['oldestEvidenceTimestampUs'] == oldest
        assert o['rgbTimestampUs'] == o['depthTimestampUs'] == times[-1]
        assert o['producedAtUs'] == start and o['frameId'] == packets[indices[-1]]['frameId']
        assert r['physicalHazard'] == labels[r['sceneId']]
        if finish - oldest > 100000:
            assert r['ageStatus'] == 'expiredAfterCompute' and released is None
        elif before['status'] == 'unavailable':
            assert r['ageStatus'] == 'unavailable' and released is None
        else:
            assert r['ageStatus'] == 'admitted' and released['status'] == before['status']
            assert released['evaluatedAtUs'] == finish
        assert r['releasedObservationPresent'] == (released is not None)
        if released and released['status'] == 'measuredClear':
            assert not labels[r['sceneId']]
            assert released['validUntilUs'] == oldest + 100000
            for s in o['sections']:
                assert s['state'] == 'measured'
                assert s['bodyObservedFraction'] == s['floorObservedFraction'] == 1
                assert s['headroomLowerBoundM'] >= 1.85 - 1e-9
                assert s['rightBoundaryLowerM'] - s['leftBoundaryUpperM'] >= .9 - 1e-9
                checks += 1
        angles = []
        for a, b in zip(indices, indices[1:]):
            ra = np.array(packets[a]['cameraToWalkingRotation']).reshape(3, 3)
            rb = np.array(packets[b]['cameraToWalkingRotation']).reshape(3, 3)
            angles.append(math.degrees(math.acos(np.clip((np.trace(ra.T @ rb) - 1) / 2, -1, 1))))
        assert math.isclose(sum(angles), r['rotationTotalDegrees'], abs_tol=1e-6)
        peak = max(v * 1000000 / (times[i + 1] - times[i]) for i, v in enumerate(angles))
        assert math.isclose(peak, r['peakRequiredRotationDegPerSec'], rel_tol=1e-9)
        checks += 15
    assert seen == {(scene, selection, schedule) for scene in layouts
                    for selection in ['full', 'minimal'] for schedule in SCHEDULES}
    assert len(data['negatives']) == 84
    assert {(r['sceneId'], r['fault']) for r in data['negatives']} == {
        (scene, fault) for scene in layouts for fault in FAULTS}
    assert all(r['measurement']['status'] != 'measuredClear' for r in data['negatives'])
    summaries = []
    for selection in ['full', 'minimal']:
        for schedule in SCHEDULES:
            rows = [r for r in data['rows'] if (r['selection'], r['scheduleId']) == (selection, schedule)]
            summaries.append({'selection': selection, 'scheduleId': schedule,
                'outcomes': dict(Counter((r['releasedMeasurement'] or {}).get('status', 'unavailable') for r in rows)),
                'preCompletionOutcomes': dict(Counter(r['preCompletionMeasurement']['status'] for r in rows)),
                'ageStatuses': dict(Counter(r['ageStatus'] for r in rows)),
                'retainedViews': sorted({len(r['retainedOriginalIndices']) for r in rows}),
                'oldestAgeAtStartUs': rows[0]['oldestAgeAtStartUs'],
                'oldestAgeAtCompletionUs': rows[0]['oldestAgeAtCompletionUs'],
                'peakRequiredRotationDegPerSec': rows[0]['peakRequiredRotationDegPerSec']})
    result = {'integrityPassed': True, 'frozenFiles': len(frozen['sources']),
        'independentChecks': checks + 84, 'rows': len(seen), 'negativeTrials': 84,
        'experimentSha256': sha(OUT / 'experiment.json'), 'summaries': summaries,
        'promotionAllowed': False, 'falseStopReductionEstablished': False}
    (OUT / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


def verify_elapsed():
    # The profile uses an advancing Stopwatch, independently of assigned
    # acquisition clocks and of the deterministic simulated-compute matrix.
    frozen = read(OUT / 'preregistration.json')
    for p, digest in frozen['sources'].items():
        assert sha(ROOT / p) == digest, p
    data = read(OUT / 'elapsed.json')
    for key in ['neuralLoad', 'captureMeasured', 'sceneMotionValidated',
                'phoneValidated', 'promotionAllowed', 'canAuthorizeMovement']:
        assert data[key] is False
    assert len(data['rows']) == 72
    layouts, selected = audit_plan()
    seen = set()
    for r in data['rows']:
        key = r['sceneId'], r['selection'], r['round']
        assert key not in seen
        seen.add(key)
        assert r['elapsedPipelineUs'] > 0
        assert r['oldestAgeAtCompletionUs'] - r['oldestAgeAtStartUs'] == r['elapsedPipelineUs']
        count = 12 if r['selection'] == 'full' else len(selected[r['sceneId']])
        capture_age = ((count - 1) * 1000000 + 60) // 120 + 2000
        assert r['oldestAgeAtStartUs'] >= capture_age
        if r['ageStatus'] == 'admitted':
            assert r['oldestAgeAtCompletionUs'] <= 100000
            assert r['releasedStatus'] in ['blocked', 'measuredClear']
            assert r['releasedObservationPresent']
        else:
            assert r['releasedStatus'] is None and not r['releasedObservationPresent']
        if r['ageStatus'] == 'expiredAfterCompute':
            assert r['oldestAgeAtCompletionUs'] > 100000
        if r['sourceStagesUs'] is not None:
            assert sum(r['sourceStagesUs'].values()) <= r['elapsedPipelineUs']
    assert seen == {(scene, selection, round_) for scene in layouts
                    for selection in ['full', 'minimal'] for round_ in range(3)}
    for mode in ['full', 'minimal']:
        values = [r['elapsedPipelineUs'] / 1000 for r in data['rows'] if r['selection'] == mode]
        summary = data['summaries'][mode]
        assert summary['samples'] == len(values) == 36
        assert math.isclose(summary['p50Ms'], np.percentile(values, 50))
        assert math.isclose(summary['p95Ms'], np.percentile(values, 95))
        assert summary['maximumMs'] == max(values)
    result = {'elapsedAuditPassed': True, 'samples': 72,
        'ageStatuses': dict(Counter(r['ageStatus'] for r in data['rows'])),
        'summaries': data['summaries'], 'elapsedSha256': sha(OUT / 'elapsed.json'),
        'promotionAllowed': False}
    (OUT / 'elapsed-validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['freeze', 'verify', 'verify-elapsed'])
    args = p.parse_args()
    {'freeze': freeze, 'verify': verify, 'verify-elapsed': verify_elapsed}[args.action]()

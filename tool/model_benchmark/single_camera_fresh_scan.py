"""Seal/audit a static-scene counterfactual; never treat assigned clocks as capture."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/single-camera-fresh-scan-2026-10-11'
FIXTURES = ROOT / 'test/fixtures/spatial_safety'
COMPLETE = FIXTURES / 'blender-scan-complete-envelope-v1'
EXACT = FIXTURES / 'blender-scan-exact-height-v1'
COVERAGE = FIXTURES / 'blender-scan-coverage-v1'
SCHEDULES = {
    'original-2200ms': (0, 2000, 0), '30fps-2ms': (30, 2000, 0),
    '60fps-2ms': (60, 2000, 0), '120fps-2ms': (120, 2000, 0),
    '120fps-25ms': (120, 25000, 0),
    '120fps-2ms-compute15ms': (120, 2000, 15000),
}
NEW = [
    'docs/single-camera-fresh-scan-protocol-2026-10-11.md',
    'lib/safety/perception/single_camera_scan_window.dart',
    'test/single_camera_scan_window_test.dart',
    'test/single_camera_fresh_scan_experiment_test.dart',
    'tool/model_benchmark/single_camera_fresh_scan.py',
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def relative(path):
    return Path(path).relative_to(ROOT).as_posix()


def freeze():
    prior = ROOT / 'scratch/single-camera-observability-2026-10-11/preregistration.json'
    paths = set(read(prior)['sources'])
    for name, expected in read(prior)['sources'].items():
        assert sha(ROOT / name) == expected, name
    paths.update(NEW)
    paths.update([
        relative(prior),
        'scratch/single-camera-observability-2026-10-11/experiment.json',
        'scratch/single-camera-observability-2026-10-11/validation.json',
        'docs/_baseline_logs/blender_scan_complete_replay_v1.json',
        'tool/model_benchmark/scan_processing_support.dart',
    ])
    for directory in [COMPLETE, EXACT, COVERAGE,
                      FIXTURES / 'blender-scan-watertight-height-v1',
                      FIXTURES / 'blender-paired-visible-body-v1',
                      FIXTURES / 'blender-paired-holdout-v1']:
        manifest = directory / ('corpus-manifest.json' if directory.name.endswith('holdout-v1') else 'manifest.json')
        data = read(manifest)
        paths.add(relative(manifest))
        for name, expected in data.get('sources', {}).items():
            assert sha(ROOT / name) == expected, name
            paths.add(name)
    for layout in read(COMPLETE / 'manifest.json')['layouts']:
        for frame in layout['frames']:
            for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity'):
                asset = frame['axisPacket'][key]
                path = COVERAGE / asset['path']
                assert sha(path) == asset['sha256']
                paths.add(relative(path))
            asset = frame['firstZLower']
            path = COMPLETE / asset['path']
            assert sha(path) == asset['sha256']
            paths.add(relative(path))
    for layout in read(EXACT / 'manifest.json')['layouts']:
        for frame in layout['frames']:
            for key in ('heightLower', 'heightUpper'):
                asset = frame[key]
                path = EXACT / asset['path']
                assert sha(path) == asset['sha256']
                paths.add(relative(path))
    OUT.mkdir(parents=True, exist_ok=True)
    receipt = {'scope': 'known static snapshots; assigned clocks are counterfactual',
               'promotionAllowed': False,
               'sources': {p: sha(ROOT / p) for p in sorted(paths)}}
    with (OUT / 'preregistration.json').open('x', encoding='utf-8') as file:
        file.write(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'frozenFiles': len(paths), 'promotionAllowed': False}))


def verify():
    frozen = read(OUT / 'preregistration.json')
    for name, expected in frozen['sources'].items():
        assert sha(ROOT / name) == expected, name
    result = read(OUT / 'experiment.json')
    assert result['maximumAgeUs'] == 100000
    assert all(result[k] is False for k in ('promotionAllowed', 'ordinaryCameraWired',
                                          'falseStopReductionEstablished', 'latencyMeasured'))
    layouts = {p['sceneId']: p for p in read(COMPLETE / 'manifest.json')['layouts']}
    assert len(layouts) == 12 and len(result['rows']) == 72
    old = read(ROOT / 'docs/_baseline_logs/blender_scan_complete_replay_v1.json')
    labels = {p['sceneId']: p['physicalHazard'] for p in old['scans']}
    base = int(datetime(2026, 10, 4, tzinfo=timezone.utc).timestamp()) * 1000000
    seen, summaries, checks = set(), [], 0
    for row in result['rows']:
        identity = row['sceneId'], row['scheduleId']
        assert identity not in seen
        seen.add(identity)
        packets = [f['axisPacket'] for f in layouts[row['sceneId']]['frames']]
        assert row['physicalHazard'] == labels[row['sceneId']]
        fps, lag, compute = SCHEDULES[row['scheduleId']]
        assert (row['fps'], row['startLagUs'], row['simulatedComputeUs']) == (fps, lag, compute)
        original = [base + p['capturedOffsetMs'] * 1000 for p in packets]
        assigned = original if fps == 0 else [base + (i * 1000000 + fps // 2) // fps for i in range(12)]
        assert row['originalCaptureTimesUs'] == original
        assert row['assignedCaptureTimesUs'] == assigned
        assert row['assignedFrameIds'] == [p['frameId'] for p in packets]
        assert row['counterfactualClock'] == (fps != 0)
        assert all(row[k] is False for k in ('sceneMotionValidated', 'singleCameraDynamicsValidated', 'canAuthorizeMovement'))
        start, finish = assigned[-1] + lag, assigned[-1] + lag + compute
        selected = [i for i, capture in enumerate(assigned) if start - capture <= 100000]
        after = [i for i in selected if finish - assigned[i] <= 100000]
        assert row['selectedIndices'] == selected
        for snapshot, indices, at in [(row['snapshot'], selected, start), (row['afterCompute'], after, finish)]:
            assert snapshot['inspectedAtUs'] == at
            assert snapshot['frameIds'] == [packets[i]['frameId'] for i in indices]
            assert snapshot['captureTimesUs'] == [assigned[i] for i in indices]
            assert snapshot['oldestCaptureUs'] == (assigned[indices[0]] if indices else None)
            assert not snapshot['canAuthorizeMovement']
            checks += 1
        oldest = assigned[selected[0]]
        assert row['oldestAgeAtStartUs'] == start - oldest <= 100000
        assert row['oldestAgeAtCompletionUs'] == finish - oldest
        observation = row['observation']
        assert observation['oldestEvidenceTimestampUs'] == oldest
        assert observation['rgbTimestampUs'] == observation['depthTimestampUs'] == assigned[-1]
        assert observation['producedAtUs'] == start
        assert observation['frameId'] == packets[-1]['frameId']
        before, released = row['preCompletionMeasurement'], row['releasedMeasurement']
        if finish - oldest > 100000:
            assert row['ageStatus'] == 'expiredAfterCompute'
            assert released is None and not row['releasedObservationPresent']
        elif before['status'] == 'unavailable':
            assert row['ageStatus'] == 'unavailable'
            assert released is None and not row['releasedObservationPresent']
        else:
            assert row['ageStatus'] == 'admitted' and row['releasedObservationPresent']
            assert released['status'] == before['status']
            assert released['evaluatedAtUs'] == finish
            if released['status'] == 'measuredClear':
                assert not row['physicalHazard']
                assert released['validUntilUs'] == oldest + 100000
                for section in observation['sections']:
                    assert section['state'] == 'measured'
                    assert section['bodyObservedFraction'] == section['floorObservedFraction'] == 1
                    assert section['rightBoundaryLowerM'] - section['leftBoundaryUpperM'] >= .9 - 1e-9
                    assert section['headroomLowerBoundM'] >= 1.85 - 1e-9
                    checks += 1
        angles = []
        for a, b in zip(packets, packets[1:]):
            ra = np.array(a['cameraToWalkingRotation']).reshape(3, 3)
            rb = np.array(b['cameraToWalkingRotation']).reshape(3, 3)
            angles.append(math.degrees(math.acos(np.clip((np.trace(ra.T @ rb) - 1) / 2, -1, 1))))
        rates = [angle * 1000000 / (assigned[i + 1] - assigned[i]) for i, angle in enumerate(angles)]
        assert np.allclose(row['rotationStepDegrees'], angles, rtol=1e-9, atol=1e-6)
        assert math.isclose(row['rotationTotalDegrees'], sum(angles), abs_tol=1e-6)
        assert math.isclose(row['peakRequiredRotationDegPerSec'], max(rates), rel_tol=1e-9)
        assert row['sweepDurationUs'] == assigned[-1] - assigned[0]
        checks += 8
    assert seen == {(scene, schedule) for scene in layouts for schedule in SCHEDULES}
    for schedule in SCHEDULES:
        rows = [r for r in result['rows'] if r['scheduleId'] == schedule]
        outcomes = Counter((r['releasedMeasurement'] or {}).get('status', 'unavailable') for r in rows)
        summaries.append({
            'scheduleId': schedule, 'snapshots': len(rows),
            'retainedFrames': sorted({len(r['selectedIndices']) for r in rows}),
            'outcomes': dict(outcomes),
            'ageStatuses': dict(Counter(r['ageStatus'] for r in rows)),
            'sweepDurationUs': rows[0]['sweepDurationUs'],
            'peakRequiredRotationDegPerSec': max(r['peakRequiredRotationDegPerSec'] for r in rows),
            'oldestAgeAtStartUs': max(r['oldestAgeAtStartUs'] for r in rows),
        })
    validation = {'integrityPassed': True, 'frozenFiles': len(frozen['sources']),
                  'independentChecks': checks, 'rows': len(seen), 'schedules': summaries,
                  'promotionAllowed': False, 'falseStopReductionEstablished': False,
                  'experimentSha256': sha(OUT / 'experiment.json')}
    (OUT / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(validation, indent=2))


def render():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    summaries = read(OUT / 'validation.json')['schedules']
    labels = ['Original 2.2 s', '30 fps + 2 ms', '60 fps + 2 ms',
              '120 fps + 2 ms', '120 fps + 25 ms', '120 fps + 2 ms + 15 ms compute']
    fig, ax = plt.subplots(figsize=(12, 6))
    left = np.zeros(len(summaries))
    for status, color in [('measuredClear', '#25877a'), ('blocked', '#cc6c31'), ('unavailable', '#b9c4d5')]:
        counts = np.array([s['outcomes'].get(status, 0) for s in summaries])
        ax.barh(labels, counts, left=left, color=color, label=status)
        for i, count in enumerate(counts):
            if count:
                ax.text(left[i] + count / 2, i, str(count), va='center', ha='center')
        left += counts
    ax.invert_yaxis()
    ax.set(xlim=(0, 12), xlabel='Known static snapshots (6 passable, 6 hazards)',
           title='Single-camera scan: strict 100 ms evidence age')
    ax.legend(loc='lower right', bbox_to_anchor=(1, 1))
    fig.text(.015, .015, 'Assigned frame rates/clocks are counterfactual. Clear relies on synthetic static-scene bounds.\nNo phone frame rate, scene-currentness, latency or movement authority established.', fontsize=10)
    fig.tight_layout(rect=[0, .10, 1, 1])
    for suffix in ('png', 'svg'):
        fig.savefig(OUT / f'fresh-scan.{suffix}', dpi=160)
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify', 'render'])
    globals()[parser.parse_args().action]()

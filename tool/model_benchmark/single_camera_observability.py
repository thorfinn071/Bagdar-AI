"""Freeze/independently audit a known-scene single-camera feasibility experiment."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/single-camera-observability-2026-10-11'
VIEWS = ROOT / 'scratch/camera-view-coverage-2026-10-09'
NEW = [
    'docs/single-camera-observability-protocol-2026-10-11.md',
    'lib/safety/perception/single_camera_observability.dart',
    'test/single_camera_observability_test.dart',
    'test/single_camera_observability_experiment_test.dart',
    'tool/model_benchmark/single_camera_observability.py',
]
INPUTS = [
    'scratch/camera-view-coverage-2026-10-09/optical/manifest.json',
    'scratch/camera-view-coverage-2026-10-09/optical/neural.json',
    'scratch/camera-view-coverage-2026-10-09/comparison.json',
    'scratch/closed-volume-control-2026-10-11/replay.json',
    'scratch/volume-holdout-2026-10-10/replay.json',
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def freeze():
    previous = read(ROOT / 'scratch/closed-volume-control-2026-10-11/preregistration.json')
    frozen = {**previous['frozenSourceSha256'], **previous['generatorSourceSha256']}
    for path, expected in frozen.items():
        assert sha(ROOT / path) == expected, path
    paths = [*frozen, *NEW, *INPUTS]
    receipt = {'scope': 'known scenes; analytic frustum gate and partial measurement comparison',
               'promotionAllowed': False, 'sources': {p: sha(ROOT / p) for p in sorted(set(paths))}}
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / 'preregistration.json').open('x', encoding='utf-8') as file:
        file.write(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'frozenFiles': len(receipt['sources']), 'promotionAllowed': False}))


def projected_inside(packet, lateral, forward, height):
    points = np.array([[x, d, h] for x in lateral for d in forward for h in height])
    camera = (points - np.array(packet['cameraOriginM'])) @ np.array(packet['cameraToWalkingRotation']).reshape(3, 3)
    z = camera[:, 2]
    if np.any(z <= .01):
        return False
    u = packet['fx'] * camera[:, 0] / z + packet['cx']
    v = packet['fy'] * camera[:, 1] / z + packet['cy']
    return bool(np.all((u >= 0) & (u < packet['width']) & (v >= 0) & (v < packet['height'])))


def verify():
    frozen = read(OUT / 'preregistration.json')
    for path, expected in frozen['sources'].items():
        assert sha(ROOT / path) == expected, path
    result = read(OUT / 'experiment.json')
    manifest = read(VIEWS / 'optical/manifest.json')
    old = read(VIEWS / 'comparison.json')
    assert result['sourceManifestSha256'] == sha(VIEWS / 'optical/manifest.json')
    assert result['priorReportSha256'] == sha(VIEWS / 'comparison.json')
    assert result['maximumAgeUs'] == 100000 and result['fixedReplayAgeUs'] == 2000
    assert all(result[k] is False for k in ('promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished', 'latencyMeasured'))
    assert len(result['rows']) == len(manifest['packets']) == 35
    checks = 0
    seen = set()
    for row in result['rows']:
        identity = row['caseId'], row['viewId']
        assert identity not in seen
        seen.add(identity)
        packet = next(p for p in manifest['packets'] if (p['caseId'], p['viewId']) == identity)
        previous = next(p for p in old['frames'] if (p['caseId'], p['viewId']) == identity)
        assert row['full'] == previous['sourcePassage']
        assert row['priorRuntimeAction'] == previous['runtime']['action'] == 'stopNow'
        assert row['physicalHazard'] == previous['physicalHazard']
        g = row['geometry']
        assert g['inputsAdmitted'] and not g['canAuthorizeMovement'] and not g['canCertifyFreeSpace']
        start, end = g['visibleStartM'], g['visibleEndM']
        if start is not None:
            assert .2 <= start < end <= 3.5
            assert g['entireRequestInView'] == (start == .2 and end == 3.5)
            for distance in (start + min(.001, (end-start)/2), (start+end)/2, end-min(.001, (end-start)/2)):
                assert projected_inside(packet, [-.45, .45], [distance], [0, .05, 1.9]), identity
                checks += 1
            if start > .2001:
                assert not projected_inside(packet, [-.45, .45], [start-.0001], [0, .05, 1.9]), identity
                checks += 1
            if end < 3.4999:
                assert not projected_inside(packet, [-.45, .45], [end+.0001], [0, .05, 1.9]), identity
                checks += 1
        else:
            assert not g['entireRequestInView']
            for distance in np.linspace(.2, 3.5, 67):
                assert not projected_inside(packet, [-.45, .45], [distance], [0, .05, 1.9]), identity
                checks += 1
        coverage = previous['coverage']
        nx, ny, nz = (coverage[k] for k in ('nx', 'ny', 'nz'))
        # Independent corner projection against the previously frozen maps,
        # not a count of sampled rays used as proof of free space.
        for ix, iy, iz, status in coverage['bodyCells']:
            if status in ('blocked', 'conflicting'):
                continue
            contained = projected_inside(packet,
                [-.45 + .9*ix/nx, -.45 + .9*(ix+1)/nx],
                [.2 + 3.3*iy/ny, .2 + 3.3*(iy+1)/ny],
                [.05 + 1.85*iz/nz, .05 + 1.85*(iz+1)/nz])
            assert contained == (status != 'outsideFrustum'), (identity, ix, iy, iz, status)
            checks += 1
        for ix, iy, status in coverage['floorCells']:
            if status in ('blocked', 'conflicting'):
                continue
            contained = projected_inside(packet,
                [-.45 + .9*ix/nx, -.45 + .9*(ix+1)/nx],
                [.2 + 3.3*iy/ny, .2 + 3.3*(iy+1)/ny], [0])
            assert contained == (status != 'outsideFrustum'), (identity, ix, iy, status)
            checks += 1
        if row['partial']:
            partial = row['partial']
            assert partial['startM'] > .2 and partial['endM'] < 3.5
            assert partial['coversCameraRecoveryVolume'] is False and partial['appliesToFullRequest'] is False
            assert projected_inside(packet, [-.45, .45], [partial['startM'], partial['endM']], [0, .05, 1.9])
            checks += 1
    views = []
    for view in ('original', 'chest-level', 'waist-level', 'waist-down', 'ideal-wide-control'):
        rows = [r for r in result['rows'] if r['viewId'] == view]
        anchor = next(r for r in rows if r['caseId'] == 'clear-final')
        views.append({'viewId': view, **anchor['geometry'],
                      'fullMeasurementStatuses': {k: sum(r['full']['status'] == k for r in rows) for k in ('measuredClear', 'blocked', 'unavailable')},
                      'partialMeasurementStatuses': {k: sum(r['partial'] is not None and r['partial']['status'] == k for r in rows) for k in ('measuredClear', 'blocked', 'unavailable')},
                      'partialUnavailableReasons': sorted({reason for r in rows if r['partial'] for reason in r['partial']['reasons']})})
    receipt = {'integrityPassed': True, 'independentProjectionChecks': checks, 'packets': len(seen),
               'scope': result['scope'], 'views': views,
               'originalMeasurementOutcomesPreserved': True, 'falseStopReductionEstablished': False,
               'promotionAllowed': False, 'ordinaryCameraWired': False,
               'experimentSha256': sha(OUT / 'experiment.json'), 'preregistrationSha256': sha(OUT / 'preregistration.json')}
    with (OUT / 'validation.json').open('w', encoding='utf-8') as file:
        file.write(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt, indent=2))


def render():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    report = read(OUT / 'validation.json')
    fig, ax = plt.subplots(figsize=(10.5, 4.7), layout='constrained')
    for index, view in enumerate(report['views']):
        ax.broken_barh([(.2, 3.3)], (index-.3, .6), facecolors='#bbc5d7')
        if view['visibleStartM'] is not None:
            ax.broken_barh([(view['visibleStartM'], view['visibleEndM']-view['visibleStartM'])],
                           (index-.3, .6), facecolors='#268478')
            ax.text(view['visibleStartM']+.02, index, f"{view['visibleStartM']:.2f} m", va='center', color='white')
    ax.set_yticks(range(5), ['Original: 1.42 m / 12 deg down', 'Chest: 1.42 m / level',
                          'Waist: 0.975 m / level', 'Waist: 0.975 m / 25 deg down', 'Ideal wide control (not phone optics)'])
    ax.set_xlim(.2, 3.5)
    ax.invert_yaxis()
    ax.set_xlabel('Distance ahead (m)')
    ax.set_title('Single-view frustum containment of full body width, height and floor')
    fig.text(.02, -.04, 'Green: fits inside frustum, measurements still required. Grey: no complete cross-section.\n'
             'Known synthetic camera configurations. No motion permission, depth interpolation or phone accuracy claim.', fontsize=9)
    for extension in ('png', 'svg'):
        fig.savefig(OUT / f'observable-intervals.{extension}', dpi=170, bbox_inches='tight')
    plt.close(fig)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify', 'render'])
    args = parser.parse_args()
    {'freeze': freeze, 'verify': verify, 'render': render}[args.action]()

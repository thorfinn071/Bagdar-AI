"""Check synthetic viewpoint evidence and preserve every preceding receipt."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SOURCES = [
    'docs/camera-view-coverage-protocol-2026-10-09.md',
    'tool/blender/export_camera_view_coverage.py',
    'tool/model_benchmark/infer_camera_view_coverage.py',
    'tool/model_benchmark/render_camera_view_coverage.py',
    'tool/model_benchmark/verify_camera_view_coverage.py',
    'tool/model_benchmark/check_camera_view_coverage.ps1',
    'test/harness/camera_view_coverage_diagnostics.dart',
    'test/camera_view_coverage_experiment_test.dart',
    'lib/safety/perception/camera_passage_clearance_source.dart',
    'lib/safety/perception/passage_clearance.dart',
    'lib/safety/perception/camera_track_association.dart',
    'lib/safety/runtime/confidence_authority_spatial_runtime.dart',
    'lib/safety/runtime/spatial_safety_runtime.dart',
    'lib/safety/planning/coverage_aware_stop_guidance.dart',
    'lib/services/generic_obstacle_detector.dart',
    'lib/tracker/generic_obstacle_tracker.dart',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def asset(directory, value, dtype, count):
    relative = value['path']
    path = (directory / relative).resolve()
    if '\\' in relative or ':' in relative or '..' in Path(relative).parts or not path.is_relative_to(directory.resolve()):
        raise ValueError('Escaped asset')
    if sha(path) != value['sha256']:
        raise ValueError('Asset hash drift: ' + relative)
    values = np.frombuffer(gzip.decompress(path.read_bytes()), dtype=dtype)
    if values.size != count:
        raise ValueError('Asset dimension drift: ' + relative)
    return values


def build(directory):
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_path_clear_stop_diagnosis.py'],
                   cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    optics = directory / 'optical'
    manifest, neural = read(optics / 'manifest.json'), read(optics / 'neural.json')
    report, baseline = read(directory / 'comparison.json'), read(directory / 'baseline-maps.json')
    for receipt in (manifest, neural):
        assert receipt['promotionAllowed'] is False
        for path, expected in receipt['sources'].items():
            assert sha(ROOT / path) == expected, path
    assert neural['manifestSha256'] == sha(optics / 'manifest.json')
    assert neural['semantics'] == 'relative inverse depth; never metres'
    assert len(manifest['packets']) == len(neural['frames']) == 35
    cases = {'clear-first', 'clear-final', 'box', 'low-headroom', 'drop', 'thin-pole', 'hidden-pole'}
    views = {'original', 'chest-level', 'waist-level', 'waist-down', 'ideal-wide-control'}
    pairs = {(p['caseId'], p['viewId']) for p in manifest['packets']}
    assert pairs == {(c, v) for c in cases for v in views}
    for packet in manifest['packets']:
        w, h = packet['width'], packet['height']
        r = np.array(packet['cameraToWalkingRotation']).reshape(3, 3)
        assert np.allclose(r.T @ r, np.eye(3), atol=1e-5) and abs(np.linalg.det(r) - 1) < 1e-5
        depth = asset(optics, packet['depth'], '<f4', w*h)
        lower = asset(optics, packet['freeZLower'], '<f4', w*h)
        upper = asset(optics, packet['surfaceZUpper'], '<f4', w*h)
        validity = asset(optics, packet['validity'], 'u1', w*h)
        assert np.isin(validity, [0, 1]).all()
        valid = validity == 1
        assert (np.isfinite(depth[valid]) & (depth[valid] > 0)).all()
        assert (np.isfinite(lower[valid]) & (lower[valid] >= 0)).all()
        yy, xx = np.mgrid[:h, :w]
        axis = depth / np.sqrt(1 + ((xx.ravel()+.5-packet['cx'])/packet['fx'])**2 +
                                   ((yy.ravel()+.5-packet['cy'])/packet['fy'])**2)
        assert (lower[valid] <= axis[valid] + 2e-5).all()
        bounded = valid & np.isfinite(upper)
        assert (upper[bounded] >= axis[bounded] - 2e-5).all()
        rgb = (optics / packet['rgb']['path']).resolve()
        assert rgb.is_relative_to(optics.resolve()) and sha(rgb) == packet['rgb']['sha256']
        record = next(n for n in neural['frames'] if (n['caseId'], n['viewId']) == (packet['caseId'], packet['viewId']))
        assert record['rgbSha256'] == packet['rgb']['sha256']
        raw = asset(optics, record['asset'], '<f4', 65536)
        assert np.isfinite(raw).all() and np.ptp(raw) > 1e-3
    assert report['manifestSha256'] == sha(optics / 'manifest.json')
    assert report['neuralReceiptSha256'] == sha(optics / 'neural.json')
    assert report['maximumAgeUs'] == 100000 and report['maximumFixedAgeUs'] == 2000
    for key in ('promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished', 'captureToCommandMeasured'):
        assert report[key] is False
    assert len(report['frames']) == 35 and len(report['faultControls']) == 30
    assert len(report['originalOpticalParity']) == 5
    assert all(p['boxAndSectionParity'] and p['maxRangeDeltaM'] == 0 for p in report['originalOpticalParity'])
    for row in report['frames']:
        runtime, coverage = row['runtime'], row['coverage']
        assert runtime['delivery'] == 'shadow' and coverage['replicaMatchesSource']
        assert not any(s.startswith('incompatible_identity') for s in runtime['associationReasons'])
        assert len(coverage['bodyCells']) == coverage['nx']*coverage['ny']*coverage['nz'] == 1716
        assert len(coverage['floorCells']) == coverage['nx']*coverage['ny'] == 132
        if row['physicalHazard']:
            assert runtime['action'] == 'stopNow' and runtime['passageApplied'] is False
            assert row['sourcePassage']['status'] != 'measuredClear'
    for fault in report['faultControls']:
        assert fault['action'] == 'stopNow' and fault['passageApplied'] is False
        assert fault['passage']['status'] == 'unavailable'
    assert len(baseline['frames']) == 11
    assert all(f['replicaMatchesSource'] and f['unknownBodyCauses']['outsideFrustum'] == 460 for f in baseline['frames'])
    assert all(s['passableStops'] == 2 and s['passableMeasuredClear'] == 0 and
               s['hazardStops'] == 5 and s['hazardUnsafeContinues'] == 0 for s in report['summary'])
    artifacts = ['comparison.json', 'baseline-maps.json', 'optical/manifest.json', 'optical/neural.json',
                 'coverage-map.png', 'coverage-map.svg', 'coverage-comparison.png', 'coverage-comparison.svg']
    return {
        'schemaVersion': 1, 'passed': True, 'promotionAllowed': False,
        'sources': {p: sha(ROOT / p) for p in SOURCES},
        'artifacts': {p: sha(directory / p) for p in artifacts},
        'priorDiagnosisContractSha256': sha(ROOT / 'docs/_baseline_logs/path_clear_stop_diagnosis_contract_v1.json'),
        'summary': {'baselineFrames': 11, 'viewSnapshots': 35, 'newNeuralInferences': 35,
                    'hazardStops': 25, 'hazardUnsafeContinues': 0, 'faultControlsStopped': 30,
                    'passableSnapshots': 10, 'passableStops': 10, 'passableMeasuredClear': 0,
                    'falseStopReductionEstablished': False},
        'evidenceClasses': {'syntheticViewExperiment': 'pass', 'falseStopReduction': 'not_established',
                           'fullCoreRc': 'not_run', 'androidBuild': 'not_run', 'namedDeviceRuntime': 'not_run',
                           'captureToCommandMeasured': False, 'controlledWalking': 'not_run'},
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', default='scratch/camera-view-coverage-2026-10-09')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    directory = (ROOT / args.directory).resolve()
    if not directory.is_relative_to(ROOT / 'scratch'):
        raise ValueError('Receipt must remain in scratch')
    value = build(directory)
    rendered = json.dumps(value, indent=2) + '\n'
    target = directory / 'validation.json'
    if args.write:
        if target.exists():
            raise ValueError('Never overwrite the first validation receipt')
        target.write_text(rendered, encoding='utf-8')
    elif target.read_text(encoding='utf-8') != rendered:
        raise ValueError('Viewpoint source/output receipt drift')
    print('View experiment: 11 baseline maps, 35 new neural/optical snapshots; 25 hazard and 30 fault stops; reduction not established')

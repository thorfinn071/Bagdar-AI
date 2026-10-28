"""Verify versioned processing evidence and all previous source freezes.

Checks measured receipts; timing numbers are observations, not deterministic
performance assertions. Functional geometry/age tests run separately in Core.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LOGS = ROOT / 'docs/_baseline_logs'
RECEIPT = LOGS / 'blender_scan_processing_contract_v1.json'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def check_sources(sources):
    for name, expected in sources.items():
        path = (ROOT / name).resolve()
        assert path.is_relative_to(ROOT), name
        assert sha(path) == expected, name


def stats(values):
    values = sorted(values)
    def percentile(p):
        index = (len(values) - 1) * p
        lo, hi = math.floor(index), math.ceil(index)
        return (values[lo] + (values[hi] - values[lo]) * (index - lo)) / 1000
    return {'samples': len(values), 'p50Ms': percentile(.5),
            'p95Ms': percentile(.95), 'maximumMs': values[-1] / 1000}


def verify_profile(path, mode):
    report = read(path)
    assert report['schemaVersion'] == 1 and report['passed'] is True
    assert report['mode'] == mode and report['rounds'] == 3
    assert report['runtimeWired'] is False and report['promotionAllowed'] is False
    assert report['captureToCommandMeasured'] is False
    assert report['deviceRuntime'] == report['controlledWalking'] == 'not_run'
    assert report['currentAgeLimitUs'] == 100000
    assert report['baselineCoreSha256'] == sha(LOGS / 'blender_scan_complete_core_rc_v1.json')
    assert report['manifestSha256'] == sha(ROOT / 'test/fixtures/spatial_safety/blender-scan-exact-height-v1/manifest.json')
    check_sources(report['sources'])
    geometry = report['geometryParity']
    assert len(geometry) == 12 and len({g['sceneId'] for g in geometry}) == 12
    reference = read(LOGS / 'blender_scan_complete_replay_v1.json')['scans']
    for g in geometry:
        frozen = next(s for s in reference if s['sceneId'] == g['sceneId'])
        assert g['physicalHazard'] == frozen['physicalHazard']
        assert g['geometryStatus'] == frozen['diagnosticStatus']
        assert g['identicalObservation'] is True and g['captureSpanUs'] == 2200000
        assert g['currentWindowViews'] == 1
        if not g['physicalHazard']:
            assert g['currentWindowGeometryStatus'] == 'unavailable'
    rows = report['samples']
    assert len(rows) == 72
    keys = set()
    for row in rows:
        key = row['round'], row['sceneId'], row['implementation']
        assert key not in keys
        keys.add(key)
        assert row['round'] in range(3) and row['implementation'] in ('frozen', 'indexed')
        g = next(g for g in geometry if g['sceneId'] == row['sceneId'])
        assert row['physicalHazard'] == g['physicalHazard']
        assert row['pipelineUs'] == sum(row[k] for k in ('sourceBuildUs', 'observationUs', 'evaluationUs', 'dispatchGuardUs'))
        assert all(isinstance(row[k], int) and row[k] >= 0 for k in ('pipelineUs', 'sourceBuildUs', 'observationUs', 'evaluationUs', 'dispatchGuardUs'))
        assert row['oldestAgeAtStartUs'] >= 2202000
        assert row['oldestAgeAtDispatchUs'] == row['oldestAgeAtStartUs'] + row['pipelineUs']
        assert row['oldestAgeAtDispatchUs'] - row['latestAgeAtDispatchUs'] == 2200000
        assert row['strictStatus'] == 'unavailable' and 'staleObservation' in row['strictReasons']
        assert row['releaseStatus'] == 'expiredBeforeCompute'
        assert row['shadowDecision'] == 'stopUnavailable' and row['unsafeContinue'] is False
    for implementation in ('frozen', 'indexed'):
        subset = [r for r in rows if r['implementation'] == implementation]
        summary = report['summaries'][implementation]
        for label, field in (('pipeline', 'pipelineUs'), ('sourceBuild', 'sourceBuildUs'),
                             ('oldestAgeAtDispatch', 'oldestAgeAtDispatchUs'), ('latestAgeAtDispatch', 'latestAgeAtDispatchUs')):
            computed = stats([r[field] for r in subset])
            for name, value in computed.items():
                assert math.isclose(summary[label][name], value, rel_tol=1e-12, abs_tol=1e-9)
        assert summary['strictStaleRejected'] == 36
        assert summary['hazardDecisions'] == summary['missedTimelyGeometricHazardDecisions'] == summary['fallbackStopsOnHazards'] == 18
        assert summary['falseStopsOnPassable'] == 18 and summary['unsafeContinue'] == 0
        assert summary['captureGateReached'] is False
        assert summary['computeWithin100ms'] == sum(r['pipelineUs'] <= 100000 for r in subset)
    # Check the actual order alternates within each snapshot pair.
    for round_id in range(3):
        order = ['frozen', 'indexed'] if round_id % 2 == 0 else ['indexed', 'frozen']
        selected = [r for r in rows if r['round'] == round_id]
        for i in range(0, len(selected), 2):
            assert [r['implementation'] for r in selected[i:i + 2]] == order
            assert selected[i]['sceneId'] == selected[i + 1]['sceneId']
    neural = report['neuralLoad']
    if mode == 'elapsed':
        assert neural is None
    else:
        ready, result = neural['ready'], neural['result']
        assert ready['ready'] is True and ready['geometryInput'] is False and ready['numThreads'] == 1
        assert ready['warmupInferences'] == 10
        corpus_root = ROOT / 'test/fixtures/spatial_safety/camera-scale-motion-v1'
        assert ready['corpusSha256'] == sha(corpus_root / 'manifest.json')
        assert ready['pinnedSha256'] == sha(corpus_root / 'ncnn/manifest.json')
        for kind, filename in (('Param', 'midas_small.ncnn.param'), ('Bin', 'midas_small.ncnn.bin')):
            assert ready[f'model{kind}Sha256'] == sha(ROOT / 'assets' / filename)
        expected_rgb = [f['rgb'] for f in read(corpus_root / 'manifest.json')['layouts'][0]['frames'][:3]]
        assert ready['rgbFrames'] == expected_rgb
        assert result['stopped'] is True and result['allOutputsMatchPinned'] is True
        assert result['inferences'] == len(result['rows']) and result['inferences'] > 0
        end = -1
        for r in result['rows']:
            assert r['startUs'] >= end and r['finishUs'] >= r['startUs']
            assert r['preprocessingUs'] >= 0 and r['inferenceUs'] > 0
            assert r['finishUs'] - r['startUs'] >= r['preprocessingUs'] + r['inferenceUs']
            end = r['finishUs']
    return {'sha256': sha(path), 'samplesPerImplementation': 36,
            'strictStaleRejectedPerImplementation': 36, 'unsafeContinue': 0}


def build():
    previous = read(LOGS / 'blender_scan_complete_contract_v1.json')
    assert previous['passed'] is True
    check_sources(previous['sources'])
    profiles = {}
    for mode in ('elapsed', 'elapsed-nn'):
        name = f'blender_scan_processing_{mode}_v1.json'
        profiles[name] = verify_profile(LOGS / name, mode)
    names = [
        'lib/safety/perception/camera_indexed_height_envelope_passage_source.dart',
        'lib/safety/runtime/camera_scan_age_gate.dart',
        'tool/model_benchmark/scan_processing_support.dart',
        'tool/model_benchmark/profile_scan_processing.dart',
        'tool/model_benchmark/scan_processing_ncnn_load.py',
        'tool/model_benchmark/verify_scan_processing.py',
        'test/camera_indexed_scan_replay_test.dart', 'test/camera_scan_age_gate_test.dart',
        'docs/blender-scan-processing-protocol-2026-10-04.md',
    ]
    return {'schemaVersion': 1, 'passed': True,
            'runtimeWired': False, 'promotionAllowed': False,
            'scope': 'known desktop static geometry and elapsed CPU competition; capture gate remains unmet',
            'priorContractSha256': sha(LOGS / 'blender_scan_complete_contract_v1.json'),
            'priorCoreSha256': sha(LOGS / 'blender_scan_complete_core_rc_v1.json'),
            'previousFrozenSources': len(previous['sources']),
            'profiles': profiles, 'sources': {name: sha(ROOT / name) for name in names}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    value = build()
    if args.write:
        with RECEIPT.open('x', encoding='utf-8', newline='\n') as f:
            f.write(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    else:
        assert read(RECEIPT) == value, 'Processing contract drift'
    print(json.dumps({'passed': True, 'previousFrozenSources': value['previousFrozenSources'],
                      'profiles': 2, 'unsafeContinue': 0, 'captureGateReached': False}))

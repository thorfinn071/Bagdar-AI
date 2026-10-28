"""Seal and independently audit scalar producer parity and elapsed clocks."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/scalar-scan-processing-2026-10-11'
PRIOR = ROOT / 'scratch/single-camera-minimal-scan-2026-10-11'
NEW = ['lib/safety/perception/camera_scalar_height_envelope_passage_source.dart',
       'test/camera_scalar_scan_replay_test.dart',
       'tool/model_benchmark/profile_scalar_scan.dart',
       'tool/model_benchmark/scalar_scan_processing.py',
       'docs/scalar-scan-processing-protocol-2026-10-11.md']


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8'))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def integrity():
    frozen = read(OUT / 'preregistration.json')
    for name, digest in frozen['sources'].items():
        assert sha(ROOT / name) == digest, name
    return frozen


def freeze():
    prior = read(PRIOR / 'preregistration.json')
    paths = set(prior['sources'])
    for name, digest in prior['sources'].items():
        assert sha(ROOT / name) == digest, name
    paths.update(NEW)
    paths.update((PRIOR / p).relative_to(ROOT).as_posix() for p in
                 ['preregistration.json', 'experiment.json', 'validation.json',
                  'elapsed.json', 'elapsed-validation.json', 'verification-summary.json'])
    OUT.mkdir(parents=True, exist_ok=True)
    result = {'scope': 'scalar optimization of existing synthetic-only source',
        'promotionAllowed': False, 'sources': {p: sha(ROOT / p) for p in sorted(paths)}}
    with (OUT / 'preregistration.json').open('x', encoding='utf-8') as f:
        f.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'frozenFiles': len(paths)}))


def verify_parity():
    frozen = integrity()
    data = read(OUT / 'parity.json')
    for key in ['promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished']:
        assert data[key] is False
    old = read(PRIOR / 'experiment.json')['rows']
    labels = {r['sceneId']: r['physicalHazard'] for r in old}
    # Full/minimal observation sections are independently compared to the
    # preceding frozen experiment; frame timing/identity remain original here.
    full = {r['sceneId']: r for r in old if r['selection'] == 'full' and r['scheduleId'] == '120fps'}
    minimal = {r['sceneId']: r for r in old if r['selection'] == 'minimal' and r['scheduleId'] == '120fps'}
    seen = set()
    for r in data['rows']:
        key = r['sceneId'], r['selection']
        assert key not in seen
        seen.add(key)
        assert r['identicalObservation'] is True
        assert r['physicalHazard'] == labels[r['sceneId']]
        if r['selection'] in ['full', 'minimal']:
            control = (full if r['selection'] == 'full' else minimal)[r['sceneId']]
            assert r['observation']['sections'] == control['observation']['sections']
            assert r['geometry']['status'] == control['preCompletionMeasurement']['status']
        elif r['physicalHazard']:
            assert r['geometry']['status'] != 'measuredClear'
    assert seen == {(scene, selection) for scene in labels
                    for selection in ['full', 'minimal', 'single', 'suffix6']}
    result = {'parityAuditPassed': True, 'frozenFiles': len(frozen['sources']),
        'corpusPairs': len(seen), 'paritySha256': sha(OUT / 'parity.json'),
        'promotionAllowed': False, 'falseStopReductionEstablished': False}
    (OUT / 'parity-validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


def verify_elapsed():
    integrity()
    data = read(OUT / 'elapsed.json')
    for key in ['neuralLoad', 'captureMeasured', 'sceneMotionValidated',
                'phoneValidated', 'promotionAllowed', 'canAuthorizeMovement']:
        assert data[key] is False
    assert data['counterfactualWarmupParityPairs'] == 24
    labels = {r['sceneId']: r['physicalHazard'] for r in read(PRIOR / 'experiment.json')['rows']}
    seen = set()
    for r in data['rows']:
        key = r['sceneId'], r['selection'], r['implementation'], r['round']
        assert key not in seen
        seen.add(key)
        elapsed = r['elapsedPipelineUs']
        assert elapsed > 0
        assert r['oldestAgeAtCompletionUs'] - r['oldestAgeAtStartUs'] == elapsed
        count = 12 if r['selection'] == 'full' else 10
        assert r['oldestAgeAtStartUs'] >= ((count - 1) * 1000000 + 60) // 120 + 2000
        if r['ageStatus'] == 'admitted':
            assert r['oldestAgeAtCompletionUs'] <= 100000
            assert r['releasedStatus'] in ['blocked', 'measuredClear']
            assert r['releasedObservationPresent']
            if r['releasedStatus'] == 'measuredClear':
                assert not labels[r['sceneId']]
        else:
            assert r['releasedStatus'] is None and not r['releasedObservationPresent']
        if r['ageStatus'] == 'expiredAfterCompute':
            assert r['oldestAgeAtCompletionUs'] > 100000
        if r['sourceStagesUs'] is not None:
            assert sum(r['sourceStagesUs'].values()) <= elapsed
    assert seen == {(scene, selection, implementation, round_) for scene in labels
                    for selection in ['full', 'minimal']
                    for implementation in ['indexed', 'scalar'] for round_ in range(3)}
    groups = {}
    for key, s in data['summaries'].items():
        selection, implementation = key.split('/')
        rows = [r for r in data['rows'] if (r['selection'], r['implementation']) == (selection, implementation)]
        values = [r['elapsedPipelineUs'] / 1000 for r in rows]
        assert s['samples'] == len(values) == 36
        assert math.isclose(s['p50Ms'], np.percentile(values, 50))
        assert math.isclose(s['p95Ms'], np.percentile(values, 95))
        assert s['maximumMs'] == max(values)
        groups[key] = {**s, 'ageStatuses': dict(Counter(r['ageStatus'] for r in rows))}
    result = {'elapsedAuditPassed': True, 'samples': len(seen), 'summaries': groups,
        'elapsedSha256': sha(OUT / 'elapsed.json'), 'promotionAllowed': False,
        'falseStopReductionEstablished': False}
    (OUT / 'elapsed-validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['freeze', 'verify-parity', 'verify-elapsed'])
    args = parser.parse_args()
    {'freeze': freeze, 'verify-parity': verify_parity, 'verify-elapsed': verify_elapsed}[args.action]()

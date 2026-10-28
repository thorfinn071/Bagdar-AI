"""Seal/audit typed publication parity and publication-inclusive elapsed clocks."""
import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/typed-scan-transport-2026-10-11'
PRIOR = ROOT / 'scratch/scalar-scan-processing-2026-10-11'
NEW = ['lib/safety/perception/camera_typed_height_envelope_frame.dart',
       'test/camera_typed_height_envelope_frame_test.dart',
       'test/camera_typed_scan_replay_test.dart',
       'tool/model_benchmark/profile_typed_scan.dart',
       'tool/model_benchmark/typed_scan_transport.py',
       'docs/typed-scan-transport-protocol-2026-10-11.md']


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
                 ['preregistration.json', 'parity.json', 'parity-validation.json',
                  'elapsed.json', 'elapsed-validation.json', 'verification-summary.json'])
    OUT.mkdir(parents=True, exist_ok=True)
    result = {'scope': 'typed publication of unchanged synthetic optical packets',
        'promotionAllowed': False, 'sources': {p: sha(ROOT / p) for p in sorted(paths)}}
    with (OUT / 'preregistration.json').open('x', encoding='utf-8') as f:
        f.write(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'frozenFiles': len(paths)}))


def verify_parity():
    frozen = integrity()
    data = read(OUT / 'parity.json')
    for key in ['promotionAllowed', 'ordinaryCameraWired', 'falseStopReductionEstablished']:
        assert data[key] is False
    old = read(PRIOR / 'parity.json')['rows']
    labels = {r['sceneId']: r['physicalHazard'] for r in old}
    controls = {(r['sceneId'], r['selection']): r for r in old}
    seen = set()
    for r in data['rows']:
        key = r['sceneId'], r['selection']
        assert key not in seen
        seen.add(key)
        assert r['identicalObservation'] is True
        assert r['physicalHazard'] == labels[r['sceneId']]
        assert r['observation'] == controls[key]['observation']
        assert r['geometry'] == controls[key]['geometry']
        if r['physicalHazard']:
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
    assert data['warmupParityPairs'] == 24 and data['publicationIncluded'] is True
    assert data['isolateDispatchMeasured'] is False
    labels = {r['sceneId']: r['physicalHazard'] for r in read(PRIOR / 'parity.json')['rows']}
    seen = set()
    for r in data['rows']:
        key = r['sceneId'], r['mode'], r['round']
        assert key not in seen
        seen.add(key)
        elapsed = r['elapsedPipelineUs']
        assert elapsed > 0
        assert r['oldestAgeAtCompletionUs'] - r['oldestAgeAtStartUs'] == elapsed
        assert r['oldestAgeAtStartUs'] >= 77000
        assert r['ageStatus'] in ['admitted', 'expiredBeforeCompute',
                                  'expiredAfterCompute', 'expiredBeforeDispatch']
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
            assert r['publicationUs'] >= 0
            assert r['publicationUs'] + sum(r['sourceStagesUs'].values()) <= elapsed
        else:
            assert r['ageStatus'] == 'expiredBeforeCompute'
            assert r['publicationUs'] is None
    assert seen == {(scene, mode, round_) for scene in labels
                    for mode in ['generic', 'typedCopy', 'typedTransfer'] for round_ in range(3)}
    groups = {}
    for key, s in data['summaries'].items():
        rows = [r for r in data['rows'] if r['mode'] == key]
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

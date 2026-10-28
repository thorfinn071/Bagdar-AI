"""Integrity and measured arithmetic; no deterministic latency pass claim."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path

from verify_scan_processing import check_sources, read, sha, stats

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'test/fixtures/spatial_safety/blender-synchronized-rig-v2'
LOGS = ROOT / 'docs/_baseline_logs'
CONTRACT = LOGS / 'blender_synchronized_rig_contract_v3.json'


def asset(descriptor):
    path = (CORPUS / descriptor['path']).resolve()
    assert path.is_relative_to(CORPUS)
    assert sha(path) == descriptor['sha256'], path
    return path


def corpus_check():
    manifest = read(CORPUS / 'manifest.json')
    prior_manifest = ROOT / 'test/fixtures/spatial_safety/blender-synchronized-rig-v1/manifest.json'
    assert manifest['priorManifestSha256'] == sha(prior_manifest)
    prior = read(prior_manifest)
    check_sources(prior['sources'])
    assert manifest['promotionAllowed'] is False and manifest['runtimeWired'] is False
    assert manifest['rigPhysicalRealization'] == 'not_established'
    check_sources(manifest['sources'])
    labels = read(asset(manifest['labels']))['labels']
    assert len(labels) == 8 and len({l['id'] for l in labels}) == 8
    assert sum(not l['dynamic'] and l['physicalHazardAtCapture'] for l in labels) == 3
    assert sum(not l['dynamic'] and not l['physicalHazardAtCapture'] for l in labels) == 3
    assert len(manifest['batches']) == 8 and len(manifest['grid']['poses']) == 12
    witnesses = 0
    for b in manifest['batches']:
        original = next(x for x in prior['batches'] if x['id'] == b['id'])
        for key in ('scene', 'sceneStateSha256', 'capturedAtUs', 'frameId', 'sessionGeneration', 'stationarySyntheticScene'):
            assert b[key] == original[key], key
        asset(b['scene'])
        label = next(l for l in labels if l['id'] == b['id'])
        assert b['stationarySyntheticScene'] == (not label['dynamic'])
        assert b['zeroSkewUs'] == 0 and len(b['channels']) == 12
        assert len({p['cameraId'] for p in b['channels']}) == 12
        for p in b['channels']:
            optical = next(x for x in original['channels'] if x['cameraId'] == p['cameraId'])
            for key in ('rgb', 'depth', 'freeZLower', 'validity', 'cameraToWalkingRotation', 'cameraOriginM', 'capturedAtUs', 'fx', 'fy', 'cx', 'cy'):
                assert p[key] == optical[key], key
            assert p['sceneStateSha256'] == b['sceneStateSha256']
            for key in ('frameId', 'capturedAtUs', 'sessionGeneration'):
                assert p[key] == b[key]
            assert p['width'] == 160 and p['height'] == 120
            for key in ('depth', 'freeZLower', 'surfaceZUpper', 'heightLower', 'heightUpper', 'firstZLower', 'validity'):
                raw = gzip.decompress(asset(p[key]).read_bytes())
                assert len(raw) == 160 * 120 * (1 if key == 'validity' else 4)
                if key == 'validity': assert set(raw).issubset({0, 1})
            asset(p['rgb'])
            assert p['rayWitnesses'] > 0
            witnesses += p['rayWitnesses']
    before, after = manifest['batches'][-2:]
    assert after['capturedAtUs'] - before['capturedAtUs'] == 40000
    assert before['sceneStateSha256'] != after['sceneStateSha256']
    # The synthetic admission change cannot change projection/index predicates.
    frozen = (ROOT / 'lib/safety/perception/camera_indexed_height_envelope_passage_source.dart').read_text()
    rig = (ROOT / 'lib/safety/perception/camera_synchronized_envelope_source.dart').read_text()
    marker = '  /// Pixel rectangle containing'
    assert frozen[frozen.index(marker):] == rig[rig.index(marker):], 'Coverage math drift'
    assert frozen[frozen.index('class _Box'):frozen.index('/// Opt-in synthetic-only')] == rig[rig.index('class _Box'):rig.index('/// Frozen indexed coverage')], 'Pixel index math drift'
    return manifest, labels, witnesses


def profile_check(path, mode, manifest, labels):
    report = read(path)
    check_sources(report['sources'])
    assert report['passed'] is True and report['mode'] == mode and report['rounds'] == 3
    assert report['manifestSha256'] == sha(CORPUS / 'manifest.json')
    assert report['promotionAllowed'] is False and report['runtimeWired'] is False
    assert report['captureToCommandMeasured'] is False and report['currentAgeLimitUs'] == 100000
    assert len(report['geometry']) == 16 and len(report['samples']) == 48
    for g in report['geometry']:
        label = next(l for l in labels if l['id'] == g['id'])
        assert g['dynamic'] == label['dynamic'] and g['physicalHazard'] == label['physicalHazardAtCapture']
        assert g['captureSpanUs'] == 0 and g['channels'] == (12 if g['mode'] == 'batch' else 1)
        if g['dynamic']:
            assert g['status'] == 'unavailable' and 'motion_bound_not_established' in g['diagnostics']
        elif g['physicalHazard']:
            assert g['status'] != 'measuredClear'
        elif g['mode'] == 'single':
            assert g['status'] == 'unavailable'
        else:
            assert g['status'] == 'measuredClear' and g['bodyObservedMinimum'] == g['floorObservedMinimum'] == 1
    keys = set()
    for r in report['samples']:
        key = r['round'], r['id'], r['mode']
        assert key not in keys
        keys.add(key)
        assert r['round'] in range(3) and r['mode'] in ('single', 'batch')
        g = next(g for g in report['geometry'] if g['id'] == r['id'] and g['mode'] == r['mode'])
        assert (r['dynamic'], r['physicalHazard']) == (g['dynamic'], g['physicalHazard'])
        timings = ('sourceBuildUs', 'observationUs', 'gateProcessRemainderUs', 'dispatchGuardUs')
        assert all(type(r[k]) is int and r[k] >= 0 for k in timings)
        assert r['pipelineUs'] == sum(r[k] for k in timings)
        assert r['ageAtStartUs'] >= 2000 and r['ageAtDispatchUs'] == r['ageAtStartUs'] + r['pipelineUs']
        assert r['captureSpanUs'] == 0 and r['unsafeContinue'] is False
        if r['strictStatus'] == 'measuredClear':
            assert not r['dynamic'] and not r['physicalHazard'] and r['ageAtDispatchUs'] <= 100000
            assert r['releaseStatus'] == 'admitted' and r['shadowDecision'] == 'continueForward'
        if r['ageAtDispatchUs'] > 100000:
            assert r['strictStatus'] == 'unavailable'
        if r['dynamic']: assert r['strictStatus'] == 'unavailable'
    for round_id in range(3):
        order = ['single', 'batch'] if round_id % 2 == 0 else ['batch', 'single']
        rows = [r for r in report['samples'] if r['round'] == round_id]
        for i in range(0, len(rows), 2):
            assert [r['mode'] for r in rows[i:i+2]] == order and rows[i]['id'] == rows[i+1]['id']
    for kind in ('single', 'batch'):
        rows = [r for r in report['samples'] if r['mode'] == kind and not r['dynamic']]
        hazards = [r for r in rows if r['physicalHazard']]
        summary = report['summaries'][kind]
        for name, field in (('pipeline', 'pipelineUs'), ('ageAtDispatch', 'ageAtDispatchUs')):
            for k, v in stats([r[field] for r in rows]).items():
                assert math.isclose(summary[name][k], v, rel_tol=1e-12, abs_tol=1e-9)
        expected = {
            'staticSamples': 18, 'computeWithin100ms': sum(r['pipelineUs'] <= 100000 for r in rows),
            'admittedClear': sum(r['strictStatus'] == 'measuredClear' for r in rows),
            'timelyGeometricHazardDecisions': sum(r['strictStatus'] == 'blocked' for r in hazards),
            'missedTimelyGeometricHazardDecisions': sum(r['strictStatus'] != 'blocked' for r in hazards),
            'fallbackStopsOnHazards': sum(r['strictStatus'] == 'unavailable' for r in hazards),
            'falseStopsOnPassable': sum(not r['physicalHazard'] and r['strictStatus'] != 'measuredClear' for r in rows),
            'unsafeContinue': 0, 'expired': sum(r['ageAtDispatchUs'] > 100000 for r in rows),
            'dynamicRejected': 6,
        }
        assert all(summary[k] == v for k, v in expected.items())
    neural = report['neuralLoad']
    if mode == 'elapsed': assert neural is None
    else:
        ready, result = neural['ready'], neural['result']
        assert ready['ready'] and ready['geometryInput'] is False and ready['numThreads'] == 1
        assert ready['warmupInferences'] == 10
        base = ROOT / 'test/fixtures/spatial_safety/camera-scale-motion-v1'
        assert ready['corpusSha256'] == sha(base / 'manifest.json')
        assert ready['pinnedSha256'] == sha(base / 'ncnn/manifest.json')
        assert ready['rgbFrames'] == [f['rgb'] for f in read(base / 'manifest.json')['layouts'][0]['frames'][:3]]
        for kind, name in [('Param', 'midas_small.ncnn.param'), ('Bin', 'midas_small.ncnn.bin')]:
            assert ready[f'model{kind}Sha256'] == sha(ROOT / 'assets' / name)
        assert result['stopped'] and result['allOutputsMatchPinned'] and result['inferences'] == len(result['rows']) > 0
        previous = 0
        for row in result['rows']:
            assert row['startUs'] >= previous and row['finishUs'] > row['startUs']
            assert row['preprocessingUs'] >= 0 and row['inferenceUs'] > 0
            previous = row['finishUs']
    return sha(path)


def build():
    manifest, labels, witnesses = corpus_check()
    prior = read(LOGS / 'blender_scan_processing_contract_v1.json')
    check_sources(prior['sources'])
    profiles = {}
    for mode in ('elapsed', 'elapsed-nn'):
        name = f'blender_synchronized_rig_{mode}_v3.json'
        profiles[name] = profile_check(LOGS / name, mode, manifest, labels)
    names = ['lib/safety/perception/camera_synchronized_envelope_source.dart',
             'test/harness/blender_synchronized_rig_fixture.dart', 'test/camera_synchronized_rig_test.dart',
             'tool/model_benchmark/profile_synchronized_rig.dart',
             'tool/model_benchmark/synchronized_rig_neural_load.dart', 'tool/model_benchmark/verify_synchronized_rig.py']
    rejected = {}
    for name, version in [('blender_synchronized_rig_elapsed_v1.json', 'v1'),
                          ('blender_synchronized_rig_elapsed-nn_v1.json', 'v1'),
                          ('blender_synchronized_rig_elapsed_v2.json', 'v2')]:
        report = read(LOGS / name)
        for source, digest in report['sources'].items():
            snapshot = ROOT / f'docs/_baseline_sources/blender_synchronized_rig_rejected_{version}' / f'{source}.snapshot'
            assert sha(snapshot) == digest, source
        rejected[name] = sha(LOGS / name)
    return {'schemaVersion': 1, 'passed': True, 'promotionAllowed': False, 'runtimeWired': False,
            'manifestSha256': sha(CORPUS / 'manifest.json'), 'profiles': profiles,
            'priorContractSha256': sha(LOGS / 'blender_scan_processing_contract_v1.json'),
            'priorCoreSha256': sha(LOGS / 'blender_scan_processing_core_rc_v1.json'),
            'rejectedProfiles': rejected,
            'opticalRayWitnesses': witnesses, 'staticScenes': 6, 'dynamicBatches': 2,
            'sources': {p: sha(ROOT / p) for p in names}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    result = build()
    if args.write:
        if CONTRACT.exists(): raise ValueError('Contract is write-once')
        CONTRACT.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    else:
        assert read(CONTRACT) == result, 'Rig contract drift'
    print(json.dumps(result), flush=True)

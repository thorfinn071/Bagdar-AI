"""Seal, infer and independently verify the closed-upper-volume control."""
import argparse
import ast
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'scratch/closed-volume-control-2026-10-11'
OLD = ROOT / 'scratch/volume-holdout-2026-10-10'
SPEC = ROOT / 'tool/blender/closed_volume_control_spec_v1.json'
NEW_SOURCES = [
    'docs/closed-volume-control-protocol-2026-10-11.md',
    'tool/blender/generate_closed_volume_control.py',
    'tool/blender/closed_volume_control_spec_v1.json',
    'tool/model_benchmark/closed_volume_control.py',
    'tool/model_benchmark/check_closed_volume_control.ps1',
    'test/harness/closed_volume_control_fixture.dart',
    'test/harness/closed_volume_control_replay.dart',
    'test/harness/closed_volume_control_faults.dart',
    'test/closed_volume_control_test.dart',
    'test/closed_volume_control_source_audit_test.dart',
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save_new(path, value):
    assert not path.exists(), f'Immutable receipt: {path}'
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def check_freeze():
    value = read(OUT / 'preregistration.json')
    for p, h in {**value['frozenSourceSha256'], **value['generatorSourceSha256']}.items():
        assert sha(ROOT / p) == h, f'Frozen source drift: {p}'
    for p, h in value['negativeControlSha256'].items():
        assert sha(OLD / p) == h, f'Original negative control drift: {p}'
    return value


def seal():
    assert not (OUT / 'corpus').exists(), 'Seal must precede export'
    prior = read(OLD / 'validation.json')
    assert prior['integrityChecksPassed'] and not prior['syntheticHoldoutGatePassed']
    frozen = dict(read(OLD / 'preregistration.json')['frozenSourceSha256'])
    frozen.update(prior['sourceSha256'])
    for p in NEW_SOURCES:
        frozen[p] = sha(ROOT / p)
    for p, h in frozen.items():
        assert sha(ROOT / p) == h, f'Prior source drift: {p}'
    tree = ast.parse((ROOT / 'tool/blender/generate_volume_holdout.py').read_text())
    sources = next(ast.literal_eval(n.value) for n in tree.body if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == 'SOURCES' for t in n.targets))
    sources += NEW_SOURCES[:3]
    spec = read(SPEC)
    OUT.mkdir(parents=True, exist_ok=True)
    save_new(OUT / 'preregistration.json', {
        'schemaVersion': 1, 'sealedAtUtc': datetime.now(timezone.utc).isoformat(),
        'scope': 'related diagnostic closed-room controls; not independent holdout',
        'frozenSourceSha256': frozen,
        'generatorSourceSha256': {p: sha(ROOT / p) for p in sources},
        'negativeControlSha256': {p: sha(OLD / p) for p in (
            'validation.json', 'preregistration.json', 'consumer-freeze.json',
            'corpus/manifest.json', 'corpus/annotations.json', 'optical/manifest.json',
            'replay.json', 'source-audit.json', 'visibility-audit.json')},
        'captureCount': len(spec['scenes']) * spec['framesPerLayout'],
        'noRuntimeTuningAfterSeal': True, 'promotionAllowed': False,
        'ordinaryCameraWired': False,
    })
    print('SEALED 21 diagnostic captures before export')


def infer(check):
    check_freeze()
    audit = read(OUT / 'source-audit.json')
    positive = [r for r in audit['rows'] if r['layoutId'].startswith('closed-clear-')]
    assert len(positive) == 14 and all(r['proofStatus'] == 'measuredClear' for r in positive), \
        'Producer precondition failed; no inference/runtime claim permitted'
    import infer_volume_holdout as base
    base.CORPUS = OUT / 'corpus'
    base.OUT = base.CORPUS / 'ncnn'
    base.main(check)


def probe(batch, label, optical_root):
    import numpy as np
    from audit_volume_holdout_visibility import ray_box
    from verify_volume_holdout import asset
    origin = np.array(batch['primaryOriginal']['cameraOriginM'])
    offset = np.array(label['walkingOriginWorldM'])
    point = np.array([-.375, .275, 1.685])
    direction = point - origin
    hits = [{'object': box['name'], 'rayParameter': t}
            for box in label['geometry']
            if (t := ray_box(origin + offset, direction, box['lowerM'], box['upperM'])) is not None]
    hits.sort(key=lambda v: v['rayParameter'])
    channels = []
    for p in batch['channels']:
        camera = np.array(p['cameraToWalkingRotation']).reshape(3, 3).T @ direction
        if camera[2] <= .01:
            continue
        u, v = p['fx'] * camera[0] / camera[2] + p['cx'], p['fy'] * camera[1] / camera[2] + p['cy']
        if not (0 <= u < p['width'] and 0 <= v < p['height']):
            continue
        i, n = int(v) * p['width'] + int(u), p['width'] * p['height']
        valid = asset(optical_root, p['validity'], n, 'u1')
        depth = asset(optical_root, p['depth'], n)
        channels.append({'cameraId': p['cameraId'], 'pixel': [int(u), int(v)],
                         'validCentreReturn': bool(valid[i]), 'finiteRange': bool(np.isfinite(depth[i]))})
    assert hits and channels and all(c['validCentreReturn'] and c['finiteRange'] for c in channels)
    return {'bodyInteriorPointM': point.tolist(), 'firstReturn': hits[0], 'coveringPixels': channels}


def verify(write):
    import numpy as np
    from PIL import Image
    from verify_volume_holdout import asset
    from render_volume_holdout import current_truth, forecast, MODES, LANES
    freeze = check_freeze()
    corpus_root, optical_root = OUT / 'corpus', OUT / 'optical'
    corpus, optical = read(corpus_root / 'manifest.json'), read(optical_root / 'manifest.json')
    nn, replay = read(corpus_root / 'ncnn/manifest.json'), read(OUT / 'replay.json')
    audit, labels, spec = read(OUT / 'source-audit.json'), read(corpus_root / 'annotations.json'), read(SPEC)
    seal_hash = sha(OUT / 'preregistration.json')
    assert corpus['sources'] == optical['sources'] == freeze['generatorSourceSha256']
    assert corpus['corpusId'] == 'closed-volume-control-2026-10-11'
    assert corpus['preregistrationSha256'] == optical['preregistrationSha256'] == replay['preregistrationSha256'] == seal_hash
    assert optical['priorCorpusSha256'] == nn['corpusManifestSha256'] == replay['corpusManifestSha256'] == sha(corpus_root / 'manifest.json')
    assert replay['opticalManifestSha256'] == sha(optical_root / 'manifest.json')
    assert len(corpus['layouts']) == len(labels['layouts']) == len(replay['cases']) == 3
    assert len(optical['batches']) == len(nn['frames']) == len(audit['rows']) == 21
    frozen_nn = read(ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json')
    for f in ('runtime', 'preprocessId', 'valueSemantics', 'calibration', 'modelBinSha256', 'modelParamSha256'):
        assert nn[f] == frozen_nn[f]
    assert nn['newScenesUsedForFit'] is False
    for suffix, field in [('bin', 'modelBinSha256'), ('param', 'modelParamSha256')]:
        assert sha(ROOT / f'assets/midas_small.ncnn.{suffix}') == nn[field]
    for f in ('promotionAllowed', 'ordinaryCameraWired', 'androidReadinessEstablished',
              'latencyMeasured', 'newFit', 'wholeObjectStationarityCertified'):
        assert replay[f] is False
    counts = {f'{m}/{a}': Counter(hazardStops=0, hazardMisses=0, falseStops=0, passableContinues=0)
              for m in MODES for a in LANES}
    hazards = clear = witnesses = 0
    all_continues_proved = True
    stamps, ids, by_layout, probes, warnings = set(), set(), [], [], []
    for case_index, (entry, layout, annotation, case) in enumerate(zip(spec['scenes'], corpus['layouts'], labels['layouts'], replay['cases'])):
        assert entry['id'] == layout['id'] == annotation['layoutId'] == case['layoutId']
        assert len(layout['frames']) == len(annotation['frames']) == len(case['frames']) == 7
        revisions = {}
        start_counts = {k: dict(v) for k, v in counts.items()}
        for index, (meta, label, row) in enumerate(zip(layout['frames'], annotation['frames'], case['frames'])):
            identity = (layout['id'], index + 1)
            batch = next(b for b in optical['batches'] if (b['layoutId'], b['frameId']) == identity)
            rec = next(r for r in nn['frames'] if (r['layoutId'], r['frameId']) == identity)
            source_row = next(r for r in audit['rows'] if (r['layoutId'], r['frameId']) == identity)
            stamp = 1790899200000000 + meta['capturedOffsetUs']
            assert meta['capturedOffsetUs'] == spec['capturedOffsetBaseUs'] + case_index * 2000000 + index * spec['intervalUs']
            assert stamp not in stamps and identity not in ids
            stamps.add(stamp); ids.add(identity)
            assert row['capturedAtUs'] == stamp and row['nowUs'] == stamp + 2000
            assert row['sessionStarts'] == 1 and row['userMoving'] is True
            assert batch['primaryOriginal'] == meta and batch['zeroSkewUs'] == 0 and batch['primaryArraysReproduced'] is True
            assert len(batch['channels']) == 12 and batch['sources'] == optical['sources']
            for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity'):
                asset(corpus_root, meta[key], meta['width'] * meta['height'], 'u1' if key == 'validity' else '<f4')
            rgb_path = corpus_root / meta['rgb']['path']
            assert sha(rgb_path) == rec['rgbSha256'] == meta['rgb']['sha256']
            pixels = asset(corpus_root / 'ncnn', rec['rgbPixels'], meta['width'] * meta['height'] * 3, 'u1')
            with Image.open(rgb_path) as image:
                assert np.array_equal(np.asarray(image.convert('RGB')).ravel(), pixels)
            assert np.isfinite(asset(corpus_root / 'ncnn', rec, 65536)).all()
            for packet in batch['channels']:
                for field in ('frameId', 'sessionGeneration', 'capturedAtUs', 'sceneStateSha256'):
                    assert packet[field] == batch[field]
                assert packet['cameraOriginM'] == meta['cameraOriginM']
                witnesses += packet['rayWitnesses']
                for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'):
                    asset(optical_root, packet[key], packet['width'] * packet['height'], 'u1' if key == 'validity' else '<f4')
            truth, blockers = current_truth(label)
            assert truth == label['physicalHazard'] and blockers == label['blockers'] and row['scoringOnly'] == label
            hazards += truth
            if not truth:
                clear += row['volume']['status'] == 'measuredClear'
                assert source_row['proofStatus'] == row['volume']['status']
                probes.append({'layoutId': layout['id'], 'frameId': index + 1, **probe(batch, label, optical_root)})
            for mode, arm in row['arms'].items():
                assert sha_bytes(arm['sharedRawTracksJson'].encode()) == arm['sharedRawTracksSha256']
                for lane, action in arm['runtime'].items():
                    key = f'{mode}/{lane}'
                    assert action['delivery'] == 'shadow' and action['arbiterActive'] is False
                    assert action['previousRevision'] == revisions.get(key, 1) and action['revision'] > action['previousRevision']
                    revisions[key] = action['revision']
                    stop = action['action'] == 'stopNow'
                    counts[key]['hazardStops' if truth and stop else 'hazardMisses' if truth else 'falseStops' if stop else 'passableContinues'] += 1
                    if lane == 'fixedRig' and action['action'] == 'continueForward':
                        all_continues_proved &= row['volume']['status'] == 'measuredClear' and row['volume']['coversCameraRecoveryVolume'] and not row['bodyMotion']['addsMotionRisk'] and row['volume']['validUntilUs'] >= row['nowUs']
                if not truth:
                    action = arm['runtime']['fixedRig']
                    warnings.append({'layoutId': layout['id'], 'frameId': index + 1, 'mode': mode,
                                     'action': action['action'], 'rule': action['rule'],
                                     'positiveBodyMotion': row['bodyMotion']['addsMotionRisk'],
                                     'oneSecondSyntheticIntersections': forecast(label)})
        by_layout.append({'layoutId': layout['id'], 'runtime': {k: {f: v[f] - start_counts[k][f] for f in v} for k, v in counts.items()}})
    assert {k: dict(v) for k, v in counts.items()} == replay['summary']['runtime']
    assert hazards == replay['summary']['physicalHazardFrames'] == 7 and replay['summary']['passableFrames'] == 14
    fault_rows = [r for t in replay['faultControls']['trials'] for r in t['frames']]
    fault_counts = {
        'trials': len(replay['faultControls']['trials']),
        'faultStops': sum(r['phase'] == 'fault' and r['action'] == 'stopNow' for r in fault_rows),
        'movingRecoveryStops': sum(r['phase'] == 'movingRecovery' and r['action'] == 'stopNow' for r in fault_rows),
        'clearPreconditions': sum(r['phase'] == 'clearPrecondition' for r in fault_rows),
        'clearPreconditionsPassed': sum(r['phase'] == 'clearPrecondition' and r['action'] == 'continueForward' for r in fault_rows),
    }
    assert fault_counts == replay['faultControls']['summary']
    for t in replay['faultControls']['trials']:
        assert t['sessionStarts'] == 1
        previous = 1
        for r in t['frames']:
            assert r['previousRevision'] == previous and r['revision'] > previous and r['userMoving'] is True
            assert r['delivery'] == 'shadow' and r['arbiterActive'] is False
            previous = r['revision']
    gates = {
        'producerPrecondition': clear == 14,
        'zeroHazardMisses': all(counts[f'{m}/{a}']['hazardMisses'] == 0 for m in MODES for a in ('fixedSingleView', 'fixedRig')),
        'allFaultsStop': fault_counts['faultStops'] == 48,
        'allMovingRecoveriesStop': fault_counts['movingRecoveryStops'] == 48,
        'afterClearPreconditions': fault_counts['clearPreconditionsPassed'] == 24,
        'aggregateSameRigFalseStopsReduced': sum(counts[f'{m}/fixedRig']['falseStops'] for m in MODES) < sum(counts[f'{m}/sameRigControl']['falseStops'] for m in MODES),
        'allContinuesHaveCurrentProof': all_continues_proved,
    }
    assert gates == replay['gates'] and replay['syntheticControlGatePassed'] == all(gates.values())
    negative = read(OLD / 'replay.json')
    assert negative['summary']['captures'] == 84 and not negative['syntheticHoldoutGatePassed']
    diagnosis = {'schemaVersion': 1, 'scope': freeze['scope'], 'gates': gates,
                 'syntheticControlGatePassed': all(gates.values()), 'promotionAllowed': False,
                 'ordinaryCameraWired': False, 'latencyMeasured': False, 'maximumFreshnessUs': 100000,
                 'summary': replay['summary'], 'faults': fault_counts, 'byLayout': by_layout,
                 'analyticFirstReturnProbes': probes, 'passableDecisions': warnings,
                 'originalNegativeControl': {'captures': 84, 'gatePassed': False,
                     'runtime': negative['summary']['runtime'], 'hashesUnchanged': True}}
    if write:
        save_new(OUT / 'diagnosis.json', diagnosis)
    else:
        assert read(OUT / 'diagnosis.json') == diagnosis
    artifacts = {p.relative_to(OUT).as_posix(): sha(p) for p in sorted(OUT.rglob('*'))
                 if p.is_file() and p.name != 'validation.json' and p.suffix != '.log'}
    value = {'schemaVersion': 1, 'integrityChecksPassed': True, 'syntheticControlGatePassed': all(gates.values()),
             'gates': gates, 'captures': 21, 'hazardFrames': hazards, 'passableFrames': 14,
             'measuredClearCaptures': clear, 'simultaneousOpticalChannels': 252,
             'independentRayWitnesses': witnesses, 'maximumFreshnessUs': 100000,
             'promotionAllowed': False, 'ordinaryCameraWired': False, 'latencyMeasured': False,
             'preregistrationSha256': seal_hash, 'sourceSha256': {p: sha(ROOT / p) for p in NEW_SOURCES},
             'artifactSha256': artifacts}
    if write:
        save_new(OUT / 'validation.json', value)
    else:
        assert read(OUT / 'validation.json') == value
    print(json.dumps({k: v for k, v in value.items() if k not in ('sourceSha256', 'artifactSha256')}, indent=2))


def sha_bytes(value):
    return hashlib.sha256(value).hexdigest()


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('command', choices=['seal', 'infer', 'verify'])
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    if args.command == 'seal':
        seal()
    elif args.command == 'infer':
        infer(args.check)
    else:
        verify(args.write)

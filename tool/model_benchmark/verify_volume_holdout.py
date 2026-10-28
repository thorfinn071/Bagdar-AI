"""Freeze/recheck integrity separately from the predeclared behavioural gate."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import numpy as np

from render_volume_holdout import ROOT, DIRECTORY, CORPUS, MODES, LANES, diagnosis, current_truth

SOURCES = [
    'docs/volume-holdout-protocol-2026-10-10.md', 'docs/volume-holdout-evaluation-2026-10-10.md',
    'tool/blender/generate_volume_holdout.py', 'tool/blender/volume_holdout_spec_v1.json',
    'tool/model_benchmark/preregister_volume_holdout.py', 'tool/model_benchmark/infer_volume_holdout.py',
    'tool/model_benchmark/render_volume_holdout.py', 'tool/model_benchmark/verify_volume_holdout.py',
    'tool/model_benchmark/test_volume_holdout_scoring.py', 'tool/model_benchmark/check_volume_holdout.ps1',
    'tool/model_benchmark/run_volume_holdout_capture_pipeline.ps1',
    'tool/model_benchmark/audit_volume_holdout_visibility.py', 'test/volume_holdout_source_audit_test.dart',
    'test/harness/volume_holdout_fixture.dart', 'test/harness/volume_holdout_replay.dart',
    'test/harness/volume_holdout_faults.dart', 'test/volume_holdout_test.dart',
]


def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def require(value, message):
    if not value: raise ValueError(message)


def asset(root, desc, n, dtype='<f4'):
    path = (root / desc['path']).resolve()
    require(path.is_relative_to(root) and sha(path) == desc['sha256'], f'Asset path/hash: {path}')
    array = np.frombuffer(gzip.decompress(path.read_bytes()), dtype=dtype)
    require(len(array) == n, f'Asset dimensions: {path}')
    return array


def build():
    prereg = read(DIRECTORY / 'preregistration.json')
    consumer = read(DIRECTORY / 'consumer-freeze.json')
    for path, h in consumer['sourceSha256'].items():
        require(sha(ROOT / path) == h, f'Frozen consumer/scoring drift: {path}')
    upstream = read(DIRECTORY / 'upstream-check-result.json')
    require(upstream['passed'] is True and upstream['exitCode'] == 0 and
            upstream['flutterRuns'] == [22, 38, 29, 137] and upstream['flutterTests'] == 226 and
            upstream['pythonUnitTests'] == 7 and upstream['exactNcnnCaptures'] == 42 and
            upstream['fullLogSha256'] == sha(DIRECTORY / 'upstream-check.log'), 'Upstream check evidence drift')
    prior = ROOT / 'scratch/evidence-authority-fix-2026-10-10/validation.json'
    require(upstream['validationSha256'] == sha(prior), 'Upstream validation binding')
    require(prereg['priorValidationSha256'] == sha(prior), 'Prior validation replaced')
    require(prereg['preregisterToolSha256'] == sha(ROOT / 'tool/model_benchmark/preregister_volume_holdout.py'), 'Seal tool drift')
    for path, h in {**prereg['frozenSourceSha256'], **prereg['generatorSourceSha256']}.items():
        require(sha(ROOT / path) == h, f'Frozen source drift: {path}')
    require(prereg['captureCount'] == 84 and prereg['noRuntimeTuningAfterSeal'] is True and
            prereg['promotionAllowed'] is False and prereg['ordinaryCameraWired'] is False, 'Predeclared scope drift')
    corpus, labels = read(CORPUS / 'manifest.json'), read(CORPUS / 'annotations.json')
    optical_root = DIRECTORY / 'optical'
    optical = read(optical_root / 'manifest.json')
    nn = read(CORPUS / 'ncnn/manifest.json')
    replay = read(DIRECTORY / 'replay.json')
    spec = read(ROOT / 'tool/blender/volume_holdout_spec_v1.json')
    require(corpus['sources'] == optical['sources'] == prereg['generatorSourceSha256'], 'Capture producer drift')
    require(corpus['preregistrationSha256'] == optical['preregistrationSha256'] == replay['preregistrationSha256'] == sha(DIRECTORY / 'preregistration.json'), 'Capture not bound to preregistration')
    require(optical['priorCorpusSha256'] == nn['corpusManifestSha256'] == replay['corpusManifestSha256'] == sha(CORPUS / 'manifest.json') and
            replay['opticalManifestSha256'] == sha(optical_root / 'manifest.json') and replay['priorValidationSha256'] == sha(prior), 'Replay input drift')
    for field in ('promotionAllowed', 'ordinaryCameraWired', 'androidReadinessEstablished',
                  'latencyMeasured', 'newFit', 'wholeObjectStationarityCertified'):
        require(replay[field] is False, 'Unsupported authority: ' + field)
    require(optical['promotionAllowed'] is False and optical['ordinaryCameraWired'] is False, 'Optical authority changed')
    frozen_nn_path = ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json'
    frozen_nn = read(frozen_nn_path)
    require(nn['frozenCalibrationSourceSha256'] == sha(frozen_nn_path) and nn['newScenesUsedForFit'] is False and
            nn['generatorSha256'] == sha(ROOT / 'tool/model_benchmark/infer_volume_holdout.py'), 'Inference fit/source drift')
    for field in ('runtime', 'preprocessId', 'valueSemantics', 'calibration', 'modelBinSha256', 'modelParamSha256'):
        require(nn[field] == frozen_nn[field], f'Frozen NCNN contract: {field}')
    for suffix, field in [('bin', 'modelBinSha256'), ('param', 'modelParamSha256')]:
        require(sha(ROOT / f'assets/midas_small.ncnn.{suffix}') == nn[field], 'Model asset drift')
    require(nn['inferenceHelperSha256'] == sha(ROOT / 'tool/model_benchmark/generate_context_ncnn_depth.py'), 'Inference helper drift')
    require(len(corpus['layouts']) == len(labels['layouts']) == len(replay['cases']) == len(spec['scenes']) == 12 and
            len(optical['batches']) == len(nn['frames']) == 84, 'Incomplete holdout')
    old_rgb = set(); old_pixel_identities = set()
    from PIL import Image
    for path in [ROOT / 'scratch/ego-motion-2026-10-10/corpus/manifest.json',
                 ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-v1/manifest.json']:
        for l in read(path)['layouts']:
            for f in l['frames']:
                old_rgb.add(f['rgb']['sha256'])
                with Image.open(path.parent / f['rgb']['path']) as image:
                    rgb_image = image.convert('RGB')
                    old_pixel_identities.add((rgb_image.width, rgb_image.height, hashlib.sha256(rgb_image.tobytes()).hexdigest()))
    identities, rgb_hashes, pixel_identities, stamps = set(), [], [], set()
    counts = {f'{m}/{a}': Counter(hazardStops=0, hazardMisses=0, falseStops=0, passableContinues=0)
              for m in MODES for a in LANES}
    hazards = clear_proofs = witnesses = 0
    all_continues_proved = True
    for case_index, (entry, layout, annotation, case) in enumerate(zip(spec['scenes'], corpus['layouts'], labels['layouts'], replay['cases'])):
        require(entry['id'] == layout['id'] == annotation['layoutId'] == case['layoutId'] and
                len(layout['frames']) == len(annotation['frames']) == len(case['frames']) == 7, 'Layout mismatch')
        previous = {}
        for index, (meta, label, row) in enumerate(zip(layout['frames'], annotation['frames'], case['frames'])):
            identity = (layout['id'], index + 1)
            batch = next(b for b in optical['batches'] if (b['layoutId'], b['frameId']) == identity)
            rec = next(r for r in nn['frames'] if (r['layoutId'], r['frameId']) == identity)
            stamp = 1790899200000000 + meta['capturedOffsetUs']
            require(meta['frameId'] == label['frameId'] == row['frameId'] == index + 1 and
                    meta['capturedOffsetUs'] == spec['capturedOffsetBaseUs'] + case_index * 2000000 + index * spec['intervalUs'], 'Reused/retimed capture')
            require(stamp not in stamps, 'Duplicate capture clock'); stamps.add(stamp)
            capture_identity = (rec['rgbPixels']['sha256'], meta['depth']['sha256'], tuple(meta['walkingOriginWorldM']), tuple(meta['cameraToWalkingRotation']))
            require(capture_identity not in identities, 'Duplicate capture identity'); identities.add(capture_identity)
            rgb = (CORPUS / meta['rgb']['path']).resolve()
            require(rgb.is_relative_to(CORPUS) and sha(rgb) == meta['rgb']['sha256'] == rec['rgbSha256'] and sha(rgb) not in old_rgb, 'RGB reuse/drift')
            rgb_hashes.append(sha(rgb))
            for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity'):
                asset(CORPUS, meta[key], meta['width'] * meta['height'], 'u1' if key == 'validity' else '<f4')
            pixels = asset(CORPUS / 'ncnn', rec['rgbPixels'], meta['width'] * meta['height'] * 3, 'u1')
            with Image.open(rgb) as image:
                require(np.array_equal(np.asarray(image.convert('RGB')).ravel(), pixels), 'Inference RGB transfer drift')
            pixel_identity = (meta['width'], meta['height'], hashlib.sha256(pixels.tobytes()).hexdigest())
            require(pixel_identity not in old_pixel_identities, 'Prior decoded RGB pixels reused')
            pixel_identities.append(pixel_identity)
            raw = asset(CORPUS / 'ncnn', rec, 65536)
            require(np.isfinite(raw).all(), 'Invalid NCNN output')
            require(batch['primaryOriginal'] == meta and batch['primaryArraysReproduced'] is True and batch['zeroSkewUs'] == 0 and
                    batch['sources'] == optical['sources'] and batch['stationarySyntheticScene'] is True and
                    batch['capturedAtUs'] == stamp and len(batch['channels']) == 12, 'Mixed capture batch')
            for packet in batch['channels']:
                for field in ('frameId', 'sessionGeneration', 'capturedAtUs', 'sceneStateSha256'):
                    require(packet[field] == batch[field], 'Foreign rig packet')
                require(packet['cameraOriginM'] == meta['cameraOriginM'] and packet['rayWitnesses'] > 0, 'Missing optical witness')
                rotation = np.array(packet['cameraToWalkingRotation']).reshape(3, 3)
                require(np.isfinite(rotation).all() and np.allclose(rotation @ rotation.T, np.eye(3), atol=1e-6), 'Bad optical rotation')
                arrays = {key: asset(optical_root, packet[key], packet['width'] * packet['height'], 'u1' if key == 'validity' else '<f4')
                          for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower')}
                require(np.isin(arrays['validity'], [0, 1]).all(), 'Validity values')
                for a, b in [('freeZLower', 'surfaceZUpper'), ('heightLower', 'heightUpper')]:
                    finite = np.isfinite(arrays[a]) & np.isfinite(arrays[b])
                    require(np.all(arrays[b][finite] >= arrays[a][finite]), 'Reversed optical envelope')
                witnesses += packet['rayWitnesses']
            truth, blockers = current_truth(label)
            require(truth == label['physicalHazard'] and blockers == label['blockers'] and
                    label['floorDiscontinuity'] == (entry['kind'] == 'gap'), 'Independent physical scoring mismatch')
            hazards += truth
            require(row['scoringOnly'] == label and row['capturedAtUs'] == stamp and row['nowUs'] == stamp + 2000 and
                    row['sessionStarts'] == 1 and row['userMoving'] is True, 'History/clock reset')
            proof = row['volume']; clear = proof['status'] == 'measuredClear'; clear_proofs += clear
            if clear:
                require(proof['coversCameraRecoveryVolume'] is True and stamp + 2000 <= proof['validUntilUs'] <= stamp + 100000, 'Unbounded clearance')
            for mode, arm in row['arms'].items():
                require(mode in MODES and json.loads(arm['sharedRawTracksJson']) == arm['rawTracks'] and arm['sharedRawTracksSha256'] == hashlib.sha256(arm['sharedRawTracksJson'].encode()).hexdigest(), 'Raw track sharing identity')
                for t in arm['rawTracks']:
                    require(t['timestamps'][-1] <= stamp and len(t['proximityHistory']) == len(t['timestamps']), 'Track history altered')
                for lane, outcome in arm['runtime'].items():
                    key = f'{mode}/{lane}'
                    require(lane in LANES and outcome['delivery'] == 'shadow' and outcome['arbiterActive'] is False and
                            outcome['revision'] > outcome['previousRevision'] and (not index or outcome['previousRevision'] == previous[key]), 'Active output/history reset')
                    previous[key] = outcome['revision']
                    stop = outcome['action'] == 'stopNow'
                    field = ('hazardStops' if stop else 'hazardMisses') if truth else ('falseStops' if stop else 'passableContinues')
                    counts[key][field] += 1
                    if lane == 'fixedRig' and not stop:
                        all_continues_proved &= clear and proof['coversCameraRecoveryVolume'] and not row['bodyMotion']['addsMotionRisk']
    require(replay['summary']['captures'] == 84 and replay['summary']['physicalHazardFrames'] == hazards and
            replay['summary']['passableFrames'] == 84 - hazards and {k: dict(v) for k, v in counts.items()} == replay['summary']['runtime'], 'Count arithmetic')
    trials = replay['faultControls']['trials']; fault_counts = Counter()
    require(len(trials) == 48, 'Fault denominator')
    trial_ids = set()
    for trial in trials:
        identity = (trial['mode'], trial['fault'], trial['afterClear'])
        require(identity not in trial_ids and trial['sessionStarts'] == 1, 'Duplicate/reset fault trial'); trial_ids.add(identity)
        previous_revision = None
        for row in trial['frames']:
            require(row['delivery'] == 'shadow' and row['arbiterActive'] is False and row['userMoving'] is True and
                    row['revision'] > row['previousRevision'] and (previous_revision is None or row['previousRevision'] == previous_revision), 'Fault history/authority drift')
            previous_revision = row['revision']
            fault_counts[row['phase']] += 1
            if row['action'] == 'stopNow': fault_counts[row['phase'] + 'Stops'] += 1
            if row['action'] == 'continueForward': fault_counts[row['phase'] + 'Continues'] += 1
    expected_faults = {'trials': 48, 'faultStops': fault_counts['faultStops'], 'movingRecoveryStops': fault_counts['movingRecoveryStops'],
                       'clearPreconditions': fault_counts['clearPrecondition'], 'clearPreconditionsPassed': fault_counts['clearPreconditionContinues']}
    require(replay['faultControls']['summary'] == expected_faults and fault_counts['fault'] == fault_counts['movingRecovery'] == 48 and fault_counts['clearPrecondition'] == 24, 'Fault count arithmetic')
    gates = {
        'zeroHazardMisses': all(counts[f'{m}/{a}']['hazardMisses'] == 0 for m in MODES for a in ('fixedSingleView', 'fixedRig')),
        'allFaultsStop': expected_faults['faultStops'] == 48,
        'allMovingRecoveriesStop': expected_faults['movingRecoveryStops'] == 48,
        'afterClearPreconditions': expected_faults['clearPreconditionsPassed'] == 24,
        'noSingleViewOptimism': all(counts[f'{m}/fixedSingleView']['passableContinues'] == 0 for m in MODES),
        'aggregateSameRigFalseStopsReduced': sum(counts[f'{m}/fixedRig']['falseStops'] for m in MODES) < sum(counts[f'{m}/sameRigControl']['falseStops'] for m in MODES),
        'allContinuesHaveCurrentProof': bool(all_continues_proved),
    }
    require(gates == replay['gates'] and replay['syntheticHoldoutGatePassed'] == all(gates.values()), 'Gate arithmetic')
    value = diagnosis()
    require(read(DIRECTORY / 'diagnosis.json') == value, 'Post-decision forecast arithmetic')
    audit = read(DIRECTORY / 'source-audit.json')
    require(len(audit['rows']) == 84 and audit['promotionAllowed'] is False, 'Producer audit scope')
    for row in audit['rows']:
        capture = next(r for c in replay['cases'] if c['layoutId'] == row['layoutId'] for r in c['frames'] if r['frameId'] == row['frameId'])
        require(row['proofStatus'] == capture['volume']['status'] and row['proofReasons'] == capture['volume']['reasons'], 'Post-outcome producer audit drift')
        require(all(0 <= s['bodyObservedFraction'] <= 1 and 0 <= s['floorObservedFraction'] <= 1 for s in row['sections']), 'Producer coverage arithmetic')
    from audit_volume_holdout_visibility import build as visibility_build
    require(read(DIRECTORY / 'visibility-audit.json') == visibility_build(), 'Independent ray witness drift')
    artifacts = {p.relative_to(DIRECTORY).as_posix(): sha(p) for p in sorted(DIRECTORY.rglob('*'))
                 if p.is_file() and p.suffix not in ('.log',) and p.name not in ('validation.json', 'full-check-result.json')}
    return {'schemaVersion': 1, 'integrityChecksPassed': True,
            'syntheticHoldoutGatePassed': all(gates.values()), 'gates': gates,
            'promotionAllowed': False, 'ordinaryCameraWired': False,
            'captures': 84, 'hazardFrames': hazards, 'passableFrames': 84 - hazards,
            'measuredClearCaptures': clear_proofs, 'simultaneousOpticalChannels': 1008,
            'independentRayWitnesses': witnesses, 'distinctCaptureIdentities': len(identities),
            'distinctRgbPngContainerHashes': len(set(rgb_hashes)),
            'distinctDecodedRgbPixelPayloads': len(set(pixel_identities)),
            'priorRgbPngReused': 0, 'priorRgbPixelReused': 0,
            'maximumFreshnessUs': 100000, 'latencyMeasured': False,
            'priorValidationSha256': sha(prior), 'preregistrationSha256': sha(DIRECTORY / 'preregistration.json'),
            'sourceSha256': {p: sha(ROOT / p) for p in SOURCES}, 'artifactSha256': artifacts}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--write', action='store_true')
    args = parser.parse_args(); value = build(); target = DIRECTORY / 'validation.json'
    if args.write:
        require(not target.exists(), 'Validation is immutable')
        target.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    else:
        require(read(target) == value, 'Source/output drift')
    print('Holdout integrity passed; behavioural gate=' + str(value['syntheticHoldoutGatePassed']) + '; promotion disabled')

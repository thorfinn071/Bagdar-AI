"""Validate repair identities, optical envelopes, history and unchanged scoring."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from render_volume_authority import diagnosis, DIRECTORY, ROOT, CORPUS

SOURCES = [
    'docs/evidence-authority-fix-protocol-2026-10-10.md',
    'docs/evidence-authority-fix-evaluation-2026-10-10.md',
    'lib/safety/runtime/volume_authority_spatial_runtime.dart',
    'test/volume_authority_runtime_test.dart', 'test/volume_authority_history_test.dart',
    'test/harness/volume_authority_regression.dart', 'test/volume_authority_regression_test.dart',
    'test/harness/ego_volume_fixture.dart', 'test/harness/ego_volume_repair.dart', 'test/ego_volume_repair_test.dart',
    'tool/blender/export_ego_volume_evidence.py',
    'tool/model_benchmark/check_volume_authority.ps1',
    'tool/model_benchmark/render_volume_authority.py', 'tool/model_benchmark/verify_volume_authority.py',
]


def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def require(value, message):
    if not value: raise ValueError(message)


def build():
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_ego_motion.py'], cwd=ROOT, check=True)
    r = read(DIRECTORY / 'ego-repair-replay.json')
    k = read(DIRECTORY / 'known-replay.json')
    old = read(ROOT / 'scratch/whole-track-evidence-2026-10-10/replay.json')
    ego = read(ROOT / 'scratch/ego-motion-2026-10-10/replay.json')
    optical_root = DIRECTORY / 'optical'
    optical = read(optical_root / 'manifest.json')
    corpus = read(CORPUS / 'manifest.json')
    labels = read(CORPUS / 'annotations.json')
    require(r['priorReplaySha256'] == sha(ROOT / 'scratch/ego-motion-2026-10-10/replay.json') and
            r['opticalManifestSha256'] == sha(optical_root / 'manifest.json') and
            r['corpusManifestSha256'] == optical['priorCorpusSha256'] == sha(CORPUS / 'manifest.json'), 'Input binding drift')
    for path, digest in optical['sources'].items():
        require(sha(ROOT / path) == digest, 'Exporter drift: ' + path)
    for field in ('promotionAllowed', 'ordinaryCameraWired', 'androidReadinessEstablished',
                  'latencyMeasured', 'newFit', 'wholeObjectStationarityCertified'):
        require(r[field] is False, 'Unsupported authority: ' + field)
    require(optical['promotionAllowed'] is False and optical['ordinaryCameraWired'] is False, 'Optical scope drift')
    require(k['maximumAgeUs'] == 100000, 'TTL changed')
    for mode in ('legacy', 'frameStable'):
        frames = k['optical'][mode]
        require(len(frames) == 11, 'Known sequence incomplete')
        for index, (row, before) in enumerate(zip(frames, old['optical'][mode])):
            require(row['tracks'] == before['tracks'] and row['frameId'] == before['frameId'] == index + 1 and
                    row['capturedAtUs'] == before['capturedAtUs'] and row['nowUs'] == before['nowUs'], 'Track/capture changed')
            require(row['action'] == 'continueForward' and row['bodyUnknown'] == 0 and
                    row['sessionStarts'] == 1 and row['userMoving'] is True and row['delivery'] == 'shadow' and
                    row['arbiterActive'] is False, 'Known resolution/authority drift')
            require(row['revision'] > row['previousRevision'] and
                    (not index or row['previousRevision'] == frames[index-1]['revision']), 'Known history reset')
        require(k['summary'][mode]['stops'] == 0 and k['summary'][mode]['continues'] == 11 and
                k['summary'][mode]['geometryUnknownPixels'] == old['summary'][mode]['geometryUnknownPixels'], 'Unknown filled or count drift')
    require(k['initialClearFaultControls'] == old['initialClearFaultControls'] and
            k['summary']['initialFaultStops'] == k['summary']['initialFaultTrials'] == 22, 'Fault/explicit risk changed')
    require(k['motionCases'] == old['motionCases'], 'Known physical history/motion decisions changed')
    known_hazards = sum(f['scoringOnly']['physicalHazard'] for c in k['motionCases'] for f in c['frames'])
    require(known_hazards == 60 and all(a['action'] == 'stopNow' for c in k['motionCases'] for f in c['frames']
            if f['scoringOnly']['physicalHazard'] for a in f['relative'].values()), 'Known hazard miss')

    require(len(optical['batches']) == 42, 'Incomplete new optics')
    witnesses = 0
    for batch in optical['batches']:
        layout = next(v for v in corpus['layouts'] if v['id'] == batch['layoutId'])
        meta = layout['frames'][batch['frameId'] - 1]
        require(batch['primaryOriginal'] == meta and batch['primaryArraysReproduced'] is True and
                batch['capturedAtUs'] == 1790899200000000 + meta['capturedOffsetUs'] and
                batch['zeroSkewUs'] == 0 and batch['stationarySyntheticScene'] is True and
                batch['sources'] == optical['sources'] and len(batch['channels']) == 12, 'Mixed/retimed optics')
        for packet in batch['channels']:
            for field in ('frameId', 'sessionGeneration', 'capturedAtUs', 'sceneStateSha256'):
                require(packet[field] == batch[field], 'Foreign optical channel')
            require(packet['cameraOriginM'] == meta['cameraOriginM'] and packet['rayWitnesses'] > 0, 'Foreign optical centre/missing witness')
            rotation = np.array(packet['cameraToWalkingRotation']).reshape(3, 3)
            require(np.isfinite(rotation).all() and np.allclose(rotation @ rotation.T, np.eye(3), atol=1e-6), 'Invalid rotation')
            n = packet['width'] * packet['height']
            arrays = {}
            for name in ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'):
                desc = packet[name]; path = (optical_root / desc['path']).resolve()
                require(path.is_relative_to(optical_root) and sha(path) == desc['sha256'], 'Optical path/hash drift')
                arrays[name] = np.frombuffer(gzip.decompress(path.read_bytes()), dtype='u1' if name == 'validity' else '<f4')
                require(len(arrays[name]) == n, 'Wrong optical dimensions')
            require(np.isin(arrays['validity'], [0, 1]).all(), 'Invalid validity mask')
            lo, hi = arrays['freeZLower'], arrays['surfaceZUpper']
            finite = np.isfinite(lo) & np.isfinite(hi)
            require(np.all(hi[finite] >= lo[finite]), 'Reversed surface bounds')
            a, b = arrays['heightLower'], arrays['heightUpper']; finite = np.isfinite(a) & np.isfinite(b)
            require(np.all(b[finite] >= a[finite]), 'Reversed height bounds')
            witnesses += packet['rayWitnesses']

    counts = {name: Counter(hazardStops=0, hazardMisses=0, falseStops=0, passableContinues=0)
              for name in r['summary']['runtime']}
    hazards, captures, clear_proofs = 0, 0, 0
    for case, prior_case, layout, annotation in zip(r['cases'], ego['cases'], corpus['layouts'], labels['layouts']):
        require(case['layoutId'] == prior_case['layoutId'] == layout['id'] == annotation['layoutId'], 'Layout drift')
        previous = {}
        for index, (row, before, label) in enumerate(zip(case['frames'], prior_case['frames'], annotation['frames'])):
            captures += 1; hazard = label['physicalHazard']; hazards += hazard
            require(row['scoringOnly'] == label and row['capturedAtUs'] == before['capturedAtUs'] and
                    row['nowUs'] == before['nowUs'] and row['sessionStarts'] == 1 and row['userMoving'] is True, 'Retimed/reset replay')
            require(row['bodyMotion'] == before['egoMotion']['bodyRelativeMotion'], 'Ego-motion changed')
            proof = row['volume']; measured_clear = proof['status'] == 'measuredClear'
            clear_proofs += measured_clear
            require(not measured_clear or proof['coversCameraRecoveryVolume'] is True and
                    proof['validUntilUs'] <= row['capturedAtUs'] + 100000, 'Unbounded volume proof')
            for mode, arm in row['arms'].items():
                require(arm['riskAttribution'] == before['arms'][mode]['riskAttribution'], 'Relative track state changed')
                for lane, outcome in arm['runtime'].items():
                    identity = f'{mode}/{lane}'
                    require(outcome['delivery'] == 'shadow' and outcome['arbiterActive'] is False and
                            outcome['revision'] > outcome['previousRevision'] and
                            (not index or outcome['previousRevision'] == previous[identity]), 'Active output/history reset')
                    previous[identity] = outcome['revision']
                    stop = outcome['action'] == 'stopNow'
                    field = ('hazardStops' if stop else 'hazardMisses') if hazard else ('falseStops' if stop else 'passableContinues')
                    counts[identity][field] += 1
                    if lane == 'singleViewControl':
                        require(outcome['action'] == before['arms'][mode]['runtime']['canonical']['action'], 'Single-view control drift')
                    if lane == 'fixedRig':
                        require(stop or measured_clear and not row['bodyMotion']['addsMotionRisk'] and not hazard, 'Unsupported release')
                        require(not row['bodyMotion']['addsMotionRisk'] or stop, 'Physical motion risk removed')
    require(captures == r['summary']['captures'] == 42 and hazards == r['summary']['physicalHazardFrames'] == 25 and
            captures-hazards == r['summary']['passableFrames'] == 17 and clear_proofs == 17, 'Scoring/proof denominator drift')
    require({k: dict(v) for k, v in counts.items()} == r['summary']['runtime'], 'Count arithmetic drift')
    for mode in ('legacy', 'frameStable'):
        require(all(counts[f'{mode}/{lane}']['hazardStops'] == 25 and counts[f'{mode}/{lane}']['hazardMisses'] == 0
                    for lane in ('singleViewControl', 'fixedSingleView', 'sameRigControl', 'fixedRig')), 'New physical hazard miss')
        require(counts[f'{mode}/fixedSingleView']['falseStops'] == 17 and
                counts[f'{mode}/sameRigControl']['falseStops'] == 8 and
                counts[f'{mode}/fixedRig']['falseStops'] == 3, 'False-stop reduction changed')
    value = diagnosis()
    require(read(DIRECTORY / 'diagnosis.json') == value and len(value['remainingPassableStops']) == 3 and
            all(v['anticipatoryUnderConstantVelocity'] for v in value['remainingPassableStops']), 'Forecast diagnosis drift')
    artifacts = {str(p.relative_to(DIRECTORY)).replace('\\', '/'): sha(p)
                 for p in sorted(optical_root.rglob('*')) if p.is_file()}
    artifacts.update({p: sha(DIRECTORY / p) for p in ('known-replay.json', 'ego-repair-replay.json', 'diagnosis.json',
                      'volume-authority.png', 'volume-authority.svg')})
    return {
        'schemaVersion': 1, 'passed': True, 'syntheticRepairGate': 'passed', 'promotionAllowed': False,
        'ordinaryCameraWired': False, 'newIndependentHoldout': False,
        'knownFalseStopsBefore': 10, 'knownFalseStopsAfter': 0, 'knownClearFrames': 11,
        'newInstantaneousFalseStopsSameRigBefore': 8, 'newInstantaneousFalseStopsAfter': 3,
        'knownHazardStopsPerMode': 60, 'newHazardStopsPerMode': 25, 'initialFaultStops': 22,
        'originalCapturesReproduced': 42, 'simultaneousOpticalChannels': 504, 'independentRayWitnesses': witnesses,
        'maximumFreshnessUs': 100000, 'wholeObjectStationarityCertified': False,
        'latencyMeasured': False, 'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run',
        'priorValidationSha256': sha(ROOT / 'scratch/ego-motion-2026-10-10/validation.json'),
        'sourceSha256': {p: sha(ROOT / p) for p in SOURCES}, 'artifactSha256': artifacts,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--write', action='store_true')
    args = parser.parse_args(); value = build(); target = DIRECTORY / 'validation.json'
    if args.write:
        require(not target.exists(), 'Validation is immutable')
        target.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    else:
        require(read(target) == value, 'Source/output drift')
    print('Volume authority: synthetic repair and immutable upstream checks passed; promotion remains disabled')

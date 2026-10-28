"""Verify new whole-support receipts and the immutable upstream chain."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np
from render_whole_track_evidence import diagnosis

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/whole-track-evidence-2026-10-10'
PRIOR = ROOT / 'scratch/motion-origin-2026-10-10'
OLD_OPTICAL = ROOT / 'scratch/sequence-first-return-2026-10-09/optical'
SOURCES = [
    'docs/whole-track-evidence-protocol-2026-10-10.md',
    'docs/whole-track-evidence-evaluation-2026-10-10.md',
    'lib/safety/perception/camera_track_motion_coverage.dart',
    'test/camera_track_motion_coverage_test.dart',
    'test/harness/whole_track_evidence_experiment.dart',
    'test/whole_track_evidence_experiment_test.dart',
    'tool/blender/export_whole_track_evidence.py',
    'tool/model_benchmark/check_whole_track_evidence.ps1',
    'tool/model_benchmark/render_whole_track_evidence.py',
    'tool/model_benchmark/verify_whole_track_evidence.py',
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def asset(root, desc, dtype='<f4'):
    path = (root / desc['path']).resolve()
    require(path.is_relative_to(root) and sha(path) == desc['sha256'], 'Asset path/hash drift')
    return np.frombuffer(gzip.decompress(path.read_bytes()), dtype=dtype)


def build():
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_motion_origin.py'], cwd=ROOT, check=True)
    r = read(DIRECTORY / 'replay.json'); old = read(PRIOR / 'replay.json')
    optical = read(DIRECTORY / 'optical/manifest.json')
    selection = read(DIRECTORY / 'optical/selection.json')
    frozen = read(OLD_OPTICAL / 'manifest.json')
    require(r['opticalManifestSha256'] == sha(DIRECTORY / 'optical/manifest.json'), 'New calibration drift')
    require(r['priorReplaySha256'] == sha(PRIOR / 'replay.json'), 'Prior replay drift')
    require(optical['priorOpticalManifestSha256'] == sha(OLD_OPTICAL / 'manifest.json'), 'Prior optics drift')
    require(optical['priorValidationSha256'] == sha(PRIOR / 'validation.json'), 'Prior validation drift')
    require(optical['selectionSha256'] == sha(DIRECTORY / 'optical/selection.json'), 'Selection drift')
    require(selection['priorReplaySha256'] == sha(PRIOR / 'replay.json'), 'Selection input drift')
    require(selection['sources'] == optical['sources'] and
            selection['priorValidationSha256'] == optical['priorValidationSha256'] and
            selection['priorOpticalManifestSha256'] == optical['priorOpticalManifestSha256'], 'Selection scope drift')
    require(all(optical[k] is False for k in ('promotionAllowed', 'ordinaryCameraWired', 'newNeuralInference')), 'Optical scope drift')
    for p, digest in optical['sources'].items():
        require(sha(ROOT / p) == digest, 'Frozen optical exporter drift: ' + p)
    require(len(optical['records']) == len(frozen['batches']) == len(selection['frames']) == 11, 'Incomplete optics')
    for i, (record, batch, selected) in enumerate(zip(optical['records'], frozen['batches'], selection['frames'])):
        p = batch['primary']; n = p['width'] * p['height']
        union = sorted(set(old['sequence']['legacy'][i]['allSupportPixels']) |
                       set(old['sequence']['frameStable'][i]['allSupportPixels']))
        require(selected['supportPixels'] == union, 'Support selection drift')
        require(record['capturedAtUs'] == selected['capturedAtUs'] == p['capturedAtUs'] and
                record['frameId'] == selected['frameId'] == p['frameId'] == i + 1 and
                record['sessionGeneration'] == p['sessionGeneration'] and
                record['sceneStateSha256'] == batch['sceneStateSha256'], 'Retimed/foreign geometry')
        require(optical['sourceBlendSha256'] == batch['sourceBlendSha256'], 'Foreign source scene')
        require(record['sources'] == optical['sources'] and record['selectionSha256'] == optical['selectionSha256'], 'Checkpoint drift')
        require(record['priorUpperSha256'] == p['surfaceZUpper']['sha256'], 'Wrong starting bounds')
        upper = asset(DIRECTORY / 'optical', record['surfaceZUpper'])
        mask = asset(DIRECTORY / 'optical', record['repairMask'], 'u1')
        old_upper = asset(OLD_OPTICAL, p['surfaceZUpper'])
        lower = asset(OLD_OPTICAL, p['freeZLower']); depth = asset(OLD_OPTICAL, p['depth'])
        valid = asset(OLD_OPTICAL, p['validity'], 'u1')
        require(all(len(a) == n for a in (upper, mask, old_upper, lower, depth, valid)), 'Wrong pixel dimensions')
        require(np.isin(mask, [0, 1]).all(), 'Nonbinary repair mask')
        chosen = np.zeros(n, dtype=bool); chosen[union] = True
        candidates = chosen & (valid == 1) & np.isfinite(depth) & np.isnan(old_upper)
        proof_path = DIRECTORY / 'optical' / record['proof']['path']
        require(proof_path.resolve().is_relative_to(DIRECTORY / 'optical') and
                sha(proof_path) == record['proof']['sha256'], 'Proof path/hash drift')
        proofs = read(proof_path)
        require(len(proofs) == record['candidates'] == int(candidates.sum()) and
                {v['index'] for v in proofs} == set(np.flatnonzero(candidates)), 'Candidate proof selection drift')
        repaired = mask == 1
        require({v['index'] for v in proofs if v['certified']} == set(np.flatnonzero(repaired)), 'Proof/mask mismatch')
        require(not np.any(repaired & ~candidates) and int(repaired.sum()) == record['certified'], 'Unselected repair')
        require(record['rayWitnesses'] == record['certified'] * 5, 'Missing independent first-hit witnesses')
        require(np.array_equal(upper[~repaired], old_upper[~repaired], equal_nan=True), 'Existing finite/failed bounds changed')
        require(np.isfinite(upper[repaired]).all() and (upper[repaired] >= lower[repaired]).all(), 'Invalid upper bound')
        for v in proofs:
            if v['certified']:
                require(v['heightLowerM'] <= v['sampledFirstHitHeightMinM'] + 2e-4 and
                        v['heightUpperM'] >= v['sampledFirstHitHeightMaxM'] - 2e-4, 'Witness outside certified height')
    for key in ('promotionAllowed', 'ordinaryCameraWired', 'newIndependentHoldout', 'newNeuralInference', 'captureToCommandMeasured'):
        require(r[key] is False, 'Unsupported promotion: ' + key)
    require(r['maximumAgeUs'] == 100000, 'Freshness changed')
    for mode, frames in r['optical'].items():
        require(len(frames) == 11, 'Sequence incomplete')
        for i, f in enumerate(frames):
            previous = old['sequence'][mode][i]
            require(f['tracks'] == previous['tracks'], 'Changed tracker/support')
            require(f['frameId'] == i+1 and f['capturedAtUs'] == previous['capturedAtUs'] and
                    f['nowUs'] == f['capturedAtUs'] + 2000, 'Retimed replay')
            require(f['sessionStarts'] == 1 and f['userMoving'] is True and f['delivery'] == 'shadow' and
                    f['arbiterActive'] is False and f['bodyUnknown'] == 0, 'Scope/authority drift')
            require(f['action'] == previous['action'], 'False-stop result changed')
            require(f['revision'] > f['previousRevision'] and
                    (not i or f['previousRevision'] == frames[i-1]['revision']), 'History reset')
        require(r['summary'][mode]['geometryUnknownPixels'] == [0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0], 'Geometric gap result drift')
        require(sum(f['action'] == 'stopNow' for f in frames) == r['summary'][mode]['stops'] == 10, 'Stop count drift')
    faults = r['initialClearFaultControls']
    require(len(faults) == len({(f['mode'], f['fault']) for f in faults}) == 22, 'Fault matrix incomplete')
    require(all(f['frame']['action'] == 'stopNow' and f['frame']['delivery'] == 'shadow' and
                f['frame']['arbiterActive'] is False for f in faults), 'Fault became safe/active')
    for f in faults:
        if f['fault'] in ('semantic', 'ttc', 'metricApproach'):
            require(any(a['reason'] == 'motion_or_semantic_priority' for a in f['frame']['associations']), 'Explicit risk lost priority')
    require(len(r['motionCases']) == 9, 'Motion corpus incomplete')
    samples = 0; hazards = 0
    for case, prior_case in zip(r['motionCases'], old['motionCases']):
        require(case['layoutId'] == prior_case['layoutId'] and case['knownRegression'] is True and
                len(case['frames']) == 7, 'Motion sequence drift')
        for f, before in zip(case['frames'], prior_case['frames']):
            require(f['frameId'] == before['frameId'] and f['capturedAtUs'] == before['capturedAtUs'] and
                    f['metricMotion'] == before['metricMotion'] and f['scoringOnly'] == before['scoringOnly'], 'Metric/label drift')
            hazard = f['scoringOnly']['physicalHazard'] is True; hazards += hazard
            for mode, value in f['relative'].items():
                require(value['tracks'] == before['relative'][mode]['tracks'] and
                        value['action'] == before['relative'][mode]['action'] and
                        value['rule'] == before['relative'][mode]['rule'] and value['delivery'] == 'shadow', 'Motion runtime/support drift')
                require(not hazard or value['action'] == 'stopNow', 'Hazard stop regressed')
                require({s['trackId'] for s in value['coverage']} == {t['id'] for t in value['tracks']}, 'Missing track diagnostic')
                for s in value['coverage']:
                    samples += 1
                    require(all(s[k] is False for k in ('completeVisibleSupport', 'wholeObjectStationarityCertified',
                                                      'mayResolveMotionPriority', 'freeSpaceCertified')), 'Negative motion authority')
                    if s['available']:
                        count = s['currentMatchedCentres']
                        require(0 <= count == s['previousMatchedCentres'] <= len(f['metricMotion']['patches']), 'Correspondence count inflation')
                        require(0 <= s['localMovingCentres'] <= count and
                                s['currentFootprintPixels'] >= count and s['previousFootprintPixels'] >= count, 'Coverage bounds drift')
                        require(s['currentCoverage'] == count / s['currentFootprintPixels'] and
                                s['previousCoverage'] == count / s['previousFootprintPixels'], 'Coverage fraction drift')
    require(hazards == 60 and samples == r['summary']['diagnosticTrackSamples'] == 256, 'Denominator drift')
    value = diagnosis()
    require(read(DIRECTORY / 'diagnosis.json') == value, 'Diagnosis drift')
    require(value['completeVisibleSamples'] == 0, 'Dense support unexpectedly established')
    return {'schemaVersion': 1, 'passed': True, 'promotionAllowed': False, 'ordinaryCameraWired': False,
        'candidateGate': value['candidateGate'], 'summary': r['summary'],
        'priorValidationSha256': sha(PRIOR / 'validation.json'),
        'sourceSha256': {p: sha(ROOT / p) for p in SOURCES},
        'artifactSha256': {p: sha(DIRECTORY / p) for p in ('replay.json', 'diagnosis.json',
          'optical/manifest.json', 'optical/selection.json', 'whole-track-evidence.png', 'whole-track-evidence.svg')},
        'hazardFramesPerMode': hazards, 'newIndependentHoldout': False, 'captureToCommandMeasured': False,
        'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run',
        'priorTimingGate': 'not_passed_4_of_21_expired'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--write', action='store_true')
    args = parser.parse_args(); value = build(); target = DIRECTORY / 'validation.json'
    if args.write:
        require(not target.exists(), 'Validation is immutable')
        target.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    else:
        require(read(target) == value, 'Source/output drift')
    print('Whole track evidence: reproducibility and safety passed; usefulness/promotion gate NOT passed')

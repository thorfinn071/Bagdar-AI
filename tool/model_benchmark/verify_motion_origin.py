"""Validate new experiment and unchanged upstream evidence without rewriting it."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

from render_motion_origin import diagnosis

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/motion-origin-2026-10-10'
CORPUS = ROOT / 'test/fixtures/spatial_safety/camera-scale-motion-v1'
SOURCES = [
    'docs/motion-origin-protocol-2026-10-10.md',
    'docs/motion-origin-evaluation-2026-10-10.md',
    'test/harness/motion_origin_experiment.dart', 'test/motion_origin_experiment_test.dart',
    'tool/model_benchmark/check_motion_origin.ps1',
    'tool/model_benchmark/render_motion_origin.py', 'tool/model_benchmark/verify_motion_origin.py',
    'lib/services/generic_obstacle_detector.dart',
    'lib/services/frame_stable_generic_obstacle_detector.dart',
    'lib/tracker/generic_obstacle_tracker.dart',
    'lib/safety/perception/camera_fast_metric_motion.dart',
    'lib/safety/perception/camera_fast_motion_types.dart',
    'lib/safety/perception/camera_track_association.dart',
    'lib/safety/runtime/confidence_authority_spatial_runtime.dart',
    'lib/safety/runtime/spatial_safety_runtime.dart',
    'lib/safety/world/generic_geometry_scene_adapter.dart',
    'lib/safety/world/local_scene_model.dart', 'lib/safety/world/scene_fusion_policy.dart',
    'lib/safety/planning/coverage_aware_stop_guidance.dart',
    'test/harness/sequence_first_return_fixture.dart',
    'test/harness/camera_visible_passage_fixture.dart',
    'tool/model_benchmark/fast_camera_motion_fixture.dart',
    'tool/model_benchmark/verify_scale_motion_assets.py',
    'assets/midas_small.ncnn.param', 'assets/midas_small.ncnn.bin',
]


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def build():
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_sequence_first_return.py'],
                   cwd=ROOT, check=True)
    subprocess.run([sys.executable, 'tool/model_benchmark/verify_scale_motion_assets.py'],
                   cwd=ROOT, check=True)
    r = read(DIRECTORY / 'replay.json')
    require(r['priorReplaySha256'] == sha(ROOT / 'scratch/sequence-first-return-2026-10-09/replay.json'), 'Prior replay drift')
    require(r['priorValidationSha256'] == sha(ROOT / 'scratch/sequence-first-return-2026-10-09/validation.json'), 'Prior validation drift')
    for key in ['promotionAllowed', 'ordinaryCameraWired', 'newIndependentHoldout',
                'newNeuralInference', 'captureToCommandMeasured']:
        require(r[key] is False, key)
    require(r['maximumAgeUs'] == 100000, 'Freshness changed')
    a, b = r['stationaryCounterfactual']
    require(a['uniqueSegmentations'] == 11 and a['positiveRelativeFrames'] == 5, 'Stateful causal result drift')
    require(b['uniqueSegmentations'] == 1 and b['positiveRelativeFrames'] == 0, 'Stable causal result drift')
    require(all(not x['runtimeUsed'] and x['calls'] == 11 for x in [a, b]), 'Counterfactual scope drift')
    selection = read(ROOT / 'scratch/sequence-first-return-2026-10-09/selection.json')
    for mode, frames in r['sequence'].items():
        require(len(frames) == 11, 'Incomplete continuous sequence')
        for i, f in enumerate(frames):
            require(f['frameId'] == i+1 and f['index'] == i, 'Order drift')
            require(f['capturedAtUs'] == selection['frames'][i]['capturedAtUs'], 'Capture drift')
            require(f['nowUs'] - f['capturedAtUs'] == 2000, 'Functional clock drift')
            require(f['sessionStarts'] == 1 and f['userMoving'] is True, 'History reset')
            require(f['delivery'] == 'shadow' and f['arbiterActive'] is False, 'Active authority')
            require(f['revision'] > f['previousRevision'], 'Revision failed')
            if i:
                require(f['previousRevision'] == frames[i-1]['revision'], 'Scene history discontinuity')
            selected = set(selection['frames'][i]['supportPixels'])
            pixels = f['allSupportPixels']
            require(pixels == sorted(set(pixels)), 'Incomplete/duplicate support')
            require(f['pixelsOutsidePriorSelection'] == len(set(pixels) - selected), 'Sparse coverage accounting drift')
        s = r['summary'][mode]
        require(s['stops'] == sum(f['action'] == 'stopNow' for f in frames) == 10, 'False-stop result drift')
        require(s['continues'] == 1 and s['motionPriorityFrames'] == 7, 'Candidate summary drift')
    faults = r['initialClearFaultControls']
    require(len(faults) == 22 and len({(f['mode'], f['fault']) for f in faults}) == 22, 'Fault matrix incomplete')
    for f in faults:
        frame = f['frame']
        require(frame['index'] == 0 and frame['action'] == 'stopNow', 'Initial-clear fault failed')
        require(frame['delivery'] == 'shadow' and frame['arbiterActive'] is False, 'Fault gained active authority')
        if f['fault'] in ('semantic', 'ttc', 'metricApproach'):
            require(any(a['reason'] == 'motion_or_semantic_priority' for a in frame['associations']), 'Explicit risk lost priority')
    baseline = read(ROOT / 'docs/_baseline_logs/camera_scale_motion.json')
    labels = {x['layoutId']: x for x in read(CORPUS / 'annotations.json')['layouts']}
    require(len(r['motionCases']) == 9, 'Missing motion case')
    hazard_frames = 0
    for case in r['motionCases']:
        expected = next(x for x in baseline['sequences'] if x['layoutId'] == case['layoutId'] and x['mode'] == 'scale-motion')
        frozen = {x['frameId']: x for x in expected['decisions']}
        annotations = {x['frameId']: x for x in labels[case['layoutId']]['frames']}
        require(case['knownRegression'] is True and len(case['frames']) == 7, 'Holdout claim/order drift')
        for f in case['frames']:
            require(f['metricMotion'] == frozen[f['frameId']]['scaleMotion'], 'Metric correspondence drift')
            require(f['scoringOnly'] == annotations[f['frameId']], 'Annotation drift')
            for key in ('motionSuppressed', 'freeSpaceCertified', 'objectStationarityCertified'):
                require(f[key] is False, 'Unsupported absence/clearance claim')
            if f['scoringOnly']['physicalHazard']:
                hazard_frames += 1
                require(all(v['action'] == 'stopNow' and v['delivery'] == 'shadow'
                            for v in f['relative'].values()), 'Hazard stop regressed')
    require(hazard_frames == 60, 'Hazard denominator drift')
    value = diagnosis()
    require(read(DIRECTORY / 'diagnosis.json') == value, 'Diagnosis drift')
    return {
        'schemaVersion': 1, 'passed': True, 'promotionAllowed': False,
        'ordinaryCameraWired': False, 'candidateGate': value['candidateGate'],
        'sourceSha256': {p: sha(ROOT / p) for p in SOURCES},
        'artifactSha256': {p: sha(DIRECTORY / p) for p in
                          ['replay.json', 'diagnosis.json', 'motion-origin.png', 'motion-origin.svg']},
        'knownCorpusSha256': sha(CORPUS / 'manifest.json'),
        'knownNeuralSha256': sha(CORPUS / 'ncnn/manifest.json'),
        'counterfactualCorpusSha256': sha(ROOT / 'test/fixtures/spatial_safety/camera-track-passage-v1/manifest.json'),
        'counterfactualNeuralSha256': sha(ROOT / 'test/fixtures/spatial_safety/camera-track-passage-v1/ncnn/manifest.json'),
        'scoringAnnotationsSha256': sha(CORPUS / 'annotations.json'),
        'frozenMetricReplaySha256': sha(ROOT / 'docs/_baseline_logs/camera_scale_motion.json'),
        'summary': r['summary'], 'hazardFramesPerMode': hazard_frames,
        'newIndependentHoldout': False, 'captureToCommandMeasured': False,
        'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run',
        'priorTimingGate': 'not_passed_4_of_21_expired',
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    value = build()
    path = DIRECTORY / 'validation.json'
    if args.write:
        require(not path.exists(), 'Validation is immutable')
        path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    else:
        require(read(path) == value, 'Source/output drift')
    print('Motion origin: reproducibility and safety checks passed; candidate usefulness gate NOT passed')

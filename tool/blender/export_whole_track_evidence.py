"""Extend frozen first-return bounds for the union of both real track supports."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_track_first_return import supplement
from generate_synchronized_rig import geometry_digest

PRIOR = ROOT / 'scratch/sequence-first-return-2026-10-09/optical'
MOTION = ROOT / 'scratch/motion-origin-2026-10-10'
CORPUS = ROOT / 'test/fixtures/spatial_safety/blender-paired-holdout-v1'
SOURCES = [
    'tool/blender/export_whole_track_evidence.py',
    'docs/whole-track-evidence-protocol-2026-10-10.md',
    'tool/blender/export_track_first_return.py',
    'tool/blender/pixel_exact_surface_envelope.py',
    'tool/blender/watertight_surface_projection.py',
    'tool/blender/generate_synchronized_rig.py',
    'tool/blender/generate_visible_passage_corpus.py',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def asset(packet, key, dtype='<f4'):
    desc = packet[key]; path = (PRIOR / desc['path']).resolve()
    assert path.is_relative_to(PRIOR) and sha(path) == desc['sha256'], path
    return np.frombuffer(gzip.decompress(path.read_bytes()), dtype=dtype).reshape(
        packet['height'], packet['width']).copy()


def run(output):
    if (output / 'manifest.json').exists():
        raise ValueError('Completed optical evidence is immutable')
    output.mkdir(parents=True, exist_ok=True)
    validation = read(MOTION / 'validation.json')
    for path, digest in validation['sourceSha256'].items():
        assert sha(ROOT / path) == digest, path
    assert sha(MOTION / 'replay.json') == validation['artifactSha256']['replay.json']
    replay = read(MOTION / 'replay.json'); prior = read(PRIOR / 'manifest.json')
    corpus = read(CORPUS / 'corpus-manifest.json')
    source = {p: sha(ROOT / p) for p in SOURCES}
    selection = {
        'priorReplaySha256': sha(MOTION / 'replay.json'),
        'priorValidationSha256': sha(MOTION / 'validation.json'),
        'priorOpticalManifestSha256': sha(PRIOR / 'manifest.json'),
        'sources': source,
        'frames': [
            {'frameId': a['frameId'], 'capturedAtUs': a['capturedAtUs'],
             'supportPixels': sorted(set(a['allSupportPixels']) | set(b['allSupportPixels']))}
            for a, b in zip(replay['sequence']['legacy'], replay['sequence']['frameStable'])],
    }
    selection_path = output / 'selection.json'
    if selection_path.exists():
        assert read(selection_path) == selection, 'Resume selection drift'
    else:
        save(selection_path, selection)
    sequence = next(s for s in corpus['sequences'] if s['sceneId'] == 'path-clear')
    blend = CORPUS / sequence['scene']['path']
    assert sha(blend) == sequence['scene']['sha256']
    records = []
    for packet_batch, selected in zip(prior['batches'], selection['frames']):
        folder = output / packet_batch['id']; folder.mkdir(exist_ok=True)
        checkpoint = folder / 'record.json'
        if checkpoint.exists():
            record = read(checkpoint)
            assert record['sources'] == source and record['selectionSha256'] == sha(selection_path)
            for k in ('surfaceZUpper', 'repairMask', 'proof'):
                assert sha(output / record[k]['path']) == record[k]['sha256']
            records.append(record); print('RESUME', record['frameId'], flush=True); continue
        started = time.perf_counter(); p = packet_batch['primary']
        assert p['frameId'] == selected['frameId'] and p['capturedAtUs'] == selected['capturedAtUs']
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        scene = bpy.context.scene; camera = scene.camera
        scene.frame_set(p['frameId']); bpy.context.view_layer.update()
        assert geometry_digest(scene) == packet_batch['sceneStateSha256']
        world = np.array(camera.matrix_world, dtype=float)
        assert np.array_equal(world[:3, :3] @ np.diag([1., -1., -1.]),
                              np.array(p['cameraToWalkingRotation']).reshape(3, 3))
        depth, lower, old_upper = [asset(p, k) for k in ('depth', 'freeZLower', 'surfaceZUpper')]
        valid = asset(p, 'validity', 'u1')
        support = np.zeros(depth.size, dtype='u1'); support[selected['supportPixels']] = 1
        arrays, proof, witnesses = supplement(scene, camera, p,
            [depth, lower, old_upper, valid & support.reshape(valid.shape)])
        upper, _, _, _, mask = arrays
        assert np.array_equal(upper[np.isfinite(old_upper)], old_upper[np.isfinite(old_upper)])
        descriptors = {}
        for key, value in [('surfaceZUpper', upper), ('repairMask', mask)]:
            path = folder / (key + '.gz'); path.write_bytes(gzip.compress(value.tobytes(), mtime=0))
            descriptors[key] = {'path': path.relative_to(output).as_posix(), 'sha256': sha(path)}
        path = folder / 'proof.json'; save(path, proof)
        descriptors['proof'] = {'path': path.relative_to(output).as_posix(), 'sha256': sha(path)}
        record = {'id': packet_batch['id'], 'frameId': p['frameId'],
            'capturedAtUs': p['capturedAtUs'], 'sessionGeneration': p['sessionGeneration'],
            'sceneStateSha256': packet_batch['sceneStateSha256'],
            'priorUpperSha256': p['surfaceZUpper']['sha256'],
            'selectionSha256': sha(selection_path), 'sources': source,
            'candidates': len(proof), 'certified': int(mask.sum()),
            'rayWitnesses': witnesses, 'elapsedSeconds': time.perf_counter() - started,
            **descriptors}
        save(checkpoint, record); records.append(record)
        print('WHOLE_TRACK', p['frameId'], len(proof), int(mask.sum()),
              round(record['elapsedSeconds'], 2), flush=True)
    save(output / 'manifest.json', {
        'schemaVersion': 1, 'promotionAllowed': False, 'ordinaryCameraWired': False,
        'newNeuralInference': False, 'sourceBlendSha256': sha(blend),
        'priorOpticalManifestSha256': sha(PRIOR / 'manifest.json'),
        'priorValidationSha256': sha(MOTION / 'validation.json'),
        'selectionSha256': sha(selection_path), 'sources': source, 'records': records,
    })


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--output', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    output = (ROOT / args.output).resolve()
    if not output.is_relative_to(ROOT / 'scratch'):
        raise ValueError('Output must remain within workspace scratch')
    run(output)

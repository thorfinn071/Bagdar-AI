"""Transfer frozen simultaneous optics to known paired scenes, write-once."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as optical
import visible_bounds_fast as primary_bounds
import visible_complete_surface_bounds as complete
from visible_exact_floor_height_bounds import floor_heights
from export_synchronized_rig_bundle_v2 import coherent_pixels
from generate_synchronized_rig import geometry_digest, witnesses
from scan_view_selection import choose_views

CASES = (
    ('clear-first', 'path-clear', 0, None, False),
    ('clear-final', 'path-clear', 10, None, False),
    ('box', 'path-box', 10, None, True),
    ('low-headroom', 'headroom-low', 10, None, True),
    ('drop', 'floor-drop', 10, None, True),
    ('thin-pole', 'path-clear', 10, 'thin', True),
    ('hidden-pole', 'path-clear', 10, 'hidden', True),
)
STAMP = 1791072000000000


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def pixel_sha(path):
    image = bpy.data.images.load(str(path), check_existing=False)
    pixels = np.empty(len(image.pixels), dtype='<f4')
    image.pixels.foreach_get(pixels)
    result = hashlib.sha256(pixels.tobytes()).hexdigest()
    bpy.data.images.remove(image)
    return result


def run(output, pilot):
    if (output / 'manifest.json').exists():
        raise ValueError('Completed corpus is immutable')
    output.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'test/fixtures/spatial_safety/blender-paired-holdout-v1'
    prior_root = ROOT / 'scratch/camera-view-coverage-2026-10-09/optical'
    corpus = json.loads((source / 'corpus-manifest.json').read_text())
    prior = json.loads((prior_root / 'manifest.json').read_text())
    paths = [Path(__file__), Path(optical.__file__), Path(primary_bounds.__file__),
             Path(complete.__file__), ROOT / 'tool/blender/visible_exact_floor_height_bounds.py',
             ROOT / 'tool/blender/export_synchronized_rig_bundle_v2.py',
             ROOT / 'tool/blender/generate_synchronized_rig.py', ROOT / 'tool/blender/scan_view_selection.py',
             ROOT / 'tool/blender/pixel_complete_surface_envelope.py',
             ROOT / 'tool/blender/pixel_exact_surface_envelope.py',
             ROOT / 'tool/blender/watertight_surface_projection.py',
             ROOT / 'docs/synchronized-passage-protocol-2026-10-09.md']
    sources = {p.relative_to(ROOT).as_posix(): sha(p) for p in paths}
    batches = []
    for case, scene_id, index, contrast, hazard in CASES[:2] if pilot else CASES:
        folder = output / case
        folder.mkdir(exist_ok=True)
        checkpoint = folder / 'batch.json'
        if checkpoint.exists():
            batch = json.loads(checkpoint.read_text())
            assert batch['exportSources'] == sources
            for p in [batch['primary'], *batch['channels']]:
                for key in ('rgb', 'depth', 'freeZLower', 'surfaceZUpper', 'validity',
                            'heightLower', 'heightUpper', 'firstZLower'):
                    if key in p:
                        assert sha(output / p[key]['path']) == p[key]['sha256']
            batches.append(batch)
            print('RESUME_BATCH', case, flush=True)
            continue
        sequence = next(s for s in corpus['sequences'] if s['sceneId'] == scene_id)
        blend = source / sequence['scene']['path']
        assert sha(blend) == sequence['scene']['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        scene, primary = bpy.context.scene, bpy.context.scene.camera
        scene.frame_set(index + 1)
        bpy.context.view_layer.update()
        horizontal = list(primary.location)[:2]
        if contrast:
            optical.cube('experiment-pole', (0., horizontal[1]+2.1, .95),
                         (.002, .002, .95), (.16, .18, .20))
            if contrast == 'hidden':
                optical.cube('experiment-opaque-occluder', (0., horizontal[1]+1.45, 1.),
                             (.60, .035, 1.), (.22, .26, .29))
        bpy.context.view_layer.update()
        state = geometry_digest(scene)

        def packet(camera, width, height, name, envelope):
            scene.camera = camera
            scene.render.resolution_x, scene.render.resolution_y = width, height
            scene.render.resolution_percentage = 100
            bpy.context.view_layer.update()
            assert geometry_digest(scene) == state
            proj = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),
                                             x=width, y=height, scale_x=1, scale_y=1)
            fx, fy, cx, cy = proj[0][0]*width/2, proj[1][1]*height/2, width/2, height/2
            world = np.array(camera.matrix_world, dtype=float)
            rotation = world[:3, :3] @ np.diag([1., -1., -1.])
            rgb = folder / f'{name}.png'
            scene.render.filepath = str(rgb)
            bpy.ops.render.render(write_still=True)
            p = {'cameraId': name, 'frameId': index+1, 'sessionGeneration': 1,
                 'capturedAtUs': STAMP + sequence['frames'][index]['capturedOffsetMs']*1000,
                 'width': width, 'height': height, 'fx': fx, 'fy': fy, 'cx': cx, 'cy': cy,
                 'cameraToWalkingRotation': rotation.ravel().tolist(),
                 'cameraOriginM': [0., 0., float(world[2, 3])], 'sceneStateSha256': state,
                 'rgb': {'path': rgb.relative_to(output).as_posix(), 'sha256': sha(rgb)}}
            if envelope:
                arrays = list(complete.visible_depth(scene, camera, fx, fy, cx, cy, width, height))
                arrays[4], arrays[5], changed = floor_heights(
                    scene, camera, fx, fy, cx, cy, arrays[0], arrays[4], arrays[5])
                candidates, certified = coherent_pixels(scene, camera, p, arrays)
                p.update(exactFloorPixels=changed, coherencePixels=candidates,
                         coherenceCertifiedPixels=certified)
                p['rayWitnesses'] = witnesses(scene, camera, p, arrays, 202610090+len(name))
                keys = ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower')
            else:
                arrays = primary_bounds.visible_depth(scene, camera, fx, fy, cx, cy, width, height)
                keys = ('depth', 'freeZLower', 'surfaceZUpper', 'validity')
            for key, array in zip(keys, arrays):
                target = folder / f'{name}-{key}.gz'
                target.write_bytes(gzip.compress(array.tobytes(), mtime=0))
                p[key] = {'path': target.relative_to(output).as_posix(), 'sha256': sha(target)}
            print('PASSAGE_PACKET', case, name, flush=True)
            return p

        primary_packet = packet(primary, 320, 240, 'primary', False)
        previous = next(p for p in prior['packets'] if p['caseId'] == case and p['viewId'] == 'original')
        primary_packet['rgbPixelSha256'] = pixel_sha(output/primary_packet['rgb']['path'])
        previous_pixels = pixel_sha(prior_root/previous['rgb']['path'])
        if primary_packet['rgbPixelSha256'] != previous_pixels:
            raise ValueError('Regenerated primary RGB pixel drift: ' + case)
        for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity'):
            assert primary_packet[key]['sha256'] == previous[key]['sha256'], (case, key)
        grid = choose_views(26/36*160, 26/36*160, 160, 120, primary.location.z)
        assert len(grid['poses']) == 12
        channels = []
        for channel, (yaw, pitch) in enumerate(grid['poses']):
            bpy.ops.object.camera_add(location=primary.location)
            camera = bpy.context.object
            camera.data.lens, camera.data.sensor_width = 26., 36.
            camera.data.sensor_fit = 'HORIZONTAL'
            camera.rotation_euler = optical.camera_rotation(yaw, pitch, 0.).to_euler()
            p = packet(camera, 160, 120, f'channel-{channel:02d}', True)
            p['yawDeg'], p['pitchDeg'] = yaw, pitch
            channels.append(p)
        batch = {'id': case, 'sceneId': scene_id, 'frameId': index+1, 'sessionGeneration': 1,
                 'capturedAtUs': primary_packet['capturedAtUs'], 'zeroSkewUs': 0,
                 'sceneStateSha256': state, 'sourceBlendSha256': sha(blend),
                 'stationarySyntheticScene': True, 'physicalHazard': hazard,
                 'contrast': contrast, 'originalFrameIndex': index, 'grid': grid,
                 'primary': primary_packet, 'channels': channels, 'exportSources': sources,
                 'priorPrimaryRgbSha256': previous['rgb']['sha256'],
                 'priorPrimaryRgbPixelSha256': previous_pixels}
        save(checkpoint, batch)
        batches.append(batch)
    result = {'schemaVersion': 1, 'promotionAllowed': False, 'runtimeWired': False,
              'corpusId': 'synchronized-paired-passage-2026-10-09', 'pilotOnly': pilot,
              'sources': sources, 'referenceFrameId': 'paired-local-walking-v1',
              'sourceCorpusSha256': sha(source/'corpus-manifest.json'),
              'priorViewManifestSha256': sha(prior_root/'manifest.json'),
              'blenderVersion': bpy.app.version_string, 'batches': batches}
    save(output / ('pilot.json' if pilot else 'manifest.json'), result)


if __name__ == '__main__':
    argv = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--pilot', action='store_true')
    args = parser.parse_args(argv)
    target = (ROOT/args.output).resolve()
    if not target.is_relative_to(ROOT/'scratch'):
        raise ValueError('Output must remain in scratch')
    run(target, args.pilot)

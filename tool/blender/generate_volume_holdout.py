"""Predeclared new scenes for the frozen volume-authority candidate."""
import gzip
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
from generate_scale_motion_corpus import texture
import visible_complete_surface_bounds as complete
from visible_exact_floor_height_bounds import floor_heights
from export_synchronized_rig_bundle_v2 import coherent_pixels
from generate_synchronized_rig import geometry_digest, witnesses
from scan_view_selection import choose_views

OUTPUT = ROOT / 'scratch/volume-holdout-2026-10-10'
CORPUS = OUTPUT / 'corpus'
OPTICS = OUTPUT / 'optical'
SPEC = ROOT / 'tool/blender/volume_holdout_spec_v1.json'
SOURCES = [
    'tool/blender/generate_volume_holdout.py', 'tool/blender/volume_holdout_spec_v1.json',
    'docs/volume-holdout-protocol-2026-10-10.md',
    'tool/blender/generate_visible_passage_corpus.py', 'tool/blender/generate_scale_motion_corpus.py',
    'tool/blender/visible_complete_surface_bounds.py', 'tool/blender/visible_exact_floor_height_bounds.py',
    'tool/blender/export_synchronized_rig_bundle_v2.py', 'tool/blender/generate_synchronized_rig.py',
    'tool/blender/scan_view_selection.py', 'tool/blender/pixel_complete_surface_envelope.py',
    'tool/blender/pixel_exact_surface_envelope.py', 'tool/blender/watertight_surface_projection.py',
]


def geometry_rows(scene):
    # Separate scoring side only; the consumer never receives these rows.
    rows = []
    for obj in scene.objects:
        if obj.type != 'MESH': continue
        points = np.array([list(obj.matrix_world @ Vector(v)) for v in obj.bound_box])
        rows.append({'name': obj.name, 'lowerM': points.min(axis=0).tolist(), 'upperM': points.max(axis=0).tolist(),
                     'velocityMps': list(obj.get('scoring_velocity', (0., 0., 0.)))})
    return sorted(rows, key=lambda v: v['name'])


def scene_setup(entry, case, spec):
    scene, primary, *_ = g.setup('covered-wide', 'test')
    primary.data.lens = 26.
    width, distance, top = entry['width'], entry['portalY'], entry['top']
    for name, sign in (('left', -1), ('right', 1)):
        bpy.data.objects[name].location.x = sign * (width / 2 + 1)
        bpy.data.objects[name].location.y = distance
    lintel = bpy.data.objects['lintel']
    lintel.location.y, lintel.location.z, lintel.scale.x = distance, top + .25, width / 2
    bpy.data.objects['back'].location.y = entry['backY']
    bpy.data.objects['floor'].location.y, bpy.data.objects['floor'].scale.y = 3.5, 4.5
    bpy.data.objects['ceiling'].location.y, bpy.data.objects['ceiling'].scale.y = 3.5, 4.5
    bpy.data.objects['ceiling'].location.z = 3.28
    for name in ('room-left', 'room-right'):
        bpy.data.objects[name].location.y, bpy.data.objects[name].scale.y = 3.5, 4.5
    kind = entry['kind']
    if kind == 'pole': g.cube('thin-pole', (.061, 2.31, .86), (.005, .005, .86), (.2, .3, .4))
    if kind == 'step': g.cube('floor-step', (.02, 1.91, .06), (.62, .19, .06), (.5, .3, .2))
    if kind == 'gap':
        bpy.data.objects.remove(bpy.data.objects['floor'], do_unlink=True)
        g.cube('near-floor', (0, .335, -.05), (4, 1.335, .05), (.3, .4, .3))
        g.cube('far-floor', (0, 5.015, -.05), (4, 2.985, .05), (.3, .4, .3))
        g.cube('lower-floor', (0, 1.85, -.29), (4, .18, .05), (.3, .4, .3))
    moving = None
    if kind in ('clear-side', 'occluded', 'approach', 'crossing'):
        moving = g.cube('actor', (0, 2.7, .72), (.20, .17, .72), (.3, .5, .4))
    if kind == 'occluded': g.cube('occluder', (.03, 1.37, .91), (.68, .09, .91), (.3, .3, .3))
    for obj in list(scene.objects):
        if obj.type == 'MESH':
            texture(obj, spec['seed'] + case * 1103 + sum(map(ord, obj.name)), plain=kind == 'clear-dim')
    scene.view_settings.view_transform, scene.view_settings.look = 'Standard', 'None'
    scene.view_settings.exposure = entry['exposure']
    views = []
    grid = choose_views(26 / 36 * 160, 26 / 36 * 160, 160, 120, spec['cameraHeightM'])
    assert len(grid['poses']) == 12
    for yaw, pitch in grid['poses']:
        bpy.ops.object.camera_add(location=(0, 0, spec['cameraHeightM']))
        camera = bpy.context.object
        camera.data.lens, camera.data.sensor_width, camera.data.sensor_fit = 26., 36., 'HORIZONTAL'
        camera.rotation_euler = g.camera_rotation(yaw, pitch, 0).to_euler()
        views.append(camera)
    return scene, primary, moving, views


def main():
    assert not (CORPUS / 'manifest.json').exists() and not (OPTICS / 'manifest.json').exists(), 'Completed holdout is immutable'
    freeze = json.loads((OUTPUT / 'preregistration.json').read_text())
    assert all(g.sha(ROOT / p) == h for p, h in freeze['frozenSourceSha256'].items()), 'Frozen runtime/source drift'
    sources = {p: g.sha(ROOT / p) for p in SOURCES}
    assert sources == freeze['generatorSourceSha256']
    spec = json.loads(SPEC.read_text())
    CORPUS.mkdir(parents=True, exist_ok=True); OPTICS.mkdir(parents=True, exist_ok=True)
    layouts, annotations, batches = [], [], []
    for case, entry in enumerate(spec['scenes']):
        identity, kind = entry['id'], entry['kind']
        scene, primary, moving, views = scene_setup(entry, case, spec)
        frames, scores = [], []
        for index in range(spec['framesPerLayout']):
            checkpoint = OPTICS / identity / str(index + 1) / 'batch.json'
            if checkpoint.exists():
                batch = json.loads(checkpoint.read_text()); assert batch['sources'] == sources
                for key in ('rgb', 'depth', 'freeZLower', 'surfaceZUpper', 'validity'):
                    item = batch['primaryOriginal'][key]
                    assert g.sha(CORPUS / item['path']) == item['sha256']
                for packet in batch['channels']:
                    for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'):
                        item = packet[key]; assert g.sha(OPTICS / item['path']) == item['sha256']
                frames.append(batch['primaryOriginal']); batches.append(batch)
                scores.append(json.loads((checkpoint.parent / 'scoring.json').read_text()))
                print('RESUME_HOLDOUT', batch['id'], flush=True); continue
            checkpoint.parent.mkdir(parents=True, exist_ok=True)
            offset, yaw, pitch, roll = [0., index * .009, 0.], -.6, -7., .4
            if kind == 'clear-forward': offset[1], yaw = index * .038, -.7 + index * .4
            if kind == 'clear-yaw': yaw = -4.3 + index * 1.65
            if kind == 'clear-dim': yaw, pitch, roll = 1.8, -9., -1.2
            if kind in ('crossing', 'occluded'): offset[0] = index * .012
            if kind == 'approach': offset[1] = index * .012
            if moving:
                if kind == 'clear-side': moving.location.x, moving.location.y = 1.08 + index * .07, 2.69
                if kind in ('crossing', 'occluded'): moving.location.x, moving.location.y = 1.36 - index * .235, 2.73
                if kind == 'approach': moving.location.x, moving.location.y = .04, 4.25 - index * .22
                moving['scoring_velocity'] = (.35, 0., 0.) if kind == 'clear-side' else ((0., -1.1, 0.) if kind == 'approach' else (-1.175, 0., 0.))
            primary.location = [offset[0], offset[1], spec['cameraHeightM']]
            primary.rotation_euler = g.camera_rotation(yaw, pitch, roll).to_euler()
            scene.camera = primary; scene.render.resolution_x, scene.render.resolution_y = g.W, g.H
            bpy.context.view_layer.update()
            projection = primary.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=g.W, y=g.H, scale_x=1, scale_y=1)
            fx, fy = projection[0][0] * g.W / 2, projection[1][1] * g.H / 2
            cx, cy = (1 - projection[0][2]) * g.W / 2, (1 + projection[1][2]) * g.H / 2
            folder = CORPUS / identity; folder.mkdir(exist_ok=True)
            prefix = f'{identity}/{index}'
            rgb = CORPUS / f'{prefix}-rgb.png'; scene.render.filepath = str(rgb)
            bpy.ops.render.render(write_still=True)
            arrays = g.visible_depth(scene, primary, fx, fy, cx, cy)
            meta = {'frameId': index + 1, 'capturedOffsetUs': spec['capturedOffsetBaseUs'] + case * 2000000 + index * spec['intervalUs'],
                    'width': g.W, 'height': g.H, 'fx': fx, 'fy': fy, 'cx': cx, 'cy': cy,
                    'cameraToWalkingRotation': (np.array(primary.matrix_world)[:3, :3] @ np.diag([1., -1., -1.])).ravel().tolist(),
                    'cameraOriginM': [0., 0., float(primary.location.z)], 'walkingOriginWorldM': offset,
                    'poseProviderId': 'synthetic-original-capture-pose', 'poseRevision': 'translation-fixed-heading-v1',
                    'posePositionErrorM': .0001, 'poseQuality': 1., 'pitchDeg': -pitch, 'yawDeg': yaw, 'rollDeg': roll,
                    'rgb': {'path': f'{prefix}-rgb.png', 'sha256': g.sha(rgb)}}
            for key, array in zip(('depth', 'freeZLower', 'surfaceZUpper', 'validity'), arrays):
                meta[key] = g.asset(CORPUS, f'{prefix}-{key}.gz', array.tobytes())
            state = geometry_digest(scene); geometry = geometry_rows(scene); packets = []
            for channel, camera in enumerate(views):
                camera.location = primary.location; scene.camera = camera
                scene.render.resolution_x, scene.render.resolution_y = 160, 120
                bpy.context.view_layer.update(); assert geometry_digest(scene) == state
                projection = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=160, y=120, scale_x=1, scale_y=1)
                packet = {'cameraId': f'channel-{channel:02d}', 'frameId': index + 1, 'sessionGeneration': 1,
                          'capturedAtUs': 1790899200000000 + meta['capturedOffsetUs'], 'sceneStateSha256': state,
                          'width': 160, 'height': 120, 'fx': projection[0][0] * 80, 'fy': projection[1][1] * 60,
                          'cx': 80., 'cy': 60., 'cameraOriginM': meta['cameraOriginM'],
                          'cameraToWalkingRotation': (np.array(camera.matrix_world)[:3, :3] @ np.diag([1., -1., -1.])).ravel().tolist()}
                values = list(complete.visible_depth(scene, camera, packet['fx'], packet['fy'], 80, 60, 160, 120))
                values[4], values[5], _ = floor_heights(scene, camera, packet['fx'], packet['fy'], 80, 60, values[0], values[4], values[5])
                coherent_pixels(scene, camera, packet, values)
                packet['rayWitnesses'] = witnesses(scene, camera, packet, values, spec['seed'] + case * 1009 + index * 31 + channel)
                for key, array in zip(('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'), values):
                    path = checkpoint.parent / f'{channel:02d}-{key}.gz'
                    path.write_bytes(gzip.compress(array.tobytes(), mtime=0))
                    packet[key] = {'path': path.relative_to(OPTICS).as_posix(), 'sha256': g.sha(path)}
                packets.append(packet)
            scene.camera = primary; scene.render.resolution_x, scene.render.resolution_y = g.W, g.H
            bpy.context.view_layer.update()
            reproduced = g.visible_depth(scene, primary, fx, fy, cx, cy)
            assert all(a.tobytes() == b.tobytes() for a, b in zip(arrays, reproduced)), 'Primary capture drift'
            # Ground truth is exported to a separate file, never to optical/RGB metadata.
            lo = np.array([offset[0] - .45, offset[1] + .2, .05]); hi = np.array([offset[0] + .45, offset[1] + 3.5, 1.8])
            blockers = [v['name'] for v in geometry if np.all(np.array(v['upperM']) > lo + 1e-6) and np.all(np.array(v['lowerM']) < hi - 1e-6)]
            score = {'frameId': index + 1, 'physicalHazard': bool(blockers) or kind == 'gap',
                     'blockers': blockers, 'floorDiscontinuity': kind == 'gap', 'geometry': geometry,
                     'walkingOriginWorldM': offset, 'originVelocityMps': [(.06 if kind in ('crossing', 'occluded') else 0.), (.19 if kind == 'clear-forward' else .06 if kind == 'approach' else .045), 0.]}
            batch = {'id': f'{identity}/{index + 1}', 'layoutId': identity, 'frameId': index + 1, 'sessionGeneration': 1,
                     'capturedAtUs': 1790899200000000 + meta['capturedOffsetUs'], 'sceneStateSha256': state,
                     'stationarySyntheticScene': True, 'zeroSkewUs': 0, 'scope': 'one instantaneous state; no inter-frame stationarity authority',
                     'primaryArraysReproduced': True, 'primaryOriginal': meta, 'sources': sources, 'channels': packets}
            g.save_json(checkpoint.parent / 'scoring.json', score); g.save_json(checkpoint, batch)
            frames.append(meta); scores.append(score); batches.append(batch)
            print('HOLDOUT_CAPTURE', batch['id'], flush=True)
        layouts.append({'id': identity, 'split': 'holdout', 'frames': frames})
        annotations.append({'layoutId': identity, 'frames': scores})
    g.save_json(CORPUS / 'manifest.json', {'schemaVersion': 1, 'corpusId': 'volume-holdout-2026-10-10', 'sources': sources,
                'preregistrationSha256': g.sha(OUTPUT / 'preregistration.json'), 'layouts': layouts,
                'promotionAllowed': False, 'blenderVersion': bpy.app.version_string})
    g.save_json(CORPUS / 'annotations.json', {'schemaVersion': 1, 'scope': 'scoring only after decisions', 'layouts': annotations})
    g.save_json(OPTICS / 'manifest.json', {'schemaVersion': 1, 'sources': sources, 'batches': batches,
                'priorCorpusSha256': g.sha(CORPUS / 'manifest.json'), 'preregistrationSha256': g.sha(OUTPUT / 'preregistration.json'),
                'promotionAllowed': False, 'ordinaryCameraWired': False})


if __name__ == '__main__': main()

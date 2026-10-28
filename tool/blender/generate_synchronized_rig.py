"""New simultaneous-state optical corpus; never retimestamps prior exports."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as optical
import visible_complete_surface_bounds as renderer
from visible_exact_floor_height_bounds import floor_heights
from scan_view_selection import choose_views

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / 'tool/blender/synchronized_rig_spec_v1.json'
SOURCES = [
    'tool/blender/generate_synchronized_rig.py', 'tool/blender/synchronized_rig_spec_v1.json',
    'tool/blender/scan_view_selection.py', 'tool/blender/generate_visible_passage_corpus.py',
    'tool/blender/visible_complete_surface_bounds.py', 'tool/blender/pixel_complete_surface_envelope.py',
    'tool/blender/visible_exact_floor_height_bounds.py', 'tool/blender/pixel_exact_surface_envelope.py',
    'tool/blender/watertight_surface_projection.py',
    'docs/blender-synchronized-rig-protocol-2026-10-04.md',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def geometry_digest(scene):
    rows = []
    for obj in sorted(scene.objects, key=lambda o: o.name):
        if obj.type == 'MESH':
            rows.append([obj.name, [list(r) for r in obj.matrix_world],
                         [list(v.co) for v in obj.data.vertices]])
    return hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()


def setup(entry, spec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    engines = scene.bl_rna.properties['render'].fixed_type.properties['engine'].enum_items.keys()
    scene.render.engine = 'BLENDER_EEVEE' if 'BLENDER_EEVEE' in engines else 'BLENDER_EEVEE_NEXT'
    scene.render.resolution_x, scene.render.resolution_y = spec['width'], spec['height']
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGB'
    scene.render.fps = 25
    scene.world = bpy.data.worlds.new('rig-world')
    scene.world.color = (.18, .18, .18)
    scene.view_settings.view_transform = 'Standard'
    bpy.ops.object.light_add(type='AREA', location=(.6, 2.4, 3.05))
    bpy.context.object.data.energy, bpy.context.object.data.size = 650, 3
    cube = optical.cube
    kind = entry['kind']
    # Entirely new room, dimensions and obstacle positions. Shared members of
    # each pair differ only in the stated physical obstacle.
    if kind == 'drop':
        cube('near-floor', (0, .74, -.065), (3.6, 1.74, .065), (.37, .39, .34))
        cube('lower-floor', (0, 4.64, -.335), (3.6, 2.16, .065), (.37, .39, .34))
    else:
        cube('floor', (0, 2.9, -.065), (3.6, 3.9, .065), (.37, .39, .34))
    cube('ceiling', (0, 2.9, 3.27), (3.6, 3.9, .07), (.61, .65, .58))
    cube('left-room', (-3.67, 2.9, 1.6), (.07, 3.9, 1.6), (.47, .44, .40))
    cube('right-room', (3.67, 2.9, 1.6), (.07, 3.9, 1.6), (.47, .44, .40))
    cube('back-room', (0, 6.87, 1.6), (3.6, .07, 1.6), (.47, .44, .40))
    # Off-corridor landmarks and shallow visible joints in both pair members.
    cube('side-cabinet', (-1.65, 4.3, .65), (.43, .36, .65), (.27, .32, .40))
    for i, y in enumerate((.88, 1.76, 3.72, 4.6)):
        z = -.27 if kind == 'drop' and y > 2.48 else 0
        cube(f'joint-{i}', (0, y, z + .0004), (3.6, .004, .0004), (.26, .28, .23))
    if kind == 'box':
        cube('obstacle', (.07, 2.17, .22), (.29, .195, .22), (.50, .30, .16))
    if kind in ('high', 'low'):
        width, top, y = 1.64, (2.25 if kind == 'high' else 1.45), 2.73
        for sign in (-1, 1):
            cube(f'portal-{sign}', (sign * (width / 2 + 1.39), y, 1.6), (1.39, .115, 1.6), (.43, .50, .52))
        cube('portal-lintel', (0, y, (top + 3.2) / 2), (width / 2, .115, (3.2 - top) / 2), (.43, .50, .52))
    if kind == 'moving':
        obj = cube('moving-obstacle', (.95, 2.05, .78), (.16, .12, .78), (.32, .25, .52))
        obj.keyframe_insert(data_path='location', frame=1)
        obj.location.x = 0
        obj.keyframe_insert(data_path='location', frame=2)
    scene.frame_set(entry.get('frame', 1))
    return scene


def witnesses(scene, camera, packet, arrays, seed):
    depth, lower, upper, valid, hlo, hhi, first = arrays
    h, w = depth.shape
    rng = np.random.default_rng(seed)
    pixels = [(0, 0), (h - 1, w - 1), (h // 2, w // 2)]
    pixels += [(int(y), int(x)) for y, x in zip(rng.integers(0, h, 24), rng.integers(0, w, 24))]
    deps = bpy.context.evaluated_depsgraph_get()
    count = 0
    for y, x in pixels:
        if not valid[y, x]:
            continue
        for du, dv in ((.5, .5), (.001, .001), (.999, .001), (.001, .999), (.999, .999)):
            ray = Vector(((x + du - packet['cx']) / packet['fx'],
                          -(y + dv - packet['cy']) / packet['fy'], -1)).normalized()
            hit, point, *_ = scene.ray_cast(deps, camera.location,
                 camera.matrix_world.to_quaternion() @ ray, distance=100)
            if not hit:
                assert not np.isfinite(upper[y, x]), (packet['cameraId'], y, x)
                continue
            z = -(camera.matrix_world.inverted() @ point).z
            assert lower[y, x] <= z + 2e-4
            if np.isfinite(upper[y, x]):
                assert z <= upper[y, x] + 2e-4
            if np.isfinite(first[y, x]):
                assert first[y, x] <= z + 2e-4
            if np.isfinite(hlo[y, x]) and np.isfinite(hhi[y, x]):
                assert hlo[y, x] <= point.z + 2e-4 and point.z <= hhi[y, x] + 2e-4
            if du == .5 and dv == .5:
                assert abs((point - camera.location).length - depth[y, x]) < 2e-4
            count += 1
    return count


def generate(output):
    if (output / 'manifest.json').exists():
        raise ValueError('Completed corpus is immutable')
    spec = json.loads(SPEC.read_text())
    sources = {p: sha(ROOT / p) for p in SOURCES}
    w, h = spec['width'], spec['height']
    fx = fy = spec['lensMm'] / spec['sensorWidthMm'] * w
    grid = choose_views(fx, fy, w, h, spec['originM'][2])
    single = min(range(len(grid['poses'])), key=lambda i: grid['poses'][i][0]**2 + (grid['poses'][i][1]+12)**2)
    output.mkdir(parents=True, exist_ok=True)
    batches, labels = [], []
    bpy.context.preferences.filepaths.save_version = 0
    for entry in spec['scenes']:
        sid = entry['id']
        checkpoint = output / sid / 'batch.json'
        folder = checkpoint.parent
        folder.mkdir(parents=True, exist_ok=True)
        identity = hashlib.sha256(json.dumps({'sources': sources, 'entry': entry, 'grid': grid}, sort_keys=True).encode()).hexdigest()
        if checkpoint.exists():
            cached = json.loads(checkpoint.read_text())
            assert cached['identity'] == identity
            batch = cached['batch']
            for packet in batch['channels']:
                for key in ('rgb', 'depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'):
                    assert sha(output / packet[key]['path']) == packet[key]['sha256']
            assert sha(output / batch['scene']['path']) == batch['scene']['sha256']
        else:
            scene = setup(entry, spec)
            cameras = []
            for i, pose in enumerate(grid['poses']):
                bpy.ops.object.camera_add(location=spec['originM'])
                camera = bpy.context.object
                camera.name = f'optical-channel-{i:02d}'
                camera.data.lens, camera.data.sensor_width = spec['lensMm'], spec['sensorWidthMm']
                camera.data.sensor_fit = 'HORIZONTAL'
                camera.rotation_euler = optical.camera_rotation(*pose, 0).to_euler()
                cameras.append(camera)
            bpy.context.view_layer.update()
            state = geometry_digest(scene)
            packets = []
            for i, camera in enumerate(cameras):
                scene.camera = camera
                bpy.context.view_layer.update()
                assert geometry_digest(scene) == state
                rgb = folder / f'channel-{i:02d}.png'
                scene.render.filepath = str(rgb)
                bpy.ops.render.render(write_still=True)
                rotation = np.array(camera.matrix_world, dtype=float)[:3, :3] @ np.diag([1., -1., -1.])
                packet = {'cameraId': camera.name, 'frameId': entry.get('frame', 1),
                    'capturedAtUs': spec['captureEpochUs'] + entry.get('offsetUs', 0),
                    'sessionGeneration': 1, 'width': w, 'height': h, 'fx': fx, 'fy': fy,
                    'cx': w / 2, 'cy': h / 2, 'cameraToWalkingRotation': rotation.flatten().tolist(),
                    'cameraOriginM': list(camera.location), 'sceneStateSha256': state,
                    'rgb': {'path': rgb.relative_to(output).as_posix(), 'sha256': sha(rgb)}}
                arrays = list(renderer.visible_depth(scene, camera, fx, fy, w/2, h/2, w, h))
                arrays[4], arrays[5], changed = floor_heights(scene, camera, fx, fy, w/2, h/2, arrays[0], arrays[4], arrays[5])
                packet['rayWitnesses'] = witnesses(scene, camera, packet, arrays, spec['seed'] + i)
                packet['exactFloorPixels'] = changed
                for key, array in zip(('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'), arrays):
                    target = folder / f'channel-{i:02d}-{key}.gz'
                    target.write_bytes(gzip.compress(array.tobytes(), mtime=0))
                    packet[key] = {'path': target.relative_to(output).as_posix(), 'sha256': sha(target)}
                assert geometry_digest(scene) == state and scene.frame_current == entry.get('frame', 1)
                packets.append(packet)
                print('SYNC_PACKET', sid, i, packet['rayWitnesses'], flush=True)
            target = folder / 'scene.blend'
            bpy.ops.wm.save_as_mainfile(filepath=str(target))
            batch = {'id': sid, 'frameId': entry.get('frame', 1), 'sessionGeneration': 1,
                     'capturedAtUs': spec['captureEpochUs'] + entry.get('offsetUs', 0),
                     'stationarySyntheticScene': not entry['dynamic'], 'zeroSkewUs': 0,
                     'sceneStateSha256': state, 'channels': packets,
                     'scene': {'path': target.relative_to(output).as_posix(), 'sha256': sha(target)}}
            save(checkpoint, {'identity': identity, 'batch': batch})
        batches.append(batch)
        labels.append({'id': sid, 'physicalHazardAtCapture': entry['hazard'], 'dynamic': entry['dynamic']})
    labelpath = output / 'scoring-labels.json'
    save(labelpath, {'labels': labels, 'consumerInput': False})
    assert all(sha(ROOT / p) == digest for p, digest in sources.items())
    save(output / 'manifest.json', {'schemaVersion': 1, 'corpusId': 'blender-synchronized-rig-v1',
         'promotionAllowed': False, 'runtimeWired': False, 'rigPhysicalRealization': 'not_established',
         'sources': sources, 'grid': grid, 'singleChannelIndex': single,
         'timestampDomain': 'utcEpochMicroseconds', 'referenceFrameId': 'synthetic-rig-walking-v1',
         'labels': {'path': labelpath.name, 'sha256': sha(labelpath)}, 'batches': batches,
         'blenderVersion': bpy.app.version_string})
    print('SYNC_CORPUS_COMPLETE', len(batches), len(grid['poses']), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    generate(args.output.resolve())

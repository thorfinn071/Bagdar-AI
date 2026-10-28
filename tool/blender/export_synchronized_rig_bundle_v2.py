"""Coherent new version; immutable v1 scene/capture/payloads remain preserved."""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sys

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_synchronized_rig import ROOT, geometry_digest, sha, save, witnesses
from watertight_surface_projection import clip_near
from pixel_exact_surface_envelope import first_return_bounds

PRIOR = ROOT / 'test/fixtures/spatial_safety/blender-synchronized-rig-v1'
OUTPUT = ROOT / 'test/fixtures/spatial_safety/blender-synchronized-rig-v2'


def coherent_pixels(scene, camera, p, arrays):
    radial, axis_lo, upper, valid, hlo, hhi, first = arrays
    selected = np.isfinite(hlo) & np.isfinite(hhi) & ~np.isfinite(first)
    candidates = {(int(y), int(x)): [] for y, x in np.argwhere(selected)}
    fx, fy, cx, cy = (p[k] for k in ('fx', 'fy', 'cx', 'cy'))
    rotation = np.array(p['cameraToWalkingRotation']).reshape(3, 3)
    hc = (rotation[2, 0]/fx, rotation[2, 1]/fy,
          rotation[2, 2]-rotation[2, 0]*cx/fx-rotation[2, 1]*cy/fy)
    inv = camera.matrix_world.inverted()
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type != 'MESH': continue
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        points = []
        for vertex in mesh.vertices:
            pt = inv @ (evaluated.matrix_world @ vertex.co)
            points.append((pt.x, -pt.y, -pt.z))
        for triangle in mesh.loop_triangles:
            poly = clip_near([points[i] for i in triangle.vertices])
            for k in range(1, len(poly)-1):
                t = np.array([poly[0], poly[k], poly[k+1]])
                screen = t[:, :2]/t[:, 2, None]*[fx, fy]+[cx, cy]
                try: coef = np.linalg.solve(np.column_stack((screen, np.ones(3))), 1/t[:, 2])
                except np.linalg.LinAlgError: continue
                # No broad-phase exclusion: tiny seams still enter exact proof.
                for (y, x), patches in candidates.items():
                    if screen[:,0].max() >= x and screen[:,0].min() <= x+1 and screen[:,1].max() >= y and screen[:,1].min() <= y+1:
                        patches.append((screen.tolist(), coef.tolist()))
        evaluated.to_mesh_clear()
    certified = 0
    for (y, x), patches in candidates.items():
        zhi, lo, hi, zlo = map(float, first_return_bounds(x, y, patches, hc, p['cameraOriginM'][2]))
        if all(np.isfinite(v) for v in (zhi, lo, hi, zlo)):
            upper[y,x], hlo[y,x], hhi[y,x], first[y,x] = zhi+1e-5, lo-1e-5, hi+1e-5, max(0, zlo-1e-5)
            certified += 1
        else:
            upper[y,x] = hlo[y,x] = hhi[y,x] = first[y,x] = np.nan
    return len(candidates), certified


def main():
    if (OUTPUT/'manifest.json').exists(): raise ValueError('Completed v2 corpus is immutable')
    manifest = json.loads((PRIOR/'manifest.json').read_text())
    sources = dict(manifest['sources'])
    for name in ('tool/blender/export_synchronized_rig_bundle_v2.py',
                 'docs/blender-synchronized-rig-bundle-protocol-2026-10-04.md'):
        sources[name] = sha(ROOT/name)
    assert all(sha(ROOT/p) == digest for p, digest in sources.items())
    OUTPUT.mkdir(parents=True, exist_ok=True)
    batches = []
    for original in manifest['batches']:
        batch = json.loads(json.dumps(original))
        scene_asset = batch['scene']
        assert sha(PRIOR/scene_asset['path']) == scene_asset['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(PRIOR/scene_asset['path']))
        scene = bpy.context.scene
        scene.frame_set(batch['frameId'])
        bpy.context.view_layer.update()
        assert geometry_digest(scene) == batch['sceneStateSha256']
        target = OUTPUT/scene_asset['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PRIOR/scene_asset['path'], target)
        for packet in batch['channels']:
            camera = scene.objects[packet['cameraId']]
            arrays = []
            for key in ('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'):
                descriptor = packet[key]
                assert sha(PRIOR/descriptor['path']) == descriptor['sha256']
                arrays.append(np.frombuffer(gzip.decompress((PRIOR/descriptor['path']).read_bytes()),
                    dtype='u1' if key=='validity' else '<f4').reshape(packet['height'], packet['width']).copy())
            total, certified = coherent_pixels(scene, camera, packet, arrays)
            packet['coherencePixels'] = total
            packet['coherenceCertifiedPixels'] = certified
            packet['rayWitnesses'] = witnesses(scene, camera, packet, arrays, 202610041+int(packet['cameraId'][-2:]))
            for key, array in zip(('depth', 'freeZLower', 'surfaceZUpper', 'validity', 'heightLower', 'heightUpper', 'firstZLower'), arrays):
                descriptor = packet[key]
                target = OUTPUT/descriptor['path']
                target.write_bytes(gzip.compress(array.tobytes(), mtime=0))
                descriptor['sha256'] = sha(target)
                if key in ('depth', 'freeZLower', 'validity'):
                    assert sha(target) == sha(PRIOR/descriptor['path'])
            descriptor = packet['rgb']
            assert sha(PRIOR/descriptor['path']) == descriptor['sha256']
            shutil.copyfile(PRIOR/descriptor['path'], OUTPUT/descriptor['path'])
            print('COHERENT_PACKET', batch['id'], packet['cameraId'], total, certified, flush=True)
        batches.append(batch)
    shutil.copyfile(PRIOR/manifest['labels']['path'], OUTPUT/manifest['labels']['path'])
    manifest.update(corpusId='blender-synchronized-rig-v2', sources=sources, batches=batches,
                    priorManifestSha256=sha(PRIOR/'manifest.json'),
                    bundleRepair='exact first-return partition; unknown on any incomplete bundle')
    assert all(sha(ROOT/p) == digest for p, digest in sources.items())
    save(OUTPUT/'manifest.json', manifest)
    print('COHERENT_RIG_COMPLETE', len(batches), flush=True)


if __name__ == '__main__': main()

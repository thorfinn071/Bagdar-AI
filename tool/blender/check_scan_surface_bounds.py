"""Renderer correctness contrasts before exporting the regression scans."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import visible_bounds_fast as frozen
import visible_bounds_union as candidate
from scan_view_selection import choose_views

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def render(scene, camera, w, h, renderer=candidate):
    bpy.context.view_layer.update()
    p = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=w, y=h, scale_x=1, scale_y=1)
    fx, fy = p[0][0]*w/2, p[1][1]*h/2
    return renderer.visible_depth(scene, camera, fx, fy, w/2, h/2, w, h), (fx, fy)


def main():
    records = []
    corpus = ROOT / 'test/fixtures/spatial_safety/blender-paired-holdout-v1'
    manifest = json.loads((corpus/'corpus-manifest.json').read_text())
    row = next(s for s in manifest['sequences'] if s['sceneId'] == 'path-clear')
    bpy.ops.wm.open_mainfile(filepath=str(corpus/row['scene']['path']))
    scene, camera = bpy.context.scene, bpy.context.scene.camera
    scene.frame_set(11)
    camera.rotation_euler = g.camera_rotation(0, -65, 0).to_euler()
    original, _ = render(scene, camera, 320, 240, frozen)
    current, optics = render(scene, camera, 320, 240)
    assert all(a.tobytes() == b.tobytes() for a,b in zip(original, current) if a is not original[2])
    additions = int((~np.isfinite(original[2]) & np.isfinite(current[2])).sum())
    assert additions > 0
    grid = choose_views(*optics, 320, 240, camera.location.z)
    assert len(grid['poses']) == 12
    records.append({'case': 'shallow-seams', 'rangeLowerValidityExact': True,
                    'newBoundedPixels': additions, 'grid': grid})
    # Subpixel thin foreground must still change whole-pixel lower bounds.
    scene, camera, *_ = g.setup('wide', 'validation')
    camera.rotation_euler = g.camera_rotation(0, -8, 0).to_euler()
    before, optics = render(scene, camera, 96, 72)
    g.cube('between-rays', (0,1.4,1.45), (.0005,.0005,.4), (.2,.2,.2))
    thin, _ = render(scene, camera, 96, 72)
    assert np.any((thin[1] < before[1]-.1) & (abs(thin[0]-before[0]) < 1e-4))
    records.append({'case': 'subpixel-foreground', 'passed': True})
    # Ray witnesses check analytic bounds inside pixels, not just their centres.
    deps = bpy.context.evaluated_depsgraph_get()
    samples = 0
    for y in range(5, 72, 11):
        for x in range(5, 96, 13):
            for u,v in ((.001,.001),(.999,.001),(.001,.999),(.999,.999),(.5,.5)):
                ray = Vector(((x+u-48)/optics[0], -(y+v-36)/optics[1], -1))
                direction = camera.matrix_world.to_quaternion() @ ray
                hit, point, *_ = scene.ray_cast(deps, camera.location, direction.normalized(), distance=100)
                if not hit:
                    assert not np.isfinite(thin[2][y,x])
                    continue
                local = camera.matrix_world.inverted() @ point
                axis = -local.z
                assert not np.isfinite(thin[1][y,x]) or thin[1][y,x] <= axis+2e-5
                assert not np.isfinite(thin[2][y,x]) or thin[2][y,x] >= axis-2e-5
                samples += 1
    records.append({'case': 'noncentral-ray-witnesses', 'boundedWitnesses': samples})
    g.cube('cover', (0,1.2,1.5), (8,.1,5), (.2,.2,.2))
    before, _ = render(scene, camera, 96, 72)
    g.cube('hidden', (0,2.2,1), (.2,.1,.5), (.5,.1,.1))
    after, _ = render(scene, camera, 96, 72)
    assert all(a.tobytes() == b.tobytes() for a,b in zip(before, after))
    records.append({'case': 'hidden-geometry-invariance', 'bitExact': True})
    # Two overlapping coplanar patches sum to >1 pixel area but leave a hole.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.object.camera_add(location=(0,0,0))
    camera = bpy.context.object
    scene.camera = camera
    bpy.context.view_layer.update()
    p = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=48, y=36, scale_x=1, scale_y=1)
    fx, fy = p[0][0]*24, p[1][1]*18
    for index,(a,b) in enumerate(((0,.7),(.1,.8))):
        corners = [(24+a,18),(24+b,18),(24+b,19),(24+a,19)]
        verts = [((u-24)*2/fx, -(v-18)*2/fy, -2) for u,v in corners]
        mesh = bpy.data.meshes.new('patch')
        mesh.from_pydata(verts, [], [(0,1,2),(0,2,3)])
        obj = bpy.data.objects.new(f'patch-{index}', mesh)
        scene.collection.objects.link(obj)
    output, _ = render(scene, camera, 48, 36)
    assert output[3][18,24] == 1 and np.isnan(output[2][18,24])
    records.append({'case': 'overlapping-coplanar-hole', 'passed': True})
    sources = ['tool/blender/check_scan_surface_bounds.py', 'tool/blender/visible_bounds_union.py',
               'tool/blender/pixel_surface_envelope.py', 'tool/blender/scan_view_selection.py',
               'tool/blender/visible_bounds_fast.py']
    receipt = {'passed': True, 'promotionAllowed': False, 'sources': {p:sha(ROOT/p) for p in sources}, 'cases': records}
    target = ROOT/'docs/_baseline_logs/blender_scan_surface_bounds_v1.json'
    if target.exists():
        raise ValueError('Renderer receipt is write-once')
    target.write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(receipt), flush=True)


if __name__ == '__main__':
    main()

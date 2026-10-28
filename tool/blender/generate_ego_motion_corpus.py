"""New capture-local RGB/first-return sequences, with bound walking poses.

Annotations are exported separately and never used by motion consumers.
"""
import argparse
import sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
from generate_scale_motion_corpus import texture

CASES = ('camera-forward', 'camera-yaw', 'object-approach',
         'combined-approach', 'crossing-camera', 'occluded-crossing')


def main(root):
    if (root/'manifest.json').exists():
        raise ValueError('Never overwrite a completed corpus')
    root.mkdir(parents=True, exist_ok=True)
    layouts, labels = [], []
    for case_id, kind in enumerate(CASES):
        identity = f'ego-{kind}'
        (root/identity).mkdir(exist_ok=True)
        scene, camera, *_ = g.setup('covered-wide', 'test')
        bpy.data.objects['back'].location.y = 4.02
        bpy.data.objects['lintel'].location.z = 2.53
        for obj in list(scene.objects):
            if obj.type == 'MESH':
                texture(obj, 27001 + case_id*71 + sum(map(ord, obj.name)))
        box = None
        if kind not in ('camera-forward', 'camera-yaw'):
            box = g.cube('moving-box', (0, 3.13, .76), (.24, .18, .76), (.3, .4, .3))
            texture(box, 29001 + case_id*83)
        if kind == 'occluded-crossing':
            obj = g.cube('opaque-occluder', (0, 1.24, .9), (.62, .08, .9), (.3, .3, .3))
            texture(obj, 31001)
        scene.view_settings.view_transform = 'Standard'
        scene.view_settings.look = 'None'
        frames, scoring, previous = [], [], None
        for index in range(7):
            offset = [0., 0., 0.]
            yaw = 0.
            if kind == 'camera-forward': offset[1] = index*.05
            if kind == 'camera-yaw': yaw = index*1.3
            if kind == 'combined-approach': offset[1] = index*.04
            if kind in ('crossing-camera', 'occluded-crossing'): offset[0] = index*.018
            if box:
                box.location.x = .03
                box.location.y = 3.13-index*.18 if kind == 'object-approach' else 3.17-index*.14
                if kind in ('crossing-camera', 'occluded-crossing'):
                    box.location.x, box.location.y = 1.22-index*.19, 2.48
            camera.location = [offset[0], offset[1], 1.53]
            camera.rotation_euler = g.camera_rotation(yaw, -6., 0.).to_euler()
            bpy.context.view_layer.update()
            p = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=g.W, y=g.H, scale_x=1, scale_y=1)
            fx, fy = p[0][0]*g.W/2, p[1][1]*g.H/2
            cx, cy = (1-p[0][2])*g.W/2, (1+p[1][2])*g.H/2
            prefix = f'{identity}/{index}'
            rgb = root/f'{prefix}-rgb.png'
            scene.render.filepath = str(rgb)
            bpy.ops.render.render(write_still=True)
            radial, lower, upper, valid = g.visible_depth(scene, camera, fx, fy, cx, cy)
            rotation = np.array(camera.matrix_world, dtype=float)[:3,:3] @ np.diag([1,-1,-1])
            frames.append({'frameId': index+1, 'capturedOffsetUs': index*200000,
                'width': g.W, 'height': g.H, 'fx': fx, 'fy': fy, 'cx': cx, 'cy': cy,
                'cameraToWalkingRotation': rotation.ravel().tolist(),
                'cameraOriginM': [0., 0., float(camera.location.z)],
                'walkingOriginWorldM': offset, 'poseProviderId': 'synthetic-original-capture-pose',
                'poseRevision': 'translation-fixed-heading-v1', 'posePositionErrorM': .0001,
                'poseQuality': 1., 'pitchDeg': 6., 'yawDeg': yaw, 'rollDeg': 0.,
                'rgb': {'path': f'{prefix}-rgb.png', 'sha256': g.sha(rgb)},
                'depth': g.asset(root, f'{prefix}-depth.f32.gz', radial.tobytes()),
                'freeZLower': g.asset(root, f'{prefix}-lower.f32.gz', lower.tobytes()),
                'surfaceZUpper': g.asset(root, f'{prefix}-upper.f32.gz', upper.tobytes()),
                'validity': g.asset(root, f'{prefix}-valid.u8.gz', valid.tobytes())})
            point = None if box is None else [float(v) for v in box.location]
            velocity = None if point is None or previous is None else [(point[j]-previous[j])/.2 for j in range(3)]
            hazard = box is not None and abs(point[0]-offset[0]) <= .45+box.scale.x and point[1]-offset[1]-box.scale.y < 3.5
            hazard = hazard or kind == 'occluded-crossing'
            scoring.append({'frameId': index+1, 'physicalHazard': bool(hazard),
                'objectVelocityWorldMps': velocity, 'motionKind': kind,
                'observationSufficientForClearance': False})
            previous = point
        layouts.append({'id': identity, 'split': 'test', 'staticSyntheticScan': False,
                        'decisionFrameIds': list(range(1,8)), 'frames': frames})
        labels.append({'layoutId': identity, 'frames': scoring})
        print('EGO_CORPUS '+identity, flush=True)
    sources = [Path(__file__), Path(g.__file__), g.REPO/'tool/blender/generate_scale_motion_corpus.py',
               g.REPO/'docs/ego-motion-protocol-2026-10-10.md']
    g.save_json(root/'manifest.json', {'schemaVersion': 1, 'corpusId': 'ego-motion-2026-10-10',
        'generatorPath': 'tool/blender/generate_ego_motion_corpus.py',
        'sources': {str(p.resolve().relative_to(g.REPO)).replace('\\','/'): g.sha(p) for p in sources},
        'blenderVersion': bpy.app.version_string,
        'referenceFrameScope': 'walking axes fixed heading; origin recentered at each original capture',
        'worldReferenceFrameId': 'synthetic-fixed-ego-world-v1',
        'encoding': 'gzip little-endian float32 row-major; NaN=unknown',
        'depthSemantics': 'euclideanRangeMetres',
        'boundsSemantics': 'cameraAxisZMetresConservativeWholePixelFootprint',
        'scope': 'RGB/visible first returns plus original-capture walking pose; labels scoring only',
        'layouts': layouts, 'promotionAllowed': False})
    g.save_json(root/'annotations.json', {'schemaVersion': 1, 'scope': 'scoring only', 'layouts': labels})


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    root = (g.REPO/args.output).resolve()
    if not root.is_relative_to(g.REPO/'scratch'):
        raise ValueError('Use a new scratch corpus')
    main(root)

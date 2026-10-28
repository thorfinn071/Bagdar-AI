"""Separate write-once static scans; prior scenes and optical packets intact."""
import gzip
import hashlib
import json
from pathlib import Path
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
RGB = ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
OLD = ROOT/'test/fixtures/spatial_safety/blender-paired-visible-body-v1'
OUTPUT = ROOT/'test/fixtures/spatial_safety/blender-scan-coverage-v1'
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as rotations
import visible_bounds_union as renderer
from scan_view_selection import choose_views


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')


def main():
    if (OUTPUT/'manifest.json').exists():
        raise ValueError('Refusing to overwrite completed scan coverage corpus')
    source_paths = ['tool/blender/export_scan_coverage.py', 'tool/blender/visible_bounds_union.py',
                    'tool/blender/pixel_surface_envelope.py', 'tool/blender/scan_view_selection.py',
                    'tool/blender/check_scan_surface_bounds.py', 'tool/blender/test_pixel_surface_envelope.py',
                    'docs/blender-scan-coverage-protocol-2026-10-04.md',
                    'docs/_baseline_logs/blender_scan_surface_bounds_v1.json']
    sources = {p:sha(ROOT/p) for p in source_paths}
    corpus = json.loads((RGB/'corpus-manifest.json').read_text())
    old = json.loads((OLD/'manifest.json').read_text())
    receipt = json.loads((ROOT/source_paths[-1]).read_text())
    assert receipt['passed'] is True
    for path, expected in receipt['sources'].items():
        assert sha(ROOT/path) == expected
    OUTPUT.mkdir(parents=True, exist_ok=True)

    def packet(scene, camera, path, frame_id, offset, reference=None):
        bpy.context.view_layer.update()
        p = camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(), x=320, y=240, scale_x=1, scale_y=1)
        fx,fy,cx,cy = p[0][0]*160, p[1][1]*120, 160.,120.
        world = np.array(camera.matrix_world, dtype=float)
        rotation = world[:3,:3] @ np.diag([1.,-1.,-1.])
        header = {'width':320,'height':240,'frameId':frame_id,'capturedOffsetMs':offset,
                  'fx':fx,'fy':fy,'cx':cx,'cy':cy,'cameraToWalkingRotation':rotation.ravel().tolist(),
                  'cameraOriginM':[0.,0.,float(world[2,3])]}
        checkpoint = OUTPUT/f'{path}.json'
        identity = hashlib.sha256(json.dumps({'sources':sources,'header':header,
                                              'scene':sha(RGB/sequence['scene']['path'])}, sort_keys=True).encode()).hexdigest()
        if checkpoint.exists():
            prior = json.loads(checkpoint.read_text())
            if prior['checkpointIdentity'] != identity:
                raise ValueError('Changed unfinished export; preserve it in a separate directory')
            result = prior['packet']
            for key in ('depth','freeZLower','surfaceZUpper','validity'):
                assert sha(OUTPUT/result[key]['path']) == result[key]['sha256']
            print('SCAN_PACKET',path,'checkpoint',flush=True)
            return result
        started = time.perf_counter()
        arrays = renderer.visible_depth(scene,camera,fx,fy,cx,cy,320,240)
        if reference:
            for key, index in (('depth',0),('freeZLower',1),('validity',3)):
                assert gzip.decompress((OLD/reference[key]['path']).read_bytes()) == arrays[index].tobytes(), (path,key)
            for key in ('fx','fy','cx','cy','cameraOriginM','cameraToWalkingRotation'):
                assert np.allclose(header[key],reference[key],atol=1e-7,rtol=0), (path,key)
            header['oldPacketUpperSha256'] = reference['surfaceZUpper']['sha256']
        for key,suffix,values in zip(('depth','freeZLower','surfaceZUpper','validity'),
                                     ('range.f32','lower.f32','upper.f32','valid.u8'),arrays):
            target = OUTPUT/f'{path}-{suffix}.gz'
            target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes(gzip.compress(values.tobytes(),mtime=0))
            header[key] = {'path':target.relative_to(OUTPUT).as_posix(),'sha256':sha(target)}
        save(checkpoint,{'checkpointIdentity':identity,'packet':header})
        print('SCAN_PACKET',path,f'{time.perf_counter()-started:.2f}s',flush=True)
        return header

    layouts = []
    for sequence in corpus['sequences']:
        assert sha(RGB/sequence['scene']['path']) == sequence['scene']['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(RGB/sequence['scene']['path']))
        scene,camera = bpy.context.scene,bpy.context.scene.camera
        scene.frame_set(11)
        original_rotation = camera.rotation_euler.copy()
        reference = next(s for s in old['sequences'] if s['sceneId']==sequence['sceneId'])
        old_views = []
        poses = [(yaw,pitch) for pitch in (-65.,-15.,35.) for yaw in (-60.,0.,60.)]
        for index,(yaw,pitch) in enumerate(poses):
            camera.rotation_euler = rotations.camera_rotation(yaw,pitch,0).to_euler()
            old_views.append(packet(scene,camera,f"{sequence['sceneId']}/old-views-{index:02d}",
                                    index+101,index*200,reference['staticScan'][index]))
        camera.rotation_euler = original_rotation
        old_views.append(packet(scene,camera,f"{sequence['sceneId']}/old-views-09",11,2000,reference['staticScan'][9]))
        grid = choose_views(old_views[-1]['fx'],old_views[-1]['fy'],320,240,camera.location.z)
        new_views = []
        for index,(yaw,pitch) in enumerate(grid['poses']):
            camera.rotation_euler = rotations.camera_rotation(yaw,pitch,0).to_euler()
            new_views.append(packet(scene,camera,f"{sequence['sceneId']}/coverage-views-{index:02d}",
                                    index+201,index*200))
        layouts.append({'sceneId':sequence['sceneId'],'grid':grid,
                        'sameViewsNewBounds':old_views,'coverageViewsNewBounds':new_views})
        print('SCAN_LAYOUT',sequence['sceneId'],'completed',flush=True)
    for path,expected in sources.items():
        assert sha(ROOT/path)==expected, 'Source changed during export'
    save(OUTPUT/'manifest.json',{'schemaVersion':1,'corpusId':'blender-scan-coverage-v1',
         'promotionAllowed':False,'metricCalibration':'synthetic_renderer_only',
         'scope':'known regression frozen-state geometry; not moving safety or phone timing',
         'sourceCorpusSha256':sha(RGB/'corpus-manifest.json'),
         'priorVisibleManifestSha256':sha(OLD/'manifest.json'),'sources':sources,'layouts':layouts})
    print('SCAN_EXPORT_COMPLETE',sum(len(l['sameViewsNewBounds'])+len(l['coverageViewsNewBounds']) for l in layouts),flush=True)


if __name__ == '__main__':
    main()

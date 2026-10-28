"""Height bounds against independent ray casts; all four prior arrays exact."""
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import visible_bounds_union as prior
import visible_height_bounds as candidate

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    corpus=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
    manifest=json.loads((corpus/'corpus-manifest.json').read_text())
    cases=[]
    for scene_id,pitch in [('path-clear',-25),('person-approach',10)]:
        row=next(s for s in manifest['sequences'] if s['sceneId']==scene_id)
        bpy.ops.wm.open_mainfile(filepath=str(corpus/row['scene']['path']))
        scene,camera=bpy.context.scene,bpy.context.scene.camera
        scene.frame_set(11)
        camera.rotation_euler=g.camera_rotation(0,pitch,0).to_euler()
        bpy.context.view_layer.update()
        w,h=96,72
        p=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=w,y=h,scale_x=1,scale_y=1)
        fx,fy=p[0][0]*w/2,p[1][1]*h/2
        args=(scene,camera,fx,fy,w/2,h/2,w,h)
        old=prior.visible_depth(*args)
        new=candidate.visible_depth(*args)
        assert all(a.tobytes()==b.tobytes() for a,b in zip(old,new[:4]))
        deps=bpy.context.evaluated_depsgraph_get()
        witnessed=0
        for y in range(3,h,7):
            for x in range(3,w,9):
                for du,dv in ((.001,.001),(.999,.001),(.001,.999),(.999,.999),(.5,.5)):
                    ray=Vector(((x+du-w/2)/fx,-(y+dv-h/2)/fy,-1)).normalized()
                    hit,point,*_=scene.ray_cast(deps,camera.location,camera.matrix_world.to_quaternion() @ ray,distance=100)
                    if np.isfinite(new[4][y,x]):
                        assert hit
                        assert new[4][y,x] <= point.z+2e-5
                        assert new[5][y,x] >= point.z-2e-5
                        witnessed+=1
        assert witnessed>0
        cases.append({'sceneId':scene_id,'fourArraysExact':True,'rayHeightWitnesses':witnessed})
        # Full opaque cover makes every existing/new hidden surface irrelevant.
        g.cube('cover',(0,camera.location.y+1.2,1.5),(8,.1,5),(.2,.2,.2))
        bpy.context.view_layer.update()
        before=candidate.visible_depth(*args)
        g.cube('hidden',(0,camera.location.y+2.2,1),(.2,.1,.5),(.5,.1,.1))
        bpy.context.view_layer.update()
        after=candidate.visible_depth(*args)
        assert all(a.tobytes()==b.tobytes() for a,b in zip(before,after))
        cases[-1]['hiddenGeometryExact']=True
    paths=['tool/blender/visible_height_bounds.py','tool/blender/pixel_surface_height_envelope.py',
           'tool/blender/check_scan_height_bounds.py','tool/blender/visible_bounds_union.py']
    receipt={'passed':True,'promotionAllowed':False,'sources':{p:sha(ROOT/p) for p in paths},'cases':cases}
    target=ROOT/'docs/_baseline_logs/blender_scan_height_bounds_v1.json'
    if target.exists(): raise ValueError('Height renderer receipt is write-once')
    target.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt),flush=True)


if __name__=='__main__': main()

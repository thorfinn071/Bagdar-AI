"""Supplement missing primary upper bounds; preserve every prior optical artifact."""
import argparse
import gzip
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as optical
from generate_synchronized_rig import geometry_digest
from pixel_exact_surface_envelope import first_return_bounds
from watertight_surface_projection import clip_near

PRIOR = ROOT/'scratch/synchronized-passage-2026-10-09/optical-v2'
CORPUS = ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
SOURCES = [Path(__file__), ROOT/'docs/track-first-return-protocol-2026-10-09.md',
           ROOT/'tool/blender/pixel_exact_surface_envelope.py',
           ROOT/'tool/blender/watertight_surface_projection.py',
           ROOT/'tool/blender/generate_synchronized_rig.py',
           ROOT/'tool/blender/generate_visible_passage_corpus.py']


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def save(p, value):
    Path(p).write_text(json.dumps(value, indent=2)+'\n', encoding='utf-8')


def load_asset(p, key):
    d=p[key]; path=PRIOR/d['path']
    assert sha(path)==d['sha256']
    return np.frombuffer(gzip.decompress(path.read_bytes()),
                         dtype='u1' if key=='validity' else '<f4').reshape(p['height'],p['width']).copy()


def supplement(scene, camera, p, arrays):
    depth, lower, old_upper, valid=arrays
    selected=(valid==1)&np.isfinite(depth)&np.isnan(old_upper)
    candidates={(int(y),int(x)):[] for y,x in np.argwhere(selected)}
    fx,fy,cx,cy=(p[k] for k in ('fx','fy','cx','cy'))
    r=np.array(p['cameraToWalkingRotation']).reshape(3,3)
    hc=(r[2,0]/fx,r[2,1]/fy,r[2,2]-r[2,0]*cx/fx-r[2,1]*cy/fy)
    inv=camera.matrix_world.inverted(); deps=bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type!='MESH': continue
        evaluated=obj.evaluated_get(deps); mesh=evaluated.to_mesh(); mesh.calc_loop_triangles()
        points=[]
        for vertex in mesh.vertices:
            v=inv@(evaluated.matrix_world@vertex.co)
            points.append((v.x,-v.y,-v.z))
        for triangle in mesh.loop_triangles:
            poly=clip_near([points[i] for i in triangle.vertices])
            for k in range(1,len(poly)-1):
                t=np.array([poly[0],poly[k],poly[k+1]])
                screen=t[:,:2]/t[:,2,None]*[fx,fy]+[cx,cy]
                try: coef=np.linalg.solve(np.column_stack((screen,np.ones(3))),1/t[:,2])
                except np.linalg.LinAlgError: continue
                # Bounding rectangles are a broad phase only, with closed edges.
                x0=max(0,int(math.ceil(screen[:,0].min())-1)); x1=min(p['width'],int(math.floor(screen[:,0].max())+1))
                y0=max(0,int(math.ceil(screen[:,1].min())-1)); y1=min(p['height'],int(math.floor(screen[:,1].max())+1))
                if x0>=x1 or y0>=y1: continue
                patch=(screen.tolist(),coef.tolist())
                for iy,ix in np.argwhere(selected[y0:y1,x0:x1]):
                    candidates[(y0+int(iy),x0+int(ix))].append(patch)
        evaluated.to_mesh_clear()
    upper=old_upper.copy(); hlo=np.full_like(upper,np.nan); hhi=hlo.copy(); first=hlo.copy()
    repaired=np.zeros_like(valid); rows=[]; ray_count=0
    for (y,x),patches in candidates.items():
        zhi,lo,hi,zlo=map(float,first_return_bounds(x,y,patches,hc,p['cameraOriginM'][2]))
        if not all(math.isfinite(v) for v in (zhi,lo,hi,zlo)):
            rows.append({'index':y*p['width']+x,'certified':False,'patches':len(patches)})
            continue
        assert zlo<=zhi and lo<=hi and zlo>=float(lower[y,x])-2e-5
        upper[y,x]=zhi+1e-5; hlo[y,x]=lo-1e-5; hhi[y,x]=hi+1e-5; first[y,x]=max(0,zlo-1e-5)
        repaired[y,x]=1
        # Independent first-hit engine: every repaired pixel, five interior rays.
        heights=[]
        for du,dv in ((.5,.5),(.001,.001),(.999,.001),(.001,.999),(.999,.999)):
            direction=Vector(((x+du-cx)/fx,-(y+dv-cy)/fy,-1)).normalized()
            hit, point, *_=scene.ray_cast(deps,camera.location,
                camera.matrix_world.to_quaternion()@direction,distance=100)
            assert hit, (y,x,'certified hole')
            z=-(inv@point).z
            assert lower[y,x]<=z+2e-4 and first[y,x]<=z+2e-4 and z<=upper[y,x]+2e-4
            assert hlo[y,x]<=point.z+2e-4 and point.z<=hhi[y,x]+2e-4
            if du==dv==.5: assert abs((point-camera.location).length-depth[y,x])<2e-4
            heights.append(float(point.z)); ray_count+=1
        rows.append({'index':y*p['width']+x,'certified':True,'patches':len(patches),
                     'heightLowerM':float(hlo[y,x]),'heightUpperM':float(hhi[y,x]),
                     'sampledFirstHitHeightMinM':min(heights),'sampledFirstHitHeightMaxM':max(heights)})
    return (upper,hlo,hhi,first,repaired),rows,ray_count


def run(output):
    if (output/'manifest.json').exists(): raise ValueError('Completed optical result is immutable')
    output.mkdir(parents=True,exist_ok=True)
    prior=json.loads((PRIOR/'manifest.json').read_text()); corpus=json.loads((CORPUS/'corpus-manifest.json').read_text())
    for path,digest in prior['sources'].items(): assert sha(ROOT/path)==digest
    sources={p.relative_to(ROOT).as_posix():sha(p) for p in SOURCES}; records=[]
    for batch in prior['batches']:
        checkpoint=output/(batch['id']+'-record.json')
        if checkpoint.exists():
            rec=json.loads(checkpoint.read_text()); assert rec['sources']==sources
            for key in ('surfaceZUpper','heightLower','heightUpper','firstZLower','repairMask'):
                assert sha(output/rec[key]['path'])==rec[key]['sha256']
            records.append(rec); print('RESUME',batch['id'],flush=True); continue
        sequence=next(s for s in corpus['sequences'] if s['sceneId']==batch['sceneId'])
        blend=CORPUS/sequence['scene']['path']; assert sha(blend)==batch['sourceBlendSha256']
        bpy.ops.wm.open_mainfile(filepath=str(blend))
        scene=bpy.context.scene; camera=scene.camera; scene.frame_set(batch['frameId']); bpy.context.view_layer.update()
        if batch['contrast']:
            optical.cube('experiment-pole',(0.,camera.location.y+2.1,.95),(.002,.002,.95),(.16,.18,.20))
            if batch['contrast']=='hidden':
                optical.cube('experiment-opaque-occluder',(0.,camera.location.y+1.45,1.),(.60,.035,1.),(.22,.26,.29))
        bpy.context.view_layer.update(); assert geometry_digest(scene)==batch['sceneStateSha256']
        p=batch['primary']; scene.render.resolution_x=p['width'];scene.render.resolution_y=p['height']; scene.render.resolution_percentage=100
        world=np.array(camera.matrix_world,dtype=float)
        assert np.array_equal(world[:3,:3]@np.diag([1.,-1.,-1.]),np.array(p['cameraToWalkingRotation']).reshape(3,3))
        assert float(world[2,3])==p['cameraOriginM'][2]
        proj=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=p['width'],y=p['height'],scale_x=1,scale_y=1)
        assert proj[0][0]*p['width']/2==p['fx'] and proj[1][1]*p['height']/2==p['fy']
        arrays=[load_asset(p,key) for key in ('depth','freeZLower','surfaceZUpper','validity')]
        started=time.perf_counter(); supplemental,rows,witnesses=supplement(scene,camera,p,arrays)
        rec={'id':batch['id'],'sources':sources,'frameId':p['frameId'],'capturedAtUs':p['capturedAtUs'],
             'sessionGeneration':p['sessionGeneration'],'sceneStateSha256':batch['sceneStateSha256'],
             'priorPrimary':p,'candidatePixels':len(rows),'certifiedPixels':int(supplemental[-1].sum()),
             'independentRayWitnesses':witnesses,'offlineExportSeconds':time.perf_counter()-started,'pixels':rows}
        for key,array in zip(('surfaceZUpper','heightLower','heightUpper','firstZLower','repairMask'),supplemental):
            path=output/(batch['id']+'-'+key+'.gz'); path.write_bytes(gzip.compress(array.tobytes(),mtime=0))
            rec[key]={'path':path.name,'sha256':sha(path)}
        save(checkpoint,rec);records.append(rec)
        print('PRIMARY_PROOF',batch['id'],rec['candidatePixels'],rec['certifiedPixels'],witnesses,flush=True)
    save(output/'manifest.json',{'schemaVersion':1,'promotionAllowed':False,'ordinaryCameraWired':False,
         'scope':'offline exact primary first-return proof; pinned prior RGB/neural/capture; known static synthetic snapshots',
         'priorManifestSha256':sha(PRIOR/'manifest.json'),'priorNeuralSha256':sha(PRIOR/'neural.json'),
         'sources':sources,'blenderVersion':bpy.app.version_string,'records':records})


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    output=(ROOT/args.output).resolve()
    if not output.is_relative_to(ROOT/'scratch'): raise ValueError('Output must remain in scratch')
    run(output)

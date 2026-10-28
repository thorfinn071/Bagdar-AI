"""Eleven pinned captures, sparse primary proofs and coherent simultaneous optics."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sys

import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as optical
import visible_complete_surface_bounds as complete
from visible_exact_floor_height_bounds import floor_heights
from export_synchronized_rig_bundle_v2 import coherent_pixels
from generate_synchronized_rig import geometry_digest,witnesses
from scan_view_selection import choose_views
from export_track_first_return import supplement

TASK=ROOT/'scratch/sequence-first-return-2026-10-09'
CORPUS=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
VISIBLE=ROOT/'test/fixtures/spatial_safety/blender-paired-visible-body-v1'
PRIOR=ROOT/'scratch/synchronized-passage-2026-10-09/optical-v2'


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def save(p,v):Path(p).write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')


def run(output):
    if (output/'manifest.json').exists():raise ValueError('Completed sequence export is immutable')
    output.mkdir(parents=True,exist_ok=True)
    selection=read(TASK/'selection.json');prior=read(PRIOR/'manifest.json');corpus=read(CORPUS/'corpus-manifest.json')
    for p,h in selection['sources'].items():assert sha(ROOT/p)==h,p
    for p,h in prior['sources'].items():assert sha(ROOT/p)==h,p
    paths=['tool/blender/export_sequence_first_return.py','docs/sequence-first-return-protocol-2026-10-09.md',
      'tool/blender/export_track_first_return.py','tool/blender/visible_complete_surface_bounds.py',
      'tool/blender/visible_exact_floor_height_bounds.py','tool/blender/export_synchronized_rig_bundle_v2.py',
      'tool/blender/generate_synchronized_rig.py','tool/blender/scan_view_selection.py',
      'tool/blender/generate_visible_passage_corpus.py','tool/blender/pixel_complete_surface_envelope.py',
      'tool/blender/pixel_exact_surface_envelope.py','tool/blender/watertight_surface_projection.py']
    sources={p:sha(ROOT/p) for p in paths};selection_sha=sha(TASK/'selection.json');batches=[]

    def copy_asset(root,d,target):
        source=root/d['path'];assert sha(source)==d['sha256'];shutil.copyfile(source,target)
        return {'path':target.relative_to(output).as_posix(),'sha256':sha(target)}

    def write_array(folder,name,array):
        path=folder/name;path.write_bytes(gzip.compress(array.tobytes(),mtime=0))
        return {'path':path.relative_to(output).as_posix(),'sha256':sha(path)}

    for entry in selection['frames']:
        folder=output/entry['id'];folder.mkdir(exist_ok=True);checkpoint=folder/'batch.json'
        if checkpoint.exists():
            b=read(checkpoint);assert b['exportSources']==sources and b['selectionSha256']==selection_sha
            for p in [b['primary'],*b['channels']]:
                for d in p.values():
                    if isinstance(d,dict) and set(d)=={'path','sha256'}:assert sha(output/d['path'])==d['sha256']
            batches.append(b);print('RESUME',entry['id'],flush=True);continue
        seq=next(s for s in corpus['sequences'] if s['sceneId']=='path-clear')
        blend=CORPUS/seq['scene']['path'];assert sha(blend)==seq['scene']['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(blend));scene=bpy.context.scene;primary=scene.camera
        scene.frame_set(entry['frameId']);bpy.context.view_layer.update();state=geometry_digest(scene)
        old=entry['primary'];world=np.array(primary.matrix_world,dtype=float)
        assert np.array_equal(world[:3,:3]@np.diag([1.,-1.,-1.]),np.array(old['cameraToWalkingRotation']).reshape(3,3))
        assert float(world[2,3])==old['cameraOriginM'][2]
        p={k:old[k] for k in ['width','height','fx','fy','cx','cy','cameraToWalkingRotation','cameraOriginM','frameId']}
        p.update(cameraId='primary',capturedAtUs=entry['capturedAtUs'],sessionGeneration=1,sceneStateSha256=state)
        arrays=[]
        for key in ['depth','freeZLower','surfaceZUpper','validity']:
            p[key]=copy_asset(VISIBLE,old[key],folder/(key+'.gz'))
            arrays.append(np.frombuffer(gzip.decompress((output/p[key]['path']).read_bytes()),
              dtype='u1' if key=='validity' else '<f4').reshape(p['height'],p['width']).copy())
        p['rgb']=copy_asset(CORPUS,entry['original']['rgb'],folder/'primary.png')
        assert old['rgbSha256']==p['rgb']['sha256']==entry['neural']['rgbSha256']
        p['originalSurfaceZUpper']=p['surfaceZUpper']
        footprint=np.zeros(p['height']*p['width'],dtype='u1');footprint[entry['supportPixels']]=1
        selected_valid=arrays[3]&footprint.reshape(p['height'],p['width'])
        supplemental,proof_rows,ray_count=supplement(scene,primary,p,[*arrays[:3],selected_valid])
        for key,array in zip(['surfaceZUpper','heightLower','heightUpper','firstZLower','repairMask'],supplemental):
            p[key]=write_array(folder,'supplemental-'+key+'.gz',array)
        p.update(sparseCandidates=len(proof_rows),sparseCertified=int(supplemental[-1].sum()),
                 independentRayWitnesses=ray_count)
        proof_path=folder/'primary-proof.json';save(proof_path,proof_rows)
        p['proof']={'path':proof_path.relative_to(output).as_posix(),'sha256':sha(proof_path)}
        neural=dict(entry['neural']);neural['asset']=copy_asset(CORPUS,neural['asset'],folder/'pinned-relative.gz')
        grid=choose_views(26/36*160,26/36*160,160,120,primary.location.z);assert len(grid['poses'])==12
        channels=[];reused=entry['frameIndex'] in (0,10)
        if reused:
            old_batch=next(b for b in prior['batches'] if b['id']==('clear-first' if entry['frameIndex']==0 else 'clear-final'))
            assert old_batch['sceneStateSha256']==state and old_batch['capturedAtUs']==entry['capturedAtUs']
            assert old_batch['grid']==json.loads(json.dumps(grid))
            for original in old_batch['channels']:
                channel=json.loads(json.dumps(original))
                for key,value in list(channel.items()):
                    if isinstance(value,dict) and set(value)=={'path','sha256'}:
                        channel[key]=copy_asset(PRIOR,value,folder/(channel['cameraId']+'-'+key+Path(value['path']).suffix))
                channels.append(channel)
        else:
            for index,(yaw,pitch) in enumerate(grid['poses']):
                bpy.ops.object.camera_add(location=primary.location);camera=bpy.context.object
                camera.data.lens=26.;camera.data.sensor_width=36.;camera.data.sensor_fit='HORIZONTAL'
                camera.rotation_euler=optical.camera_rotation(yaw,pitch,0.).to_euler()
                scene.camera=camera;scene.render.resolution_x=160;scene.render.resolution_y=120;scene.render.resolution_percentage=100
                bpy.context.view_layer.update();assert geometry_digest(scene)==state
                projection=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=160,y=120,scale_x=1,scale_y=1)
                rotation=np.array(camera.matrix_world,dtype=float)[:3,:3]@np.diag([1.,-1.,-1.])
                c={'cameraId':f'channel-{index:02d}','frameId':entry['frameId'],'sessionGeneration':1,
                  'capturedAtUs':entry['capturedAtUs'],'sceneStateSha256':state,'width':160,'height':120,
                  'fx':projection[0][0]*80,'fy':projection[1][1]*60,'cx':80.,'cy':60.,
                  'cameraToWalkingRotation':rotation.ravel().tolist(),'cameraOriginM':[0.,0.,float(world[2,3])],
                  'yawDeg':yaw,'pitchDeg':pitch}
                values=list(complete.visible_depth(scene,camera,c['fx'],c['fy'],80,60,160,120))
                values[4],values[5],changed=floor_heights(scene,camera,c['fx'],c['fy'],80,60,values[0],values[4],values[5])
                candidates,certified=coherent_pixels(scene,camera,c,values)
                c.update(exactFloorPixels=changed,coherencePixels=candidates,coherenceCertifiedPixels=certified,
                         rayWitnesses=witnesses(scene,camera,c,values,202610090+len(c['cameraId'])))
                for key,array in zip(['depth','freeZLower','surfaceZUpper','validity','heightLower','heightUpper','firstZLower'],values):
                    c[key]=write_array(folder,c['cameraId']+'-'+key+'.gz',array)
                channels.append(c);print('SEQUENCE_CHANNEL',entry['id'],c['cameraId'],flush=True)
        b={'id':entry['id'],'sceneId':'path-clear','contrast':None,'frameId':entry['frameId'],
          'sessionGeneration':1,'capturedAtUs':entry['capturedAtUs'],'zeroSkewUs':0,'sceneStateSha256':state,
          'sourceBlendSha256':sha(blend),'stationarySyntheticScene':True,'physicalHazard':False,
          'originalFrameIndex':entry['frameIndex'],'grid':grid,'primary':p,'channels':channels,
          'neural':neural,'exportSources':sources,'selectionSha256':selection_sha,'rigPayloadsReused':reused}
        save(checkpoint,b);batches.append(b)
        print('SEQUENCE_FRAME',b['id'],p['sparseCandidates'],p['sparseCertified'],flush=True)
    save(output/'manifest.json',{'schemaVersion':1,'promotionAllowed':False,'runtimeWired':False,'pilotOnly':False,
      'referenceFrameId':'paired-local-walking-v1','scope':'eleven original captures; sparse camera-visible proof; ideal static rig; pinned neural output',
      'sources':sources,'selectionSha256':selection_sha,'sourceCorpusSha256':sha(CORPUS/'corpus-manifest.json'),
      'priorRigManifestSha256':sha(PRIOR/'manifest.json'),'newNeuralInference':False,'batches':batches})


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);output=(ROOT/args.output).resolve()
    if not output.is_relative_to(ROOT/'scratch'):raise ValueError('Output must remain in scratch')
    run(output)

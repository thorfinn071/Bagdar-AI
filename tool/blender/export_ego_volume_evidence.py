"""Simultaneous visible optics at unchanged ego-corpus capture states."""
import gzip
import json
from pathlib import Path
import sys
import bpy
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import generate_ego_motion_corpus as original
import visible_complete_surface_bounds as complete
from visible_exact_floor_height_bounds import floor_heights
from export_synchronized_rig_bundle_v2 import coherent_pixels
from generate_synchronized_rig import geometry_digest,witnesses
from scan_view_selection import choose_views

INPUT=ROOT/'scratch/ego-motion-2026-10-10/corpus'
OUTPUT=ROOT/'scratch/evidence-authority-fix-2026-10-10/optical'
SOURCES=['tool/blender/export_ego_volume_evidence.py','tool/blender/generate_ego_motion_corpus.py',
 'tool/blender/generate_visible_passage_corpus.py','tool/blender/generate_scale_motion_corpus.py',
 'tool/blender/visible_complete_surface_bounds.py','tool/blender/visible_exact_floor_height_bounds.py',
 'tool/blender/export_synchronized_rig_bundle_v2.py','tool/blender/generate_synchronized_rig.py',
 'tool/blender/scan_view_selection.py','tool/blender/pixel_complete_surface_envelope.py',
 'tool/blender/pixel_exact_surface_envelope.py','tool/blender/watertight_surface_projection.py',
 'docs/evidence-authority-fix-protocol-2026-10-10.md']


def main():
    if (OUTPUT/'manifest.json').exists():raise ValueError('Completed optics are immutable')
    OUTPUT.mkdir(parents=True,exist_ok=True)
    source=json.loads((INPUT/'manifest.json').read_text())
    sources={p:g.sha(ROOT/p) for p in SOURCES}
    batches=[]
    for case_id,(kind,layout) in enumerate(zip(original.CASES,source['layouts'])):
        assert layout['id']=='ego-'+kind
        scene,primary,*_=g.setup('covered-wide','test')
        bpy.data.objects['back'].location.y=4.02
        bpy.data.objects['lintel'].location.z=2.53
        box=None
        if kind not in ('camera-forward','camera-yaw'):
            box=g.cube('moving-box',(0,3.13,.76),(.24,.18,.76),(.3,.4,.3))
        if kind=='occluded-crossing':
            g.cube('opaque-occluder',(0,1.24,.9),(.62,.08,.9),(.3,.3,.3))
        cameras=[]
        grid=choose_views(26/36*160,26/36*160,160,120,1.53)
        assert len(grid['poses'])==12
        for channel,(yaw,pitch) in enumerate(grid['poses']):
            bpy.ops.object.camera_add(location=(0,0,1.53));camera=bpy.context.object
            camera.data.lens=26.;camera.data.sensor_width=36.;camera.data.sensor_fit='HORIZONTAL'
            camera.rotation_euler=g.camera_rotation(yaw,pitch,0).to_euler();cameras.append(camera)
        for index,meta in enumerate(layout['frames']):
            folder=OUTPUT/layout['id']/str(meta['frameId']);folder.mkdir(parents=True,exist_ok=True)
            checkpoint=folder/'batch.json'
            if checkpoint.exists():
                batch=json.loads(checkpoint.read_text());assert batch['sources']==sources
                for packet in batch['channels']:
                    for desc in packet.values():
                        if isinstance(desc,dict) and set(desc)=={'path','sha256'}:
                            assert g.sha(OUTPUT/desc['path'])==desc['sha256']
                batches.append(batch);print('RESUME_VOLUME',batch['id'],flush=True);continue
            offset=meta['walkingOriginWorldM'];yaw=meta['yawDeg']
            if box:
                box.location.x=.03
                box.location.y=3.13-index*.18 if kind=='object-approach' else 3.17-index*.14
                if kind in ('crossing-camera','occluded-crossing'):
                    box.location.x,box.location.y=1.22-index*.19,2.48
            primary.location=[offset[0],offset[1],1.53]
            primary.rotation_euler=g.camera_rotation(yaw,-6.,0.).to_euler()
            bpy.context.view_layer.update()
            assert np.array_equal(np.array(primary.matrix_world)[:3,:3]@np.diag([1.,-1.,-1.]),
                                  np.array(meta['cameraToWalkingRotation']).reshape(3,3))
            # Re-render the original measurement arrays, never alter them.
            arrays=g.visible_depth(scene,primary,meta['fx'],meta['fy'],meta['cx'],meta['cy'])
            for key,array in zip(('depth','freeZLower','surfaceZUpper','validity'),arrays):
                desc=meta[key];assert g.sha(INPUT/desc['path'])==desc['sha256']
                expected=gzip.decompress((INPUT/desc['path']).read_bytes())
                assert array.tobytes()==expected,('Primary geometry drift',layout['id'],index,key)
            state=geometry_digest(scene);packets=[]
            for channel,camera in enumerate(cameras):
                camera.location=primary.location;scene.camera=camera
                scene.render.resolution_x=160;scene.render.resolution_y=120
                bpy.context.view_layer.update();assert geometry_digest(scene)==state
                projection=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=160,y=120,scale_x=1,scale_y=1)
                rotation=np.array(camera.matrix_world)[:3,:3]@np.diag([1.,-1.,-1.])
                packet={'cameraId':f'channel-{channel:02d}','frameId':meta['frameId'],
                    'sessionGeneration':1,'capturedAtUs':1790899200000000+meta['capturedOffsetUs'],
                    'sceneStateSha256':state,'width':160,'height':120,
                    'fx':projection[0][0]*80,'fy':projection[1][1]*60,'cx':80.,'cy':60.,
                    'cameraToWalkingRotation':rotation.ravel().tolist(),'cameraOriginM':[0.,0.,float(primary.location.z)]}
                values=list(complete.visible_depth(scene,camera,packet['fx'],packet['fy'],80,60,160,120))
                values[4],values[5],_=floor_heights(scene,camera,packet['fx'],packet['fy'],80,60,values[0],values[4],values[5])
                coherent_pixels(scene,camera,packet,values)
                packet['rayWitnesses']=witnesses(scene,camera,packet,values,202610100+index*31+channel)
                for key,array in zip(('depth','freeZLower','surfaceZUpper','validity','heightLower','heightUpper','firstZLower'),values):
                    path=folder/f'{channel:02d}-{key}.gz';path.write_bytes(gzip.compress(array.tobytes(),mtime=0))
                    packet[key]={'path':path.relative_to(OUTPUT).as_posix(),'sha256':g.sha(path)}
                packets.append(packet)
            batch={'id':f"{layout['id']}/{meta['frameId']}",'layoutId':layout['id'],'frameId':meta['frameId'],
                'sessionGeneration':1,'capturedAtUs':1790899200000000+meta['capturedOffsetUs'],
                'sceneStateSha256':state,'stationarySyntheticScene':True,'zeroSkewUs':0,
                'scope':'one instantaneous synthetic state; no inter-frame stationarity claim',
                'primaryArraysReproduced':True,'primaryOriginal':meta,'sources':sources,'channels':packets}
            g.save_json(checkpoint,batch);batches.append(batch)
            print('EGO_VOLUME',batch['id'],flush=True)
    g.save_json(OUTPUT/'manifest.json',{'schemaVersion':1,'promotionAllowed':False,'ordinaryCameraWired':False,
        'priorCorpusSha256':g.sha(INPUT/'manifest.json'),'sources':sources,'batches':batches})


if __name__=='__main__':main()

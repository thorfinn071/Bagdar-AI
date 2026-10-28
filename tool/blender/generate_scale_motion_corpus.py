"""Predeclared independent motion scenes; only visible first returns exported."""
import argparse
import sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g

CASES = [(s,k) for s,ks in (
    ('validation',('approach','approach-fast','receding','stationary','camera-yaw','crossing')),
    ('test',('approach-slow','approach-fast','approach-small','receding','stationary','camera-yaw','mixed','occluded','textureless','wide')))
    for k in ks]

def texture(obj,seed,plain=False):
    mat=bpy.data.materials.new('visible-material');mat.use_nodes=True
    nodes=mat.node_tree.nodes;nodes.clear()
    out=nodes.new('ShaderNodeOutputMaterial');emit=nodes.new('ShaderNodeEmission')
    emit.inputs['Color'].default_value=(.4,.4,.4,1)
    if not plain:
        rng=np.random.default_rng(seed)
        image=bpy.data.images.new('visible-random-texture',width=32,height=32)
        pixels=np.ones((32,32,4),dtype=np.float32);pixels[:,:,:3]=rng.uniform(.035,.85,(32,32,3))
        image.pixels=pixels.ravel().tolist()
        tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest'
        coord=nodes.new('ShaderNodeTexCoord');sep=nodes.new('ShaderNodeSeparateXYZ');comb=nodes.new('ShaderNodeCombineXYZ')
        mat.node_tree.links.new(coord.outputs['Generated'],sep.inputs[0])
        mat.node_tree.links.new(sep.outputs['X'],comb.inputs['X']);mat.node_tree.links.new(sep.outputs['Z'],comb.inputs['Y'])
        mat.node_tree.links.new(comb.outputs[0],tex.inputs['Vector'])
        mat.node_tree.links.new(tex.outputs['Color'],emit.inputs['Color'])
    mat.node_tree.links.new(emit.outputs[0],out.inputs['Surface'])
    obj.data.materials.clear();obj.data.materials.append(mat)

def main(root):
    if (root/'manifest.json').exists():raise ValueError('Never overwrite the independent corpus')
    root.mkdir(parents=True,exist_ok=True);layouts=[];labels=[]
    for case_id,(split,kind) in enumerate(CASES):
        identity=f'{split}-scale-motion-{kind}-{case_id:02d}';(root/identity).mkdir(exist_ok=True)
        static=kind=='wide';scene,camera,*_=g.setup('covered-wide' if static else 'covered-box','test')
        distance=2.69+.019*case_id;width=1.83+.013*case_id;height=2.27+.007*case_id
        for name,x in [('left',-width/2-1),('right',width/2+1)]:
            obj=bpy.data.objects[name];obj.location.x=x;obj.location.y=distance
        lintel=bpy.data.objects['lintel'];lintel.location.y=distance;lintel.location.z=height+.25;lintel.scale.x=width/2
        for name in ['left','right','lintel','back']:texture(bpy.data.objects[name],17000+case_id*5+len(name))
        if not static:
            box=bpy.data.objects['box'];box.scale=(.22 if kind=='approach-small' else .35,.21,.80);box.location.z=.8
            texture(box,19000+case_id,plain=kind=='textureless')
        if kind=='occluded':
            g.cube('occluder',(0,1.18,.85),(.60,.08,.85),(.2,.2,.2));texture(bpy.data.objects['occluder'],22000+case_id)
        scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0
        poses=g.POSES+[(0.,-8.)]*3 if static else [(0.,-6.)]*7
        frames=[];frame_labels=[];previous=None;scoring_frames=[]
        variant=1 if split=='test' else -1
        for index,(yaw,pitch) in enumerate(poses):
            origin=[0.,0.,1.55]
            if not static:
                box.location.x=.03+.002*case_id;box.location.y=2.06+.011*case_id
                if kind.startswith('approach'):
                    rate={'approach':.22,'approach-fast':.29,'approach-slow':.14,'approach-small':.21}[kind]
                    box.location.y=3.23+.007*case_id-index*rate
                elif kind=='receding':box.location.y=1.35+.011*case_id+index*.23
                elif kind=='crossing':box.location.x=1.19+.005*case_id-index*.16
                elif kind=='mixed':box.location.x=1.13-index*.14;box.location.y=2.85-index*.15;origin[0]=index*.018;yaw=-index*1.1
                elif kind=='camera-yaw':yaw=variant*index*1.7
                elif kind=='camera-translation':origin[0]=variant*index*.025
                elif kind=='occluded':box.location.x=.85-index*.14
                point=[float(v) for v in box.location];velocity=None if previous is None else [(point[j]-previous[j])/.2 for j in range(3)]
                previous=point
                hazardous=abs(box.location.x)<=.45+box.scale.x and box.location.y-box.scale.y<3.5
                frame_labels.append({'frameId':index+1,'physicalHazard':bool(hazardous) or kind=='occluded',
                    'observationSufficient':False,'objectVelocityMps':velocity,'motionKind':kind})
            camera.location=origin;camera.rotation_euler=g.camera_rotation(yaw,pitch,0).to_euler();bpy.context.view_layer.update()
            p=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=g.W,y=g.H,scale_x=1,scale_y=1)
            fx,fy=p[0][0]*g.W/2,p[1][1]*g.H/2;cx,cy=(1-p[0][2])*g.W/2,(1+p[1][2])*g.H/2
            prefix=f'{identity}/{index}';rgb=root/f'{prefix}-rgb.png';scene.render.filepath=str(rgb);bpy.ops.render.render(write_still=True)
            radial,lower,upper,valid=g.visible_depth(scene,camera,fx,fy,cx,cy)
            rotation=np.array(camera.matrix_world,dtype=float)[:3,:3]@np.diag([1,-1,-1])
            if not static:
                xx,yy=np.meshgrid(np.arange(g.W)+.5,np.arange(g.H)+.5)
                axis=radial/np.sqrt(1+((xx-cx)/fx)**2+((yy-cy)/fy)**2)
                optical=np.stack(((xx-cx)/fx*axis,(yy-cy)/fy*axis,axis),axis=-1)
                world=optical@rotation.T+np.array(origin)
                centre=np.array(box.location);half=np.array(box.scale)
                mask=np.isfinite(axis)&(np.abs(world-centre)<=half+1e-4).all(axis=-1)
                scoring_frames.append({'frameId':index+1,'visibleObjectMask':g.asset(root,f'{identity}/{index}-scorer-object.u8.gz',mask.astype('uint8').tobytes())})
            frames.append({'frameId':index+1,'capturedOffsetUs':index*200000,'width':g.W,'height':g.H,
                'fx':fx,'fy':fy,'cx':cx,'cy':cy,'cameraToWalkingRotation':rotation.ravel().tolist(),
                'cameraOriginM':origin,'poseQuality':1.,'rollDeg':0.,'yawDeg':yaw,'pitchDeg':-pitch,'opticalPitchUpDeg':pitch,
                'projectionMatrix':np.array(p,dtype=float).ravel().tolist(),
                'rgb':{'path':f'{prefix}-rgb.png','sha256':g.sha(rgb)},
                'depth':g.asset(root,f'{prefix}-depth.f32.gz',radial.tobytes()),
                'freeZLower':g.asset(root,f'{prefix}-lower.f32.gz',lower.tobytes()),
                'surfaceZUpper':g.asset(root,f'{prefix}-upper.f32.gz',upper.tobytes()),
                'validity':g.asset(root,f'{prefix}-valid.u8.gz',valid.tobytes())})
        decisions=[1,11,12,13] if static else list(range(1,8))
        if static:frame_labels=[{'frameId':fid,'physicalHazard':False,'observationSufficient':fid>1,
            'objectVelocityMps':[0,0,0] if fid>1 else None,'motionKind':'wide'} for fid in decisions]
        dangerous=[f for f in frame_labels if f['physicalHazard']];onset=(dangerous[0]['frameId']-1)*200000 if dangerous else None
        layouts.append({'id':identity,'split':split,'staticSyntheticScan':static,'decisionFrameIds':decisions,'frames':frames})
        labels.append({'layoutId':identity,'physicalHazard':bool(dangerous),'criticalOnsetOffsetUs':onset,
            'latestStopOffsetUs':None if onset is None else onset+300000,'frames':frame_labels,'visibleObjectFrames':scoring_frames})
        print('METRIC_MOTION_CORPUS '+identity,flush=True)
    g.save_json(root/'manifest.json',{'schemaVersion':1,'corpusId':'camera-scale-motion-v1',
        'generatorPath':'tool/blender/generate_scale_motion_corpus.py','generatorSha256':g.sha(__file__),
        'baseRendererSha256':g.sha(g.__file__),'protocolSha256':g.sha(g.REPO/'docs/camera-scale-motion-protocol-2026-10-03.md'),
        'blenderVersion':bpy.app.version_string,'encoding':'gzip little-endian float32 row-major; NaN=unknown',
        'depthSemantics':'euclideanRangeMetres','boundsSemantics':'cameraAxisZMetresConservativeWholePixelFootprint',
        'scope':'RGB/first-return only; geometry and velocity labels never consumer inputs','layouts':layouts})
    g.save_json(root/'annotations.json',{'schemaVersion':1,'scope':'scoring only','layouts':labels})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:]);root=(g.REPO/args.output).resolve()
    if not root.is_relative_to(g.REPO) or root.name!='camera-scale-motion-v1':raise ValueError('Use separate corpus')
    main(root)

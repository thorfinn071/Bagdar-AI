"""Predeclared temporal RGB/first-return corpus. Labels are scoring-only."""
import argparse
import sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g

CASES = [
    ('validation','wide',2.49,1.58,2.13),
    ('validation','door-pass',2.79,1.66,2.18),
    ('validation','outside-pole',2.57,1.62,2.15),
    ('validation','low-bar',2.73,1.60,1.48),
    ('validation','approach',2.91,1.64,2.16),
    ('validation','crossing',2.64,1.60,2.12),
    ('test','wide',2.47,1.56,2.09),
    ('test','wide',3.13,1.68,2.20),
    ('test','door-pass',2.96,1.64,2.17),
    ('test','outside-pole',2.69,1.60,2.14),
    ('test','low-bar',2.83,1.62,1.47),
    ('test','pole',3.03,1.60,2.15),
    ('test','subpixel-pole',2.78,1.58,2.14),
    ('test','approach',3.07,1.66,2.18),
    ('test','crossing',2.86,1.62,2.16),
    ('test','receding',2.99,1.64,2.19),
    ('test','camera-yaw',2.71,1.62,2.13),
    ('test','camera-translation',2.92,1.66,2.16),
]
TEMPORAL = {'approach','crossing','receding','camera-yaw','camera-translation'}

def main(root):
    if (root/'manifest.json').exists():
        raise ValueError('Separate corpus already exists; do not overwrite frozen geometry')
    root.mkdir(parents=True,exist_ok=True)
    layouts=[]; labels=[]
    for case_id,(split,kind,distance,width,height) in enumerate(CASES):
        identity=f'{split}-temporal-{kind}-{case_id:02d}'
        folder=root/identity; folder.mkdir(exist_ok=True)
        dynamic=kind in TEMPORAL
        base='box' if dynamic else 'pole' if kind=='outside-pole' else kind
        scene,camera,*_=g.setup('covered-'+base,'test')
        left,right,lintel=[bpy.data.objects[n] for n in ('left','right','lintel')]
        left.location.x=-width/2-1; right.location.x=width/2+1
        for obj in (left,right,lintel):obj.location.y=distance
        lintel.location.z=height+.25; lintel.scale.x=width/2
        if kind=='door-pass':
            door=bpy.data.objects['door'];door.location.x=-width/2+.1;door.location.y=distance-.03
        if 'pole' in kind:bpy.data.objects['pole'].location.y=distance-.35
        if kind=='outside-pole':bpy.data.objects['pole'].location.x=.67
        if dynamic:
            box=bpy.data.objects['box'];box.scale=(.30,.18,.80);box.location.z=.80
        poses=[(0.,-3.)]*7 if dynamic else [(y,p+5) for y,p in g.POSES]+[(0.,-3.)]*3
        frames=[]; event_labels=[]
        for index,(yaw,pitch) in enumerate(poses):
            origin=[0.,0.,1.45]
            if dynamic:
                variant=.07 if split=='test' else 0.
                if kind=='approach':box.location.x=0.;box.location.y=3.28+variant-index*.39
                elif kind=='crossing':box.location.x=1.25+variant-index*.20;box.location.y=2.03+variant
                elif kind=='receding':box.location.x=0.;box.location.y=.88+index*.41
                else:
                    box.location.x=0.;box.location.y=1.93
                    if kind=='camera-yaw':yaw=index*3.
                    else:origin[0]=index*.025
                hazardous=abs(box.location.x)<=.45+box.scale.x and box.location.y-box.scale.y<3.5
                event_labels.append({'frameId':index+1,'physicalHazard':bool(hazardous),'observationSufficient':False})
            camera.location=origin
            camera.rotation_euler=g.camera_rotation(yaw,pitch,0).to_euler()
            bpy.context.view_layer.update()
            p=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=g.W,y=g.H,scale_x=1,scale_y=1)
            fx,fy=p[0][0]*g.W/2,p[1][1]*g.H/2
            cx,cy=(1-p[0][2])*g.W/2,(1+p[1][2])*g.H/2
            prefix=f'{identity}/{index}'
            rgb=root/f'{prefix}-rgb.png';scene.render.filepath=str(rgb)
            bpy.ops.render.render(write_still=True)
            radial,lower,upper,valid=g.visible_depth(scene,camera,fx,fy,cx,cy)
            rotation=np.array(camera.matrix_world,dtype=float)[:3,:3] @ np.diag([1,-1,-1])
            frames.append({'frameId':index+1,'capturedOffsetUs':index*200000,'width':g.W,'height':g.H,
                'fx':fx,'fy':fy,'cx':cx,'cy':cy,'cameraToWalkingRotation':rotation.ravel().tolist(),
                'cameraOriginM':origin,'poseQuality':1.,'rollDeg':0.,'yawDeg':yaw,
                'pitchDeg':-pitch,'opticalPitchUpDeg':pitch,
                'projectionMatrix':np.array(p,dtype=float).ravel().tolist(),
                'rgb':{'path':f'{prefix}-rgb.png','sha256':g.sha(rgb)},
                'depth':g.asset(root,f'{prefix}-depth.f32.gz',radial.tobytes()),
                'freeZLower':g.asset(root,f'{prefix}-lower.f32.gz',lower.tobytes()),
                'surfaceZUpper':g.asset(root,f'{prefix}-upper.f32.gz',upper.tobytes()),
                'validity':g.asset(root,f'{prefix}-valid.u8.gz',valid.tobytes())})
        layouts.append({'id':identity,'split':split,'staticSyntheticScan':not dynamic,
            'decisionFrameIds':list(range(1,8)) if dynamic else [1,11,12,13],'frames':frames})
        passable=kind in ('wide','door-pass','outside-pole')
        if not dynamic:
            event_labels=[{'frameId':fid,'physicalHazard':not passable,
                'observationSufficient':passable and fid>1} for fid in [1,11,12,13]]
        hazardous_frames=[f for f in event_labels if f['physicalHazard']]
        onset=(hazardous_frames[0]['frameId']-1)*200000 if hazardous_frames else None
        labels.append({'layoutId':identity,'physicalHazard':bool(hazardous_frames),
            'idealWidthM':width-(.2 if kind=='door-pass' else 0),'idealHeadroomM':height,
            'criticalOnsetOffsetUs':onset,'latestStopOffsetUs':None if onset is None else onset+300000,
            'frames':event_labels})
        print('TEMPORAL_CORPUS '+identity,flush=True)
    g.save_json(root/'manifest.json',{'schemaVersion':1,'corpusId':'camera-temporal-passage-v1',
        'generatorPath':'tool/blender/generate_temporal_passage_corpus.py','generatorSha256':g.sha(__file__),
        'baseRendererSha256':g.sha(g.__file__),'protocolSha256':g.sha(g.REPO/'docs/camera-temporal-stability-protocol-2026-10-03.md'),
        'blenderVersion':bpy.app.version_string,'encoding':'gzip little-endian float32 row-major; NaN=unknown',
        'depthSemantics':'euclideanRangeMetres','boundsSemantics':'cameraAxisZMetresConservativeWholePixelFootprint',
        'scope':'predeclared whole-scene temporal holdout; only opaque first surfaces are consumer inputs',
        'layouts':layouts})
    g.save_json(root/'annotations.json',{'schemaVersion':1,'scope':'scoring only, never an inference input','layouts':labels})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    root=(g.REPO/args.output).resolve()
    if not root.is_relative_to(g.REPO) or root.name!='camera-temporal-passage-v1':raise ValueError('Use separate temporal corpus')
    main(root)

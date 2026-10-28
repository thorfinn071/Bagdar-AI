"""Predeclared whole-geometry holdout for camera/track association.

Frozen before implementation/testing. Only the first-return renderer sees meshes.
"""
import argparse
import sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g

# Six development scenes; sixteen never-inspected test scenes. No test fitting.
CASES = [
    ('validation','wide',2.53,1.57,2.11),
    ('validation','door-pass',2.84,1.63,2.16),
    ('validation','outside-pole',2.41,1.61,2.12),
    ('validation','boundary-pole',2.66,1.59,2.12),
    ('validation','near-box',2.88,1.63,2.14),
    ('validation','low-bar',2.59,1.57,1.49),
    ('test','wide',2.29,1.53,2.07),
    ('test','wide',2.87,1.67,2.17),
    ('test','wide',3.17,1.59,2.19),
    ('test','door-pass',2.58,1.61,2.12),
    ('test','door-pass',3.08,1.65,2.18),
    ('test','outside-pole',2.81,1.65,2.16),
    ('test','narrow',2.63,.77,2.13),
    ('test','pole',2.81,1.59,2.14),
    ('test','boundary-pole',2.93,1.61,2.14),
    ('test','low-bar',2.76,1.61,1.46),
    ('test','box',3.06,1.63,2.16),
    ('test','floor-gap',2.89,1.59,2.18),
    ('test','near-box',3.04,1.65,2.16),
    ('test','subpixel-pole',2.68,1.57,2.13),
    ('test','between-rays-pole',2.97,1.63,2.15),
    ('test','occluded-pole',3.19,1.61,2.17),
]

def main(root):
    root.mkdir(parents=True,exist_ok=True)
    layouts=[]; labels=[]
    for case_id,(split,kind,distance,width,height) in enumerate(CASES):
        identity=f'{split}-association-{kind}-{case_id:02d}'
        folder=root/identity; folder.mkdir(exist_ok=True)
        base='pole' if kind in ('outside-pole','boundary-pole') else 'box' if kind=='near-box' else kind
        scene,camera,*_=g.setup('covered-'+base,'test')
        left,right,lintel=[bpy.data.objects[n] for n in ('left','right','lintel')]
        left.location.x=-width/2-1; right.location.x=width/2+1
        for obj in (left,right,lintel):obj.location.y=distance
        lintel.location.z=height+.25; lintel.scale.x=width/2
        if kind=='door-pass':
            door=bpy.data.objects['door']; door.location.x=-width/2+.1; door.location.y=distance-.03
        if 'pole' in kind:bpy.data.objects['pole'].location.y=distance-.35
        if kind=='outside-pole':bpy.data.objects['pole'].location.x=.64
        if kind=='boundary-pole':bpy.data.objects['pole'].location.x=.445
        if kind=='box':bpy.data.objects['box'].location.y=distance-.4
        if kind=='near-box':
            box=bpy.data.objects['box'];box.location.y=.12;box.scale.y=.02
            box.location.z=.9;box.scale.z=.9
        frames=[]
        for index,(yaw,pitch) in enumerate(g.POSES):
            camera.rotation_euler=g.camera_rotation(yaw,pitch+5,0).to_euler()
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
                'cameraOriginM':[0.,0.,1.45],'poseQuality':1.,'rollDeg':0.,'yawDeg':yaw,
                'pitchDeg':-(pitch+5),'opticalPitchUpDeg':pitch+5,'scanPitchPerturbationDeg':5.,
                'projectionMatrix':np.array(p,dtype=float).ravel().tolist(),
                'rgb':{'path':f'{prefix}-rgb.png','sha256':g.sha(rgb)},
                'depth':g.asset(root,f'{prefix}-depth.f32.gz',radial.tobytes()),
                'freeZLower':g.asset(root,f'{prefix}-lower.f32.gz',lower.tobytes()),
                'surfaceZUpper':g.asset(root,f'{prefix}-upper.f32.gz',upper.tobytes()),
                'validity':g.asset(root,f'{prefix}-valid.u8.gz',valid.tobytes())})
        layouts.append({'id':identity,'split':split,'staticSyntheticScan':True,'frames':frames})
        passable=kind in ('wide','door-pass','outside-pole')
        labels.append({'layoutId':identity,'physicalHazard':not passable,'orientationUsable':True,
            'idealWidthM':width-(.2 if kind=='door-pass' else 0),'idealHeadroomM':height,
            'singleObservationSufficient':False,'scanObservationSufficient':passable,
            'criticalOnsetOffsetUs':0,'latestStopOffsetUs':300000})
        print('TRACK_CORPUS '+identity,flush=True)
    g.save_json(root/'manifest.json',{'schemaVersion':1,'corpusId':'camera-track-passage-v1',
        'generatorPath':'tool/blender/generate_track_passage_corpus.py','generatorSha256':g.sha(__file__),
        'baseRendererSha256':g.sha(g.__file__),'blenderVersion':bpy.app.version_string,
        'encoding':'gzip little-endian float32 row-major; NaN=unknown','depthSemantics':'euclideanRangeMetres',
        'boundsSemantics':'cameraAxisZMetresConservativeWholePixelFootprint',
        'scope':'predeclared whole-layout holdout for track association; no hidden geometry consumer inputs',
        'layouts':layouts})
    g.save_json(root/'annotations.json',{'schemaVersion':1,'scope':'scoring only, never an inference input','layouts':labels})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    root=(g.REPO/args.output).resolve()
    if not root.is_relative_to(g.REPO) or root.name!='camera-track-passage-v1':raise ValueError('Use separate track corpus')
    main(root)

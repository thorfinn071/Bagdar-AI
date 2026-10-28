"""Predeclared independent scenes for passage recovery; never tune on test.

Imports the already verified first-return renderer. No old corpus is mutated.
"""
import argparse
import json
import sys
from pathlib import Path
import bpy
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g

# Freeze geometry before evaluating the recovery patch. Four development
# layouts and twelve new held-out layouts, including six passable cases.
CASES = [
    ('validation','wide',2.45,1.50,2.08),
    ('validation','door-pass',2.70,1.50,2.06),
    ('validation','pole',2.35,1.45,2.06),
    ('validation','low-bar',2.80,1.50,1.55),
    ('test','wide',2.22,1.46,2.03),
    ('test','wide',2.78,1.58,2.10),
    ('test','wide',3.24,1.52,2.14),
    ('test','door-pass',2.36,1.48,2.04),
    ('test','door-pass',2.91,1.56,2.09),
    ('test','door-pass',3.31,1.62,2.13),
    ('test','narrow',2.47,.79,2.10),
    ('test','pole',2.62,1.52,2.08),
    ('test','low-bar',3.07,1.52,1.47),
    ('test','box',2.73,1.58,2.03),
    ('test','floor-gap',3.12,1.54,2.15),
    ('test','subpixel-pole',2.51,1.54,2.12),
]

def main(root):
    root.mkdir(parents=True,exist_ok=True)
    layouts=[]; labels=[]
    for case_id,(split,kind,distance,width,height) in enumerate(CASES):
        identity=f'{split}-recovery-{kind}-{case_id:02d}'
        folder=root/identity; folder.mkdir(exist_ok=True)
        scene,camera,*_=g.setup('covered-'+kind,'test')
        left,right,lintel=[bpy.data.objects[n] for n in ('left','right','lintel')]
        left.location.x=-width/2-1; right.location.x=width/2+1
        for obj in (left,right,lintel):obj.location.y=distance
        lintel.location.z=height+.25; lintel.scale.x=width/2
        if kind=='door-pass':
            door=bpy.data.objects['door']; door.location.x=-width/2+.1; door.location.y=distance-.03
        if 'pole' in kind:bpy.data.objects['pole'].location.y=distance-.35
        if kind=='box':bpy.data.objects['box'].location.y=distance-.4
        frames=[]
        for index,(yaw,pitch) in enumerate(g.POSES):
            camera.rotation_euler=g.camera_rotation(yaw,pitch+5,0).to_euler()
            bpy.context.view_layer.update()
            p=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=g.W,y=g.H,scale_x=1,scale_y=1)
            fx,fy=p[0][0]*g.W/2,p[1][1]*g.H/2
            cx,cy=(1-p[0][2])*g.W/2,(1+p[1][2])*g.H/2
            prefix=f'{identity}/{index}'
            rgb=root/f'{prefix}-rgb.png'; scene.render.filepath=str(rgb)
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
        passable=kind in ('wide','door-pass')
        labels.append({'layoutId':identity,'physicalHazard':not passable,'orientationUsable':True,
            'idealWidthM':width-(.2 if kind=='door-pass' else 0),'idealHeadroomM':height,
            'singleObservationSufficient':False,'scanObservationSufficient':passable,
            'criticalOnsetOffsetUs':0,'latestStopOffsetUs':300000})
        print('RECOVERY_CORPUS '+identity,flush=True)
    g.save_json(root/'manifest.json',{'schemaVersion':1,'corpusId':'camera-visible-passage-recovery-v1',
        'generatorPath':'tool/blender/generate_passage_recovery_corpus.py','generatorSha256':g.sha(__file__),
        'baseRendererSha256':g.sha(g.__file__),'blenderVersion':bpy.app.version_string,
        'encoding':'gzip little-endian float32 row-major; NaN=unknown','depthSemantics':'euclideanRangeMetres',
        'boundsSemantics':'cameraAxisZMetresConservativeWholePixelFootprint',
        'scope':'new whole-layout holdout for recovery, no hidden geometry inputs to producer','layouts':layouts})
    g.save_json(root/'annotations.json',{'schemaVersion':1,'scope':'scoring only, never an inference input','layouts':labels})

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    root=(g.REPO/args.output).resolve()
    if not root.is_relative_to(g.REPO) or root.name!='camera-visible-passage-recovery-v1':raise ValueError('Use separate recovery corpus')
    main(root)

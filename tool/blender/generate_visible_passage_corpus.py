"""Camera-scoped first-return corpus, with conservative pixel footprint bounds.

blender -b --python-exit-code 1 --python tool/blender/generate_visible_passage_corpus.py -- --output test/fixtures/spatial_safety/camera-visible-passage-v1

Only this renderer sees meshes. The consumer receives depth/validity/pose,
never meshes, object names, semantic masks or scoring annotations. Occluded
triangles cannot increase the free-space bound. No existing blend is modified.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix

W, H = 384, 288
REPO = Path(__file__).resolve().parents[2]
POSES = [(0., -8.)] + [(yaw, pitch) for pitch in (-65., -15., 35.) for yaw in (-60., 0., 60.)]
KINDS = ('wide', 'narrow', 'offset', 'door-pass', 'door-block', 'pole', 'low-bar', 'box', 'floor-gap', 'occluded-pole', 'subpixel-pole', 'between-rays-pole')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def cube(name, location, scale, color):
    bpy.ops.mesh.primitive_cube_add(size=2, location=location)
    obj = bpy.context.object
    obj.name, obj.scale = name, scale
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    obj.data.materials.append(mat)
    return obj


def setup(kind, split, roll=0., extra_pitch=0.):
    covered=kind.startswith('covered-')
    kind=kind.removeprefix('covered-')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    s = bpy.context.scene
    s.render.engine = 'BLENDER_EEVEE'
    s.render.resolution_x, s.render.resolution_y = W, H
    s.render.resolution_percentage = 100
    s.render.image_settings.file_format = 'PNG'
    s.render.image_settings.color_mode = 'RGB'
    s.world = bpy.data.worlds.new('world')
    s.world.color = (.15, .15, .15)
    bpy.ops.object.light_add(type='SUN', location=(1, -2, 5))
    bpy.context.object.data.energy = 2
    bpy.context.object.rotation_euler = (.4, -.3, -.4)
    # The ceiling blocks the sun. A real indoor light is necessary; uniform
    # unlit RGB would not be a meaningful camera/MiDaS observation experiment.
    bpy.ops.object.light_add(type='AREA',location=(0,1.5,2.8))
    bpy.context.object.data.energy=600
    bpy.context.object.data.shape='DISK'
    bpy.context.object.data.size=3
    # Distinct whole layouts, not neighbouring frames split into sets.
    distance = {'calibration': 2.3, 'validation': 2.65, 'test': 2.95}[split]
    width = .8 if kind == 'narrow' else 1.4
    if split == 'test':
        width += .02
    height = 1.5 if kind == 'low-bar' else 1.95
    center = .8 if kind == 'offset' else 0.
    if kind == 'floor-gap':
        cube('floor-near', (0, .8, -.05), (4, .8, .05), (.42, .40, .37))
        cube('floor-far', (0, 4.1, -.05), (4, 2.2, .05), (.42, .40, .37))
        cube('lower-floor', (0, 1.75, -.35), (4, .15, .05), (.42, .40, .37))
    else:
        cube('floor', (0, 3, -.05), (4, 4, .05), (.42, .40, .37))
    cube('back', (0, 5.5, 1.8), (4, .1, 1.8), (.52, .48, .42))
    # Positive indoor scenes need actual returns above the aperture. Empty
    # sky/no return cannot prove the near upper body volume is unobstructed.
    cube('ceiling', (0, 3, 3.05), (4, 4, .05), (.62, .60, .57))
    if covered:
        cube('room-left',(-4.05,3,1.5),(.05,4,1.5),(.5,.48,.43))
        cube('room-right',(4.05,3,1.5),(.05,4,1.5),(.5,.48,.43))
    cube('left', (center - width / 2 - 1, distance, 1.5), (1, .10, 1.5), (.45, .39, .32))
    cube('right', (center + width / 2 + 1, distance, 1.5), (1, .10, 1.5), (.45, .39, .32))
    cube('lintel', (center, distance, height + .25), (width / 2, .1, .25), (.45, .39, .32))
    if kind.startswith('door-'):
        panel = .2 if kind == 'door-pass' else .6
        cube('door', (-width / 2 + panel / 2, distance - .03, .95), (panel / 2, .08, .95), (.25, .22, .19))
    if kind in ('pole', 'occluded-pole', 'subpixel-pole', 'between-rays-pole'):
        diameter = .004 if kind == 'subpixel-pole' else .02
        x = .0073 if kind == 'between-rays-pole' else 0.
        cube('pole', (x, distance - .35, .9), (diameter / 2, diameter / 2, .9), (.18, .19, .2))
    if kind == 'occluded-pole':
        cube('occluder', (0, 1.5, 1), (.6, .06, 1), (.22, .26, .29))
    if kind == 'box':
        cube('box', (0, distance - .4, .15), (.25, .2, .15), (.25, .27, .3))
    bpy.ops.object.camera_add(location=(0, 0, 1.45))
    c = bpy.context.object
    c.data.lens, c.data.sensor_width = 26., 36.
    s.camera = c
    return s, c, distance, width, height, center


def camera_rotation(yaw, pitch, roll):
    yaw, pitch, roll = map(math.radians, (yaw, pitch, roll))
    # Camera right, up, backwards in walking x/forward/height axes.
    right = np.array([math.cos(yaw), -math.sin(yaw), 0.])
    forward = np.array([math.sin(yaw)*math.cos(pitch), math.cos(yaw)*math.cos(pitch), math.sin(pitch)])
    up = np.cross(right, forward)
    r = right * math.cos(roll) + up * math.sin(roll)
    u = up * math.cos(roll) - right * math.sin(roll)
    return Matrix(np.column_stack((r, u, -forward)).tolist())


def clip_near(points, near=.01):
    out = []
    for a, b in zip(points, points[1:] + points[:1]):
        ai, bi = a[2] >= near, b[2] >= near
        if ai:
            out.append(a)
        if ai != bi:
            out.append(a + (b-a) * ((near-a[2])/(b[2]-a[2])))
    return out


def clipped_area(triangle, x, y):
    p = [q.copy() for q in triangle]
    for axis, bound, sign in ((0,x,1), (0,x+1,-1), (1,y,1), (1,y+1,-1)):
        out = []
        for a,b in zip(p,p[1:]+p[:1]):
            da,db = sign*(a[axis]-bound),sign*(b[axis]-bound)
            if da >= 0:
                out.append(a)
            if (da >= 0) != (db >= 0):
                out.append(a+(b-a)*(da/(da-db)))
        p = out
        if len(p) < 3:
            return 0.
    return abs(sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(p,p[1:]+p[:1]))) / 2


def visible_depth(scene, camera, fx, fy, cx, cy):
    """Conservative rasterization of opaque triangles in camera coordinates.

    Minimum axis depth over a WHOLE pixel footprint (not its centre) prevents
    subpixel occupancy from disappearing. Surface upper bounds are published
    only when a coplanar group covers the entire pixel and no competing plane
    can occlude it. Thus hidden surfaces never certify floor or free space.
    """
    inv = camera.matrix_world.inverted()
    groups = {}
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in scene.objects:
        if obj.type != 'MESH':
            continue
        e = obj.evaluated_get(deps)
        mesh = e.to_mesh()
        mesh.calc_loop_triangles()
        pts = []
        for v in mesh.vertices:
            p = inv @ (e.matrix_world @ v.co)
            pts.append(np.array([p.x, -p.y, -p.z]))
        for tri in mesh.loop_triangles:
            poly = clip_near([pts[i] for i in tri.vertices])
            for i in range(1, len(poly)-1):
                t = np.array([poly[0],poly[i],poly[i+1]])
                screen = t[:,:2] / t[:,2,None] * [fx,fy] + [cx,cy]
                try:
                    coef = np.linalg.solve(np.column_stack((screen,np.ones(3))),1/t[:,2])
                except np.linalg.LinAlgError:
                    continue
                key = tuple(np.round(coef, 9))
                groups.setdefault(key, []).append((screen,coef))
        e.to_mesh_clear()
    centre = np.full((H,W),np.inf)
    lower = np.full((H,W),np.inf)
    records = []
    for triangles in groups.values():
        covered = np.zeros((H,W))
        nearest = np.full((H,W),np.inf)
        farthest = np.zeros((H,W))
        hit_centre = np.full((H,W),np.inf)
        for t,coef in triangles:
            x0=max(0,int(math.floor(t[:,0].min()))); x1=min(W,int(math.ceil(t[:,0].max())))
            y0=max(0,int(math.floor(t[:,1].min()))); y1=min(H,int(math.ceil(t[:,1].max())))
            if x0>=x1 or y0>=y1:
                continue
            xx,yy=np.meshgrid(np.arange(x0,x1)+.5,np.arange(y0,y1)+.5)
            signed=[]
            orientation=np.cross(t[1]-t[0],t[2]-t[0])
            sign=1 if orientation>=0 else -1
            for a,b in zip(t,np.roll(t,-1,axis=0)):
                dx,dy=b-a
                v=sign*(dx*(yy-a[1])-dy*(xx-a[0]))
                radius=(abs(dx)+abs(dy))*.5
                signed.append((v,radius))
            overlap=np.logical_and.reduce([v+r>=-1e-9 for v,r in signed])
            inside=np.logical_and.reduce([v-r>=-1e-9 for v,r in signed])
            at_centre=np.logical_and.reduce([v>=-1e-9 for v,r in signed])
            inverse=coef[0]*xx+coef[1]*yy+coef[2]
            spread=(abs(coef[0])+abs(coef[1]))*.5
            lo=np.where(overlap & (inverse+spread>0),1/np.maximum(inverse+spread,1e-20),np.inf)
            hi=np.where(overlap & (inverse-spread>0),1/np.maximum(inverse-spread,1e-20),np.inf)
            sub=nearest[y0:y1,x0:x1]; np.minimum(sub,lo,out=sub)
            sub=farthest[y0:y1,x0:x1]; np.maximum(sub,np.where(overlap,hi,0),out=sub)
            sub=hit_centre[y0:y1,x0:x1]; np.minimum(sub,np.where(at_centre & (inverse>0),1/np.maximum(inverse,1e-20),np.inf),out=sub)
            area=inside.astype(float)
            for iy,ix in np.argwhere(overlap & ~inside):
                area[iy,ix]=clipped_area(t,x0+ix,y0+iy)
            covered[y0:y1,x0:x1]+=area
        np.minimum(centre,hit_centre,out=centre)
        np.minimum(lower,nearest,out=lower)
        records.append((covered,nearest,farthest,hit_centre))
    upper=np.full((H,W),np.nan)
    for index,(covered,nearest,farthest,hit_centre) in enumerate(records):
        full=(covered>=1-1e-7) & np.isfinite(hit_centre) & (abs(hit_centre-centre)<1e-5)
        for other,(oc,on,of,oh) in enumerate(records):
            if other!=index:
                full &= on > farthest + 1e-7
        upper[full]=farthest[full]
    xx,yy=np.meshgrid(np.arange(W)+.5,np.arange(H)+.5)
    ray_length=np.sqrt(1+((xx-cx)/fx)**2+((yy-cy)/fy)**2)
    valid=np.isfinite(centre) & (centre*ray_length<=20)
    radial=np.where(valid,centre*ray_length,np.nan)
    lower=np.where(valid & np.isfinite(lower),np.maximum(0,lower-1e-5),np.nan)
    upper=np.where(valid & np.isfinite(upper),upper+1e-5,np.nan)
    return radial.astype('<f4'),lower.astype('<f4'),upper.astype('<f4'),valid.astype('uint8')


def asset(root, path, data):
    with gzip.GzipFile(filename=str(root/path),mode='wb',mtime=0) as f:
        f.write(data)
    return {'path':path,'sha256':sha(root/path)}


def generate(root, extend=False, rgb_only=False, metadata_only=False):
    root.mkdir(parents=True,exist_ok=True)
    layouts=[]; labels=[]
    previous_frames={}
    if rgb_only or metadata_only:
        old=json.loads((root/'manifest.json').read_text(encoding='utf-8'))
        previous_frames={(l['id'],i):f for l in old['layouts'] for i,f in enumerate(l['frames'])}
    cases=[('calibration','wide',0.,0.,i) for i in range(4)]
    cases += [(split,kind,0.,0.,0) for split in ('validation','test') for kind in KINDS]
    cases += [(split,'wide',roll,pitch,0) for split in ('validation','test') for roll,pitch in ((0.,10.),(15.,0.),(35.,0.))]
    covered_cases=[(split,kind,0.,5.,0) for split in ('validation','test') for kind in ('covered-wide','covered-door-pass')]
    cases+=covered_cases
    if extend:
        layouts=json.loads((root/'manifest.json').read_text(encoding='utf-8'))['layouts']
        labels=json.loads((root/'annotations.json').read_text(encoding='utf-8'))['layouts']
        layouts=[l for l in layouts if '-covered-' not in l['id']]
        labels=[l for l in labels if '-covered-' not in l['layoutId']]
        for label in labels:label['scanObservationSufficient']=False
        cases=covered_cases
    for split,kind,roll,pitch,variant in cases:
        identity=f'{split}-{kind}-r{roll:g}-p{pitch:g}-v{variant}'
        folder=root/identity; folder.mkdir(exist_ok=True)
        s,c,distance,width,height,center=setup(kind,split,roll,pitch)
        if split=='calibration':
            # Independent geometric scales for the affine inverse-depth fit.
            for obj in s.objects:
                if obj.type=='MESH':
                    obj.location.y += variant*.35
        frames=[]
        for index,(yaw,elevation) in enumerate(POSES):
            c.rotation_euler=camera_rotation(yaw,elevation+pitch,roll).to_euler()
            bpy.context.view_layer.update()
            p=c.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=W,y=H,scale_x=1,scale_y=1)
            fx,fy=p[0][0]*W/2,p[1][1]*H/2
            cx,cy=(1-p[0][2])*W/2,(1+p[1][2])*H/2
            pose_metadata={'yawDeg':yaw,'pitchDeg':-(elevation+pitch),
                'opticalPitchUpDeg':elevation+pitch,'scanPitchPerturbationDeg':pitch,
                'projectionMatrix':np.array(p,dtype=float).ravel().tolist()}
            if metadata_only:
                old_frame=previous_frames[(identity,index)]
                assert abs(old_frame['fx']-fx)<1e-6 and abs(old_frame['fy']-fy)<1e-6
                rotation=np.array(c.matrix_world,dtype=float)[:3,:3] @ np.diag([1,-1,-1])
                assert np.allclose(rotation.ravel(),old_frame['cameraToWalkingRotation'],atol=1e-6)
                frames.append({**old_frame,**pose_metadata})
                continue
            rgb=folder/f'{index}-rgb.png'; s.render.filepath=str(rgb)
            bpy.ops.render.render(write_still=True)
            if rgb_only:
                old_frame=previous_frames[(identity,index)]
                assert abs(old_frame['fx']-fx)<1e-6 and abs(old_frame['fy']-fy)<1e-6
                frames.append({**old_frame,**pose_metadata,'rgb':{'path':f'{identity}/{index}-rgb.png','sha256':sha(rgb)}})
                continue
            radial,lower,upper,valid=visible_depth(s,c,fx,fy,cx,cy)
            world=np.array(c.matrix_world,dtype=float)
            # Camera coordinates here are right/down/forward. Walking is x/y/z.
            r=world[:3,:3] @ np.diag([1,-1,-1])
            prefix=f'{identity}/{index}'
            frames.append({'frameId':index+1,'capturedOffsetUs':index*200000,'width':W,'height':H,
                'fx':fx,'fy':fy,'cx':cx,'cy':cy,'cameraToWalkingRotation':r.ravel().tolist(),
                'cameraOriginM':[0.,0.,1.45], 'poseQuality':1.,'rollDeg':roll,**pose_metadata,
                'rgb':{'path':f'{prefix}-rgb.png','sha256':sha(rgb)},
                'depth':asset(root,f'{prefix}-depth.f32.gz',radial.tobytes()),
                'freeZLower':asset(root,f'{prefix}-lower.f32.gz',lower.tobytes()),
                'surfaceZUpper':asset(root,f'{prefix}-upper.f32.gz',upper.tobytes()),
                'validity':asset(root,f'{prefix}-valid.u8.gz',valid.tobytes())})
        layouts.append({'id':identity,'split':split,'staticSyntheticScan':True,'frames':frames})
        hazard=kind not in ('wide','door-pass','covered-wide','covered-door-pass')
        labels.append({'layoutId':identity,'physicalHazard':hazard,'orientationUsable':abs(roll)<=20,
                       'idealWidthM':width-(.2 if kind.endswith('door-pass') else .6 if kind=='door-block' else 0),
                       'idealHeadroomM':height,'singleObservationSufficient':False,
                       'scanObservationSufficient':kind.startswith('covered-') and abs(roll)<=20,
                       'criticalOnsetOffsetUs':0,'latestStopOffsetUs':300000})
        print(f'CAMERA_CORPUS {identity}',flush=True)
    manifest={'schemaVersion':1,'corpusId':'camera-visible-passage-v1','generatorSha256':sha(__file__),
              'blenderVersion':bpy.app.version_string,'encoding':'gzip little-endian float32 row-major; NaN=unknown',
              'depthSemantics':'euclideanRangeMetres','boundsSemantics':'cameraAxisZMetresConservativeWholePixelFootprint',
              'scope':'opaque first-return synthetic camera; no hidden geometry inputs to producer',
              'layouts':layouts}
    save_json(root/'manifest.json',manifest)
    save_json(root/'annotations.json',{'schemaVersion':1,'scope':'scoring only, never an inference input','layouts':labels})
    print(f'Wrote {len(layouts)} layouts, {sum(len(x["frames"]) for x in layouts)} camera views',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--output',required=True)
    parser.add_argument('--extend-covered',action='store_true',help='Render only new enclosed positive layouts; preserve existing views')
    parser.add_argument('--relight-rgb',action='store_true',help='Rerender lighting only, retaining identical camera/depth geometry')
    parser.add_argument('--refresh-pose-metadata',action='store_true',help='Refresh projection/angle metadata; verify poses, preserve RGB and depth')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    root=(REPO/args.output).resolve()
    if not root.is_relative_to(REPO) or root.name!='camera-visible-passage-v1':
        raise ValueError('Use the separate camera-visible-passage-v1 corpus directory')
    generate(root,args.extend_covered,args.relight_rgb,args.refresh_pose_metadata)

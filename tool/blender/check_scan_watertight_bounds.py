"""Independent ray and negative witnesses for the canonical height supplement."""
import gzip,hashlib,json,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import visible_complete_surface_bounds as prior
from visible_floor_height_bounds import floor_heights

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(base,asset):
    return np.frombuffer(gzip.decompress((base/asset['path']).read_bytes()),dtype='<f4').reshape(240,320)

def main():
    corpus=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
    cm=json.loads((corpus/'corpus-manifest.json').read_text())
    axisroot=ROOT/'test/fixtures/spatial_safety/blender-scan-coverage-v1'
    complete=ROOT/'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1'
    manifest=json.loads((complete/'manifest.json').read_text())
    row=next(s for s in cm['sequences'] if s['sceneId']=='path-clear')
    bpy.ops.wm.open_mainfile(filepath=str(corpus/row['scene']['path']))
    scene,camera=bpy.context.scene,bpy.context.scene.camera;scene.frame_set(11)
    camera.rotation_euler=g.camera_rotation(0,-25,0).to_euler();bpy.context.view_layer.update()
    packet=manifest['layouts'][0]['frames'][4];axis=packet['axisPacket']
    radial=load(axisroot,axis['depth']);oldlo=load(complete,packet['heightLower']);oldhi=load(complete,packet['heightUpper'])
    lo,hi,count=floor_heights(scene,camera,axis['fx'],axis['fy'],160,120,radial,oldlo,oldhi)
    assert oldlo[111,150]<-.15 and lo[111,150]>-.001 and hi[111,150]<.001
    deps=bpy.context.evaluated_depsgraph_get();witnesses=0
    for y,x in np.argwhere(np.isfinite(lo)&((lo!=oldlo)|(hi!=oldhi)))[::5]:
        for du,dv in ((.001,.001),(.999,.001),(.001,.999),(.999,.999),(.5,.5)):
            ray=Vector(((x+du-160)/axis['fx'],-(y+dv-120)/axis['fy'],-1)).normalized()
            hit,point,*_=scene.ray_cast(deps,camera.location,camera.matrix_world.to_quaternion()@ray,distance=100)
            assert hit and lo[y,x]<=point.z+2e-5 and hi[y,x]>=point.z-2e-5
            witnesses+=1
    assert witnesses>0
    # An opaque foreground cover makes added hidden geometry irrelevant.
    g.cube('cover',(0,camera.location.y+1.2,1.5),(8,.1,5),(.2,.2,.2));bpy.context.view_layer.update()
    args=(scene,camera,axis['fx']*.3,axis['fy']*.3,48,36,96,72)
    before=prior.visible_depth(*args)
    bh=floor_heights(scene,camera,*args[2:6],before[0],before[4],before[5])[:2]
    g.cube('hidden',(0,camera.location.y+2.2,1),(.2,.1,.5),(.5,.1,.1));bpy.context.view_layer.update()
    after=prior.visible_depth(*args)
    ah=floor_heights(scene,camera,*args[2:6],after[0],after[4],after[5])[:2]
    assert all(a.tobytes()==b.tobytes() for a,b in zip(bh,ah))
    # Thin foreground at floor height: no centre-ray clearing may erase it.
    g.setup('wide','test');scene,camera=bpy.context.scene,bpy.context.scene.camera
    camera.rotation_euler=g.camera_rotation(0,-25,0).to_euler();bpy.context.view_layer.update()
    g.cube('off-centre-pole',(.027,1.3,.15),(.0005,.02,.15),(.2,.2,.2));bpy.context.view_layer.update()
    small=prior.visible_depth(scene,camera,90,90,64,48,128,96)
    lows,highs,_=floor_heights(scene,camera,90,90,64,48,small[0],small[4],small[5])
    # Every previously certified non-floor foreground pixel stays non-floor
    # or becomes unknown; the supplement must not turn it into floor support.
    unsafe=np.isfinite(small[5])&(small[5]>.1)&np.isfinite(small[4])&(small[4]<.05)
    assert np.count_nonzero(unsafe)>0
    assert not np.any(unsafe&np.isfinite(highs)&(highs<=.05)&np.isfinite(lows)&(lows>=-.05))
    paths=['tool/blender/check_scan_watertight_bounds.py','tool/blender/visible_floor_height_bounds.py',
           'tool/blender/pixel_watertight_surface_envelope.py','tool/blender/watertight_surface_projection.py',
           'tool/blender/test_pixel_watertight_surface_envelope.py',
           'docs/blender-scan-watertight-protocol-2026-10-04.md']
    receipt={'passed':True,'promotionAllowed':False,'localizedSlabBottomRemoved':True,
             'recomputedPixels':count,'fractionalHeightRayWitnesses':witnesses,
             'hiddenGeometryExact':True,'thinForegroundPixelsRetained':int(np.count_nonzero(unsafe)),
             'sources':{p:sha(ROOT/p) for p in paths}}
    target=ROOT/'docs/_baseline_logs/blender_scan_watertight_bounds_v1.json'
    if target.exists():raise ValueError('Canonical projection receipt is write-once')
    target.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt),flush=True)

if __name__=='__main__':main()

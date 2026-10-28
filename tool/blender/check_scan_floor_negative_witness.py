"""Before/after witness isolating an actual off-centre floor obstruction."""
import hashlib,json,sys
from pathlib import Path
import bpy,numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import visible_complete_surface_bounds as prior
from visible_exact_floor_height_bounds import floor_heights

def main():
    scene,camera,*_=g.setup('wide','test')
    camera.rotation_euler=g.camera_rotation(0,-25,0).to_euler()
    bpy.context.view_layer.update()
    args=(scene,camera,90,90,64,48,128,96)
    before=prior.visible_depth(*args)
    before_height=floor_heights(scene,camera,*args[2:6],before[0],before[4],before[5])[:2]
    g.cube('off-centre-pole',(.027,1.3,.15),(.0005,.02,.15),(.2,.2,.2))
    bpy.context.view_layer.update()
    after=prior.visible_depth(*args)
    after_height=floor_heights(scene,camera,*args[2:6],after[0],after[4],after[5])[:2]
    floor=np.isfinite(before_height[0])&np.isfinite(before_height[1])&(before_height[0]>=-.05)&(before_height[1]<=.05)
    # The new foreground is the sole scene mutation. A smaller whole-pixel
    # free bound with identical centre range isolates rays missed at centre.
    affected=floor&np.isfinite(after[6])&np.isfinite(before[6])&(after[6]<before[6]-.1)&(abs(after[0]-before[0])<1e-4)
    count=int(affected.sum())
    assert count>0,'No isolated off-centre foreground witness'
    cleared=np.isfinite(after_height[0])&np.isfinite(after_height[1])&(after_height[0]>=-.05)&(after_height[1]<=.05)
    assert not np.any(affected&cleared),'A real foreground was incorrectly certified as floor'
    sources={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in
             ['tool/blender/check_scan_floor_negative_witness.py','tool/blender/visible_exact_floor_height_bounds.py',
              'tool/blender/pixel_exact_surface_envelope.py','tool/blender/watertight_surface_projection.py',
              'tool/blender/visible_complete_surface_bounds.py','tool/blender/generate_visible_passage_corpus.py']}
    report={'passed':True,'promotionAllowed':False,'isolatedOffCentreForegroundPixels':count,
            'incorrectlyCertifiedFloorPixels':0,'sources':sources}
    target=ROOT/'docs/_baseline_logs/blender_scan_floor_negative_witness_v1.json'
    if target.exists():raise ValueError('Floor negative witness is write-once')
    target.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report),flush=True)

if __name__=='__main__':main()

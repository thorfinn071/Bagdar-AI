"""A thin off-centre foreground must constrain the new independent free-Z."""
import hashlib
import json
from pathlib import Path
import sys
import bpy
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as g
import visible_complete_surface_bounds as renderer
ROOT=Path(__file__).resolve().parents[2]


def main():
    scene,camera,*_=g.setup('wide','validation')
    camera.rotation_euler=g.camera_rotation(0,-8,0).to_euler()
    bpy.context.view_layer.update()
    p=camera.calc_matrix_camera(bpy.context.evaluated_depsgraph_get(),x=96,y=72,scale_x=1,scale_y=1)
    args=(scene,camera,p[0][0]*48,p[1][1]*36,48,36,96,72)
    before=renderer.visible_depth(*args)
    g.cube('between-rays',(0,1.4,1.45),(.0005,.0005,.4),(.2,.2,.2))
    bpy.context.view_layer.update()
    thin=renderer.visible_depth(*args)
    affected=np.isfinite(thin[6]) & (thin[6]<before[6]-.1) & (abs(thin[0]-before[0])<1e-4)
    count=int(affected.sum())
    assert count>0, 'Independent free bound erased a subpixel foreground'
    sources={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in
             ['tool/blender/check_scan_complete_negatives.py','tool/blender/visible_complete_surface_bounds.py',
              'tool/blender/pixel_complete_surface_envelope.py','tool/blender/generate_visible_passage_corpus.py']}
    receipt={'passed':True,'promotionAllowed':False,'offCentreForegroundPixelsRetained':count,'sources':sources}
    target=ROOT/'docs/_baseline_logs/blender_scan_complete_negatives_v1.json'
    if target.exists(): raise ValueError('Negative receipt is write-once')
    target.write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(receipt),flush=True)


if __name__=='__main__': main()

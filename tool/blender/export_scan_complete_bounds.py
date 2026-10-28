"""Additional height envelopes; byte-preserve the four v1 optical arrays."""
import gzip
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
RGB=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
PRIOR=ROOT/'test/fixtures/spatial_safety/blender-scan-coverage-v1'
OUTPUT=ROOT/'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1'
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as rotations
import visible_complete_surface_bounds as renderer


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path,data):
    path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')


def main():
    if (OUTPUT/'manifest.json').exists(): raise ValueError('Completed height export is immutable')
    prior=json.loads((PRIOR/'manifest.json').read_text())
    corpus=json.loads((RGB/'corpus-manifest.json').read_text())
    receipt=json.loads((ROOT/'docs/_baseline_logs/blender_scan_complete_bounds_v1.json').read_text())
    assert receipt['passed'] is True
    for p,expected in receipt['sources'].items(): assert sha(ROOT/p)==expected
    negatives=json.loads((ROOT/'docs/_baseline_logs/blender_scan_complete_negatives_v1.json').read_text())
    assert negatives['passed'] is True and negatives['offCentreForegroundPixelsRetained']>0
    for p,expected in negatives['sources'].items(): assert sha(ROOT/p)==expected
    paths=['tool/blender/export_scan_complete_bounds.py','tool/blender/visible_complete_surface_bounds.py',
           'tool/blender/pixel_complete_surface_envelope.py','tool/blender/test_pixel_complete_surface_envelope.py',
           'tool/blender/check_scan_complete_bounds.py','docs/_baseline_logs/blender_scan_complete_bounds_v1.json',
           'docs/blender-scan-complete-envelope-protocol-2026-10-04.md',
           'tool/blender/check_scan_complete_negatives.py','docs/_baseline_logs/blender_scan_complete_negatives_v1.json']
    sources={p:sha(ROOT/p) for p in paths}
    OUTPUT.mkdir(parents=True,exist_ok=True)
    layouts=[]
    for layout in prior['layouts']:
        scene_id=layout['sceneId']
        sequence=next(s for s in corpus['sequences'] if s['sceneId']==scene_id)
        assert sha(RGB/sequence['scene']['path'])==sequence['scene']['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(RGB/sequence['scene']['path']))
        scene,camera=bpy.context.scene,bpy.context.scene.camera
        scene.frame_set(11)
        frames=[]
        for index,(axis_packet,pose) in enumerate(zip(layout['coverageViewsNewBounds'],layout['grid']['poses'])):
            checkpoint=OUTPUT/f'{scene_id}/height-{index:02d}.json'
            identity=hashlib.sha256(json.dumps({'sources':sources,'axisPacket':axis_packet,'pose':pose},sort_keys=True).encode()).hexdigest()
            if checkpoint.exists():
                cached=json.loads(checkpoint.read_text())
                assert cached['identity']==identity
                record=cached['frame']
                for key in ('heightLower','heightUpper','firstZLower'): assert sha(OUTPUT/record[key]['path'])==record[key]['sha256']
            else:
                camera.rotation_euler=rotations.camera_rotation(*pose,0).to_euler()
                bpy.context.view_layer.update()
                arrays=renderer.visible_depth(scene,camera,axis_packet['fx'],axis_packet['fy'],axis_packet['cx'],axis_packet['cy'],320,240)
                for key,a in zip(('depth','freeZLower','surfaceZUpper','validity'),arrays[:4]):
                    assert gzip.decompress((PRIOR/axis_packet[key]['path']).read_bytes())==a.tobytes(),(scene_id,index,key)
                record={'axisPacket':axis_packet,'fourArraysExact':True}
                for key,a in zip(('heightLower','heightUpper','firstZLower'),arrays[4:]):
                    target=OUTPUT/f'{scene_id}/height-{index:02d}-{key}.f32.gz'
                    target.parent.mkdir(parents=True,exist_ok=True)
                    target.write_bytes(gzip.compress(a.tobytes(),mtime=0))
                    record[key]={'path':target.relative_to(OUTPUT).as_posix(),'sha256':sha(target)}
                save(checkpoint,{'identity':identity,'frame':record})
            frames.append(record)
            print('HEIGHT_PACKET',scene_id,index,flush=True)
        layouts.append({'sceneId':scene_id,'frames':frames})
    for p,expected in sources.items(): assert sha(ROOT/p)==expected
    save(OUTPUT/'manifest.json',{'schemaVersion':1,'corpusId':'blender-scan-complete-envelope-v1',
         'promotionAllowed':False,'scope':'synthetic first-visible height intervals only',
         'priorManifestSha256':sha(PRIOR/'manifest.json'),'sources':sources,'layouts':layouts})
    print('HEIGHT_EXPORT_COMPLETE',sum(len(l['frames']) for l in layouts),flush=True)


if __name__=='__main__': main()

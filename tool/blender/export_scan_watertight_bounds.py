"""Separate canonical height supplement; preserves all prior packet assets."""
import gzip,hashlib,json,sys
from pathlib import Path
import bpy,numpy as np
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(Path(__file__).resolve().parent))
import generate_visible_passage_corpus as rotations
from visible_floor_height_bounds import floor_heights
RGB=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
AXIS=ROOT/'test/fixtures/spatial_safety/blender-scan-coverage-v1'
PRIOR=ROOT/'test/fixtures/spatial_safety/blender-scan-complete-envelope-v1'
OUTPUT=ROOT/'test/fixtures/spatial_safety/blender-scan-watertight-height-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,data):p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def load(base,asset):
    assert sha(base/asset['path'])==asset['sha256']
    return np.frombuffer(gzip.decompress((base/asset['path']).read_bytes()),dtype='<f4').reshape(240,320)

def main():
    if (OUTPUT/'manifest.json').exists():raise ValueError('Completed supplement is immutable')
    receipt=json.loads((ROOT/'docs/_baseline_logs/blender_scan_watertight_bounds_v1.json').read_text())
    assert receipt['passed'] is True
    for p,expected in receipt['sources'].items():assert sha(ROOT/p)==expected
    sources=dict(receipt['sources'])
    for p in ['tool/blender/export_scan_watertight_bounds.py','docs/_baseline_logs/blender_scan_watertight_bounds_v1.json']:
        sources[p]=sha(ROOT/p)
    corpus=json.loads((RGB/'corpus-manifest.json').read_text())
    prior=json.loads((PRIOR/'manifest.json').read_text())
    axism=json.loads((AXIS/'manifest.json').read_text())
    OUTPUT.mkdir(parents=True,exist_ok=True);layouts=[]
    for layout in prior['layouts']:
        sid=layout['sceneId'];scene_record=next(s for s in corpus['sequences'] if s['sceneId']==sid)
        assert sha(RGB/scene_record['scene']['path'])==scene_record['scene']['sha256']
        bpy.ops.wm.open_mainfile(filepath=str(RGB/scene_record['scene']['path']))
        scene,camera=bpy.context.scene,bpy.context.scene.camera;scene.frame_set(11)
        axis_layout=next(l for l in axism['layouts'] if l['sceneId']==sid)
        frames=[]
        for index,previous in enumerate(layout['frames']):
            axis=previous['axisPacket'];pose=axis_layout['grid']['poses'][index]
            identity=hashlib.sha256(json.dumps({'sources':sources,'priorPacket':previous,'pose':pose},sort_keys=True).encode()).hexdigest()
            checkpoint=OUTPUT/f'{sid}/height-{index:02d}.json'
            if checkpoint.exists():
                cached=json.loads(checkpoint.read_text());assert cached['identity']==identity
                record=cached['frame']
                for key in ('heightLower','heightUpper'):assert sha(OUTPUT/record[key]['path'])==record[key]['sha256']
            else:
                camera.rotation_euler=rotations.camera_rotation(*pose,0).to_euler();bpy.context.view_layer.update()
                lo,hi,count=floor_heights(scene,camera,axis['fx'],axis['fy'],axis['cx'],axis['cy'],
                    load(AXIS,axis['depth']),load(PRIOR,previous['heightLower']),load(PRIOR,previous['heightUpper']))
                record={'priorPacket':previous,'recomputedPixels':count}
                for key,array in [('heightLower',lo),('heightUpper',hi)]:
                    target=OUTPUT/f'{sid}/height-{index:02d}-{key}.f32.gz';target.parent.mkdir(parents=True,exist_ok=True)
                    target.write_bytes(gzip.compress(array.tobytes(),mtime=0))
                    record[key]={'path':target.relative_to(OUTPUT).as_posix(),'sha256':sha(target)}
                save(checkpoint,{'identity':identity,'frame':record})
            frames.append(record);print('CANONICAL_PACKET',sid,index,record['recomputedPixels'],flush=True)
        layouts.append({'sceneId':sid,'frames':frames})
    for p,expected in sources.items():assert sha(ROOT/p)==expected
    save(OUTPUT/'manifest.json',{'schemaVersion':1,'corpusId':'blender-scan-watertight-height-v1',
        'promotionAllowed':False,'scope':'canonical shared boundaries; independent whole-pixel heights',
        'priorManifestSha256':sha(PRIOR/'manifest.json'),'sources':sources,'layouts':layouts})
    print('CANONICAL_EXPORT_COMPLETE',sum(len(l['frames']) for l in layouts),flush=True)

if __name__=='__main__':main()

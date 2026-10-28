"""Verify visible packets and pinned identity without scoring decisions."""
import gzip
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-metric-motion-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def asset(folder,entry):
    path=(folder/entry['path']).resolve()
    assert path.is_relative_to(folder) and sha(path)==entry['sha256'],'Asset path/hash mismatch'
    return path
def verify():
    m=json.loads((CORPUS/'manifest.json').read_text())
    assert m['corpusId']=='camera-metric-motion-v1' and len(m['layouts'])==17
    assert sum(l['split']=='validation' for l in m['layouts'])==7
    assert sum(l['split']=='test' for l in m['layouts'])==10
    assert m['generatorSha256']==sha(ROOT/m['generatorPath'])
    assert m['baseRendererSha256']==sha(ROOT/'tool/blender/generate_visible_passage_corpus.py')
    assert m['protocolSha256']==sha(ROOT/'docs/camera-metric-motion-protocol-2026-10-03.md')
    old=set()
    for name in ['camera-visible-passage-v1','camera-visible-passage-recovery-v1','camera-track-passage-v1','camera-temporal-passage-v1']:
        folder=CORPUS.parent/name
        for l in json.loads((folder/'manifest.json').read_text())['layouts']:
            rgb=np.asarray(Image.open(folder/l['frames'][0]['rgb']['path']).convert('RGB'))
            old.add(hashlib.sha256(rgb.tobytes()).hexdigest())
    ids=set();signatures=set();expected={}
    for l in m['layouts']:
        assert set(l)=={'id','split','staticSyntheticScan','decisionFrameIds','frames'}
        assert l['id'] not in ids;ids.add(l['id'])
        anchor=np.asarray(Image.open(asset(CORPUS,l['frames'][0]['rgb'])).convert('RGB'))
        signature=hashlib.sha256(anchor.tobytes()).hexdigest()
        assert signature not in old and signature not in signatures,'Pixel-identical scene leakage'
        signatures.add(signature)
        static=l['staticSyntheticScan'];assert len(l['frames'])==(13 if static else 7)
        assert l['decisionFrameIds']==([1,11,12,13] if static else list(range(1,8)))
        if static:assert {(f['yawDeg'],f['opticalPitchUpDeg']) for f in l['frames'][1:10]}=={(y,p) for y in (-60.,0.,60.) for p in (-65.,-15.,35.)}
        for index,f in enumerate(l['frames']):
            expected[l['id'],f['frameId']]=f
            assert f['frameId']==index+1 and f['capturedOffsetUs']==index*200000
            assert not ({'objectVelocity','objectBounds','mesh','objectMask','expectedDecision'} & set(f))
            r=np.array(f['cameraToWalkingRotation']).reshape(3,3)
            assert np.allclose(r.T@r,np.eye(3),atol=1e-5) and np.isclose(np.linalg.det(r),1)
            p=np.array(f['projectionMatrix']).reshape(4,4);w,h=f['width'],f['height']
            assert abs(p[0,0]*w/2-f['fx'])<1e-6 and abs(p[1,1]*h/2-f['fy'])<1e-6
            assert abs((1-p[0,2])*w/2-f['cx'])<1e-6 and abs((1+p[1,2])*h/2-f['cy'])<1e-6
            range_m,lo,hi=[np.frombuffer(gzip.decompress(asset(CORPUS,f[k]).read_bytes()),dtype='<f4').reshape(h,w) for k in ('depth','freeZLower','surfaceZUpper')]
            valid=np.frombuffer(gzip.decompress(asset(CORPUS,f['validity']).read_bytes()),dtype='uint8').reshape(h,w)
            assert set(np.unique(valid))<={0,1};valid=valid.astype(bool)
            assert np.array_equal(valid,np.isfinite(range_m)) and np.isnan(lo[~valid]).all() and np.isnan(hi[~valid]).all()
            xx,yy=np.meshgrid(np.arange(w)+.5,np.arange(h)+.5)
            axis=range_m/np.sqrt(1+((xx-f['cx'])/f['fx'])**2+((yy-f['cy'])/f['fy'])**2)
            assert np.all(lo[valid]>=0) and np.all(lo[valid]<=axis[valid]+1e-4)
            full=valid&np.isfinite(hi);assert np.all(hi[full]>=axis[full]-1e-4) and np.all(hi[full]>=lo[full])
            asset(CORPUS,f['rgb'])
    labels=json.loads((CORPUS/'annotations.json').read_text())['layouts']
    assert {l['layoutId'] for l in labels}==ids
    n=json.loads((CORPUS/'ncnn/manifest.json').read_text());assert n['corpusManifestSha256']==sha(CORPUS/'manifest.json')
    assert n['generatorSha256']==sha(ROOT/'tool/model_benchmark/generate_metric_motion_ncnn.py')
    assert n['modelParamSha256']==sha(ROOT/'assets/midas_small.ncnn.param') and n['modelBinSha256']==sha(ROOT/'assets/midas_small.ncnn.bin')
    original=CORPUS.parent/'camera-visible-passage-v1/ncnn/manifest.json'
    assert n['frozenCalibrationSourceSha256']==sha(original) and not n['newScenesUsedForFit']
    assert n['calibration']==json.loads(original.read_text())['calibration'] and not n['calibration']['accepted']
    seen=set()
    for f in n['frames']:
        key=f['layoutId'],f['frameId'];assert key not in seen;seen.add(key)
        assert f['rgbSha256']==expected[key]['rgb']['sha256'] and f['variant']=='clean'
        raw=np.frombuffer(gzip.decompress(asset(CORPUS/'ncnn',f).read_bytes()),dtype='<f4')
        assert raw.size==65536 and np.isfinite(raw).all()
        pixels=gzip.decompress(asset(CORPUS/'ncnn',f['rgbPixels']).read_bytes())
        assert pixels==np.asarray(Image.open(asset(CORPUS,expected[key]['rgb'])).convert('RGB'),dtype=np.uint8).tobytes()
    assert seen==set(expected)
    for path in ['lib/safety/perception/camera_metric_motion.dart','lib/safety/runtime/camera_metric_motion_shadow_scene.dart']:
        source=(ROOT/path).read_text()
        assert 'dart:io' not in source and 'annotations' not in source and 'bpy' not in source
    print(f'Metric motion: {len(ids)} independent scenes, {len(expected)} visible RGB/depth pairs; no duplicate anchors or hidden inputs')
if __name__=='__main__':verify()

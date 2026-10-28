"""Temporal corpus integrity without evaluating neural or planner outcomes."""
import gzip
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-temporal-passage-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def asset(item):
    p=(CORPUS/item['path']).resolve()
    assert p.is_relative_to(CORPUS) and sha(p)==item['sha256'],'Asset path/hash mismatch'
    return p

def verify():
    m=json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    assert m['corpusId']=='camera-temporal-passage-v1'
    assert m['generatorSha256']==sha(ROOT/m['generatorPath'])
    assert m['baseRendererSha256']==sha(ROOT/'tool/blender/generate_visible_passage_corpus.py')
    assert m['protocolSha256']==sha(ROOT/'docs/camera-temporal-stability-protocol-2026-10-03.md')
    assert len(m['layouts'])==18
    assert sum(l['split']=='validation' for l in m['layouts'])==6
    assert sum(l['split']=='test' for l in m['layouts'])==12
    previous_signatures=set()
    for name in ['camera-visible-passage-v1','camera-visible-passage-recovery-v1','camera-track-passage-v1']:
        previous=json.loads((CORPUS.parent/name/'manifest.json').read_text(encoding='utf-8'))
        previous_signatures.update(l['frames'][0]['rgb']['sha256'] for l in previous['layouts'])
    ids=set();signatures=set();views=0
    for layout in m['layouts']:
        assert layout['id'] not in ids;ids.add(layout['id'])
        assert layout['split'] in ('validation','test')
        sig=layout['frames'][0]['rgb']['sha256']
        assert sig not in signatures and sig not in previous_signatures;signatures.add(sig)
        frames=layout['frames'];static=layout['staticSyntheticScan']
        assert len(frames)==(13 if static else 7)
        assert layout['decisionFrameIds']==([1,11,12,13] if static else list(range(1,8)))
        if static:
            assert {(f['yawDeg'],f['opticalPitchUpDeg']-5) for f in frames[1:10]}=={(y,p) for y in (-60.,0.,60.) for p in (-65.,-15.,35.)}
            for f in frames[10:]:
                # Actual repeated render, not a detector outcome or copied NN map.
                # PNG Date/RenderTime metadata can differ; inference reads RGB.
                assert np.array_equal(np.asarray(Image.open(asset(f['rgb'])).convert('RGB')),
                    np.asarray(Image.open(asset(frames[0]['rgb'])).convert('RGB')))
                assert gzip.decompress(asset(f['depth']).read_bytes())==gzip.decompress(asset(frames[0]['depth']).read_bytes())
        else:assert len({f['rgb']['sha256'] for f in frames})==7
        for index,f in enumerate(frames):
            views+=1;assert f['frameId']==index+1 and f['capturedOffsetUs']==index*200000
            assert abs(f['fx']-f['fy'])<.001 and f['poseQuality']==1
            r=np.array(f['cameraToWalkingRotation']).reshape(3,3)
            assert np.allclose(r.T@r,np.eye(3),atol=1e-5) and np.isclose(np.linalg.det(r),1)
            w,h=f['width'],f['height'];p=np.array(f['projectionMatrix']).reshape(4,4)
            assert abs(p[0,0]*w/2-f['fx'])<1e-6 and abs(p[1,1]*h/2-f['fy'])<1e-6
            assert abs((1-p[0,2])*w/2-f['cx'])<1e-6 and abs((1+p[1,2])*h/2-f['cy'])<1e-6
            assert f['pitchDeg']==-f['opticalPitchUpDeg']
            yaw,pitch=np.deg2rad([f['yawDeg'],f['opticalPitchUpDeg']])
            assert np.allclose(r[:,2],[np.sin(yaw)*np.cos(pitch),np.cos(yaw)*np.cos(pitch),np.sin(pitch)],atol=1e-5)
            z,lo,hi=[np.frombuffer(gzip.decompress(asset(f[k]).read_bytes()),dtype='<f4').reshape(h,w) for k in ('depth','freeZLower','surfaceZUpper')]
            valid=np.frombuffer(gzip.decompress(asset(f['validity']).read_bytes()),dtype='uint8').reshape(h,w)
            assert set(np.unique(valid))<={0,1};valid=valid.astype(bool)
            assert np.array_equal(valid,np.isfinite(z))
            assert np.isnan(lo[~valid]).all() and np.isnan(hi[~valid]).all()
            xx,yy=np.meshgrid(np.arange(w)+.5,np.arange(h)+.5)
            axis=z/np.sqrt(1+((xx-f['cx'])/f['fx'])**2+((yy-f['cy'])/f['fy'])**2)
            assert np.all(lo[valid]>=0) and np.all(lo[valid]<=axis[valid]+1e-4)
            full=valid&np.isfinite(hi)
            assert np.all(hi[full]>=axis[full]-1e-4) and np.all(hi[full]>=lo[full])
            asset(f['rgb'])
    labels=json.loads((CORPUS/'annotations.json').read_text(encoding='utf-8'))['layouts']
    assert {l['layoutId'] for l in labels}==ids
    for l in labels:
        layout=next(x for x in m['layouts'] if x['id']==l['layoutId'])
        assert [f['frameId'] for f in l['frames']]==layout['decisionFrameIds']
        assert all(not f['observationSufficient'] for f in l['frames'] if f['physicalHazard'])
        if not layout['staticSyntheticScan']:assert all(not f['observationSufficient'] for f in l['frames'])
    n=json.loads((CORPUS/'ncnn/manifest.json').read_text(encoding='utf-8'))
    assert n['corpusManifestSha256']==sha(CORPUS/'manifest.json')
    assert n['generatorSha256']==sha(ROOT/'tool/model_benchmark/generate_temporal_passage_ncnn.py')
    assert n['inferenceHelperSha256']==sha(ROOT/'tool/model_benchmark/generate_context_ncnn_depth.py')
    frozen=CORPUS.parent/'camera-visible-passage-v1/ncnn/manifest.json'
    assert n['frozenCalibrationSourceSha256']==sha(frozen) and not n['newScenesUsedForFit']
    assert n['calibration']==json.loads(frozen.read_text(encoding='utf-8'))['calibration']
    assert n['calibration']['accepted'] is False and not n['calibration']['testUsedForFit']
    assert n['modelParamSha256']==sha(ROOT/'assets/midas_small.ncnn.param')
    assert n['modelBinSha256']==sha(ROOT/'assets/midas_small.ncnn.bin')
    assert len(n['frames'])==views
    expected={(l['id'],f['frameId']):f for l in m['layouts'] for f in l['frames']}
    seen=set()
    for f in n['frames']:
        key=(f['layoutId'],f['frameId']);assert key not in seen;seen.add(key)
        assert f['rgbSha256']==expected[key]['rgb']['sha256'] and f['variant']=='clean'
        path=(CORPUS/'ncnn'/f['path']).resolve()
        assert path.is_relative_to(CORPUS/'ncnn') and sha(path)==f['sha256']
        raw=np.frombuffer(gzip.decompress(path.read_bytes()),dtype='<f4')
        assert raw.size==65536 and np.isfinite(raw).all()
    assert seen==set(expected)
    print(f'Temporal corpus verified: {len(ids)} whole scenes, {views} views and pinned maps; annotations separate')

if __name__=='__main__':verify()

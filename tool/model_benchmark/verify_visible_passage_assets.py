"""Read-only camera corpus, split, footprint and frozen-fit integrity checks."""
import gzip
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-visible-passage-v1'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def asset(item):
    p=(CORPUS/item['path']).resolve()
    if not p.is_relative_to(CORPUS) or sha(p)!=item['sha256']:raise ValueError('Asset hash/path mismatch')
    return p

def verify():
    m=json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    recovery=CORPUS.name=='camera-visible-passage-recovery-v1'
    association=CORPUS.name=='camera-track-passage-v1'
    generator='tool/blender/generate_track_passage_corpus.py' if association else 'tool/blender/generate_passage_recovery_corpus.py' if recovery else 'tool/blender/generate_visible_passage_corpus.py'
    assert m['generatorSha256']==sha(ROOT/generator)
    if recovery or association:
        assert m['generatorPath']==generator
        assert m['baseRendererSha256']==sha(ROOT/'tool/blender/generate_visible_passage_corpus.py')
    ids=set();signatures=set();views=0
    for layout in m['layouts']:
        assert layout['id'] not in ids;ids.add(layout['id'])
        assert layout['split'] in ('calibration','validation','test')
        # Whole layouts share no baseline RGB, not just different frame IDs.
        sig=layout['frames'][0]['rgb']['sha256'];assert sig not in signatures;signatures.add(sig)
        assert {(f['yawDeg'],f['opticalPitchUpDeg']-f['scanPitchPerturbationDeg']) for f in layout['frames'][1:]}=={(yaw,pitch) for yaw in (-60.,0.,60.) for pitch in (-65.,-15.,35.)}
        previous=-1
        for f in layout['frames']:
            views+=1;assert f['capturedOffsetUs']>previous;previous=f['capturedOffsetUs']
            assert abs(f['fx']-f['fy'])<.001
            r=np.array(f['cameraToWalkingRotation']).reshape(3,3)
            assert np.allclose(r.T@r,np.eye(3),atol=1e-5) and np.isclose(np.linalg.det(r),1)
            w,h=f['width'],f['height']
            p=np.array(f['projectionMatrix']).reshape(4,4)
            assert np.isfinite(p).all()
            assert abs(p[0,0]*w/2-f['fx'])<1e-6 and abs(p[1,1]*h/2-f['fy'])<1e-6
            assert abs((1-p[0,2])*w/2-f['cx'])<1e-6 and abs((1+p[1,2])*h/2-f['cy'])<1e-6
            assert f['pitchDeg']==-f['opticalPitchUpDeg']
            yaw,pitch=np.deg2rad([f['yawDeg'],f['opticalPitchUpDeg']])
            assert np.allclose(r[:,2],[np.sin(yaw)*np.cos(pitch),np.cos(yaw)*np.cos(pitch),np.sin(pitch)],atol=1e-5)
            z,lo,hi=[np.frombuffer(gzip.decompress(asset(f[key]).read_bytes()),dtype='<f4').reshape(h,w) for key in ('depth','freeZLower','surfaceZUpper')]
            valid=np.frombuffer(gzip.decompress(asset(f['validity']).read_bytes()),dtype='uint8').reshape(h,w).astype(bool)
            assert np.array_equal(valid,np.isfinite(z))
            xx,yy=np.meshgrid(np.arange(w)+.5,np.arange(h)+.5)
            axis=z/np.sqrt(1+((xx-f['cx'])/f['fx'])**2+((yy-f['cy'])/f['fy'])**2)
            assert np.all(lo[valid]>=0) and np.all(lo[valid]<=axis[valid]+1e-4)
            full=valid&np.isfinite(hi)
            assert np.all(hi[full]>=axis[full]-1e-4) and np.all(hi[full]>=lo[full])
            asset(f['rgb'])
    labels=json.loads((CORPUS/'annotations.json').read_text(encoding='utf-8'))
    assert {l['layoutId'] for l in labels['layouts']}==ids
    n=json.loads((CORPUS/'ncnn/manifest.json').read_text(encoding='utf-8'))
    assert n['corpusManifestSha256']==sha(CORPUS/'manifest.json')
    inference='generate_track_passage_ncnn.py' if association else 'generate_passage_recovery_ncnn.py' if recovery else 'generate_visible_passage_ncnn.py'
    assert n['generatorSha256']==sha(ROOT/'tool/model_benchmark'/inference)
    if recovery or association:
        frozen=ROOT/'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json'
        assert n['frozenCalibrationSourceSha256']==sha(frozen) and not n['newScenesUsedForFit']
        assert n['calibration']==json.loads(frozen.read_text(encoding='utf-8'))['calibration']
    c=n['calibration'];assert c['fitSplit']=='calibration' and c['validationSplit']=='validation' and not c['testUsedForFit']
    for f in n['frames']:
        p=(CORPUS/'ncnn'/f['path']).resolve()
        assert p.is_relative_to(CORPUS/'ncnn') and sha(p)==f['sha256']
        raw=np.frombuffer(gzip.decompress(p.read_bytes()),dtype='<f4')
        assert raw.size==65536 and np.isfinite(raw).all()
    print(f'Visible corpus verified: {len(ids)} independent layouts, {views} views, {len(n["frames"])} NCNN maps')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--recovery',action='store_true')
    parser.add_argument('--association',action='store_true')
    args=parser.parse_args()
    if args.recovery and args.association:parser.error('Choose one corpus')
    if args.recovery:CORPUS=ROOT/'test/fixtures/spatial_safety/camera-visible-passage-recovery-v1'
    if args.association:CORPUS=ROOT/'test/fixtures/spatial_safety/camera-track-passage-v1'
    verify()

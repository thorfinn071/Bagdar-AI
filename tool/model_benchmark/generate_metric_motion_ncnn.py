"""Pinned inference on every real temporal RGB; no new metric fitting."""
import argparse
import gzip
import json
import time
from pathlib import Path
import ncnn
import numpy as np
from PIL import Image
from generate_context_ncnn_depth import PARAM, BIN, infer, ncnn_blob_names
from generate_visible_passage_ncnn import sha, save, percentile

ROOT = Path(__file__).resolve().parents[2]
CORPUS = ROOT / 'test/fixtures/spatial_safety/camera-metric-motion-v1'
OUT = CORPUS / 'ncnn'
FROZEN = ROOT / 'test/fixtures/spatial_safety/camera-visible-passage-v1/ncnn/manifest.json'

def main(check):
    manifest=json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    frozen=json.loads(FROZEN.read_text(encoding='utf-8'))
    assert frozen['modelParamSha256']==sha(PARAM) and frozen['modelBinSha256']==sha(BIN)
    OUT.mkdir(exist_ok=True)
    net=ncnn.Net();net.opt.use_vulkan_compute=False;net.opt.num_threads=1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):raise RuntimeError('Pinned model load failed')
    inp,out=ncnn_blob_names(PARAM)
    first=manifest['layouts'][0]['frames'][0]
    with Image.open(CORPUS/first['rgb']['path']) as img:warm=np.asarray(img.convert('RGB'),dtype=np.float32)/255
    ys=np.arange(256)*first['height']//256;xs=np.arange(256)*first['width']//256
    for _ in range(10):infer(net,inp,out,warm[ys[:,None],xs[None,:]])
    records=[];times=[]
    for layout in manifest['layouts']:
        for f in layout['frames']:
            start=time.perf_counter_ns()
            path=(CORPUS/f['rgb']['path']).resolve()
            if not path.is_relative_to(CORPUS) or sha(path)!=f['rgb']['sha256']:raise ValueError('RGB identity mismatch')
            with Image.open(path) as img:pixels=np.asarray(img.convert('RGB'),dtype=np.uint8)
            pixel_name=f"{layout['id']}-rgb-{f['frameId']}.u8.gz"
            if check:
                assert gzip.decompress((OUT/pixel_name).read_bytes())==pixels.tobytes(),'Decoded RGB drift'
            else:(OUT/pixel_name).write_bytes(gzip.compress(pixels.tobytes(),mtime=0))
            a=pixels.astype(np.float32)/255
            ys=np.arange(256)*f['height']//256;xs=np.arange(256)*f['width']//256
            rgb=a[ys[:,None],xs[None,:]];prep=time.perf_counter_ns()
            raw=infer(net,inp,out,rgb);end=time.perf_counter_ns()
            name=f"{layout['id']}-clean-{f['frameId']}.f32.gz"
            if check:
                if gzip.decompress((OUT/name).read_bytes())!=raw.astype('<f4').tobytes():raise ValueError('NCNN drift '+name)
            else:
                (OUT/name).write_bytes(gzip.compress(raw.astype('<f4').tobytes(),mtime=0))
                times.append({'layoutId':layout['id'],'frameId':f['frameId'],'preprocessingMs':(prep-start)/1e6,'inferenceMs':(end-prep)/1e6})
            records.append({'layoutId':layout['id'],'frameId':f['frameId'],'variant':'clean',
                'rgbSha256':f['rgb']['sha256'],'path':name,'sha256':sha(OUT/name),
                'rgbPixels':{'path':pixel_name,'sha256':sha(OUT/pixel_name)}})
        print('METRIC_MOTION_NCNN '+layout['id'],flush=True)
    receipt={'schemaVersion':1,'corpusManifestSha256':sha(CORPUS/'manifest.json'),
        'generatorSha256':sha(__file__),'modelParamSha256':sha(PARAM),'modelBinSha256':sha(BIN),
        'runtime':frozen['runtime'],'preprocessId':frozen['preprocessId'],'valueSemantics':frozen['valueSemantics'],
        'calibration':frozen['calibration'],'frozenCalibrationSourceSha256':sha(FROZEN),'newScenesUsedForFit':False,
        'inferenceHelperSha256':sha(ROOT/'tool/model_benchmark/generate_context_ncnn_depth.py'),
        'frames':records,'promotionAllowed':False}
    if check:
        assert json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))==receipt,'NCNN receipt drift'
        print('Temporal RGB maps match pinned inference and original rejected calibration')
    else:
        save(OUT/'manifest.json',receipt)
        save(ROOT/'docs/_baseline_logs/camera_metric_motion_ncnn_timing.json',{
            'scope':'measured desktop CPU serial pinned inference; excludes rendering and scan','warmupInferences':10,
            'preprocessingP50Ms':percentile([r['preprocessingMs'] for r in times],50),
            'preprocessingP95Ms':percentile([r['preprocessingMs'] for r in times],95),
            'inferenceP50Ms':percentile([r['inferenceMs'] for r in times],50),
            'inferenceP95Ms':percentile([r['inferenceMs'] for r in times],95),'frames':times})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

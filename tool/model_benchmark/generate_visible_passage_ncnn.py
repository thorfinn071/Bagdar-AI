"""Pinned NCNN maps and frozen, held-out synthetic diagnostic scale fitting.

Functional receipts are deterministic. Measured CPU times are a separate file.
The scorer alone reads exact depth; inference receives RGB only. No per-frame
test fit, oracle dropout mask, semantics or hidden geometry enters MiDaS.
"""
from __future__ import annotations
import argparse
import gzip
import hashlib
import json
import time
from pathlib import Path

import ncnn
import numpy as np
from PIL import Image, ImageFilter
from generate_context_ncnn_depth import infer, ncnn_blob_names, PARAM, BIN

ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-visible-passage-v1'
OUT=CORPUS/'ncnn'


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read_asset(item):
    p=(CORPUS/item['path']).resolve()
    if not p.is_relative_to(CORPUS) or sha(p)!=item['sha256']:
        raise ValueError('Asset path/hash mismatch')
    return p
def save(p,value):p.write_text(json.dumps(value,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def percentile(x,p):return None if not x else float(np.percentile(x,p))


def main(check):
    corpus=json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    OUT.mkdir(exist_ok=True)
    net=ncnn.Net();net.opt.use_vulkan_compute=False;net.opt.num_threads=1
    if net.load_param(str(PARAM)) or net.load_model(str(BIN)):raise RuntimeError('Model load')
    inp,out=ncnn_blob_names(PARAM)
    records=[];fit_x=[];fit_y=[];validation=[];held_out=[];times=[]
    first=read_asset(corpus['layouts'][0]['frames'][0]['rgb'])
    with Image.open(first) as img: a=np.asarray(img.convert('RGB'),dtype=np.float32)/255
    ys=np.arange(256)*a.shape[0]//256;xs=np.arange(256)*a.shape[1]//256
    for _ in range(10):infer(net,inp,out,a[ys[:,None],xs[None,:]])
    for layout in corpus['layouts']:
        variants=['clean']
        if ('-wide-r0-p0-v0' in layout['id'] or '-covered-wide-r0-p5-v0' in layout['id']) and layout['split']!='calibration':variants+=['rgb-noise','rgb-blur']
        for variant in variants:
            for f in layout['frames']:
                start=time.perf_counter_ns()
                with Image.open(read_asset(f['rgb'])) as img:
                    img=img.convert('RGB')
                    if variant=='rgb-blur':img=img.filter(ImageFilter.GaussianBlur(1.5))
                    a=np.asarray(img,dtype=np.float32)/255
                if variant=='rgb-noise':
                    rng=np.random.default_rng(10000+f['frameId'])
                    a=np.clip(a+rng.normal(0,2/255,a.shape),0,1).astype(np.float32)
                ys=np.arange(256)*f['height']//256;xs=np.arange(256)*f['width']//256
                rgb=a[ys[:,None],xs[None,:]]
                prep=time.perf_counter_ns();raw=infer(net,inp,out,rgb);end=time.perf_counter_ns()
                if not check:times.append({'layoutId':layout['id'],'variant':variant,'frameId':f['frameId'],'preprocessingMs':(prep-start)/1e6,'inferenceMs':(end-prep)/1e6})
                path=f"{layout['id']}-{variant}-{f['frameId']}.f32.gz"
                payload=gzip.compress(raw.astype('<f4').tobytes(),mtime=0)
                if check:
                    if gzip.decompress((OUT/path).read_bytes())!=raw.tobytes():raise ValueError('NCNN map drift: '+path)
                else:(OUT/path).write_bytes(payload)
                records.append({'layoutId':layout['id'],'variant':variant,'frameId':f['frameId'],'rgbSha256':f['rgb']['sha256'],'path':path,'sha256':sha(OUT/path)})
                # Independent depth reference is used only for fitting/scoring.
                if variant=='clean':
                    z=np.frombuffer(gzip.decompress(read_asset(f['depth']).read_bytes()),dtype='<f4').reshape(f['height'],f['width'])
                    z=z[ys[:,None],xs[None,:]]
                    xx,yy=np.meshgrid(xs+.5,ys+.5)
                    axial=z/np.sqrt(1+((xx-f['cx'])/f['fx'])**2+((yy-f['cy'])/f['fy'])**2)
                    good=np.isfinite(axial)&(axial>.1)&(axial<10)
                    x=raw[good].astype(float)[::16];y=1/axial[good].astype(float)[::16]
                    if layout['split']=='calibration':fit_x.extend(x);fit_y.extend(y)
                    elif layout['split']=='validation':validation.append((x,y))
                    else:held_out.append((layout['id'],f['frameId'],x,y))
        print('NCNN '+layout['id'],flush=True)
    x=np.asarray(fit_x);y=np.asarray(fit_y);design=np.column_stack((x,np.ones_like(x)))
    # Huber IRLS on calibration only; freeze before validation/test use.
    coef=np.linalg.lstsq(design,y,rcond=None)[0]
    for _ in range(10):
        residual=design@coef-y;weight=np.minimum(1,.05/np.maximum(abs(residual),1e-12))
        coef=np.linalg.lstsq(design*np.sqrt(weight[:,None]),y*np.sqrt(weight),rcond=None)[0]
    errors=[];invalid=0;total=0
    for vx,vy in validation:
        inverse=coef[0]*vx+coef[1];good=inverse>0;invalid+=int((~good).sum());total+=len(good)
        errors.extend(abs(1/inverse[good]-1/vy[good]))
    p95=percentile(errors,95);maximum=max(errors) if errors else None
    accepted=bool(coef[0]>0 and invalid==0 and p95 is not None and p95<=.05 and maximum<=.1)
    calibration={'scope':'synthetic diagnostic only; no device metric calibration','fitSplit':'calibration','validationSplit':'validation','testUsedForFit':False,
                 'a':float(coef[0]),'b':float(coef[1]),'sampleCount':len(x),'validationAbsErrorP50M':percentile(errors,50),
                 'validationAbsErrorP95M':p95,'validationAbsErrorMaxM':maximum,'invalidValidationFraction':invalid/total,
                 'accepted':accepted,'maximumAllowedP95M':.05,'maximumAllowedMaxM':.1,'promotionAllowed':False}
    test_errors=[]
    for identity,frame,vx,vy in held_out:
        inv=coef[0]*vx+coef[1];good=inv>0
        err=abs(1/inv[good]-1/vy[good]).tolist()
        test_errors.append({'layoutId':identity,'frameId':frame,'absErrorP50M':percentile(err,50),'absErrorP95M':percentile(err,95),
                            'absErrorMaxM':max(err) if err else None,'invalidFraction':float((~good).mean())})
    receipt={'schemaVersion':1,'corpusManifestSha256':sha(CORPUS/'manifest.json'),'generatorSha256':sha(__file__),
             'modelParamSha256':sha(PARAM),'modelBinSha256':sha(BIN),'runtime':f'ncnn-{ncnn.__version__}-cpu-threads1',
             'preprocessId':'rgb01-chw-256-nearest-stretch-no-crop-v1','valueSemantics':'rawRelativeInverseDepthLargerNearer',
             'calibration':calibration,'heldOutTestDepthErrors':test_errors,'frames':records,'promotionAllowed':False}
    if check:
        if json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))!=receipt:raise ValueError('NCNN receipt drift')
        print('NCNN maps and frozen calibration match')
    else:
        save(OUT/'manifest.json',receipt)
        save(ROOT/'docs/_baseline_logs/camera_visible_ncnn_timing.json',{'scope':'measured desktop NCNN CPU; not Android; excludes render and scan duration','warmupInferences':10,
             'preprocessingP50Ms':percentile([r['preprocessingMs'] for r in times],50),'preprocessingP95Ms':percentile([r['preprocessingMs'] for r in times],95),
             'inferenceP50Ms':percentile([r['inferenceMs'] for r in times],50),'inferenceP95Ms':percentile([r['inferenceMs'] for r in times],95),'frames':times})
        print(json.dumps(calibration))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

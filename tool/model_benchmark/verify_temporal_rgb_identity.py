"""Posthoc pixel identity: PNG timestamps must not establish scene novelty.

No scene selection, scoring, calibration or implementation changes. This
supplements the frozen corpus checker with decoded RGB/preprocessed hashes.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'test/fixtures/spatial_safety'
OUT=ROOT/'docs/_baseline_logs/camera_temporal_rgb_identity.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fingerprints(path):
    with Image.open(path) as img:rgb=np.asarray(img.convert('RGB'))
    ys=np.arange(256)*rgb.shape[0]//256;xs=np.arange(256)*rgb.shape[1]//256
    return hashlib.sha256(rgb.tobytes()).hexdigest(),hashlib.sha256(rgb[ys[:,None],xs[None,:]].tobytes()).hexdigest()

def main(check):
    previous=set();sources={};records=[]
    for name in ['camera-visible-passage-v1','camera-visible-passage-recovery-v1','camera-track-passage-v1']:
        root=BASE/name;path=root/'manifest.json';sources[str(path.relative_to(ROOT)).replace('\\','/')]=sha(path)
        manifest=json.loads(path.read_text(encoding='utf-8'))
        for l in manifest['layouts']:previous.add(fingerprints(root/l['frames'][0]['rgb']['path'])[1])
    root=BASE/'camera-temporal-passage-v1';path=root/'manifest.json';sources[str(path.relative_to(ROOT)).replace('\\','/')]=sha(path)
    manifest=json.loads(path.read_text(encoding='utf-8'));seen=set()
    for layout in manifest['layouts']:
        frames=layout['frames'];current=[]
        for f in frames:
            path=root/f['rgb']['path'];assert sha(path)==f['rgb']['sha256']
            rgb,nn=fingerprints(path);current.append((rgb,nn))
            records.append({'layoutId':layout['id'],'split':layout['split'],'frameId':f['frameId'],
                'decodedRgbSha256':rgb,'nearest256RgbSha256':nn})
        assert current[0][1] not in previous and current[0][1] not in seen,'Decoded/preprocessed anchor duplicate'
        seen.add(current[0][1])
        if layout['staticSyntheticScan']:assert all(c==current[0] for c in current[10:]),'Repeated anchor pixels changed'
        else:assert len(set(current))==7 and len({c[1] for c in current})==7,'Temporal RGB pixels are repeated'
    result={'scope':'posthoc pixel/preprocessing integrity; no tuning, scene selection or labels',
        'sourceSha256':sources,'checkerSha256':sha(Path(__file__)),
        'wholeSceneAnchors':len(seen),'previousAnchorNearest256Count':len(previous),
        'crossScenePixelDuplicates':0,'temporalDecisionInputDuplicates':0,'frames':records}
    rendered=json.dumps(result,indent=2)+'\n'
    if check:assert OUT.read_text(encoding='utf-8')==rendered,'Decoded RGB integrity receipt drift'
    else:OUT.write_text(rendered,encoding='utf-8')
    print('18 anchors distinct from all previous decoded/preprocessed anchors; temporal RGB genuinely changes')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

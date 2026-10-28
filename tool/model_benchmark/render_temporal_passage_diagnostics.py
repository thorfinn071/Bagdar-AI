"""Post-replay RGB/visible-depth plots; no annotations or hidden geometry."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-temporal-passage-v1'
REPORT=ROOT/'docs/_baseline_logs/camera_temporal_passage.json'
OUT=ROOT/'docs/_baseline_logs/camera_temporal_diagnostics'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def main(check):
    report=json.loads(REPORT.read_text(encoding='utf-8'))
    manifest=json.loads((CORPUS/'manifest.json').read_text(encoding='utf-8'))
    layouts={l['id']:l for l in manifest['layouts']}
    rows={(s['layoutId'],s['mode']):s for s in report['sequences']}
    font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',14)
    large=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',18)
    OUT.mkdir(exist_ok=True);images=[]
    for (identity,mode),sequence in rows.items():
        if mode!='associated-stable' or sequence['split']!='test':continue
        prior=rows[identity,'associated-stateful'];decisions=sequence['decisions'];count=len(decisions)
        canvas=Image.new('RGB',(count*256,560),'#101820');d=ImageDraw.Draw(canvas)
        d.text((12,10),identity,font=large,fill='white')
        d.text((12,38),'RGB / first visible depth / actual shadow decisions; no hidden geometry',font=font,fill='#9babb8')
        frames={f['frameId']:f for f in layouts[identity]['frames']}
        for column,trace in enumerate(decisions):
            f=frames[trace['frameId']];x=column*256
            rgbpath=CORPUS/f['rgb']['path'];assert sha(rgbpath)==f['rgb']['sha256']
            rgb=Image.open(rgbpath).convert('RGB').resize((256,192),Image.Resampling.NEAREST)
            canvas.paste(rgb,(x,70))
            depthpath=CORPUS/f['depth']['path'];assert sha(depthpath)==f['depth']['sha256']
            z=np.frombuffer(gzip.decompress(depthpath.read_bytes()),dtype='<f4').reshape(f['height'],f['width'])
            v=np.nan_to_num(np.clip(z/6,0,1),nan=0)
            color=np.stack([255*(1-v),180*v,255*v],axis=-1).astype('uint8');color[~np.isfinite(z)]=[30,30,30]
            heat=Image.fromarray(color).resize((256,192),Image.Resampling.NEAREST)
            canvas.paste(heat,(x,274))
            trend=max([t['approachTrend'] for t in trace['tracks']]+[0.])
            status=(trace['passage'] or {}).get('status','none')
            text=[f"t={trace['captureOffsetUs']/1e6:.1f}s frame={trace['frameId']}",
                f"stable: {trace['action']}",f"prior: {prior['decisions'][column]['action']}",
                f"depth: {status} trend={trend:.3f}"]
            for line,t in enumerate(text):d.text((x+6,476+line*20),t,font=font,fill='white')
        target=OUT/f'{identity}.png'
        if check:
            import io
            data=io.BytesIO();canvas.save(data,format='PNG')
            assert target.read_bytes()==data.getvalue(),'Diagnostic PNG drift'
        else:canvas.save(target)
        images.append({'layoutId':identity,'path':target.relative_to(ROOT).as_posix(),'sha256':sha(target)})
    receipt={'scope':'posthoc report visualization; reads no scoring annotations',
        'reportSha256':sha(REPORT),'corpusManifestSha256':sha(CORPUS/'manifest.json'),
        'generatorSha256':sha(__file__),'images':images}
    rendered=json.dumps(receipt,indent=2)+'\n'
    if check:assert (OUT/'manifest.json').read_text(encoding='utf-8')==rendered
    else:(OUT/'manifest.json').write_text(rendered,encoding='utf-8')
    print(f'{len(images)} temporal camera plots '+('verified' if check else 'written'))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

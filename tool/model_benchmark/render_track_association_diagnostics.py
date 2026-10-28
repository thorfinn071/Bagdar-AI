"""Deterministic engineering plots of RGB/components/depth and protected volume.

Scoring annotations are never read. This renderer runs after the decision replay.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]

def sha(data):return hashlib.sha256(data).hexdigest()

def plot(corpus,layout,row):
    frame=layout['frames'][0];w,h=frame['width'],frame['height']
    rgb=Image.open(corpus/frame['rgb']['path']).convert('RGB')
    r=np.array(frame['cameraToWalkingRotation']).reshape(3,3)
    origin=np.array(frame['cameraOriginM'])
    def project(p):
        q=r.T@(np.array(p)-origin)
        if q[2]<=.01:return None
        return (frame['fx']*q[0]/q[2]+frame['cx'],frame['fy']*q[1]/q[2]+frame['cy'])
    draw=ImageDraw.Draw(rgb)
    corners=[(x,y,z) for x in (-.45,.45) for y in (.2,3.5) for z in (.05,1.85)]
    for i,a in enumerate(corners):
        for b in corners[i+1:]:
            if sum(x!=y for x,y in zip(a,b))==1:
                p,q=project(a),project(b)
                if p and q:draw.line([p,q],fill=(20,210,245),width=2)
    support=np.zeros((256,256,3),dtype=np.uint8)
    lines=[]
    for track in row['final']['tracks']:
        association=track['association'] or {};rel=association.get('relation','not applied')
        color={'outsidePassage':(40,220,90),'intersectsPassage':(245,65,60),'unknown':(255,185,40)}.get(rel,(160,160,160))
        bounds=track['normalizedBounds'];rect=[bounds[0]*w,bounds[1]*h,bounds[2]*w,bounds[3]*h]
        draw.rectangle(rect,outline=color,width=2)
        draw.text((rect[0]+2,rect[1]+2),str(track['trackId']),fill=color)
        indices=track.get('componentSupport')
        if indices:
            flat=support.reshape(-1,3);flat[indices]=color
        else:
            d=Image.fromarray(support);ImageDraw.Draw(d).rectangle([v*256 for v in bounds],outline=color,width=1);support=np.array(d)
        lines.append(f"track {track['trackId']} {track['geometry']} / {track['zone']}: {rel}")
        lines.append(f"  {association.get('reason','')} unknown={association.get('unknownPixels','-')} intersects={association.get('intersectingPixels','-')}")
    depth=np.frombuffer(gzip.decompress((corpus/frame['depth']['path']).read_bytes()),dtype='<f4').reshape(h,w)
    val=np.clip(np.nan_to_num(depth,nan=0)/6,0,1)
    color=np.stack((255*(1-val),180*val,255*val),axis=-1).astype(np.uint8)
    color[~np.isfinite(depth)]=0
    output=Image.new('RGB',(w*3,max(h+140,h+20*len(lines)+35)),(20,24,30))
    output.paste(rgb,(0,30));output.paste(Image.fromarray(support).resize((w,h),Image.Resampling.NEAREST),(w,30))
    output.paste(Image.fromarray(color),(w*2,30))
    d=ImageDraw.Draw(output)
    d.text((4,8),'RGB + component boxes + protected volume (cyan)',fill='white')
    d.text((w+4,8),'NCNN detector support (no hidden masks)',fill='white')
    d.text((2*w+4,8),'First visible metric range: red near / blue far',fill='white')
    title=f"{layout['id']} | {row['mode']} | {row['final']['action']} | passage={row['final']['passage']['status']}"
    d.text((4,h+38),title,fill='white')
    for j,line in enumerate(lines):d.text((4,h+60+j*18),line,fill='white')
    return output

def main(args):
    corpus=(ROOT/args.corpus).resolve();report_path=(ROOT/args.report).resolve();out=(ROOT/args.output).resolve()
    if not all(p.is_relative_to(ROOT) for p in (corpus,report_path,out)):raise ValueError('Workspace paths only')
    report=json.loads(report_path.read_text(encoding='utf-8'))
    layouts={x['id']:x for x in json.loads((corpus/'manifest.json').read_text(encoding='utf-8'))['layouts']}
    rows=[r for r in report['sequences'] if r['mode']=='visible-associated']
    out.mkdir(parents=True,exist_ok=True);records=[]
    import io
    for row in rows:
        buf=io.BytesIO();plot(corpus,layouts[row['layoutId']],row).save(buf,format='PNG')
        data=buf.getvalue();name=row['layoutId']+'.png'
        if args.check:
            if (out/name).read_bytes()!=data:raise ValueError('Diagnostic plot drift: '+name)
        else:(out/name).write_bytes(data)
        records.append({'layoutId':row['layoutId'],'path':name,'sha256':sha(data)})
    manifest={'scope':'post-decision camera-only diagnostic plots; no scorer labels','reportSha256':sha(report_path.read_bytes()),
        'corpusManifestSha256':sha((corpus/'manifest.json').read_bytes()),'rendererSha256':sha(Path(__file__).read_bytes()),'plots':records}
    rendered=json.dumps(manifest,indent=2)+'\n'
    if args.check:
        if (out/'manifest.json').read_text(encoding='utf-8')!=rendered:raise ValueError('Diagnostic receipt drift')
    else:(out/'manifest.json').write_text(rendered,encoding='utf-8')
    print(f'Diagnostic camera plots verified: {len(records)}' if args.check else f'Created {len(records)} diagnostic camera plots')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--corpus',required=True);p.add_argument('--report',required=True);p.add_argument('--output',required=True)
    p.add_argument('--check',action='store_true');main(p.parse_args())

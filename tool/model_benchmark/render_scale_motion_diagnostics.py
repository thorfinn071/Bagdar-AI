"""Post-hoc visible RGB/depth/motion plots; not an inference dependency."""
import gzip
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-scale-motion-v1'
OUT=ROOT/'docs/_baseline_logs/camera_scale_motion_diagnostics'
COLORS={'approaching':'#ff4b4b','receding':'#57a6ff','lateral':'#ffb52e','consistentWithStationary':'#48cf88','uncertain':'#bbbbbb'}
def main():
    report=json.loads((ROOT/'docs/_baseline_logs/camera_scale_motion.json').read_text())
    manifest=json.loads((CORPUS/'manifest.json').read_text());OUT.mkdir(exist_ok=True);records=[]
    for row in report['sequences']:
        if row['mode']!='scale-motion' or row['split']!='test':continue
        layout=next(l for l in manifest['layouts'] if l['id']==row['layoutId'])
        panels=[]
        for decision in row['decisions'][1:]:
            f=next(f for f in layout['frames'] if f['frameId']==decision['frameId'])
            rgb=Image.open(CORPUS/f['rgb']['path']).convert('RGB')
            panel=Image.new('RGB',(384,350),'#161922');panel.paste(rgb,(0,38));draw=ImageDraw.Draw(panel)
            draw.text((8,6),f"frame {f['frameId']} | {decision['action']} | {decision['ruleId']}",fill='white')
            motion=decision['scaleMotion']
            for p in motion['patches']:
                x,y=p['currentPixel'];color=COLORS[p['classification']]
                draw.ellipse((x-3,y+35,x+3,y+41),outline=color,width=2)
                a=p['previousPixel'];draw.line((a[0],a[1]+38,x,y+38),fill=color,width=1)
            draw.text((8,330),f"matched {len(motion['patches'])} | unknown {motion['unknownPatches']} | motion risk {motion['addsMotionRisk']}",fill='white')
            panels.append(panel)
        canvas=Image.new('RGB',(384*3,350*2+54),'#161922');draw=ImageDraw.Draw(canvas)
        draw.text((10,8),row['layoutId'],fill='white')
        draw.text((10,26),'Visible local matches only: green=stationary-compatible red=approach blue=recede orange=lateral gray=uncertain',fill='white')
        for i,p in enumerate(panels):canvas.paste(p,((i%3)*384,54+(i//3)*350))
        path=OUT/f"{row['layoutId']}.png";canvas.save(path)
        records.append({'layoutId':row['layoutId'],'path':str(path.relative_to(ROOT))})
    (OUT/'manifest.json').write_text(json.dumps({'scope':'post-hoc RGB/local correspondence diagnostics; no hidden geometry','plots':records},indent=2)+'\n')
    print(f'Rendered {len(records)} visible motion plots')
if __name__=='__main__':main()


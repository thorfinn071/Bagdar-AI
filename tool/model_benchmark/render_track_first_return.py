"""Post-decision pixel diagnosis. It never supplies geometry to the runtime."""
import argparse
import gzip
import json
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/track-first-return-2026-10-09'
PRIOR=ROOT/'scratch/synchronized-passage-2026-10-09/optical-v2'


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8-sig'))


def floats(p):
    return np.frombuffer(gzip.decompress(Path(p).read_bytes()),dtype='<f4')


def diagnosis():
    replay=read(DIRECTORY/'replay.json'); proof=read(DIRECTORY/'optical/manifest.json'); rows=[]
    for f in replay['frames']:
        if f['physicalHazard']: continue
        old=next(a for a in f['originalBounds']['pixelAudits'] if a['trackId']==2)
        new=next(a for a in f['supplementalBounds']['pixelAudits'] if a['trackId']==2)
        p=next(p for p in proof['records'] if p['id']==f['id'])
        indices=[u['index'] for u in old['unknownPixels']]
        hi=floats(DIRECTORY/'optical'/p['heightUpper']['path'])
        lo=floats(DIRECTORY/'optical'/p['heightLower']['path'])
        new_category={i:k for k,values in new['mask'].items() for i in values}
        rows.append({'id':f['id'],'originalUnknownPixels':len(indices),
          'originalCategories':old['categories'],'supplementalCategories':new['categories'],
          'originalUnknownNowBoundedOutside':sum(new_category[i]=='boundedOutside' for i in indices),
          'originalUnknownNowIntersects':sum(new_category[i]=='boundedIntersects' for i in indices),
          'originalUnknownStillUnknown':sum(new_category[i] in ['invalidReturnOrBounds','unboundedMayIntersect'] for i in indices),
          'originalUnknownCertifiedFloor':sum(bool(np.isfinite(lo[i]) and np.isfinite(hi[i]) and lo[i]>=-.05 and hi[i]<=.05) for i in indices),
          'originalUnknownHeightMinM':float(np.nanmin(lo[indices])),
          'originalUnknownHeightMaxM':float(np.nanmax(hi[indices])),
          'originalAction':f['originalBounds']['action'],'supplementalAction':f['supplementalBounds']['action']})
    return {'promotionAllowed':False,'newNeuralInference':False,
            'scope':'post-decision pixel audit and renderer proof; known synthetic snapshots only','rows':rows}


def render():
    replay=read(DIRECTORY/'replay.json'); proof=read(DIRECTORY/'optical/manifest.json')
    fig,axes=plt.subplots(2,2,figsize=(11,8))
    fig.subplots_adjust(left=.02,right=.98,top=.88,bottom=.12,wspace=.05,hspace=.25)
    for row,ident in enumerate(['clear-first','clear-final']):
        f=next(f for f in replay['frames'] if f['id']==ident)
        p=next(p for p in proof['records'] if p['id']==ident)['priorPrimary']
        old=next(a for a in f['originalBounds']['pixelAudits'] if a['trackId']==2)
        new=next(a for a in f['supplementalBounds']['pixelAudits'] if a['trackId']==2)
        image=np.array(Image.open(PRIOR/p['rgb']['path']).convert('RGB'))
        old_indices=[u['index'] for u in old['unknownPixels']]
        category={i:k for k,values in new['mask'].items() for i in values}
        for col,mode in enumerate(['originalBounds','supplementalBounds']):
            rgb=image.copy();flat=rgb.reshape(-1,3)
            for i in old_indices:
                flat[i]=(255,165,30) if col==0 or category[i] in ['unboundedMayIntersect','invalidReturnOrBounds'] else (
                    (35,225,120) if category[i]=='boundedOutside' else (255,50,65))
            ax=axes[row,col];ax.imshow(rgb);ax.axis('off')
            unknown=len(old['unknownPixels']) if col==0 else len(new['unknownPixels'])
            ax.set_title(f"{ident}: {'original' if col==0 else 'supplemental'} bounds\n"
                         f"track 2 unknown pixels: {unknown}; action: {f[mode]['action']}",fontsize=11)
    fig.suptitle('Track localization: missing first-return bounds',fontsize=16,weight='bold')
    fig.text(.02,.035,'Orange: original unresolved pixels. Green: same pixels now bounded outside. Red: may intersect.\n'
             'Pinned MiDaS and RGB; offline exact renderer proof; 12-view ideal rig unchanged. '
             'Fresh shadow snapshots only. No phone or temporal-recovery claim.',fontsize=10)
    for ext in ['png','svg']:fig.savefig(DIRECTORY/f'pixel-diagnosis.{ext}',dpi=170,bbox_inches='tight')
    plt.close(fig)
    value=diagnosis();target=DIRECTORY/'diagnosis.json'
    if target.exists():
        assert read(target)==value, 'Diagnosis drift'
    else:target.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(value['rows'],indent=2))


if __name__=='__main__':
    render()

"""Independent FOV witness, no producer, neural predictions or planner output."""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-metric-motion-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(check):
    nominal=CORPUS/'annotations.nominal.json';target=CORPUS/'annotations.json'
    if not nominal.exists():
        if check:raise ValueError('Missing original nominal labels')
        nominal.write_bytes(target.read_bytes())
    labels=json.loads(nominal.read_text());m=json.loads((CORPUS/'manifest.json').read_text());rows=[]
    for layout in m['layouts']:
        if not layout['staticSyntheticScan']:continue
        # Upper volume includes the allowed 50mm floor rise. One unseen point
        # disproves sufficient coverage; seeing these points does not certify it.
        points=[[float(x),.2,1.85] for x in np.linspace(-.45,.45,19)]
        unseen=[]
        for point in points:
            seen=False
            for f in layout['frames'][1:10]:
                r=np.array(f['cameraToWalkingRotation']).reshape(3,3)
                q=r.T@(np.array(point)-np.array(f['cameraOriginM']))
                if q[2]<=0:continue
                u=f['cx']+f['fx']*q[0]/q[2];v=f['cy']+f['fy']*q[1]/q[2]
                if 0<=u<f['width'] and 0<=v<f['height']:seen=True;break
            if not seen:unseen.append(point)
        label=next(l for l in labels['layouts'] if l['layoutId']==layout['id'])
        if unseen:
            for f in label['frames']:f['observationSufficient']=False
        rows.append({'layoutId':layout['id'],'unseenProtectedVolumeWitnessesM':unseen,
            'observationSufficientDisproved':bool(unseen)})
    labels['observabilityMethod']='independent FOV witness on upper protected volume; no producer/planner decisions'
    rendered=json.dumps(labels,indent=2,allow_nan=False)+'\n'
    receipt={'scope':'nominal scan labels corrected before first test replay using projection only',
        'scriptSha256':sha(Path(__file__)),'manifestSha256':sha(CORPUS/'manifest.json'),
        'nominalAnnotationSha256':sha(nominal),'annotationsSha256':hashlib.sha256(rendered.encode()).hexdigest(),
        'decisionReportsRead':False,'witnesses':rows}
    path=CORPUS/'observability.json';receipt_text=json.dumps(receipt,indent=2)+'\n'
    if check:assert target.read_text()==rendered and path.read_text()==receipt_text,'Observability label drift'
    else:
        if path.exists():raise ValueError('Do not rewrite frozen observation labels')
        target.write_text(rendered,encoding='utf-8');path.write_text(receipt_text,encoding='utf-8')
    print(json.dumps(rows))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

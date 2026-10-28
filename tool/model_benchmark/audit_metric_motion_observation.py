"""Post-hoc nominal vs conservative coverage scoring; no tuning."""
import argparse
import json
from pathlib import Path
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-metric-motion-v1'
def main(check=False):
    nominal=json.loads((CORPUS/'annotations.nominal.json').read_text())
    report=json.loads((ROOT/'docs/_baseline_logs/camera_metric_motion.json').read_text())
    manifest=json.loads((CORPUS/'manifest.json').read_text());rows=[]
    for layout in manifest['layouts']:
        if not layout['staticSyntheticScan']:continue
        unseen={}
        for height in [1.8,1.85]:
            points=[]
            for x in np.linspace(-.45,.45,19):
                point=np.array([x,.2,height]);seen=False
                for f in layout['frames'][1:10]:
                    q=np.array(f['cameraToWalkingRotation']).reshape(3,3).T@(point-np.array(f['cameraOriginM']))
                    if q[2]<=0:continue
                    u=f['cx']+f['fx']*q[0]/q[2];v=f['cy']+f['fy']*q[1]/q[2]
                    if 0<=u<f['width'] and 0<=v<f['height']:seen=True;break
                if not seen:points.append(point.tolist())
            unseen[str(height)]=points
        rows.append({'layoutId':layout['id'],'split':layout['split'],'unseenRayWitnessesAtHeightsM':unseen,
            'seeingWitnessPointsCertifiesVolume':False,'floorRiseRefinementImplemented':False})
    summaries={}
    nominal_by_id={l['layoutId']:l for l in nominal['layouts']}
    for mode in ['associated-stable','metric-motion']:
        sufficient=[r for r in report['sequences'] if r['split']=='test' and r['mode']==mode and nominal_by_id[r['layoutId']]['frames'][-1]['observationSufficient']]
        summaries[mode]={'nominalSufficientPassableSequences':len(sufficient),
            'nominalFalseStops':sum(r['final']['action']=='stopNow' for r in sufficient),
            'conservativeSufficientPassableSequences':report['summaries'][mode]['sufficientPassableSequences']}
    out={'scope':'post-hoc audit exposes nominal and conservative scoring; labels and frozen decisions unchanged',
        'fundamentalCameraInsufficiencyProvenForNominal1_8m':False,'summaries':summaries,'witnesses':rows}
    path=ROOT/'docs/_baseline_logs/camera_metric_motion_observation_audit.json'
    rendered=json.dumps(out,indent=2)+'\n'
    if check:assert path.read_text()==rendered,'Nominal observation audit drift'
    else:path.write_text(rendered,encoding='utf-8')
    print(json.dumps(out,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

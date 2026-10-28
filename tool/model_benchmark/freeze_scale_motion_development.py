"""Write-once freeze after validation, before the first fresh test replay."""
import argparse
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DEV=ROOT/'docs/_baseline_logs/camera_scale_motion_development.json'
OUT=ROOT/'docs/_baseline_logs/camera_scale_motion_development_freeze.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(check):
    d=json.loads(DEV.read_text());assert d['summarySplit']=='validation' and len(d['sequences'])==18
    assert all(r['split']=='validation' for r in d['sequences'])
    assert d['summaries']['scale-motion']['unsafeContinueSteps']==0 and d['summaries']['scale-motion']['unjustifiedClearances']==0
    for key,row in d['motionSummary'].items():
        if row['mode']!='scale-motion':continue
        scores=row['correspondenceScores']
        assert scores['surfaceMismatch']==scores['incorrectVelocityIntervals']==scores['falseBackgroundMotion']==0
        if row['motionKindLabel'] in ('approach','approach-fast'):
            assert row['framesAddingMotionRisk']==row['framesApplyingMotionRisk']==6
        if row['motionKindLabel'] in ('stationary','camera-yaw'):
            assert row['framesAddingMotionRisk']==0
    for path,value in d['sourceSha256'].items():assert sha(ROOT/path)==value,'Source drift '+path
    receipt={'scope':'scale-aware patch motion frozen after validation; old approach is inspected regression',
        'sourceSha256':d['sourceSha256'],'developmentReportSha256':sha(DEV),
        'corpusManifestSha256':sha(ROOT/'test/fixtures/spatial_safety/camera-scale-motion-v1/manifest.json'),
        'testUsedForTuning':False,'relativeMotionRiskRemoved':False,'promotionAllowed':False}
    rendered=json.dumps(receipt,indent=2)+'\n'
    if check:assert OUT.read_text()==rendered,'Metric motion freeze drift';print('Metric motion development freeze matches')
    else:
        if OUT.exists():raise ValueError('Do not rewrite freeze after inspecting test')
        OUT.write_text(rendered,encoding='utf-8');print('Metric motion implementation frozen; fresh test may run')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

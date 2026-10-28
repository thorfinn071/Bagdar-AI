"""Write-once development freeze; never select or score test decisions."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/_baseline_logs/camera_temporal_development_freeze.json'
DEV=ROOT/'docs/_baseline_logs/camera_temporal_development.json'
REG=ROOT/'docs/_baseline_logs/camera_temporal_known_regression.json'
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-temporal-passage-v1/manifest.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main(check):
    development=json.loads(DEV.read_text(encoding='utf-8'))
    regression=json.loads(REG.read_text(encoding='utf-8'))
    assert len(development['sequences'])==18 and development['summarySplit']=='validation'
    assert all(r['split']=='validation' for r in development['sequences'])
    for report in [development,regression]:
        for path,value in report['sourceSha256'].items():assert sha(ROOT/path)==value,'Stale source '+path
    summary=development['summaries']['associated-stable']
    assert summary['hazardSequences']==3 and summary['unsafeContinueSteps']==0 and summary['unjustifiedClearances']==0
    assert regression['summaries']['associated-stateful']['falseStopSequences']==1
    assert regression['summaries']['associated-stable']['falseStopSequences']==0
    receipt={'scope':'temporal implementation frozen after validation, before first fresh holdout; known regression is not held out',
        'corpusManifestSha256':sha(CORPUS),'developmentReportSha256':sha(DEV),
        'knownRegressionReportSha256':sha(REG),'sourceSha256':development['sourceSha256'],
        'fixedRansacSeed':7,'historyReset':False,'testUsedForTuning':False,'promotionAllowed':False}
    rendered=json.dumps(receipt,indent=2)+'\n'
    if check:
        assert OUT.read_text(encoding='utf-8')==rendered,'Temporal development freeze drift'
        print('Temporal freeze matches validation, immutable source and predeclared corpus')
    else:
        if OUT.exists():raise ValueError('Do not rewrite freeze after inspecting holdout')
        OUT.write_text(rendered,encoding='utf-8')
        print('Temporal implementation frozen; first holdout may run')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

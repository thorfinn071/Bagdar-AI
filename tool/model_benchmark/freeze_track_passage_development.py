"""Freeze camera-association implementation after development, before test.

This reads development and previously inspected regression reports only. It
does not score or select held-out frames. --check never rewrites the receipt.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/_baseline_logs/camera_track_development_freeze.json'
DEV=ROOT/'docs/_baseline_logs/camera_track_development_replay.json'
REG=ROOT/'docs/_baseline_logs/camera_track_known_regressions.json'
CORPUS=ROOT/'test/fixtures/spatial_safety/camera-track-passage-v1/manifest.json'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main(check):
    development=json.loads(DEV.read_text(encoding='utf-8'))
    regression=json.loads(REG.read_text(encoding='utf-8'))
    assert len(development['sequences'])==18
    assert all(r['split']=='validation' for r in development['sequences'])
    for report in [development,regression]:
        for path,value in report['sourceSha256'].items():
            assert sha(ROOT/path)==value, 'Stale development source: '+path
    safe=[r for r in development['sequences'] if r['mode']=='visible-associated' and not r['physicalHazard']]
    hazards=[r for r in development['sequences'] if r['mode']=='visible-associated' and r['physicalHazard']]
    assert len(safe)==3 and all(r['final']['action']=='continueForward' for r in safe)
    assert len(hazards)==3 and all(r['onTimeStop'] and not r['continues'] for r in hazards)
    assert all(not r['unjustifiedClearances'] for r in development['sequences'])
    paths=[p for p in development['sourceSha256'] if not p.startswith('test/fixtures/')]
    paths+=['tool/blender/generate_track_passage_corpus.py','tool/blender/generate_visible_passage_corpus.py',
            'tool/model_benchmark/generate_track_passage_ncnn.py',
            'tool/model_benchmark/freeze_track_passage_development.py']
    receipt={'scope':'implementation frozen after validation, before first holdout replay; test not used for tuning',
        'corpusManifestSha256':sha(CORPUS),'developmentReportSha256':sha(DEV),
        'previouslyInspectedRegressionReportSha256':sha(REG),
        'sourceSha256':{p:sha(ROOT/p) for p in paths},
        'metricMarginM':.02,'sourcePixelRegistrationMargin':1,'nearProtectedStartM':0,
        'associationMaximumAgeUs':100000,'promotionAllowed':False}
    rendered=json.dumps(receipt,indent=2)+'\n'
    if check:
        assert OUT.read_text(encoding='utf-8')==rendered, 'Development freeze drift'
        print('Development freeze matches current source and geometry')
    else:
        if OUT.exists():raise ValueError('Freeze already exists; do not rewrite after viewing test')
        OUT.write_text(rendered,encoding='utf-8')
        print('Implementation frozen; holdout may now run')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');main(p.parse_args().check)

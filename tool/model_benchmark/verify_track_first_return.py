"""Bind supplemental pixels, real runtime replay and unchanged prior receipts."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from render_track_first_return import diagnosis

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/track-first-return-2026-10-09'
PRIOR=ROOT/'scratch/synchronized-passage-2026-10-09'
SOURCES=['docs/track-first-return-protocol-2026-10-09.md',
 'tool/blender/export_track_first_return.py','tool/model_benchmark/render_track_first_return.py',
 'tool/model_benchmark/verify_track_first_return.py','tool/model_benchmark/check_track_first_return.ps1',
 'test/harness/track_first_return_fixture.dart','test/harness/track_first_return_pixel_audit.dart',
 'test/harness/track_first_return_replay.dart','test/track_first_return_experiment_test.dart']


def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def asset(root,d,dtype,count):
    p=(root/d['path']).resolve();assert p.is_relative_to(root.resolve()) and sha(p)==d['sha256']
    a=np.frombuffer(gzip.decompress(p.read_bytes()),dtype=dtype);assert a.size==count
    return a


def build():
    subprocess.run([sys.executable,'tool/model_benchmark/verify_synchronized_passage.py'],cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    optical=DIRECTORY/'optical';proof=read(optical/'manifest.json');old=read(PRIOR/'optical-v2/manifest.json')
    assert proof['promotionAllowed'] is False and proof['ordinaryCameraWired'] is False
    assert proof.get('pilotOnly',False) is False and len(proof['records'])==7
    assert proof['priorManifestSha256']==sha(PRIOR/'optical-v2/manifest.json')
    assert proof['priorNeuralSha256']==sha(PRIOR/'optical-v2/neural.json')
    for p,h in proof['sources'].items():assert sha(ROOT/p)==h,p
    total=repaired=witnesses=0
    for rec in proof['records']:
        p=next(b for b in old['batches'] if b['id']==rec['id'])['primary'];assert p==rec['priorPrimary']
        assert rec['sources']==proof['sources']
        for key in ['frameId','sessionGeneration','capturedAtUs','sceneStateSha256']:assert rec[key]==p[key]
        n=p['width']*p['height'];old_root=PRIOR/'optical-v2'
        original=asset(old_root,p['surfaceZUpper'],'<f4',n)
        lower=asset(old_root,p['freeZLower'],'<f4',n);depth=asset(old_root,p['depth'],'<f4',n)
        valid=asset(old_root,p['validity'],'u1',n)
        upper=asset(optical,rec['surfaceZUpper'],'<f4',n);lo=asset(optical,rec['heightLower'],'<f4',n)
        hi=asset(optical,rec['heightUpper'],'<f4',n);first=asset(optical,rec['firstZLower'],'<f4',n)
        mask=asset(optical,rec['repairMask'],'u1',n);assert np.isin(mask,[0,1]).all()
        selected=(valid==1)&np.isfinite(depth)&np.isnan(original)
        assert selected.sum()==rec['candidatePixels']==len(rec['pixels'])
        assert np.array_equal(upper[mask==0],original[mask==0],equal_nan=True)
        ok=mask==1;assert (selected[ok]).all() and ok.sum()==rec['certifiedPixels']
        assert np.isfinite(upper[ok]).all() and np.isfinite(lo[ok]).all() and np.isfinite(hi[ok]).all() and np.isfinite(first[ok]).all()
        assert (lo[ok]<=hi[ok]).all() and (lower[ok]<=first[ok]+2e-5).all() and (first[ok]<=upper[ok]).all()
        yy,xx=np.mgrid[:p['height'],:p['width']]
        z=depth/np.sqrt(1+((xx.ravel()+.5-p['cx'])/p['fx'])**2+((yy.ravel()+.5-p['cy'])/p['fy'])**2)
        assert (first[ok]<=z[ok]+2e-5).all() and (z[ok]<=upper[ok]+2e-5).all()
        assert rec['independentRayWitnesses']==int(ok.sum())*5
        assert len({r['index'] for r in rec['pixels']})==len(rec['pixels'])
        assert {r['index'] for r in rec['pixels']}==set(np.flatnonzero(selected))
        for r in rec['pixels']:
            i=r['index'];assert r['certified']==bool(mask[i])
            if r['certified']:
                assert r['heightLowerM']==float(lo[i]) and r['heightUpperM']==float(hi[i])
                assert lo[i]<=r['sampledFirstHitHeightMinM']+2e-4 and r['sampledFirstHitHeightMaxM']<=hi[i]+2e-4
        total+=rec['candidatePixels'];repaired+=rec['certifiedPixels'];witnesses+=rec['independentRayWitnesses']
    replay=read(DIRECTORY/'replay.json')
    for k in ['pilotOnly','promotionAllowed','ordinaryCameraWired','captureToCommandMeasured','temporalRecoveryEstablished','newNeuralInference']:
        assert replay[k] is False
    assert replay['manifestSha256']==sha(optical/'manifest.json') and replay['maximumAgeUs']==100000
    assert replay['neuralReceiptSha256']==sha(PRIOR/'optical-v2/neural.json') and replay['priorManifestSha256']==sha(PRIOR/'optical-v2/manifest.json')
    summary=replay['summary'];assert summary['completePassages']==2 and summary['controlStops']==2
    assert summary['supplementalStops']==0 and summary['supplementalContinues']==2
    assert summary['singleCameraStops']==2
    assert summary['hazardStops']==5 and summary['hazardUnsafeContinues']==0
    assert summary['faultChecks']==38 and summary['faultStops']==36 and summary['priorityUnknowns']==2
    for f in replay['frames']:
        assert f['priorRuntimeParity'] is True
        for name in ['originalBounds','supplementalBounds']:
            assert f[name]['delivery']=='shadow'
            for a in f[name]['pixelAudits']:assert a['productionCountParity'] is True
        if f['physicalHazard']:assert f['sourcePassage']['status']!='measuredClear' and f['supplementalBounds']['action']=='stopNow'
        else:
            assert f['sourcePassage']['status']=='measuredClear'
            assert f['supplementalWithoutRig']['action']=='stopNow' and f['supplementalWithoutRig']['passage']['status']=='unavailable'
    for f in replay['faultControls']:
        if f['fault']=='motionOrSemanticPriority':assert f['association']['relation']=='unknown'
        else:assert f['action']=='stopNow'
    assert read(DIRECTORY/'diagnosis.json')==diagnosis()
    files=['optical/manifest.json','replay.json','diagnosis.json','pixel-diagnosis.png','pixel-diagnosis.svg']
    return {'schemaVersion':1,'passed':True,'promotionAllowed':False,'ordinaryCameraWired':False,
      'sources':{p:sha(ROOT/p) for p in SOURCES},'artifacts':{p:sha(DIRECTORY/p) for p in files},
      'priorValidationSha256':sha(PRIOR/'validation.json'),'summary':summary,
      'candidatePixels':total,'certifiedPixels':repaired,'independentRayWitnesses':witnesses,
      'fullTimingGate':'not_passed_prior_4_of_21_expired','captureToCommandMeasured':False,
      'namedDeviceRuntime':'not_run','controlledWalking':'not_run','temporalRecoveryEstablished':False}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    value=build();path=DIRECTORY/'validation.json'
    if args.write:
        if path.exists():raise ValueError('Validation is immutable')
        path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    else:assert read(path)==value,'Source/output drift'
    print('Primary first-return experiment: runtime/pixel parity, hazards/faults and prior receipts verified')

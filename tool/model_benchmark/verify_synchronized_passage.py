"""Freeze new packets and measurements; preserve earlier rig/view receipts."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT/'scratch/synchronized-passage-2026-10-09'
SOURCES = [
    'docs/synchronized-passage-protocol-2026-10-09.md',
    'tool/blender/export_synchronized_passage.py',
    'tool/model_benchmark/infer_synchronized_passage.py',
    'tool/model_benchmark/profile_synchronized_passage.dart',
    'tool/model_benchmark/render_synchronized_passage.py',
    'tool/model_benchmark/verify_synchronized_passage.py',
    'tool/model_benchmark/check_synchronized_passage.ps1',
    'test/harness/synchronized_passage_fixture.dart',
    'test/harness/synchronized_passage_replay.dart',
    'test/synchronized_passage_experiment_test.dart',
    'lib/safety/perception/camera_synchronized_envelope_source.dart',
    'lib/safety/runtime/camera_scan_age_gate.dart',
    'lib/safety/runtime/spatial_safety_runtime.dart',
    'lib/safety/runtime/confidence_authority_spatial_runtime.dart',
    'lib/safety/perception/camera_track_association.dart',
    'lib/safety/planning/coverage_aware_stop_guidance.dart',
    'lib/safety/world/generic_geometry_scene_adapter.dart',
    'lib/services/generic_obstacle_detector.dart',
    'lib/tracker/generic_obstacle_tracker.dart',
]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def check_sources(sources):
    for p, expected in sources.items():
        assert sha(ROOT/p)==expected, p


def asset(root, descriptor, dtype, count):
    path=(root/descriptor['path']).resolve()
    assert path.is_relative_to(root.resolve()) and sha(path)==descriptor['sha256']
    a=np.frombuffer(gzip.decompress(path.read_bytes()),dtype=dtype)
    assert a.size==count
    return a


def percentiles(values):
    return {'samples':len(values),'p50Ms':float(np.percentile(values,50))/1000,
            'p95Ms':float(np.percentile(values,95))/1000,'maximumMs':max(values)/1000}


def build():
    for previous in ['verify_camera_view_coverage.py','verify_synchronized_rig.py']:
        subprocess.run([sys.executable,'tool/model_benchmark/'+previous],cwd=ROOT,
                       check=True,stdout=subprocess.DEVNULL)
    optical=DIRECTORY/'optical-v2'
    manifest,neural=read(optical/'manifest.json'),read(optical/'neural.json')
    assert manifest['promotionAllowed'] is False and manifest['runtimeWired'] is False
    assert manifest['pilotOnly'] is False and len(manifest['batches'])==7
    assert neural['promotionAllowed'] is False and len(neural['frames'])==7
    assert neural['manifestSha256']==sha(optical/'manifest.json')
    check_sources(manifest['sources']); check_sources(neural['sources'])
    witness_count=0
    for b in manifest['batches']:
        assert len(b['channels'])==12 and b['stationarySyntheticScene'] is True
        assert len({p['cameraId'] for p in b['channels']})==12 and b['zeroSkewUs']==0
        assert b['primary']['rgbPixelSha256']==b['priorPrimaryRgbPixelSha256']
        for p in [b['primary'],*b['channels']]:
            for key in ['frameId','sessionGeneration','capturedAtUs','sceneStateSha256']:
                assert p[key]==b[key]
            w,h=p['width'],p['height']
            r=np.array(p['cameraToWalkingRotation']).reshape(3,3)
            assert np.allclose(r.T@r,np.eye(3),atol=1e-5) and abs(np.linalg.det(r)-1)<1e-5
            rgb=(optical/p['rgb']['path']).resolve()
            assert rgb.is_relative_to(optical.resolve()) and sha(rgb)==p['rgb']['sha256']
            depth=asset(optical,p['depth'],'<f4',w*h)
            lower=asset(optical,p['freeZLower'],'<f4',w*h)
            upper=asset(optical,p['surfaceZUpper'],'<f4',w*h)
            valid=asset(optical,p['validity'],'u1',w*h)
            assert np.isin(valid,[0,1]).all()
            yy,xx=np.mgrid[:h,:w]
            z=depth/np.sqrt(1+((xx.ravel()+.5-p['cx'])/p['fx'])**2+((yy.ravel()+.5-p['cy'])/p['fy'])**2)
            ok=valid==1
            assert np.isfinite(depth[ok]).all() and (depth[ok]>0).all()
            assert np.isfinite(lower[ok]).all() and (lower[ok]>=0).all()
            assert (lower[ok]<=z[ok]+2e-5).all()
            if p['cameraId']!='primary':
                lo=asset(optical,p['heightLower'],'<f4',w*h)
                hi=asset(optical,p['heightUpper'],'<f4',w*h)
                first=asset(optical,p['firstZLower'],'<f4',w*h)
                bounded=np.isfinite(lo)&np.isfinite(hi)
                assert np.isfinite(first[bounded]).all() and np.isfinite(upper[bounded]).all()
                assert (lo[bounded]<=hi[bounded]).all() and (first[bounded]<=z[bounded]+2e-5).all()
                assert (first[bounded]>=lower[bounded]-2e-5).all()
                assert p['rayWitnesses']>0
                witness_count+=p['rayWitnesses']
        n=next(n for n in neural['frames'] if n['id']==b['id'])
        assert n['rawOutputMatchesPrior'] is True and n['canonicalRgbU8Sha256']==n['priorCanonicalRgbU8Sha256']
        raw=asset(optical,n['asset'],'<f4',65536)
        assert np.isfinite(raw).all() and np.ptp(raw)>1e-3
    replay=read(DIRECTORY/'replay.json')
    for key in ['promotionAllowed','ordinaryCameraWired','captureToCommandMeasured','temporalRecoveryEstablished']:
        assert replay[key] is False
    assert replay['manifestSha256']==sha(optical/'manifest.json') and replay['maximumAgeUs']==100000
    assert len(replay['frames'])==7 and len(replay['faultControls'])==20
    assert replay['summary']['completePassages']==2 and replay['summary']['controlStops']==2
    assert replay['summary']['hazardStops']==5 and replay['summary']['hazardUnsafeContinues']==0
    for f in replay['frames']:
        assert f['withRig']['delivery']=='shadow' and f['controlWithoutRig']['delivery']=='shadow'
        assert not any(a['reason'].startswith('incompatible_identity') for a in f['withRig']['associations'])
        if f['physicalHazard']:
            assert f['sourcePassage']['status']!='measuredClear' and f['withRig']['action']=='stopNow'
        else:
            assert f['sourcePassage']['status']=='measuredClear' and f['unknownBodyBoxes']==0
            assert all(s['bodyObservedFraction']==s['floorObservedFraction']==1 for s in f['sections'])
    for f in replay['faultControls']:
        assert f['action']=='stopNow' and f['passageApplied'] is False and f['passage']['status']=='unavailable'
    profiles={}
    for name,mode in [('elapsed-no-nn.json','no-NN'),('elapsed-nn.json','concurrent-NCNN')]:
        p=read(DIRECTORY/name)
        assert p['mode']==mode and p['manifestSha256']==sha(optical/'manifest.json')
        assert p['promotionAllowed'] is False and p['captureToCommandMeasured'] is False
        assert p['currentAgeLimitUs']==100000 and len(p['samples'])==42 and len(p['geometry'])==14
        check_sources(p['sources'])
        for r in p['samples']:
            if r['strictStatus']=='measuredClear':
                assert not r['physicalHazard'] and r['ageAtDispatchUs']<=100000 and r['gate']=='admitted'
            assert r['unsafeContinue'] is False
        for m in ['single','rig']:
            rows=[r for r in p['samples'] if r['mode']==m]
            s=p['summary'][m]
            for key,data in [('pipeline',[r['pipelineUs'] for r in rows]),('ageAtDispatch',[r['ageAtDispatchUs'] for r in rows])]:
                expected=percentiles(data)
                assert s[key]['samples']==expected['samples']
                for v in ['p50Ms','p95Ms','maximumMs']:
                    assert abs(s[key][v]-expected[v])<1e-9
            assert s['expired']==sum(r['ageAtDispatchUs']>100000 for r in rows)
            assert s['admittedClear']==sum(not r['physicalHazard'] and r['strictStatus']=='measuredClear' for r in rows)
        if mode=='concurrent-NCNN':
            assert p['neuralCompetition']['result']['allOutputsMatchPinned'] is True
            assert p['neuralCompetition']['result']['inferences']>=1
        profiles[mode]=p['summary']
    artifacts=['optical-v2/manifest.json','optical-v2/neural.json','replay.json',
               'elapsed-no-nn.json','elapsed-nn.json','coverage-transfer.png','coverage-transfer.svg']
    return {'schemaVersion':1,'passed':True,'promotionAllowed':False,'ordinaryCameraWired':False,
            'sources':{p:sha(ROOT/p) for p in SOURCES},'artifacts':{p:sha(DIRECTORY/p) for p in artifacts},
            'summary':replay['summary'],'profiles':profiles,'sampledOpticalRayWitnesses':witness_count,
            'priorViewReceiptSha256':sha(ROOT/'scratch/camera-view-coverage-2026-10-09/validation.json'),
            'priorRigReceiptSha256':sha(ROOT/'docs/_baseline_logs/blender_synchronized_rig_contract_v3.json'),
            'fullCoreRc':'not_run','androidBuild':'not_run','namedDeviceRuntime':'not_run','controlledWalking':'not_run',
            'captureToCommandMeasured':False,'temporalRecoveryEstablished':False}


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--write',action='store_true')
    args=parser.parse_args()
    value=build()
    target=DIRECTORY/'validation.json'
    if args.write:
        if target.exists(): raise ValueError('First validation is immutable')
        target.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    else:
        assert read(target)==value,'New source/output receipt drift'
    print('Synchronized passage: complete known clear snapshots; protected hazards/faults; frozen source and measured clocks')

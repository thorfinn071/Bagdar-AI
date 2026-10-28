"""Verify all eleven captures, sparse bounds, continuous state and old receipts."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import numpy as np

from render_sequence_first_return import diagnosis

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/sequence-first-return-2026-10-09'
PRIOR=ROOT/'scratch/synchronized-passage-2026-10-09/optical-v2'
VISIBLE=ROOT/'test/fixtures/spatial_safety/blender-paired-visible-body-v1'
CORPUS=ROOT/'test/fixtures/spatial_safety/blender-paired-holdout-v1'
SOURCES=['docs/sequence-first-return-protocol-2026-10-09.md',
 'tool/blender/export_sequence_first_return.py','tool/model_benchmark/render_sequence_first_return.py',
 'tool/model_benchmark/verify_sequence_first_return.py','tool/model_benchmark/check_sequence_first_return.ps1',
 'test/prepare_sequence_first_return_test.dart','test/harness/sequence_first_return_fixture.dart',
 'test/harness/sequence_first_return_replay.dart','test/sequence_first_return_experiment_test.dart']


def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def checked(root,d):
    path=(root/d['path']).resolve()
    assert path.is_relative_to(root.resolve()) and sha(path)==d['sha256'],path
    return path


def asset(root,d,dtype,n):
    a=np.frombuffer(gzip.decompress(checked(root,d).read_bytes()),dtype=dtype)
    assert a.size==n
    return a


def build():
    subprocess.run([sys.executable,'tool/model_benchmark/verify_track_first_return.py'],
      cwd=ROOT,check=True,stdout=subprocess.DEVNULL)
    root=DIRECTORY/'optical';m=read(root/'manifest.json');selection=read(DIRECTORY/'selection.json')
    old=read(PRIOR/'manifest.json');total=certified=witnesses=rig_witnesses=0
    for k in ['promotionAllowed','runtimeWired','pilotOnly','newNeuralInference']:assert m[k] is False
    assert len(m['batches'])==11 and len(selection['frames'])==11
    assert m['selectionSha256']==sha(DIRECTORY/'selection.json')
    assert m['sourceCorpusSha256']==sha(CORPUS/'corpus-manifest.json')
    assert m['priorRigManifestSha256']==sha(PRIOR/'manifest.json')
    for sources in [m['sources'],selection['sources']]:
        for p,h in sources.items():assert sha(ROOT/p)==h,p
    for i,(b,s) in enumerate(zip(m['batches'],selection['frames'])):
        assert b['id']==s['id']==f'clear-{i:02d}' and b['frameId']==s['frameId']==i+1
        assert b['capturedAtUs']==s['capturedAtUs']==1791072000000000+i*200000
        assert b['sessionGeneration']==1 and b['zeroSkewUs']==0
        assert b['stationarySyntheticScene'] is True and b['rigPayloadsReused']==(i in (0,10))
        assert b['exportSources']==m['sources'] and b['selectionSha256']==m['selectionSha256']
        assert len(b['channels'])==len(b['grid']['poses'])==12
        assert [p['cameraId'] for p in b['channels']]==[f'channel-{j:02d}' for j in range(12)]
        p=b['primary'];n=p['width']*p['height'];original=s['primary']
        for k in ['width','height','fx','fy','cx','cy','cameraToWalkingRotation','cameraOriginM','frameId']:
            assert p[k]==original[k],k
        for k in ['depth','freeZLower','validity']:
            assert p[k]['sha256']==original[k]['sha256'];checked(VISIBLE,original[k])
        assert p['originalSurfaceZUpper']['sha256']==original['surfaceZUpper']['sha256']
        assert p['rgb']['sha256']==s['original']['rgb']['sha256']==b['neural']['rgbSha256']
        checked(root,p['rgb']);checked(CORPUS,s['original']['rgb'])
        assert b['neural']['asset']['sha256']==s['neural']['asset']['sha256']
        assert np.isfinite(asset(root,b['neural']['asset'],'<f4',65536)).all()
        depth=asset(root,p['depth'],'<f4',n);lower=asset(root,p['freeZLower'],'<f4',n)
        valid=asset(root,p['validity'],'u1',n);before=asset(root,p['originalSurfaceZUpper'],'<f4',n)
        upper=asset(root,p['surfaceZUpper'],'<f4',n);mask=asset(root,p['repairMask'],'u1',n)
        lo=asset(root,p['heightLower'],'<f4',n);hi=asset(root,p['heightUpper'],'<f4',n)
        first=asset(root,p['firstZLower'],'<f4',n)
        support=np.zeros(n,dtype=bool);support[s['supportPixels']]=True
        selected=(valid==1)&np.isfinite(depth)&np.isnan(before)&support
        rows=read(checked(root,p['proof']))
        assert selected.sum()==p['sparseCandidates']==len(rows)
        assert {r['index'] for r in rows}==set(np.flatnonzero(selected)) and len(rows)==len({r['index'] for r in rows})
        assert np.isin(mask,[0,1]).all() and mask.sum()==p['sparseCertified']
        ok=mask==1;assert selected[ok].all()
        assert np.array_equal(upper[~ok],before[~ok],equal_nan=True)
        assert np.isfinite(upper[ok]).all() and np.isfinite(lo[ok]).all() and np.isfinite(hi[ok]).all()
        assert np.isfinite(first[ok]).all() and (lo[ok]<=hi[ok]).all()
        yy,xx=np.mgrid[:p['height'],:p['width']]
        z=depth/np.sqrt(1+((xx.ravel()+.5-p['cx'])/p['fx'])**2+((yy.ravel()+.5-p['cy'])/p['fy'])**2)
        assert (lower[ok]<=first[ok]+2e-5).all() and (first[ok]<=z[ok]+2e-5).all()
        assert (z[ok]<=upper[ok]+2e-5).all()
        for r in rows:
            j=r['index'];assert r['certified']==bool(mask[j])
            if r['certified']:
                assert r['heightLowerM']==float(lo[j]) and r['heightUpperM']==float(hi[j])
                assert lo[j]<=r['sampledFirstHitHeightMinM']+2e-4 and r['sampledFirstHitHeightMaxM']<=hi[j]+2e-4
        assert p['independentRayWitnesses']==int(mask.sum())*5
        total+=p['sparseCandidates'];certified+=p['sparseCertified'];witnesses+=p['independentRayWitnesses']
        for packet in [p,*b['channels']]:
            for k in ['frameId','sessionGeneration','capturedAtUs','sceneStateSha256']:assert packet[k]==b[k]
            rotation=np.array(packet['cameraToWalkingRotation']).reshape(3,3)
            assert np.allclose(rotation.T@rotation,np.eye(3),atol=1e-5) and abs(np.linalg.det(rotation)-1)<1e-5
            for d in packet.values():
                if isinstance(d,dict) and set(d)=={'path','sha256'}:checked(root,d)
            if packet is p:continue
            count=packet['width']*packet['height']
            dep=asset(root,packet['depth'],'<f4',count);low=asset(root,packet['freeZLower'],'<f4',count)
            up=asset(root,packet['surfaceZUpper'],'<f4',count);v=asset(root,packet['validity'],'u1',count)
            hl=asset(root,packet['heightLower'],'<f4',count);hh=asset(root,packet['heightUpper'],'<f4',count)
            fz=asset(root,packet['firstZLower'],'<f4',count)
            yy,xx=np.mgrid[:packet['height'],:packet['width']]
            z=dep/np.sqrt(1+((xx.ravel()+.5-packet['cx'])/packet['fx'])**2+((yy.ravel()+.5-packet['cy'])/packet['fy'])**2)
            assert np.isin(v,[0,1]).all() and np.isfinite(dep[v==1]).all() and (dep[v==1]>0).all()
            bounded=np.isfinite(hl)&np.isfinite(hh)
            assert np.isfinite(fz[bounded]).all() and np.isfinite(up[bounded]).all()
            assert (hl[bounded]<=hh[bounded]).all() and (low[bounded]<=fz[bounded]+2e-5).all()
            assert (fz[bounded]<=z[bounded]+2e-5).all() and (z[bounded]<=up[bounded]+2e-5).all()
            assert packet['rayWitnesses']>0;rig_witnesses+=packet['rayWitnesses']
        if b['rigPayloadsReused']:
            prior=next(x for x in old['batches'] if x['id']==('clear-first' if i==0 else 'clear-final'))
            assert prior['grid']==b['grid']
            for packet,prev in zip(b['channels'],prior['channels']):
                for k,v in prev.items():
                    assert (packet[k]['sha256']==v['sha256'] if isinstance(v,dict) and set(v)=={'path','sha256'} else packet[k]==v),k
    replay=read(DIRECTORY/'replay.json')
    assert replay['manifestSha256']==sha(root/'manifest.json') and replay['selectionSha256']==m['selectionSha256']
    assert replay['priorHazardReplaySha256']==sha(ROOT/'scratch/track-first-return-2026-10-09/replay.json')
    for k in ['promotionAllowed','ordinaryCameraWired','captureToCommandMeasured','namedDeviceValidated','newNeuralInference']:assert replay[k] is False
    assert replay['maximumAgeUs']==100000 and replay['summary']['completePassages']==11
    assert replay['summary']['single-original']['stops']==11 and replay['summary']['rig-original']['stops']==11
    assert replay['summary']['rig-supplemental']['stops']==10 and replay['summary']['rig-supplemental']['continues']==1
    for source in replay['sourceFrames']:assert source['bodyUnknown']==0 and source['passage']['status']=='measuredClear'
    for mode,frames in replay['continuous'].items():
        assert len(frames)==11
        for i,r in enumerate(frames):
            assert r['sessionStarts']==1 and r['lastFrameId']==r['frameId']==i+1
            assert r['capturedAtUs']==1791072000000000+i*200000 and r['nowUs']-r['capturedAtUs']==2000
            assert r['userMoving'] is True and r['delivery']=='shadow' and r['arbiterActive'] is False
            if i:assert r['previousRevision']==frames[i-1]['revision']
            assert r['revision']>r['previousRevision'] and r['tracks']==selection['frames'][i]['tracks']
        assert replay['summary'][mode]['stops']==sum(r['action']=='stopNow' for r in frames)
        assert replay['summary'][mode]['continues']==sum(r['action']=='continueForward' for r in frames)
        if mode=='rig-supplemental':
            for r in frames:
                for a in r['geometryOnlyQueries']:
                    if 'pixelAudit' in a:
                        assert a['pixelAudit']['productionCountParity'] is True
                        assert len(a['pixelAudit']['unknownPixels'])==a['unknownPixels']
    assert len(replay['faultTrials'])==18 and replay['summary']['afterFaultMovingContinues']==0
    for trial in replay['faultTrials']:
        frames=trial['frames'];assert len(frames)==11 and frames[5]['action']=='stopNow'
        assert not any(r['action']=='continueForward' for r in frames[6:])
        assert all(r['sessionStarts']==1 and r['userMoving'] is True for r in frames)
        for i,r in enumerate(frames):
            if i:assert r['previousRevision']==frames[i-1]['revision']
            assert r['delivery']=='shadow' and r['arbiterActive'] is False and r['lastFrameId']==i+1
            expected=selection['frames'][i]['tracks']
            assert len(r['tracks'])==len(expected)
            for track,original in zip(r['tracks'],expected):
                assert track['componentSupportCount']==len(original['componentSupport'])
                assert all(track[k]==v for k,v in original.items() if k!='componentSupport')
        if trial['fault'] in ['missingChannel','reorderedChannels','captureSkew1us','relativeUnits','foreignPose',
          'incompleteFirstZ','providerFailed','noReturns','unestablishedMotion','staleOriginalCapture']:
            assert frames[5]['passageApplied'] is False and frames[5]['passage']['status']=='unavailable'
    assert read(DIRECTORY/'diagnosis.json')==diagnosis()
    files=['selection.json','optical/manifest.json','replay.json','diagnosis.json',
      'sequence-diagnosis.png','sequence-diagnosis.svg']
    return {'schemaVersion':1,'passed':True,'promotionAllowed':False,'ordinaryCameraWired':False,
      'sources':{p:sha(ROOT/p) for p in SOURCES},'artifacts':{p:sha(DIRECTORY/p) for p in files},
      'priorValidationSha256':sha(ROOT/'scratch/track-first-return-2026-10-09/validation.json'),
      'summary':replay['summary'],'sparseCandidates':total,'sparseCertified':certified,
      'independentPrimaryRayWitnesses':witnesses,'rigRayWitnesses':rig_witnesses,
      'fullTimingGate':'not_passed_prior_4_of_21_expired','captureToCommandMeasured':False,
      'namedDeviceRuntime':'not_run','controlledWalking':'not_run'}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true');args=parser.parse_args()
    value=build();path=DIRECTORY/'validation.json'
    if args.write:
        if path.exists():raise ValueError('Validation is immutable')
        path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    else:assert read(path)==value,'Source/output drift'
    print('Eleven-frame experiment: capture/pixel/history parity, fault stops and previous receipts verified')

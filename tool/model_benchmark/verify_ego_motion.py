"""Independently check ego-frame arithmetic, source/asset identity and gates."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import numpy as np
from render_ego_motion import diagnosis

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/ego-motion-2026-10-10'
CORPUS=DIRECTORY/'corpus'
PRIOR=ROOT/'scratch/whole-track-evidence-2026-10-10'
SOURCES=[
    'docs/ego-motion-protocol-2026-10-10.md','docs/ego-motion-evaluation-2026-10-10.md',
    'lib/safety/perception/camera_ego_motion.dart','lib/safety/perception/separated_motion_risk.dart',
    'lib/safety/runtime/ego_motion_shadow_adapter.dart','test/camera_ego_motion_test.dart',
    'test/ego_motion_shadow_adapter_test.dart','test/harness/ego_motion_experiment.dart',
    'test/ego_motion_experiment_test.dart','tool/blender/generate_ego_motion_corpus.py',
    'tool/model_benchmark/infer_ego_motion.py','tool/model_benchmark/check_ego_motion.ps1',
    'tool/model_benchmark/render_ego_motion.py','tool/model_benchmark/verify_ego_motion.py',
    'lib/safety/perception/camera_fast_metric_motion.dart',
    'lib/safety/runtime/camera_metric_motion_shadow_scene.dart',
    'lib/safety/runtime/spatial_safety_runtime.dart',
    'lib/safety/runtime/confidence_authority_spatial_runtime.dart',
    'lib/safety/world/generic_geometry_scene_adapter.dart',
    'lib/services/generic_obstacle_detector.dart','lib/services/frame_stable_generic_obstacle_detector.dart',
    'lib/tracker/generic_obstacle_tracker.dart',
]


def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def require(ok,message):
    if not ok:raise ValueError(message)


def asset(desc,dtype):
    path=(CORPUS/desc['path']).resolve()
    require(path.is_relative_to(CORPUS) and sha(path)==desc['sha256'],'Asset path/hash drift')
    return np.frombuffer(gzip.decompress(path.read_bytes()),dtype=dtype)


def build():
    subprocess.run([sys.executable,'tool/model_benchmark/verify_whole_track_evidence.py'],cwd=ROOT,check=True)
    corpus=read(CORPUS/'manifest.json');r=read(DIRECTORY/'replay.json');ncnn=read(CORPUS/'ncnn/manifest.json')
    require(len(corpus['layouts'])==len(r['cases'])==6,'Case count drift')
    require(r['corpusManifestSha256']==ncnn['corpusManifestSha256']==sha(CORPUS/'manifest.json'),'Corpus identity drift')
    require(r['ncnnManifestSha256']==sha(CORPUS/'ncnn/manifest.json'),'Inference identity drift')
    require(ncnn['newScenesUsedForFit'] is False and r['newFit'] is False,'New fitting')
    for path,digest in corpus['sources'].items():
        require(sha(ROOT/path)==digest,'Capture generator/protocol drift')
    for key in ('promotionAllowed','latencyMeasured','androidReadinessEstablished','bodyCoverageEstablished',
                'wholeObjectStationarityCertified','canonicalRuntimeChanged'):
        require(r[key] is False,'Unsupported authority: '+key)
    counts={k:Counter(hazardStops=0,hazardMisses=0,falseStops=0,passableContinues=0)
            for k in r['summary']['runtime']}
    motion_counts={k:Counter(pairsAvailable=0,riskFrames=0,approaching=0,receding=0,lateral=0,
                            consistentWithStationary=0,uncertain=0) for k in r['summary']['motion']}
    hazards=0;captures=0
    annotation=read(CORPUS/'annotations.json')
    for layout,case in zip(corpus['layouts'],r['cases']):
        require(layout['id']==case['layoutId'] and len(layout['frames'])==len(case['frames'])==7,'Sequence drift')
        labels=next(v for v in annotation['layouts'] if v['layoutId']==layout['id'])['frames']
        previous={}
        for index,(meta,row,label) in enumerate(zip(layout['frames'],case['frames'],labels)):
            captures+=1;hazard=label['physicalHazard'];hazards+=hazard
            require(row['scoringOnly']==label,'Label drift')
            require(not any(k in meta for k in ('physicalHazard','objectVelocityWorldMps','motionKind')),'Scoring leaked into input')
            stamp=1790899200000000+index*200000
            require(row['frameId']==meta['frameId']==index+1 and row['capturedAtUs']==stamp and
                    row['nowUs']==stamp+2000 and row['sessionStarts']==1 and row['userMoving'] is True,'Retimed/reset replay')
            p=(CORPUS/meta['rgb']['path']).resolve()
            require(p.is_relative_to(CORPUS) and sha(p)==meta['rgb']['sha256'],'RGB drift')
            size=meta['width']*meta['height']
            arrays={k:asset(meta[k], 'u1' if k=='validity' else '<f4')
                    for k in ('depth','freeZLower','surfaceZUpper','validity')}
            require(all(len(a)==size for a in arrays.values()),'Depth dimensions drift')
            lo,hi=arrays['freeZLower'],arrays['surfaceZUpper'];finite=np.isfinite(lo)&np.isfinite(hi)
            require(np.all(hi[finite]>=lo[finite]) and np.isin(arrays['validity'],[0,1]).all(),'Invalid depth bounds')
            ego=row['egoMotion'];world=ego['worldMotion'];body=ego['bodyRelativeMotion']
            require(ego['poseAccepted'] is True and all(ego[k] is False for k in
                    ('wholeObjectStationarityCertified','relativeHypothesisResolved','freeSpaceCertified','promotionAllowed')),'Negative authority')
            for lane,motion in (('naive',row['naiveLocalMotion']),('world',world),('body',body)):
                count=motion_counts[f"{layout['id']}/{lane}"]
                count['pairsAvailable']+=motion['available'];count['riskFrames']+=motion['addsMotionRisk']
                require(motion['frameId']==index+1 and motion['validUntilUs']<=stamp+100000 and
                        stamp-motion['oldestEvidenceTimestampUs']<=400000,'Clock/TTL drift')
                require(motion['absenceOfMotionCertified'] is False and motion['freeSpaceCertified'] is False,'Absence authority')
                require(motion['available']==bool(motion['patches']),'Unavailable mismatch')
                threatening=0
                for patch in motion['patches']:
                    count[patch['classification']]+=1
                    for lower,upper in (('velocityLowerMps','velocityUpperMps'),('positionLowerM','positionUpperM')):
                        a,b=np.array(patch[lower]),np.array(patch[upper])
                        require(a.shape==b.shape==(3,) and np.isfinite(a).all() and np.isfinite(b).all() and np.all(a<=b),'Unbounded patch')
                    threatening+=patch['classification'] in ('approaching','receding','lateral') and patch['possibleBodyIntersection']
                require(threatening==motion['threateningPatches'] and (threatening>=3)==motion['addsMotionRisk'],'Positive risk threshold drift')
            require(len(world['patches'])==len(body['patches']),'Pair mismatch')
            if world['available']:
                prior=layout['frames'][index-1]
                error=meta['posePositionErrorM']+prior['posePositionErrorM']
                delta=np.array(meta['walkingOriginWorldM'])-prior['walkingOriginWorldM']
                elo,ehi=(delta-error)/.2,(delta+error)/.2
                require(np.allclose(elo,ego['originVelocityLowerMps'],rtol=0,atol=1e-12) and
                        np.allclose(ehi,ego['originVelocityUpperMps'],rtol=0,atol=1e-12),'Ego interval arithmetic drift')
                for w,b in zip(world['patches'],body['patches']):
                    require(w['currentPixel']==b['currentPixel'] and w['previousPixel']==b['previousPixel'],'Match ownership drift')
                    expected={'velocityLowerMps':np.array(w['velocityLowerMps'])-ehi,
                              'velocityUpperMps':np.array(w['velocityUpperMps'])-elo,
                              'positionLowerM':np.array(w['positionLowerM'])-meta['walkingOriginWorldM']-meta['posePositionErrorM'],
                              'positionUpperM':np.array(w['positionUpperM'])-meta['walkingOriginWorldM']+meta['posePositionErrorM']}
                    for k,v in expected.items():require(np.allclose(v,b[k],rtol=0,atol=1e-12),'Body-relative subtraction drift')
                    vlo,vhi=expected['velocityLowerMps'],expected['velocityUpperMps']
                    name=('approaching' if vhi[1]<-.2 else 'receding' if vlo[1]>.2 else
                          'lateral' if vhi[0]<-.2 or vlo[0]>.2 else
                          'consistentWithStationary' if np.all(vlo>=-.2) and np.all(vhi<=.2) else 'uncertain')
                    require(name==b['classification'],'Classification drift')
                    swept_lo=np.minimum(expected['positionLowerM'],expected['positionLowerM']+vlo)
                    swept_hi=np.maximum(expected['positionUpperM'],expected['positionUpperM']+vhi)
                    intersects=bool(np.all(swept_hi>=[-.55,0,.1]) and np.all(swept_lo<=[.55,3.5,1.9]))
                    require(intersects==b['possibleBodyIntersection'],'Body-relative sweep drift')
            for mode,arm in row['arms'].items():
                attribution=arm['riskAttribution']
                require(all(attribution[k] is False for k in ('wholeObjectStationarityCertified','relativeHypothesisResolved','freeSpaceCertified')),'Relative risk retired')
                for track in attribution['tracks']:
                    require(track['mayDropRelativeHypothesis'] is False and track['relativeTrendIsMetric'] is False and
                            track['relativeHypothesis']==(track['relativeTrend']>0),'Relative/metric confusion')
                control=arm['runtime']['additiveControl'];candidate=arm['runtime']['additiveShadow']
                require(candidate['observedFraction']<=control['observedFraction'] and candidate['unknown']>=control['unknown'],'Added free authority')
                require(control['action']!='stopNow' or candidate['action']=='stopNow','Stop released by compensation')
                for lane,outcome in arm['runtime'].items():
                    identity=f'{mode}/{lane}'
                    require(outcome['delivery']=='shadow' and outcome['arbiterActive'] is False and
                            outcome['revision']>outcome['previousRevision'] and
                            (not index or outcome['previousRevision']==previous[identity]),'History/active output drift')
                    previous[identity]=outcome['revision']
                    stop=outcome['action']=='stopNow'
                    key=('hazardStops' if stop else 'hazardMisses') if hazard else ('falseStops' if stop else 'passableContinues')
                    counts[identity][key]+=1
    require(captures==r['summary']['captures']==42 and hazards==r['summary']['physicalHazardFrames']==25 and
            captures-hazards==r['summary']['passableFrames']==17,'Scoring denominator drift')
    require({k:dict(v) for k,v in counts.items()}==r['summary']['runtime'],'Action summary drift')
    require({k:dict(v) for k,v in motion_counts.items()}==r['summary']['motion'],'Motion summary drift')
    for mode in ('legacy','frameStable'):
        require(counts[f'{mode}/canonical']['hazardMisses']==0,'Canonical hazard regression')
        require(counts[f'{mode}/additiveShadow']['hazardMisses']<=counts[f'{mode}/additiveControl']['hazardMisses'],'Additional hazard miss')
    d=diagnosis()
    require(read(DIRECTORY/'diagnosis.json')==d and d['candidateGate']=='not_passed' and
            d['knownFalseStopsBefore']==d['knownFalseStopsAfter']==10,'Failed gate hidden')
    artifacts={str(p.relative_to(DIRECTORY)).replace('\\','/'):sha(p) for p in sorted(CORPUS.rglob('*')) if p.is_file()}
    artifacts.update({p:sha(DIRECTORY/p) for p in ('replay.json','diagnosis.json','ego-motion.png','ego-motion.svg')})
    return {'schemaVersion':1,'reproducibilityAndMonotonicityPassed':True,'candidateGate':'not_passed',
        'promotionAllowed':False,'ordinaryCameraWired':False,'newSyntheticCaptures':42,
        'canonicalNewHazardStopsPerMode':25,'newPassableFalseStopsPerMode':17,
        'experimentalAdditiveHazardStopsPerMode':24,'experimentalAdditiveHazardMissesPerMode':1,
        'knownHazardStopsPerMode':60,'knownFalseStopsPerMode':10,'knownFalseStopFrames':11,
        'priorValidationSha256':sha(PRIOR/'validation.json'),
        'sourceSha256':{p:sha(ROOT/p) for p in SOURCES},'artifactSha256':artifacts,
        'latencyMeasured':False,'namedDeviceRuntime':'not_run','controlledWalking':'not_run'}


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--write',action='store_true')
    args=parser.parse_args();value=build();target=DIRECTORY/'validation.json'
    if args.write:
        require(not target.exists(),'Validation is immutable')
        target.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    else:require(read(target)==value,'Source/output drift')
    print('Ego motion: reproducibility and monotonic risk checks passed; false-stop/promotion gate NOT passed')

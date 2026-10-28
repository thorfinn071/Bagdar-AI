"""Serial-stage desktop estimates; never compare timings in functional RC."""
import hashlib
import json
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
LOG=ROOT/'docs/_baseline_logs'
def read(name):return json.loads((LOG/name).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def stats(values):return {'p50':float(np.percentile(values,50,method='inverted_cdf')),'p95':float(np.percentile(values,95,method='inverted_cdf'))}

def main():
    inference=read('camera_temporal_ncnn_timing.json')
    normalization=read('camera_temporal_normalization_timing.json')
    decision=read('camera_temporal_passage_decision_timing.json')
    functional=read('camera_temporal_passage.json')
    nn={(r['layoutId'],r['frameId']):r for r in inference['frames']}
    norm={(r['layoutId'],r['frameId']):r for r in normalization['frames']}
    splits={r['layoutId']:r['split'] for r in functional['sequences']}
    rows=[]
    for r in decision['frames']:
        key=r['layoutId'],r['frameId'];a=nn[key];n=norm[key]
        total=a['preprocessingMs']+a['inferenceMs']+n['normalizationMs']+r['decisionComputeMs']
        rows.append({**r,'split':splits[r['layoutId']],'preprocessingMs':a['preprocessingMs'],
            'inferenceMs':a['inferenceMs'],'normalizationMs':n['normalizationMs'],
            'serialStagesEstimateMs':total})
    stages=['preprocessingMs','inferenceMs','normalizationMs','detectorTrackerMs','reconstructionMs','runtimeMs','serialStagesEstimateMs']
    summaries={mode:{stage:stats([r[stage] for r in rows if r['split']=='test' and r['mode']==mode])
        for stage in stages} for mode in functional['summaries']}
    source_names=['camera_temporal_ncnn_timing.json','camera_temporal_normalization_timing.json',
        'camera_temporal_passage_decision_timing.json','camera_temporal_passage.json']
    indexed={(r['layoutId'],r['mode'],r['captureOffsetUs']):r for r in rows}
    reactions=[]
    for sequence in functional['sequences']:
        if sequence['split']!='test' or not sequence['physicalHazard'] or sequence['firstHazardStopOffsetUs'] is None:continue
        offset=sequence['firstHazardStopOffsetUs']-functional['functionalProcessingOffsetUs']
        row=indexed[sequence['layoutId'],sequence['mode'],offset]
        waiting=(offset-sequence['criticalOnsetOffsetUs'])/1000
        estimate=waiting+row['serialStagesEstimateMs']
        reactions.append({'layoutId':sequence['layoutId'],'mode':sequence['mode'],
            'captureOffsetUs':offset,'waitAfterHazardOnsetMs':waiting,
            'serialStagesEstimateMs':row['serialStagesEstimateMs'],
            'reactionSerialEstimateMs':estimate,'within300MsEstimate':estimate<=300})
    budgets={mode:{'testDecisionSteps':len([r for r in rows if r['split']=='test' and r['mode']==mode]),
        'over100MsEstimate':sum(r['serialStagesEstimateMs']>100 for r in rows if r['split']=='test' and r['mode']==mode),
        'hazardReactionEvents':len([r for r in reactions if r['mode']==mode]),
        'within300MsReactionEstimate':sum(r['within300MsEstimate'] for r in reactions if r['mode']==mode)}
        for mode in functional['summaries']}
    report={'scope':'desktop serial-stage estimate from separately recorded matching RGB/depth inputs; not capture-to-command or phone latency',
        'excludes':['depth/NN fixture loading','render','scan duration','device capture/transport/scheduling','posthoc report diagnostics'],
        'rgbPreprocessingIncludes':['PNG decode','RGB hash verification','RGB01 nearest stretch'],
        'syntheticStaticScanDurationMs':2000,'functionalProcessingOffsetIsMeasured':False,
        'sourceSha256':{name:sha(LOG/name) for name in source_names},'summarizerSha256':sha(Path(__file__)),
        'summariesTestOnly':summaries,'budgetsTestOnly':budgets,'hazardReactionEstimates':reactions,'frames':rows}
    (LOG/'camera_temporal_latency.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summaries,indent=2))

if __name__=='__main__':main()

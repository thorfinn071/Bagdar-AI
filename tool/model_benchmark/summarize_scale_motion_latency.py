"""Variable wall-clock stage estimates are never part of the functional --check."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def pct(values,q):
    values=sorted(values)
    if not values:return None
    import math
    return values[max(0,math.ceil(len(values)*q)-1)]
def main():
    folder=ROOT/'docs/_baseline_logs'
    n=json.loads((folder/'camera_scale_motion_ncnn_timing.json').read_text())
    t=json.loads((folder/'camera_scale_motion_decision_timing.json').read_text())
    functional=json.loads((folder/'camera_scale_motion.json').read_text())
    inference={(r['layoutId'],r['frameId']):r for r in n['frames']}
    rows=[]
    for r in t['frames']:
        if not r['layoutId'].startswith('test-'):continue
        nn=inference[r['layoutId'],r['frameId']]
        row={**r,'preprocessingMs':nn['preprocessingMs'],'inferenceMs':nn['inferenceMs']}
        row['serialStageEstimateMs']=row['preprocessingMs']+row['inferenceMs']+row['normalizationMs']+row['decisionComputeMs']
        row['currentEvidenceWouldExceed100ms']=row['serialStageEstimateMs']>100
        rows.append(row)
    keys=['preprocessingMs','inferenceMs','normalizationMs','detectorTrackerMs','reconstructionMs','scaleMotionMs','runtimeMs','decisionComputeMs','serialStageEstimateMs']
    summaries={}
    for mode in ['fixed-patch','spatial-only','scale-motion']:
        current=[r for r in rows if r['mode']==mode]
        summaries[mode]={'decisionFrames':len(current),'exceeds100msFrames':sum(r['currentEvidenceWouldExceed100ms'] for r in current),
            'stages':{key:{'p50':pct([r[key] for r in current],.5),'p95':pct([r[key] for r in current],.95)} for key in keys}}
    reaction=[]
    for r in functional['sequences']:
        if r['split']!='test' or not r['physicalHazard']:continue
        onset=r['criticalOnsetOffsetUs'];first=r['firstHazardStopOffsetUs']
        if first is None:continue
        step=next(f for f in r['decisions'] if f['captureOffsetUs']==first-2000)
        measured=next(v for v in rows if v['layoutId']==r['layoutId'] and v['mode']==r['mode'] and v['frameId']==step['frameId'])
        estimate=max(0,(first-2000-onset)/1000)+measured['serialStageEstimateMs']
        reaction.append({'layoutId':r['layoutId'],'mode':r['mode'],'firstStopFrameId':step['frameId'],
            'functionalReactionMs':(first-onset)/1000,'desktopSerialReactionEstimateMs':estimate,'within300msEstimate':estimate<=300})
    report={'scope':'desktop test-only matched serial stages; NN measured separately, excludes render/capture/transport/scheduling/depth fixture loading/scan',
        'captureToCommandMeasured':False,'functionalOffsetIsMeasuredLatency':False,
        'metricMotionStageIncludesDecodedRGBFixtureLoading':True,'summaries':summaries,'hazardReactionEstimates':reaction,'frames':rows}
    (folder/'camera_scale_motion_latency.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'summaries':summaries,'reaction':reaction},indent=2))
if __name__=='__main__':main()


"""Keep source coverage, current track priority and retained state distinct."""
import json
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/sequence-first-return-2026-10-09'


def read(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def diagnosis():
    replay=read(DIRECTORY/'replay.json')
    full=replay['continuous']['rig-supplemental']
    fresh=replay['diagnosticAblations']['freshRuntimeRetainedTracker']
    reset=replay['diagnosticAblations']['freshDetectorTrackerRuntime']
    rows=[]
    for i,r in enumerate(full):
        direct=[a for a in r['geometryOnlyQueries'] if a['bounds']=='supplemental']
        original=[a for a in r['geometryOnlyQueries'] if a['bounds']=='original']
        rows.append({'id':r['id'],'index':i,'action':r['action'],'rule':r['rule'],
          'sourceStatus':replay['sourceFrames'][i]['passage']['status'],
          'unknownBodyBoxes':replay['sourceFrames'][i]['bodyUnknown'],
          'geometryOnlyUnknownBefore':sum(a['unknownPixels'] for a in original),
          'geometryOnlyUnknownAfter':sum(a['unknownPixels'] for a in direct),
          'geometryOnlyUnknownTracks':[{'trackId':a['trackId'],'reason':a['reason']} for a in direct if a['relation']=='unknown'],
          'currentGeometryUnknownTracks':[a['trackId'] for a in direct if a['relation']=='unknown' and a['reason']!='track_not_observed_in_matching_frame'],
          'currentPriorityTracks':[a['trackId'] for a in r['associations'] if a['reason']=='motion_or_semantic_priority'],
          'positiveTrends':{str(t['id']):t['approachTrend'] for t in r['tracks'] if t['approachTrend']>0},
          'forwardRejections':r['forwardRejections'],
          'freshRuntimeAction':fresh[i]['action'],'freshAllActionDifferentFootprint':reset[i]['action'],
          'freshRuntimeRule':fresh[i]['rule'],
          'continuousStopWithFreshRuntimeContinue':r['action']=='stopNow' and fresh[i]['action']=='continueForward',
          'hazardHistory':r['hazardHistory']})
    return {'schemaVersion':1,'promotionAllowed':False,
      'scope':'geometry-only queries and fresh-state ablations are diagnostics, never runtime authority',
      'summary':{'continuous':replay['summary'],
        'supplementalRuleCounts':dict(Counter(r['rule'] for r in full)),
        'currentPriorityFrames':sum(bool(r['currentPriorityTracks']) for r in rows),
        'currentGeometryUnknownTracksAfter':sum(len(r['currentGeometryUnknownTracks']) for r in rows),
        'staleTrackUnknownAssociations':sum(a['reason']=='track_not_observed_in_matching_frame' for r in rows for a in r['geometryOnlyUnknownTracks']),
        'freshRuntimeStops':sum(r['action']=='stopNow' for r in fresh),
        'freshAllStopsDifferentFootprint':sum(r['action']=='stopNow' for r in reset),
        'continuousStopWithFreshRuntimeContinue':sum(r['continuousStopWithFreshRuntimeContinue'] for r in rows)},
      'frames':rows}


def render():
    value=diagnosis();path=DIRECTORY/'diagnosis.json'
    if path.exists():raise ValueError('Diagnosis is immutable')
    path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
    replay=read(DIRECTORY/'replay.json');rows=value['frames'];x=np.arange(11)
    fig,axes=plt.subplots(3,1,figsize=(12,8),gridspec_kw={'height_ratios':[2,1.3,1.5]},layout='constrained')
    labels=['Original single camera','Original primary + ideal rig','Supplemental primary + ideal rig',
      'Fresh runtime; detector/tracker retained','Fresh all; DIFFERENT detector support']
    series=[*replay['continuous'].values(),*replay['diagnosticAblations'].values()]
    for y,(label,frames) in enumerate(zip(labels,series)):
        colors=['#31856c' if r['action']=='continueForward' else '#c95b52' for r in frames]
        axes[0].scatter(x,np.full(11,y),c=colors,s=240,marker='s')
        for i,r in enumerate(frames):axes[0].text(i,y,'GO' if r['action']=='continueForward' else 'STOP',ha='center',va='center',fontsize=7,color='white')
    axes[0].set_yticks(range(5),labels);axes[0].invert_yaxis();axes[0].set_title('11 original captures in order — shadow decisions',loc='left',weight='bold')
    axes[1].plot(x,[r['geometryOnlyUnknownBefore'] for r in rows],'-o',label='Missing primary pixels before supplement',color='#ab6751')
    axes[1].plot(x,[r['geometryOnlyUnknownAfter'] for r in rows],'-o',label='After exact sparse proof (geometry-only query)',color='#31856c')
    axes[1].set_ylabel('Unknown support pixels');axes[1].legend(fontsize=8,loc='upper right')
    for tid in sorted({t['id'] for r in replay['continuous']['rig-supplemental'] for t in r['tracks']}):
        axes[2].plot(x,[next((t['approachTrend'] for t in r['tracks'] if t['id']==tid),np.nan)
          for r in replay['continuous']['rig-supplemental']],'-o',label=f'Track {tid}',markersize=3)
    axes[2].axhline(0,color='#777',linewidth=.8);axes[2].set_ylabel('Relative proximity trend\n(not metric velocity)');axes[2].legend(fontsize=8)
    axes[2].set_xlabel('Original frame index · 200 ms per capture · userMoving=true throughout')
    for ax in axes:ax.set_xticks(x);ax.set_xlim(-.5,10.5);ax.grid(axis='x',alpha=.15)
    fig.suptitle('Source passage clear on all 11 ideal-rig snapshots; motion and history still retain authority\nFixed +2 ms functional clock · 100 ms freshness · offline synthetic evidence',fontsize=12)
    for ext in ['png','svg']:fig.savefig(DIRECTORY/f'sequence-diagnosis.{ext}',dpi=170)
    plt.close(fig)


if __name__=='__main__':render()

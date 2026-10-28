"""Plot measured replay classifications, keeping failed gates visible."""
import json
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
plt.rcParams['svg.hashsalt']='ego-motion-2026-10-10'

ROOT=Path(__file__).resolve().parents[2]
DIRECTORY=ROOT/'scratch/ego-motion-2026-10-10'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def diagnosis():
    replay=read(DIRECTORY/'replay.json')
    prior=read(ROOT/'scratch/whole-track-evidence-2026-10-10/replay.json')
    misses=[]
    for case in replay['cases']:
        for frame in case['frames']:
            if not frame['scoringOnly']['physicalHazard']: continue
            for mode,arm in frame['arms'].items():
                for lane,outcome in arm['runtime'].items():
                    if outcome['action']!='stopNow':
                        misses.append({'layoutId':case['layoutId'],'frameId':frame['frameId'],
                                       'mode':mode,'lane':lane,'action':outcome['action'],'rule':outcome['rule']})
    return {'schemaVersion':1,'promotionAllowed':False,
        'candidateGate':'not_passed', 'knownFalseStopsBefore':prior['summary']['frameStable']['stops'],
        'knownFalseStopsAfter':prior['summary']['frameStable']['stops'],
        'knownFalseStopFrames':11,'knownRuntimeChanged':False,
        'newCorpusSummary':replay['summary'],'newHazardMisses':misses,
        'zeroNewHazardMissGate':not misses,
        'stationaryVisiblePatchesMayClearRelativeRisk':False,
        'bodyCoverageEstablished':False,'worldMotionIsNotBodyClosing':True,
        'timingEvidence':'fixed replay clock only; no measured latency',
        'androidReadinessEstablished':False}


def main():
    value=diagnosis()
    target=DIRECTORY/'diagnosis.json'
    text=json.dumps(value,indent=2)+'\n'
    if target.exists():
        assert target.read_text(encoding='utf-8')==text, 'Immutable diagnosis drift'
    else:target.write_text(text,encoding='utf-8')
    summary=value['newCorpusSummary'];motion=summary['motion']
    cases=list(dict.fromkeys(k.rsplit('/',1)[0] for k in motion))
    colors=['#c64c3b','#db9854','#478ab2','#82a887','#c9c9c9']
    classes=['approaching','lateral','receding','consistentWithStationary','uncertain']
    fig,axes=plt.subplots(2,3,figsize=(14,9),layout='constrained')
    fig.suptitle('Ego motion: world motion and body closing are separate\n'
                 '42 new synthetic captures | unchanged detector/tracker | shadow only',fontsize=15)
    for ax,case in zip(axes.flat,cases):
        bottom=np.zeros(3)
        for name,color in zip(classes,colors):
            y=[motion[f'{case}/{lane}'][name] for lane in ('naive','world','body')]
            ax.bar(['Local (naive)','World (aligned)','Body relative'],y,bottom=bottom,label=name,color=color)
            bottom+=y
        ax.set_title(case.removeprefix('ego-'))
        ax.set_ylabel('Visible matched patches, all 6 pairs')
        risks=[motion[f'{case}/{lane}']['riskFrames'] for lane in ('naive','world','body')]
        ax.text(.02,.98,'Positive risk frames: '+ ' / '.join(map(str,risks)),transform=ax.transAxes,va='top',fontsize=9)
        ax.margins(y=.23)
    handles,labels=axes.flat[0].get_legend_handles_labels()
    fig.legend(handles,labels,loc='outside lower center',ncol=5)
    fig.savefig(DIRECTORY/'ego-motion.png',dpi=150)
    fig.savefig(DIRECTORY/'ego-motion.svg',metadata={'Date':None})
    plt.close(fig)
    print(json.dumps({k:v for k,v in value.items() if k!='newCorpusSummary'},indent=2))


if __name__=='__main__':main()

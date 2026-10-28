"""Whole visible support coverage, with no negative-motion authority."""
import json
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/whole-track-evidence-2026-10-10'
PRIOR = ROOT / 'scratch/motion-origin-2026-10-10'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def diagnosis():
    r = read(DIRECTORY / 'replay.json')
    old = read(PRIOR / 'replay.json')
    optical = read(DIRECTORY / 'optical/manifest.json')
    cases = []
    all_samples = []
    for c in r['motionCases']:
        modes = {}
        for mode in ('legacy', 'frameStable'):
            samples = [a for f in c['frames'] for a in f['relative'][mode]['coverage']]
            all_samples.extend(samples)
            valid = [s for s in samples if s['available']]
            modes[mode] = {
                'trackSamples': len(samples), 'availableSamples': len(valid),
                'unavailableReasons': dict(Counter(s['reason'] for s in samples if not s['available'])),
                'samplesWithMatchedCentres': sum(s['currentMatchedCentres'] > 0 for s in valid),
                'matchedCentres': sum(s['currentMatchedCentres'] for s in valid),
                'footprintPixels': sum(s['currentFootprintPixels'] for s in valid),
                'maximumVisibleCoverage': max((s['currentCoverage'] for s in valid), default=0),
                'completeVisibleSamples': sum(s['completeVisibleSupport'] for s in samples),
                'localMovingCentres': sum(s['localMovingCentres'] for s in valid),
            }
        cases.append({'layoutId': c['layoutId'], 'motionKindLabel': c['frames'][-1]['scoringOnly']['motionKind'],
                      'modes': modes})
    valid = [s for s in all_samples if s['available']]
    return {
        'schemaVersion': 1, 'promotionAllowed': False, 'ordinaryCameraWired': False,
        'candidateGate': 'not_passed_no_false_stop_reduction_or_whole_object_motion_absence',
        'certifiedAdditionalFirstReturnPixels': sum(r['certified'] for r in optical['records']),
        'firstReturnCandidates': sum(r['candidates'] for r in optical['records']),
        'independentFirstHitWitnesses': sum(r['rayWitnesses'] for r in optical['records']),
        'optical': {mode: {
            'beforeUnknownPixelQueries': [sum(a['unknownPixels'] for a in f['geometryOnlyQueries'])
                                          for f in old['sequence'][mode]],
            'afterUnknownPixelQueries': r['summary'][mode]['geometryUnknownPixels'],
            'stopsBefore': old['summary'][mode]['stops'], 'stopsAfter': r['summary'][mode]['stops'],
            'continuesAfter': r['summary'][mode]['continues'],
            'motionPriorityFrames': sum(any(a['reason'] == 'motion_or_semantic_priority'
                                           for a in f['associations']) for f in r['optical'][mode]),
            'missedTrackFrames': sum(any(t['misses'] > 0 for t in f['tracks']) for f in r['optical'][mode]),
        } for mode in ('legacy', 'frameStable')},
        'initialFaultTrials': r['summary']['initialFaultTrials'],
        'initialFaultStops': r['summary']['initialFaultStops'],
        'trackSamples': len(all_samples), 'availableSamples': len(valid),
        'samplesWithMatchedCentres': sum(s['currentMatchedCentres'] > 0 for s in valid),
        'completeVisibleSamples': sum(s['completeVisibleSupport'] for s in all_samples),
        'maximumVisibleCoverage': max((s['currentCoverage'] for s in valid), default=0),
        'wholeObjectStationarityCertified': False, 'motionPriorityResolved': False,
        'hazardFramesPerMode': sum(f['scoringOnly']['physicalHazard'] is True
                                 for c in r['motionCases'] for f in c['frames']),
        'hazardStopsPerMode': {mode: sum(f['scoringOnly']['physicalHazard'] is True and
                               f['relative'][mode]['action'] == 'stopNow'
                               for c in r['motionCases'] for f in c['frames'])
                               for mode in ('legacy', 'frameStable')},
        'cases': cases,
        'limitations': [
            'Additional first-return geometry does not measure material correspondence or hidden extent.',
            'A correspondence centre and its 3x3 registration bounds are one measurement, not nine matches.',
            'Diagnostic full visible support is necessary for a visible coverage claim, not sufficient for whole object stationarity.',
            'Known synthetic inputs; no new independent holdout, neural inference, device or controlled walking proof.',
            'Functional capture+2 ms clock; no measured capture-to-command latency. Prior age gate remains open.',
        ],
    }


def render():
    targets = [DIRECTORY / n for n in ('diagnosis.json', 'whole-track-evidence.png', 'whole-track-evidence.svg')]
    if any(p.exists() for p in targets):
        raise ValueError('Completed diagnosis/figures are immutable')
    v = diagnosis()
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10})
    fig, axes = plt.subplots(3, 1, figsize=(12, 10), layout='constrained')
    colors = ['#bb684a', '#337d80']
    for j, mode in enumerate(('legacy', 'frameStable')):
        s = v['optical'][mode]
        axes[0].plot(range(11), s['beforeUnknownPixelQueries'], '--o', color=colors[j], label=f'{mode}: prior bounds')
        axes[0].plot(range(11), s['afterUnknownPixelQueries'], '-x', color=colors[j], label=f'{mode}: extended bounds')
    axes[0].set_title('A. Optical support gap largely closed; failed proof stays unknown', loc='left', weight='bold')
    axes[0].set_ylabel('Unknown pixel queries'); axes[0].set_xticks(range(11)); axes[0].legend(fontsize=8)
    r = read(DIRECTORY / 'replay.json')
    for y, mode in enumerate(('legacy', 'frameStable')):
        for x, f in enumerate(r['optical'][mode]):
            go = f['action'] == 'continueForward'
            axes[1].scatter(x, y, marker='s', s=520, color=colors[1] if go else colors[0])
            axes[1].text(x, y, 'GO' if go else 'STOP', ha='center', va='center', color='white', fontsize=7)
    axes[1].set_yticks([0, 1], ['Stateful detector', 'Frame-stable detector'])
    axes[1].set_xticks(range(11)); axes[1].set_ylim(1.5, -.5); axes[1].set_xlim(-.6, 10.6)
    axes[1].set_title('B. Same continuous outcome: 10 STOP / 11 frames in both modes', loc='left', weight='bold')
    axes[1].set_xlabel('Original path-clear frame index; one session; no time shifting')
    x = np.arange(len(v['cases']))
    for j, mode in enumerate(('legacy', 'frameStable')):
        axes[2].bar(x + (j - .5) * .36,
                    [c['modes'][mode]['maximumVisibleCoverage'] * 100 for c in v['cases']],
                    .36, color=colors[j], label=mode)
    axes[2].set_xticks(x, ['Approach\nslow', 'Approach\nfast', 'Approach\nsmall', 'Receding',
                           'Stationary', 'Camera\nyaw', 'Mixed', 'Occluded', 'Textureless'])
    axes[2].set_ylabel('Best covered track pixels (%)'); axes[2].legend(fontsize=8)
    axes[2].set_title(f"C. Sparse matched centres: 0/{v['trackSamples']} complete visible track samples", loc='left', weight='bold')
    fig.suptitle('Whole visible track evidence — 10 October 2026\nKnown synthetic replay · shadow only · no motion-priority removal', fontsize=14)
    fig.supxlabel('Complete visible coverage would still not prove whole object stationarity. No device or latency claim.', fontsize=9)
    fig.savefig(targets[1], dpi=160); fig.savefig(targets[2]); plt.close(fig)
    targets[0].write_text(json.dumps(v, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    render()

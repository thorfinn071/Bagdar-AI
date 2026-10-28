"""Summarize rank drift without granting motion-absence or clearance authority."""
import json
from collections import Counter
from pathlib import Path

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/motion-origin-2026-10-10'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def diagnosis():
    replay = read(DIRECTORY / 'replay.json')
    cases = []
    for case in replay['motionCases']:
        frames = case['frames']
        classes = Counter(p['classification'] for f in frames
                          for p in f['metricMotion']['patches'])
        cases.append({
            'layoutId': case['layoutId'],
            'motionKindLabel': frames[-1]['scoringOnly']['motionKind'],
            'pairs': len(frames) - 1,
            'relativePositiveFrames': {
                mode: sum(f['relative'][mode]['positiveRelativeTracks'] > 0 for f in frames)
                for mode in ('legacy', 'frameStable')},
            'localPatchClassifications': dict(classes),
            'unknownCandidates': sum(f['metricMotion']['unknownPatches'] for f in frames),
            **case['summary'],
        })
    full = replay['sequence']
    return {
        'schemaVersion': 1, 'promotionAllowed': False, 'ordinaryCameraWired': False,
        'newIndependentHoldout': False, 'objectStationarityCertified': False,
        'candidateGate': 'not_passed_no_continuous_false_stop_reduction',
        'stationaryCounterfactual': replay['stationaryCounterfactual'],
        'sequenceSummary': replay['summary'],
        'perFrame': [{
            'index': a['index'],
            'legacyAction': a['action'], 'frameStableAction': b['action'],
            'legacyPositiveTracks': a['positiveRelativeTracks'],
            'frameStablePositiveTracks': b['positiveRelativeTracks'],
            'frameStablePixelsOutsidePriorSelection': b['pixelsOutsidePriorSelection'],
            'legacyGeometryOnlyUnknownPixels': sum(x['unknownPixels'] for x in a['geometryOnlyQueries']),
            'frameStableGeometryOnlyUnknownPixels': sum(x['unknownPixels'] for x in b['geometryOnlyQueries']),
        } for a, b in zip(full['legacy'], full['frameStable'])],
        'knownMotionCases': cases,
        'totalHazardFramesPerMode': sum(c['hazardFrames'] for c in cases),
        'unsafeContinuesPerMode': {m: sum(c['unsafeContinues'][m] for c in cases)
                                  for m in ('legacy', 'frameStable')},
        'limitations': [
            'Counterfactual identical-map calls are not physical captures or runtime evidence.',
            'Original sparse metric supplement was selected for legacy support; different candidate support stays unknown.',
            'Patch motion cannot certify whole-object stationarity or absence of motion.',
            'Known synthetic regression data, not a new holdout; metric depth and pose are independent renderer inputs.',
            'Functional capture+2 ms clock; capture-to-command latency and Android not measured.',
        ],
    }


def render():
    value = diagnosis()
    targets = [DIRECTORY / f'motion-origin.{ext}' for ext in ('png', 'svg')]
    target = DIRECTORY / 'diagnosis.json'
    if target.exists() or any(p.exists() for p in targets):
        raise ValueError('Diagnosis and figure are immutable; use a new experiment directory')
    plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 10})
    fig, axes = plt.subplots(3, 1, figsize=(12, 10), layout='constrained',
                             gridspec_kw={'height_ratios': [1.2, 1.3, 2]})
    colors = ['#bb684a', '#337d80']
    repeats = value['stationaryCounterfactual']
    axes[0].barh([1, 0], [r['positiveRelativeFrames'] for r in repeats], color=colors)
    axes[0].set_yticks([1, 0], ['Stateful detector', 'Frame-stable detector'])
    axes[0].set_xlim(0, 11)
    axes[0].set_xlabel('Calls with positive relative approach trend (11 identical maps)')
    axes[0].set_title('A. Sampling alone can create relative approach', loc='left', weight='bold')
    for y, r in zip([1, 0], repeats):
        axes[0].text(r['positiveRelativeFrames'] + .15, y,
                     f"{r['positiveRelativeFrames']}/11", va='center')
    for y, (mode, label) in enumerate([('legacy', 'Stateful detector'),
                                       ('frameStable', 'Frame-stable detector')]):
        rows = read(DIRECTORY / 'replay.json')['sequence'][mode]
        for x, r in enumerate(rows):
            color = '#337d80' if r['action'] == 'continueForward' else '#bb684a'
            axes[1].scatter(x, y, marker='s', s=470, color=color)
            axes[1].text(x, y, 'GO' if r['action'] == 'continueForward' else 'STOP',
                         ha='center', va='center', color='white', fontsize=7)
    axes[1].set_yticks([0, 1], ['Stateful detector', 'Frame-stable detector'])
    axes[1].set_xticks(range(11)); axes[1].set_xlim(-.6, 10.6)
    axes[1].set_ylim(1.5, -.5)
    axes[1].set_xlabel('Original path-clear frame index; 200 ms interval; one continuous session')
    axes[1].set_title('B. Continuous false stops remain 10/11 in both modes', loc='left', weight='bold')
    cases = value['knownMotionCases']; x = np.arange(len(cases)); width = .24
    for j, (key, label, color) in enumerate([
        ('legacy', 'Relative positive trend: stateful', colors[0]),
        ('frameStable', 'Relative positive trend: frame-stable', colors[1]),
        ('metric', 'Any local metric motion', '#5966a4'),
    ]):
        values = [c['positiveLocalMotionFrames'] if key == 'metric'
                  else c['relativePositiveFrames'][key] for c in cases]
        axes[2].bar(x + (j - 1) * width, values, width, label=label, color=color)
    axes[2].set_xticks(x, ['Approach\nslow', 'Approach\nfast', 'Approach\nsmall',
                           'Receding', 'Stationary', 'Camera\nyaw', 'Mixed',
                           'Occluded', 'Textureless'])
    axes[2].set_yticks(range(7)); axes[2].set_ylabel('Frames with signal / 6 pairs')
    axes[2].set_title('C. Relative rank and pose-compensated local motion are different signals',
                      loc='left', weight='bold')
    axes[2].legend(fontsize=9, loc='upper center', bbox_to_anchor=(.5, -.2), ncol=3)
    fig.suptitle('Motion origin experiment — 10 October 2026\nKnown synthetic inputs · shadow only · no motion-priority removal', fontsize=14)
    fig.supxlabel('No local motion does not prove a stationary object or free passage. No Android or latency claim.', fontsize=9)
    for p in targets:
        fig.savefig(p, dpi=160)
    plt.close(fig)
    target.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    render()

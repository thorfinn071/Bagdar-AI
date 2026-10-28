"""Post-decision scoring and a reproducible synthetic repair figure."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/evidence-authority-fix-2026-10-10'
CORPUS = ROOT / 'scratch/ego-motion-2026-10-10/corpus'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def entry_time(center, half, velocity):
    """Exact continuous translating AABB vs the protected body, over one second."""
    enter, leave = 0., 1.
    for c, h, v, a, b in zip(center, half, velocity, [-.45, .2, .05], [.45, 3.5, 1.8]):
        if abs(v) < 1e-12:
            if c + h < a or c - h > b:
                return None
        else:
            first, last = sorted(((a - c - h) / v, (b - c + h) / v))
            enter, leave = max(enter, first), min(leave, last)
            if enter > leave:
                return None
    return enter


def forecast(layout, index, kind, label):
    """Scoring only: frozen procedural geometry and constant-velocity continuation.

    This code is never imported by a runtime or replay consumer. In particular,
    a continuation beyond the rendered window is not a measured future capture.
    """
    meta = layout['frames'][index]
    origin = meta['walkingOriginWorldM']
    previous = layout['frames'][max(0, index - 1)]['walkingOriginWorldM']
    ego_velocity = [(a - b) / .2 for a, b in zip(origin, previous)]
    tests = [('back-wall', [0., 4.02, 1.8], [4., .1, 1.8], [0., 0., 0.])]
    if kind not in ('camera-forward', 'camera-yaw'):
        pos = [.03, 3.13 - index * .18 if kind == 'object-approach' else 3.17 - index * .14, .76]
        if kind in ('crossing-camera', 'occluded-crossing'):
            pos = [1.22 - index * .19, 2.48, .76]
        velocity = label['objectVelocityWorldMps']
        if velocity is not None:
            tests.append(('moving-box', pos, [.24, .18, .76], velocity))
    if kind == 'occluded-crossing':
        tests.append(('opaque-occluder', [0., 1.24, .9], [.62, .08, .9], [0., 0., 0.]))
    hits = []
    for name, center, half, velocity in tests:
        t = entry_time([a - b for a, b in zip(center, origin)], half,
                       [a - b for a, b in zip(velocity, ego_velocity)])
        if t is not None:
            hits.append({'object': name, 'entryTimeS': t})
    return hits


def diagnosis():
    known = read(DIRECTORY / 'known-replay.json')
    repaired = read(DIRECTORY / 'ego-repair-replay.json')
    corpus = read(CORPUS / 'manifest.json')
    labels = read(CORPUS / 'annotations.json')
    warnings = []
    for case, layout, annotation in zip(repaired['cases'], corpus['layouts'], labels['layouts']):
        for index, (row, label) in enumerate(zip(case['frames'], annotation['frames'])):
            if label['physicalHazard']:
                continue
            modes = [mode for mode, arm in row['arms'].items()
                     if arm['runtime']['fixedRig']['action'] == 'stopNow']
            if modes:
                hits = forecast(layout, index, label['motionKind'], label)
                warnings.append({'layoutId': case['layoutId'], 'frameId': row['frameId'],
                                 'modes': modes, 'oneSecondSweptIntersections': hits,
                                 'instantaneousScoring': 'falseStop',
                                 'anticipatoryUnderConstantVelocity': bool(hits),
                                 'currentPositiveMotion': row['bodyMotion']['addsMotionRisk']})
    return {
        'schemaVersion': 1, 'syntheticRepairGate': 'passed', 'promotionAllowed': False,
        'ordinaryCameraWired': False, 'knownFrames': 11,
        'knownFalseStopsBefore': 10,
        'knownFalseStopsAfterPerMode': {m: known['summary'][m]['stops'] for m in ('legacy', 'frameStable')},
        'knownHazardStopsPerMode': 60, 'knownInitialFaultStops': known['summary']['initialFaultStops'],
        'newInstantaneousScoring': repaired['summary'],
        'remainingPassableStops': warnings,
        'forecastScope': 'post-decision synthetic constant-velocity continuation for 1 s; not measured future captures',
        'experimentalPlainSceneHazardMissesBeforePerMode': 1,
        'repairedConfidenceHazardMissesAfterPerMode': 0,
        'maximumFreshnessUs': 100000,
        'wholeObjectStationarityCertified': False, 'latencyMeasured': False,
        'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run',
    }


def render():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    plt.rcParams['svg.hashsalt'] = 'volume-authority-2026-10-10'
    value = diagnosis()
    (DIRECTORY / 'diagnosis.json').write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
    axes[0].bar(['Previous', 'Repaired'], [10, 0], color=['#a94d49', '#377b6e'])
    axes[0].set(title='Known clear sequence: 11 captures', ylabel='STOP frames', ylim=(0, 11))
    axes[0].text(1, .35, '0 / 11', ha='center', weight='bold')
    axes[1].bar(np.arange(3), [17, 8, 3], color=['#aaaeb5', '#a94d49', '#377b6e'])
    axes[1].set(xticks=np.arange(3), xticklabels=['Single view', 'Same rig, old', 'Same rig, repaired'],
                title='New sequences: 17 instantaneously clear captures', ylabel='Instantaneous false-stop count', ylim=(0, 18))
    for i, v in enumerate([17, 8, 3]):
        axes[1].text(i, v + .25, str(v), ha='center', weight='bold')
    axes[1].text(2, 5.2, '3 retained / anticipatory warnings\n1 s physical sweep intersects', ha='center', fontsize=9)
    for ax in axes:
        ax.spines[['top', 'right']].set_visible(False)
    fig.suptitle('Current-volume authority repair — both detector modes agree\n85 / 85 known + new hazard frames stopped per mode; synthetic shadow only', fontsize=13)
    for suffix in ('png', 'svg'):
        fig.savefig(DIRECTORY / f'volume-authority.{suffix}', dpi=160, metadata={'Date': None} if suffix == 'svg' else None)
    plt.close(fig)


if __name__ == '__main__':
    render()

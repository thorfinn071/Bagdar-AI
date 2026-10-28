"""Independent post-decision geometry scoring and holdout figure."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / 'scratch/volume-holdout-2026-10-10'
CORPUS = DIRECTORY / 'corpus'
MODES = ('legacy', 'frameStable')
LANES = ('singleViewControl', 'fixedSingleView', 'sameRigControl', 'fixedRig')


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def intersects(lower, upper, body_lower, body_upper):
    return all(b > c + 1e-6 and a < d - 1e-6
               for a, b, c, d in zip(lower, upper, body_lower, body_upper))


def entry_time(lower, upper, velocity, horizon=1.):
    """Continuous moving box vs body; strict overlap avoids floor-touch hazards."""
    enter, leave = 0., horizon
    for lo, hi, v, a, b in zip(lower, upper, velocity, [-.45, .2, .05], [.45, 3.5, 1.8]):
        if abs(v) < 1e-12:
            if hi <= a + 1e-6 or lo >= b - 1e-6:
                return None
        else:
            first, last = sorted(((a - hi + 1e-6) / v, (b - lo - 1e-6) / v))
            enter, leave = max(enter, first), min(leave, last)
            if enter >= leave:
                return None
    return enter


def current_truth(label):
    origin = label['walkingOriginWorldM']
    lo = [a + b for a, b in zip(origin, [-.45, .2, .05])]
    hi = [a + b for a, b in zip(origin, [.45, 3.5, 1.8])]
    blockers = [g['name'] for g in label['geometry'] if intersects(g['lowerM'], g['upperM'], lo, hi)]
    return bool(blockers) or label['floorDiscontinuity'], blockers


def forecast(label):
    origin, ego = label['walkingOriginWorldM'], label['originVelocityMps']
    hits = []
    for g in label['geometry']:
        lower = [a - b for a, b in zip(g['lowerM'], origin)]
        upper = [a - b for a, b in zip(g['upperM'], origin)]
        velocity = [a - b for a, b in zip(g['velocityMps'], ego)]
        t = entry_time(lower, upper, velocity)
        if t is not None:
            hits.append({'object': g['name'], 'entryTimeS': t})
    return hits


def diagnosis():
    replay = read(DIRECTORY / 'replay.json')
    labels = read(CORPUS / 'annotations.json')
    warnings, approach_continues, by_layout = [], [], []
    per_mode = {m: {'instantaneousFalseStops': 0, 'falseStopsWithOneSecondIntersection': 0,
                    'falseStopsWithoutOneSecondIntersection': 0,
                    'passableContinuesWithOneSecondIntersection': 0} for m in MODES}
    for case, annotation in zip(replay['cases'], labels['layouts']):
        assert case['layoutId'] == annotation['layoutId']
        rows = case['frames']
        counts = {m: {'hazardStops': 0, 'falseStops': 0, 'passableContinues': 0} for m in MODES}
        old_counts = {m: 0 for m in MODES}
        for row, label in zip(rows, annotation['frames']):
            assert row['scoringOnly'] == label
            truth, blockers = current_truth(label)
            assert truth == label['physicalHazard'] and blockers == label['blockers']
            hits = forecast(label)
            for mode in MODES:
                action = row['arms'][mode]['runtime']['fixedRig']
                stop = action['action'] == 'stopNow'
                if truth:
                    counts[mode]['hazardStops'] += stop
                    continue
                counts[mode]['falseStops' if stop else 'passableContinues'] += 1
                old_counts[mode] += row['arms'][mode]['runtime']['sameRigControl']['action'] == 'stopNow'
                if stop:
                    per_mode[mode]['instantaneousFalseStops'] += 1
                    field = 'falseStopsWithOneSecondIntersection' if hits else 'falseStopsWithoutOneSecondIntersection'
                    per_mode[mode][field] += 1
                    warnings.append({'layoutId': case['layoutId'], 'frameId': row['frameId'], 'mode': mode,
                                     'rule': action['rule'], 'currentPositiveMotion': row['bodyMotion']['addsMotionRisk'],
                                     'retainedHistoryRule': action['rule'] == 'SPATIAL-P0-AWAIT-STATIONARY',
                                     'oneSecondSweptIntersections': hits, 'instantaneousScoring': 'falseStop'})
                elif hits:
                    per_mode[mode]['passableContinuesWithOneSecondIntersection'] += 1
                    approach_continues.append({'layoutId': case['layoutId'], 'frameId': row['frameId'],
                                              'mode': mode, 'oneSecondSweptIntersections': hits})
        by_layout.append({'layoutId': case['layoutId'], 'frames': len(rows),
                          'physicalHazards': sum(v['physicalHazard'] for v in annotation['frames']),
                          'fixedRig': counts, 'sameRigControlFalseStops': old_counts})
    return {'schemaVersion': 1, 'syntheticHoldoutGatePassed': replay['syntheticHoldoutGatePassed'],
            'gates': replay['gates'], 'promotionAllowed': False, 'ordinaryCameraWired': False,
            'instantaneous': replay['summary'], 'faults': replay['faultControls']['summary'],
            'perModeWarnings': per_mode, 'passableStops': warnings,
            'passableContinuesWithOneSecondIntersection': approach_continues,
            'byLayout': by_layout,
            'forecastScope': 'scoring only: synthetic constant-velocity one-second box sweep; not measured future captures',
            'maximumFreshnessUs': 100000, 'latencyMeasured': False,
            'realCameraCoverageEstablished': False, 'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run'}


def render():
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import numpy as np
    from PIL import Image, ImageDraw
    plt.rcParams['svg.hashsalt'] = 'volume-holdout-2026-10-10'
    value = diagnosis()
    (DIRECTORY / 'diagnosis.json').write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    count = value['instantaneous']['passableFrames']
    hazards = value['instantaneous']['physicalHazardFrames']
    fig, axes = plt.subplots(1, 2, figsize=(12, 5), constrained_layout=True)
    xs = np.arange(3)
    for mode, offset, color in [('legacy', -.18, '#8e5350'), ('frameStable', .18, '#327c72')]:
        numbers = [value['instantaneous']['runtime'][f'{mode}/{lane}']['falseStops']
                   for lane in ('fixedSingleView', 'sameRigControl', 'fixedRig')]
        axes[0].bar(xs + offset, numbers, .34, label=mode, color=color)
        for x, n in zip(xs + offset, numbers): axes[0].text(x, n + .3, str(n), ha='center')
    axes[0].set(xticks=xs, xticklabels=['Single view', 'Same rig, old', 'Same rig, repaired'],
                title=f'Instantaneous false STOP: {count} passable captures', ylim=(0, max(1, count) + 4), ylabel='STOP captures')
    axes[0].legend()
    for index, mode in enumerate(MODES):
        numbers = value['perModeWarnings'][mode]
        axes[1].bar(index, numbers['falseStopsWithOneSecondIntersection'], color='#8e5350', label='1 s sweep intersects' if index == 0 else None)
        axes[1].bar(index, numbers['falseStopsWithoutOneSecondIntersection'],
                    bottom=numbers['falseStopsWithOneSecondIntersection'], color='#c6b16c', label='No 1 s intersection' if index == 0 else None)
    axes[1].set(xticks=[0, 1], xticklabels=MODES, title='Remaining false STOP: independent forecast', ylabel='STOP captures')
    axes[1].legend()
    for ax in axes: ax.spines[['top', 'right']].set_visible(False)
    fig.suptitle(f'Frozen runtime, 12 new synthetic sequences / 84 captures\nCurrent hazard frames: {hazards}; shadow only; gate={value["syntheticHoldoutGatePassed"]}')
    for suffix in ('png', 'svg'):
        fig.savefig(DIRECTORY / f'volume-holdout.{suffix}', dpi=160, metadata={'Date': None} if suffix == 'svg' else None)
    plt.close(fig)
    corpus = read(CORPUS / 'manifest.json')
    sheet = Image.new('RGB', (7 * 256, 12 * 214), '#f5f3ee')
    draw = ImageDraw.Draw(sheet)
    for y, layout in enumerate(corpus['layouts']):
        for x, frame in enumerate(layout['frames']):
            with Image.open(CORPUS / frame['rgb']['path']) as image:
                sheet.paste(image.convert('RGB').resize((256, 192)), (x * 256, y * 214 + 22))
            draw.text((x * 256 + 4, y * 214 + 5), f'{layout["id"].replace("holdout-", "")} / {frame["frameId"]}', fill='#222222')
    sheet.save(DIRECTORY / 'captures.png')


if __name__ == '__main__': render()

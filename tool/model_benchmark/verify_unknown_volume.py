"""Independently audit and render known synthetic unknown-volume cell maps."""
import argparse
from collections import Counter
import copy
import gzip
import hashlib
import itertools
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
OPTICAL = ROOT / 'test/fixtures/spatial_safety/blender-paired-visible-body-v1'
LABELS = {
    'observed': 'Подтверждено',
    'outsideFrustum': 'Вне поля зрения',
    'invalidPixel': 'Нет возврата',
    'missingPixelBounds': 'Нет границ глубины',
    'incompatiblePixelBounds': 'Противоречивые границы',
    'firstReturnIntersectsVolume': 'Недостаточная свободная граница',
    'floorHeightUncertain': 'Неопределённая высота пола',
    'blocked': 'Заблокированное сечение',
    'conflicting': 'Конфликт измерений',
}
COLORS = ['#d7ece7', '#dfb85e', '#cd7185', '#c78acb', '#bf4545',
          '#689bb2', '#8673b9', '#5e666e', '#ef7a37']
SKIPPED = {'blocked', 'conflicting'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def checked_source(relative):
    path = (ROOT / relative).resolve()
    require(path.is_relative_to(ROOT) and not Path(relative).is_absolute(), 'Escaped source path')
    return path


def bounds_for(m, kind, cell):
    ix, iy = cell[:2]
    lo_h, hi_h = (0., 0.) if kind == 'floor' else (
        m['heightEdgesM'][cell[2]], m['heightEdgesM'][cell[2] + 1])
    return [m['xEdgesM'][ix], m['xEdgesM'][ix + 1],
            m['forwardEdgesM'][iy], m['forwardEdgesM'][iy + 1], lo_h, hi_h]


def ray_interval(packet, b, x, y):
    ray = np.array([(x + .5 - packet['cx']) / packet['fx'],
                    (y + .5 - packet['cy']) / packet['fy'], 1.])
    direction = np.array(packet['cameraToWalkingRotation']).reshape(3, 3) @ ray
    origin = np.array(packet['cameraOriginM'])
    enter, leave = 0., float('inf')
    for axis in range(3):
        if direction[axis] == 0:
            if not b[2*axis] <= origin[axis] <= b[2*axis+1]:
                return None
        else:
            ts = [(b[2*axis+j] - origin[axis]) / direction[axis] for j in (0, 1)]
            enter, leave = max(enter, min(ts)), min(leave, max(ts))
            if enter > leave:
                return None
    return (enter, leave) if leave > 0 else None


def load_array(asset, dtype):
    path = checked_source(f'{OPTICAL.relative_to(ROOT).as_posix()}/{asset["path"]}')
    require(sha(path) == asset['sha256'], 'Changed optical payload')
    return np.frombuffer(gzip.decompress(path.read_bytes()), dtype=dtype)


def audit_frame(row, packet):
    m = row['map']
    require(m['replicaMatchesSource'] and not m['canAuthorizeMovement']
            and not m['canCertifyFreeSpace'], 'Map must have no movement authority')
    require(row['frameId'] == packet['frameId'] and row['fixedReplayAgeUs'] == 2000,
            'Capture or replay identity changed')
    require(m['nx'] == 6 and m['ny'] == 22 and m['nz'] == 13, 'Changed requested grid')
    for name, expected in [('xEdgesM', np.linspace(-.45, .45, 7)),
                           ('forwardEdgesM', np.linspace(.2, 3.5, 23)),
                           ('heightEdgesM', np.linspace(.05, 1.9, 14))]:
        require(np.allclose(m[name], expected, rtol=0, atol=1e-14), f'Changed {name}')
    require(len(m['sections']) == 22, 'Missing source sections')
    require(len(m['bodyCells']) == 1716 and len(m['floorCells']) == 132, 'Partial cell map')
    checked_cells = 0
    flagged = set()
    for kind in ('body', 'floor'):
        cells = m[f'{kind}Cells']
        width = 3 if kind == 'floor' else 4
        keys = [tuple(c[:width-1]) for c in cells]
        require(len(set(keys)) == len(cells), 'Duplicate map cell')
        expected_keys = set(itertools.product(range(6), range(22))) if kind == 'floor' else set(
            itertools.product(range(6), range(22), range(13)))
        require(set(keys) == expected_keys, 'Incomplete cell indices')
        statuses = [c[width-1] for c in cells]
        require(set(statuses) <= LABELS.keys(), 'Unmapped coverage status')
        actual_counts = Counter(statuses)
        require(all(m['counts'][kind][k] == actual_counts[k] for k in LABELS), 'Count mismatch')
        # Vectorized independent projection of all eight cell corners.
        b = np.array([bounds_for(m, kind, c) for c in cells])
        corners = np.stack([b[:, [x, y, h]]
                            for x in (0, 1) for y in (2, 3) for h in (4, 5)], axis=1)
        camera = ((corners - np.array(packet['cameraOriginM'])) @
                  np.array(packet['cameraToWalkingRotation']).reshape(3, 3))
        z = camera[:, :, 2]
        with np.errstate(divide='ignore', invalid='ignore'):
            u = packet['fx'] * camera[:, :, 0] / z + packet['cx']
            v = packet['fy'] * camera[:, :, 1] / z + packet['cy']
        outside = np.any((z <= .01) | (u < 0) | (u >= packet['width']) |
                         (v < 0) | (v >= packet['height']), axis=1)
        for i, cell in enumerate(cells):
            status = statuses[i]
            if status not in SKIPPED:
                require(bool(outside[i]) == (status == 'outsideFrustum'), 'Independent frustum mismatch')
            if cell[-1]:
                require(status not in SKIPPED | {'observed', 'outsideFrustum'}, 'Invalid witness target')
                flagged.add((kind, *keys[i]))
        require(sum(bool(c[-1]) for c in cells) == m['occlusionWitnessCells'][kind], 'Witness count mismatch')
        for iy, section in enumerate(m['sections']):
            observed = sum(c[1] == iy and c[width-1] == 'observed' for c in cells)
            fraction = observed / (6 if kind == 'floor' else 6*13)
            require(section[kind] == fraction, 'Section fraction mismatch')
        checked_cells += len(cells)
    body = m['counts']['body']
    require(m['certifiedBodyBoxes'] == body['observed'], 'Certified box mismatch')
    require(m['unknownBodyBoxes'] == sum(body[k] for k in LABELS if k not in SKIPPED | {'observed'}),
            'Unknown box mismatch')
    witnesses = m['occlusionWitnesses']
    witness_keys = [(w['kind'], *w['cell']) for w in witnesses]
    require(len(set(witness_keys)) == len(witnesses) and set(witness_keys) == flagged,
            'Missing or duplicate positive witness records')
    if witnesses:
        arrays = {k: load_array(packet[k], 'u1' if k == 'validity' else '<f4')
                  for k in ('depth', 'validity', 'freeZLower', 'surfaceZUpper')}
        for w in witnesses:
            x, y = w['pixel']
            require(0 <= x < packet['width'] and 0 <= y < packet['height'], 'Witness outside image')
            i = y * packet['width'] + x
            lo, hi, distance = [float(arrays[k][i]) for k in ('freeZLower', 'surfaceZUpper', 'depth')]
            require(arrays['validity'][i] == 1 and np.isfinite([lo, hi, distance]).all()
                    and 0 <= lo <= hi and distance > 0, 'Invalid witness return')
            expected_bounds = bounds_for(m, w['kind'], w['cell'])
            require(w['cellBoundsM'] == expected_bounds, 'Wrong witness cell')
            interval = ray_interval(packet, expected_bounds, x, y)
            require(interval is not None and np.allclose(interval, [w['rayEntryZ'], w['rayExitZ']],
                                                         rtol=0, atol=1e-12), 'Ray does not intersect claimed cell')
            # This fixture stores exact synthetic intervals with errorM=0.
            require(w['errorM'] == 0 and w['firstReturnUpperZ'] == hi
                    and hi < interval[0] and w['clearanceAuthority'] is False,
                    'No strict first-return occlusion witness')
            norm = np.sqrt(1 + ((x+.5-packet['cx'])/packet['fx'])**2 +
                           ((y+.5-packet['cy'])/packet['fy'])**2)
            require(lo <= distance / norm + 1e-5 and hi >= distance / norm - 1e-5,
                    'Inconsistent pixel bounds')
    return checked_cells, len(witnesses)


def verify(directory):
    experiment = read(directory / 'experiment.json')
    require(experiment['maximumAgeUs'] == 100000 and experiment['frames'] == 132,
            'Changed freshness or corpus')
    require(all(experiment[k] is False for k in ('promotionAllowed', 'ordinaryCameraWired',
                                                'falseStopReductionEstablished', 'newHoldout')),
            'Unsupported authority claim')
    require(sha(OPTICAL / 'manifest.json') == experiment['opticalManifestSha256'], 'Changed optical identity')
    for path, expected in experiment['sourceFingerprint'].items():
        require(sha(checked_source(path)) == expected, f'Changed source {path}')
    manifest = read(OPTICAL / 'manifest.json')
    packets = {(s['sceneId'], p['frameId']): p for s in manifest['sequences'] for p in s['single']}
    rows = [json.loads(line) for line in (directory / 'maps.jsonl').read_text(encoding='utf-8').splitlines()]
    require(len(rows) == 132 and {(r['sceneId'], r['frameId']) for r in rows} == packets.keys(),
            'Missing or duplicate frame maps')
    cells, witnesses = 0, 0
    for row in rows:
        n, w = audit_frame(row, packets[row['sceneId'], row['frameId']])
        cells += n
        witnesses += w
    # Reject altered diagnostics in memory without rewriting any input artifact.
    mutation_checks = 0
    row = next(r for r in rows if any(c[3] == 'outsideFrustum' for c in r['map']['bodyCells']))
    altered = copy.deepcopy(row)
    cell = next(c for c in altered['map']['bodyCells'] if c[3] == 'outsideFrustum')
    cell[3] = 'observed'
    # Keep counters self-consistent so the independent corner projection,
    # rather than a superficial total, must reject the invented observation.
    altered['map']['counts']['body']['outsideFrustum'] -= 1
    altered['map']['counts']['body']['observed'] += 1
    altered['map']['certifiedBodyBoxes'] += 1
    altered['map']['unknownBodyBoxes'] -= 1
    mutants = [altered]
    altered = copy.deepcopy(row)
    altered['map']['canAuthorizeMovement'] = True
    mutants.append(altered)
    if any(r['map']['occlusionWitnesses'] for r in rows):
        witnessed = next(r for r in rows if r['map']['occlusionWitnesses'])
        altered = copy.deepcopy(witnessed)
        altered['map']['occlusionWitnesses'][0]['firstReturnUpperZ'] = 1000
        mutants.append(altered)
    for altered in mutants:
        try:
            audit_frame(altered, packets[altered['sceneId'], altered['frameId']])
        except ValueError:
            mutation_checks += 1
        else:
            raise ValueError('Tampered diagnostic was accepted')
    def aggregate(selected):
        result = {}
        for kind in ('body', 'floor'):
            counts = Counter()
            for r in selected:
                counts.update(r['map']['counts'][kind])
            unknown = sum(v for k, v in counts.items() if k not in SKIPPED | {'observed'})
            result[kind] = {'counts': dict(counts), 'unknownCells': unknown,
                            'outsideFovShareOfUnknown': counts['outsideFrustum']/unknown if unknown else None,
                            'occlusionWitnessCells': sum(r['map']['occlusionWitnessCells'][kind] for r in selected)}
        result['runtimeOutcomes'] = dict(Counter(r['runtime']['outcome'] for r in selected))
        return result
    scenes = []
    for scene in dict.fromkeys(r['sceneId'] for r in rows):
        frames = [r for r in rows if r['sceneId'] == scene]
        outcome = Counter(r['runtime']['outcome'] for r in frames)
        stats = {}
        for kind in ('body', 'floor'):
            counts = Counter()
            for r in frames:
                counts.update(r['map']['counts'][kind])
            stats[kind] = {'counts': dict(counts),
                           'unknownCells': sum(v for k, v in counts.items() if k not in SKIPPED | {'observed'}),
                           'occlusionWitnessCells': sum(r['map']['occlusionWitnessCells'][kind] for r in frames)}
        scenes.append({'sceneId': scene, 'frames': len(frames), 'runtimeOutcomes': dict(outcome), **stats})
    summary = {
        'schemaVersion': 1, 'independentChecksPassed': True,
        'scope': experiment['scope'], 'frames': len(rows), 'independentCellProjectionChecks': cells,
        'independentOcclusionWitnessChecks': witnesses, 'tamperedMapsRejected': mutation_checks,
        'runtimeDecisionsCompared': experiment['runtimeDecisionsCompared'],
        'sourceFingerprintCount': len(experiment['sourceFingerprint']),
        'promotionAllowed': False, 'ordinaryCameraWired': False,
        'falseStopReductionEstablished': False, 'captureToDecisionMs': None,
        'namedDeviceRuntime': 'not_run', 'controlledWalking': 'not_run',
        'mapsSha256': sha(directory / 'maps.jsonl'), 'experimentSha256': sha(directory / 'experiment.json'),
        'verifierSha256': sha(__file__), 'scenes': scenes,
        'passableSceneAggregate': aggregate([r for r in rows if r['scoringOnly']['referencePassable'] is True]),
        'hazardSceneAggregate': aggregate([r for r in rows if r['scoringOnly']['physicalHazard'] is True]),
    }
    return rows, summary


def report_markdown(summary):
    free = summary['passableSceneAggregate']
    text = ['# Карта неизвестного объёма', '',
            '132 известных синтетических кадра. Полная сетка ячеек сверена с неизменённым производителем.',
            'Решения повторены текущим runtime и совпали с предыдущим диагностическим отчётом.', '',
            f"На свободных сценах {free['body']['counts']['outsideFrustum']} из "
            f"{free['body']['unknownCells']} неизвестных ячеек тела "
            f"({100*free['body']['outsideFovShareOfUnknown']:.1f}%) выходят из поля зрения.",
            'Эта доля относится к ячейкам заданного синтетического стенда, а не к устройствам или реальным пользователям.', '',
            '| Сцена | Неизвестные ячейки тела | Из них вне поля зрения | С лучевым свидетельством перекрытия | Неизвестные участки пола |',
            '|---|---:|---:|---:|---:|']
    for s in summary['scenes']:
        b, f = s['body'], s['floor']
        text.append(f"| {s['sceneId']} | {b['unknownCells']} | {b['counts'].get('outsideFrustum', 0)} | "
                    f"{b['occlusionWitnessCells']} | {f['unknownCells']} |")
    text += ['', 'Числа относятся к ячейкам всех 11 кадров каждой сцены, а не к независимым физическим наблюдениям.',
             'Заблокированные/конфликтующие сечения учитываются отдельно и не объявляются неизвестными свободными ячейками.', '',
             '## Значение категорий', '',
             'Код отказа — первый неуспешный уточнённый участок в существующем проверяющем модуле. '
             'Это полная карта ячеек, но не исчерпывающий список физических причин каждой ячейки.', '',
             'Отметка перекрытия требует допустимого первого возврата строго перед входом луча в ячейку. '
             'Она относится к одному лучу через ячейку; не доказывает перекрытие всей ячейки. '
             'Отсутствие такой отметки не доказывает отсутствие окклюзии. Неопределённые границы остаются неопределёнными.', '',
             f"Независимо проверены {summary['independentCellProjectionChecks']} проекций ячеек и "
             f"{summary['independentOcclusionWitnessChecks']} лучевых свидетельств; "
             f"отклонены {summary['tamperedMapsRejected']} испорченные копии отчётов.", '',
             'Все 132 решения runtime сверены. Shadow и TTL 100 мс сохранены. '
             'Снижение ложных STOP, новый holdout, точность iPhone/Android и задержка устройства не установлены.', '',
             'Полные данные: `maps.jsonl`, сводка: `summary.json`, изображения: `overview.png`, `path-comparison.png`.']
    return '\n'.join(text) + '\n'


def render(directory, rows, summary):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.colors import ListedColormap
    from matplotlib.patches import Patch

    keys = list(LABELS)
    palette = dict(zip(keys, COLORS))
    unknown = [k for k in keys if k not in SKIPPED | {'observed'}]
    fig, axes = plt.subplots(1, 2, figsize=(14, 7.5), layout='constrained')
    for ax, kind, title in zip(axes, ('body', 'floor'), ('Объём тела', 'Пол')):
        left = np.zeros(len(summary['scenes']))
        for key in unknown:
            values = np.array([100 * s[kind]['counts'].get(key, 0) / max(1, s[kind]['unknownCells'])
                               for s in summary['scenes']])
            ax.barh(range(len(left)), values, left=left, color=palette[key], label=LABELS[key])
            left += values
        ax.set_yticks(range(len(left)), [s['sceneId'] for s in summary['scenes']])
        ax.invert_yaxis()
        ax.set_xlim(0, 100)
        ax.set_xlabel('Доля среди неизвестных ячеек, %')
        ax.set_title(title)
    handles = [Patch(facecolor=palette[k], label=LABELS[k]) for k in unknown]
    fig.legend(handles=handles, loc='outside lower center', ncol=3, fontsize=8)
    fig.suptitle('Причины нехватки покрытия: 12 известных синтетических сцен\n'
                 '11 кадров на сцену; геометрическая диагностика без изменения решений STOP', fontsize=12)
    fig.savefig(directory / 'overview.png', dpi=160)
    fig.savefig(directory / 'overview.svg')
    plt.close(fig)

    fig, axes = plt.subplots(2, 2, figsize=(13, 7.8), layout='constrained')
    for col, scene in enumerate(('path-clear', 'path-box')):
        row = max((r for r in rows if r['sceneId'] == scene), key=lambda r: r['frameId'])
        m = row['map']
        for i, kind in enumerate(('body', 'floor')):
            shape = (m['nz'], m['ny']) if kind == 'body' else (m['nx'], m['ny'])
            grid = np.zeros(shape, dtype=int)
            crosses = []
            for cell in m[f'{kind}Cells']:
                if kind == 'body':
                    ix, iy, iz, status, witnessed = cell
                    if ix != m['nx']//2:
                        continue
                    horizontal, vertical = m['forwardEdgesM'], m['heightEdgesM']
                    j = iz
                else:
                    ix, iy, status, witnessed = cell
                    horizontal, vertical = m['forwardEdgesM'], m['xEdgesM']
                    j = ix
                grid[j, iy] = keys.index(status)
                if witnessed:
                    crosses.append(((horizontal[iy]+horizontal[iy+1])/2,
                                    (vertical[j]+vertical[j+1])/2))
            ax = axes[i, col]
            ax.imshow(grid, origin='lower', aspect='auto', interpolation='nearest',
                      extent=[horizontal[0], horizontal[-1], vertical[0], vertical[-1]],
                      cmap=ListedColormap(COLORS), vmin=-.5, vmax=len(keys)-.5)
            if crosses:
                ax.scatter(*np.array(crosses).T, marker='x', c='black', s=13, linewidths=.7)
            ax.set_xlabel('Вперёд, м')
            ax.set_ylabel('Высота, м' if kind == 'body' else 'Поперёк прохода, м')
            ax.set_title(f"{scene}, кадр {row['frameId']}: " + ('срез тела x = 0–0,15 м' if kind == 'body' else 'весь пол'))
    handles = [Patch(facecolor=palette[k], label=LABELS[k]) for k in keys
               if any(s[kind]['counts'].get(k, 0) for s in summary['scenes'] for kind in ('body', 'floor'))]
    handles.append(plt.Line2D([], [], marker='x', color='black', linestyle='', label='Лучевой свидетель перекрытия'))
    fig.legend(handles=handles, loc='outside lower center', ncol=3, fontsize=8)
    fig.suptitle('Полные ячейки: границы поля зрения и допустимые возвраты\n'
                 'Синтетический исследовательский источник; карта не разрешает движение', fontsize=12)
    fig.savefig(directory / 'path-comparison.png', dpi=160)
    fig.savefig(directory / 'path-comparison.svg')
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--render', action='store_true')
    args = parser.parse_args()
    for name in ('summary.json', 'report.md', 'overview.png', 'overview.svg', 'path-comparison.png', 'path-comparison.svg'):
        require(not (args.directory / name).exists(), f'Preserve existing artifact: {name}')
    rows, summary = verify(args.directory)
    if args.render:
        render(args.directory, rows, summary)
    (args.directory / 'summary.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
    (args.directory / 'report.md').write_text(report_markdown(summary), encoding='utf-8')
    print(json.dumps({k: v for k, v in summary.items() if k != 'scenes'}, indent=2))


if __name__ == '__main__':
    main()

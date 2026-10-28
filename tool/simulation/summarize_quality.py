"""Describe paired observations without fitting a threshold or claiming accuracy."""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def summarize(root, report):
    result = json.loads((root/'baseline.json').read_text(encoding='utf-8'))
    if result['corpusManifestSha256'] != sha(root/'manifest.json'):
        raise ValueError('Baseline belongs to a different corpus')
    manifest = json.loads((root/'manifest.json').read_text())
    if result['protocolSha256'] != sha(root/'protocol.json') or manifest['promotionAllowed'] is not False:
        raise ValueError('Foreign protocol or invalid promotion policy')
    if len(result['images']) != len(manifest['images']):
        raise ValueError('Incomplete baseline')
    reference = {row['id']: row for row in manifest['images']}
    if len(reference) != len(manifest['images']) or len({r['id'] for r in result['images']}) != len(reference):
        raise ValueError('Duplicate image identities')
    for row in result['images']:
        source = reference[row['id']]
        for name, value in source.items():
            if row[name] != value:
                raise ValueError('Baseline metadata differs from the manifest')
        path = (root/source['asset']['path']).resolve()
        if not path.is_relative_to(root.resolve()) or sha(path) != source['asset']['sha256']:
            raise ValueError('Diagnostic input bytes changed')
    rows = result['images']
    groups = defaultdict(list)
    base = defaultdict(dict)
    for row in rows:
        groups[(row['split'], row['condition'])].append(row)
        if row['split'] != 'diagnostic':
            base[row['baseId']][row['condition']] = row
    paired = []
    for identifier, conditions in base.items():
        blurred, noisy = conditions['defocus-5'], conditions['defocus-5-noise-8']
        paired.append({'baseId': identifier, 'split': blurred['split'],
            'blurRejected': blurred['rejected'], 'noisyBlurRejected': noisy['rejected'],
            'blurScore': blurred['score'], 'noisyBlurScore': noisy['score']})
    phase_groups = defaultdict(list)
    for row in rows:
        if row['family'] == 'periodic-checker':
            phase_groups[row['baseId']].append(row)
    phase = [{'baseId': identifier, 'phases': len(items),
        'accepted': sum(not r['rejected'] for r in items),
        'denseAccepted': sum(not r['denseRejected'] for r in items),
        'scoreMin': min(r['score'] for r in items), 'scoreMax': max(r['score'] for r in items),
        'denseScoreMin': min(r['denseScore'] for r in items),
        'denseScoreMax': max(r['denseScore'] for r in items)} for identifier, items in phase_groups.items()]
    sharp_groups = defaultdict(list)
    for row in rows:
        if row['split'] != 'diagnostic' and row['condition'] == 'sharp':
            sharp_groups[(row['split'], row['family'], row['contrast'], row['width'], row['height'])].append(row)
    sharp_controls = [{'split': split, 'family': family, 'contrast': contrast, 'width': width, 'height': height,
        'images': len(items), 'rejected': sum(r['rejected'] for r in items)}
        for (split, family, contrast, width, height), items in sharp_groups.items()]
    condition_rows = [{'split': split, 'condition': condition, 'images': len(items),
        'accepted': sum(not r['rejected'] for r in items), 'rejected': sum(r['rejected'] for r in items),
        'samplingDisagreements': sum(r['rejected'] != r['denseRejected'] for r in items)}
        for (split, condition), items in groups.items() if split != 'diagnostic']
    summary = {'schemaVersion': 1, 'scope': result['scope'], 'promotionAllowed': False,
        'corpusManifestSha256': result['corpusManifestSha256'], 'protocolSha256': result['protocolSha256'],
        'productionSourceSha256': result['productionSourceSha256'], 'threshold': result['threshold'],
        'images': len(rows), 'conditions': condition_rows, 'pairs': paired, 'phaseProbes': phase,
        'sharpControlsByFamilyContrastAndSize': sharp_controls,
        'noiseMaskingBlurPairs': sum(p['blurRejected'] and not p['noisyBlurRejected'] for p in paired),
        'samplingDecisionDisagreements': sum(r['rejected'] != r['denseRejected'] for r in rows),
        'physicalDeviceValidation': 'not_run', 'modelAccuracy': 'not_measured'}
    initial_path = root/'baseline-initial.json'
    if initial_path.exists():
        initial = json.loads(initial_path.read_text())
        if initial['images'] != rows or initial['corpusManifestSha256'] != result['corpusManifestSha256']:
            raise ValueError('Initial and rerun baseline values differ')
        summary['initialBaselineSha256'] = sha(initial_path)
        summary['initialAndRerunImageResultsIdentical'] = True
    (root/'summary.json').write_text(json.dumps(summary, indent=2)+'\n', encoding='utf-8')
    lines = ['# Bagdar: независимая проверка фильтра резкости', '',
        '27 октября 2026 года. Протокол: `docs/image-quality-protocol-2026-10-27.md`.', '',
        f"Проверено **{len(rows)}** новых диагностических изображений. "
        f"Вызван неизменённый `BlurDetector` с порогом **{result['threshold']}** и шагом **8**. "
        'Порог не подбирался; настройки приложения не изменялись.', '',
        'Изображения — контролируемые двумерные схемы и тестовые поля. '
        'Это независимая проверка механизма фильтра, без оценки узнаваемости препятствий или точности навигации.', '',
        '## Решения по условиям', '',
        'В таблице указано число изображений, **принятых фильтром**, от общего числа. '
        'Это разрешение дальнейшей обработки, а не подтверждение качества или безопасности.', '',
        '| Условие | Development | Holdout |', '|---|---:|---:|']
    protocol = json.loads((root/'protocol.json').read_text())
    for condition in protocol['conditions']:
        counts = []
        for split in ('development', 'holdout'):
            items = groups[(split, condition['id'])]
            counts.append(f"{sum(not r['rejected'] for r in items)}/{len(items)}")
        lines.append(f"| {condition['id']} | {' | '.join(counts)} |")
    lines.extend(['', '## Парный эффект шума', '',
        f"В **{summary['noiseMaskingBlurPairs']}/{len(paired)}** пар одна и та же размытая картинка "
        'была отклонена без шума и принята после добавления шума sigma 8. '
        'В этих парах оптические детали не восстанавливались; изменялся последний этап — добавление шума.', ''])
    for split in ('development', 'holdout'):
        items = [p for p in paired if p['split'] == split]
        lines.append(f"- {split}: {sum(p['blurRejected'] and not p['noisyBlurRejected'] for p in items)}/{len(items)} пар.")
    lines.extend(['', '## Резкие контроли по семействам', '',
        '| Семейство | Split | Отклонено |', '|---|---|---:|'])
    for split, selection in protocol['splits'].items():
        for family in selection['families']:
            items = [r for r in rows if r['family'] == family and r['condition'] == 'sharp']
            lines.append(f"| {family} | {split} | {sum(r['rejected'] for r in items)}/{len(items)} |")
    lines.extend(['', 'Разбивка по контрасту и размеру сохранена в `summary.json`. '
        'Отклонение резкого малотекстурного контроля не означает ошибку навигации: '
        'даже резкий кадр может не содержать достаточной информации.', ''])
    lines.extend(['', '## Зависимость от положения сетки', '',
        'Резкий периодический рисунок смещён по X/Y с сохранением размера клетки. '
        'В каждой группе 64 фазы. Полный перебор пикселей — диагностическое сравнение с тем же порогом.', '',
        '| Группа | Принято, шаг 8 | Принято, шаг 1 | Диапазон оценки, шаг 8 |', '|---|---:|---:|---:|'])
    for item in phase:
        lines.append(f"| {item['baseId']} | {item['accepted']}/{item['phases']} | {item['denseAccepted']}/{item['phases']} | "
                     f"{item['scoreMin']:.2f}–{item['scoreMax']:.2f} |")
    lines.extend(['', '## Отклик ровного поля на шум', '',
        '| Размер | Sigma шума | Оценка | Принято |', '|---|---:|---:|---|'])
    for row in rows:
        if row['family'] == 'flat':
            lines.append(f"| {row['width']}×{row['height']} | {row['transform']['noiseSigmaLuma']} | {row['score']:.2f} | "
                         f"{'да' if not row['rejected'] else 'нет'} |")
    lines.extend(['', '## Практический вывод', '',
        'Одного порога этого показателя недостаточно для разделения текстуры, размытия и шума. '
        'Простое снижение порога или замена шага 8 на 1 не устанавливает решение всех трёх задач. '
        'Резкие малотекстурные изображения могут оставаться неинформативными; '
        'их нельзя автоматически объявить качественными для навигации.', '',
        'Следующее изменение следует проверять как отдельную кандидатную оценку с явной неопределённостью: '
        'отделить достоверное размытие от отсутствия текстуры и от шума. '
        'Для любых подобранных параметров нужна новая независимая выборка. '
        'Пока production-фильтр и решения безопасности сохраняются.', '',
        '## Воспроизводимость', '',
        f"- Манифест входов SHA-256: `{result['corpusManifestSha256']}`.",
        f"- Протокол SHA-256: `{result['protocolSha256']}`.",
        f"- Производственный исходник SHA-256: `{result['productionSourceSha256']}`.",
        f"- Артефакты: `{root.as_posix()}/` — `baseline.json`, `summary.json`, `manifest.json`, `protocol.json`, `examples.jpg` и проверенные байты яркости.",
        '- Семейства и seed development/holdout не пересекаются. Это не доказывает репрезентативность реального мира.',
        '- Реальный телефон, TalkBack, ходьба и точность моделей этим тестом не проверялись. `promotionAllowed=false`.', ''])
    if initial_path.exists():
        lines.extend(['Первоначальный `baseline-initial.json` и исходник оценщика '
            '`scorer-initial.dart.txt` сохранены. После исправления импорта и стиля повторная '
            'оценка дала те же 968 результатов. Android-проверка связана с SHA-256 '
            'первоначального baseline; обе версии доступны для проверки.', ''])
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({k: v for k, v in summary.items() if k not in ('conditions', 'pairs', 'phaseProbes', 'sharpControlsByFamilyContrastAndSize')}, indent=2))
    return summary


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('corpus', type=Path)
    p.add_argument('--report', type=Path, required=True)
    a = p.parse_args()
    summarize(a.corpus, a.report)

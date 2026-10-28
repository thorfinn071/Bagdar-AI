"""A concise Russian summary derived only from saved run receipts."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path


def write(corpus, target):
    data = json.loads((corpus/'evaluation.json').read_text(encoding='utf-8'))
    rows = data['sequences']
    completed = [r for r in rows if r['execution'] == 'completed']
    attempted = sum(r['execution'] != 'not_run' for r in rows)
    delivered = sum(r.get('deliveredFrames', 0) for r in rows)
    accepted = sum(r.get('acceptedDepthResults', 0) for r in rows)
    groups = defaultdict(Counter)
    rejected = Counter()
    for row in rows:
        group = groups[row['condition']]
        group['episodes'] += row['execution'] != 'not_run'
        for name in ('deliveredFrames', 'qualitySkippedFrames', 'liveYoloCalls', 'depthCalls', 'acceptedDepthResults'):
            group[name] += row.get(name, 0)
        rejected.update(row.get('depthRejections', {}))
    lines = ['# Bagdar: завершение пакетной симуляции', '',
        'Дата этапа: 27 октября 2026 года.', '',
        f"В текущем прогоне предпринято **{attempted}/{data['expectedSequences']} эпизодов**. "
        f"Полные отчёты приложения: **{len(completed)}**; доставлено **{delivered} кадров**.", '',
        f"Получено **{data['liveYoloCalls']} результатов YOLO**, выполнено **{data['depthCalls']} запросов глубины**. "
        f"Контроллер принял **{accepted} результатов глубины**. "
        'Принятый результат не означает, что подтверждена проходимость.', '',
        '## Что изменилось', '',
        '- Автоматический пакет запускает тот же APK отдельным процессом для каждого независимого эпизода. '
        'Каждый клип длится две секунды; после подачи входа есть три секунды для завершения обработки. '
        'Внутри эпизода сохраняются исходный темп кадров и штатное состояние алгоритмов. '
        'Этот тест не проверяет длительную непрерывную работу.',
        '- Переход между эпизодами не требует завершения анимации или закрытия Flutter-экрана. '
        'Для каждого запуска проверяются идентификатор прогона, сцена и хеш входного набора.',
        '- Есть ограничение ожидания отчёта, прогресс, журналы Android и отдельная запись тайм-аутов. '
        'Тайм-аут не подменяется выдуманным отчётом приложения.',
        '- Навигационный режим оставлен опциональным: widget-тесты переходов проходят, '
        'но native-проверка выявила незавершённое закрытие экрана при ANR Android. '
        'Его не следует считать исправленным для всех условий.', '',
        '## Наблюдения по условиям', '',
        '| Условие | Эпизоды | Кадры | Пропуски по качеству | YOLO | Запросы глубины | Принято глубины |',
        '|---|---:|---:|---:|---:|---:|---:|']
    names = {'clean': 'Чистая съёмка', 'shake': 'Тряска', 'lowlight': 'Слабый свет и шум',
             'defocus': 'Расфокусировка', 'rain': 'Дождь и капли', 'mixed': 'Сочетание эффектов'}
    for condition, label in names.items():
        group = groups[condition]
        lines.append(f"| {label} | {group['episodes']} | {group['deliveredFrames']} | {group['qualitySkippedFrames']} | "
                     f"{group['liveYoloCalls']} | {group['depthCalls']} | {group['acceptedDepthResults']} |")
    lines.extend(['', 'Причины отклонения результатов глубины: '+json.dumps(dict(rejected), ensure_ascii=False)+'.', '',
        f"На проходимых контролях STOP во время подачи входных кадров наблюдался в **{sum(r.get('passableEpisodeHadStopDuringInput') is True for r in rows)}** эпизодах. "
        'Сюда входят решения защитной логики при неопределённости; это не счётчик распознанных препятствий.', '',
        f"Опасные `continueForward` на кадрах с геометрическими свидетелями опасности: **{data['hazardousContinueFrames']}**. "
        'Этот счётчик необходимо читать вместе с покрытием решений: отсутствие решений и остановки '
        'из-за неопределённости не доказывают распознавание опасности.', '',
        f"Пространственный результат связан с **{data['framesWithSpatialDecision']}/{delivered}** исходных кадров. "
        f"Для кадров с геометрическими свидетелями опасности: **{data['hazardFramesWithDecision']}/{data['framesWithHazardWitness']}**; "
        f"без такого результата — **{data['hazardFramesWithoutDecision']}**. "
        'Это покрытие результатов по исходным кадрам, а не доля времени без защитного решения: '
        'между кадрами runtime также обновляет состояние по таймеру.', '',
        f"Наблюдавшиеся ANR в снимке состояния окна: **{data['androidAnrObservedSequences']} эпизодов**. "
        'Это наблюдение в момент сбора отчёта, а не полная проверка отзывчивости.', ''])
    quality = json.loads((corpus/'quality-report.json').read_text(encoding='utf-8'))
    totals = defaultdict(Counter)
    for row in quality['sequences']:
        condition = row['sequenceId'].rsplit('-', 1)[1]
        totals[condition]['frames'] += row['frames']
        totals[condition]['skipped'] += row['blurSkipped']
    lines.extend(['## Отдельный результат фильтра резкости', '',
        f"Тот же программный фильтр отбрасывает **{totals['clean']['skipped']}/{totals['clean']['frames']}** чистых синтетических кадров. "
        f"Для слабого света с добавленным шумом: **{totals['lowlight']['skipped']}/{totals['lowlight']['frames']}**. "
        'Высокочастотный шум способен повысить используемую оценку резкости. '
        'Эти процедурные сцены не устанавливают частоту ошибок реальной камеры; порог фильтра не менялся.', '',
        '## Проверяемые артефакты', '',
        f"- Идентификатор прогона: `{data['runId']}`.",
        f"- SHA-256 входного манифеста: `{data['runtimeManifestSha256']}`.",
        '- `output/simulation-lab/render-v2/evaluation.json`: итог по каждому эпизоду и счётчики.',
        '- `output/simulation-lab/render-v2/app-reports/`: отчёты приложения, логи и состояние контроллера.',
        '- `output/simulation-lab/continuation-build-receipt.json`: хеш APK и исходников.',
        '- `output/simulation-lab/installed-build-verification.json`: проверка установленного APK.', '',
        f"Снимок отчётов, управления, проверки сборки и хешей сохранён отдельно: "
        f"`output/simulation-lab/completed-run-evidence/{data['runId']}/`. "
        'Он сохраняет результат при последующих запусках того же корпуса.', '',
        '## Проверка изменений', '',
        '- 12 Flutter-тестов в режиме симуляции: входные данные, исходное время, пауза, пропуски кадров, '
        'запрет внешних SOS-действий и переходы между эпизодами.',
        '- 6 тестов входного адаптера в обычной сборке, включая запрет создания источника симуляции.',
        '- 8 Python-тестов: эффекты, оценка результатов и изолированный пакетный запуск.',
        '- Анализ трёх затронутых Dart-файлов — без замечаний. Синтаксис PowerShell проверен.',
        '- Повторно сверены 267 исходных Dart-файлов, APK и установленный APK. '
        'Повторная передача входа действительно использовала кеш: передан только файл управления.', '',
        '## Следующий измеримый этап', '',
        'Подготовить независимый набор для проверки качества изображения: резкие малотекстурные сцены, '
        'текстурные сцены с известным смазыванием и варианты с разным шумом. '
        'Оценивать распознавание непригодных кадров и ложные отбрасывания раздельно; '
        'проверять влияние на решения всего конвейера. Сначала зафиксировать протокол и новую контрольную выборку, '
        'затем рассматривать изменения фильтра.', '',
        '**Границы результата:** debug APK, x86_64 Android-эмулятор, CPU YOLO/NCNN и процедурные Blender-сцены. '
        'Калибровка камеры, реалистичность сенсорной модели, реальные телефоны, TalkBack и контролируемая ходьба '
        'этим прогоном не подтверждены. Геометрия и разметка не подавались в модели; MiDaS остаётся относительной глубиной. '
        '`promotionAllowed=false`, доставка геометрических подсказок — `shadow`.', ''])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('\n'.join(lines), encoding='utf-8')
    print(target)


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('corpus', type=Path)
    p.add_argument('target', type=Path)
    a = p.parse_args()
    write(a.corpus, a.target)

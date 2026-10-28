# Наблюдаемое пространство для тела — 2026-10-04

Этот этап проверяет две причины ложных остановок отдельно: ошибочные
компоненты пола и отсутствие полного наблюдения пространства для тела.
Веса MiDaS, 132 исходных RGB, их raw NCNN и прежняя confidence-authority
политика сохранены. Новый источник — независимая точная синтетическая
metric depth, а не превращение относительной MiDaS в метры.

## Что выполнено

Экспортированы 252 optical packet: 132 исходные позы и 120 видов отдельных
неподвижных обзоров на последнем состоянии сцен. Каждый packet содержит
range, conservative whole-pixel нижнюю/верхнюю границы первой видимой
поверхности, validity, intrinsics и pose. Meshes видит только renderer;
производитель evidence не получает semantic masks, object names или labels.
Замороженные состояния обзора не являются временными записями движущихся сцен.

Весь новый range сравнен с прежним depth PGM на 132 исходных позах:
максимальное различие **0,000506 м**, в пределах исходного округления до
миллиметров. Optical packet admission прошёл для всех 252 пакетов.
Исходные source/output freezes не перезаписаны.

Для выполнимого времени выгрузки добавлен отдельный renderer с теми же
whole-pixel bounds. Минимум конкурирующих поверхностей вычисляется через
две наименьшие глубины по отдельным records, включая ties. Сравнение
range/lower/upper/validity с frozen renderer прошло **побайтово** на кадрах
пола со швами и детальной фигуры человека. Это ускорение генерации тестовых
данных; скорость нейросети или приложения из него не следует.

## Почему исходного кадра недостаточно

Запрошенный объём: ширина 0,9 м, высота 1,85 м, forward 0,2–3,5 м;
допуск rise/drop пола — 0,05 м. Camera source учитывает верхнюю границу тела
с допуском rise и начинает body cells выше 0,05 м.

Камера находится на высоте 1,42 м, наклонена вниз на 12°; вертикальное поле
зрения по intrinsics — около 54,88°. Даже без перекрытий оно охватывает:

| Вперёд от камеры | Высоты в центральном вертикальном сечении |
| --- | --- |
| 0,2 м | 1,255–1,475 м |
| 0,5 м | 1,009–1,558 м |
| 1,0 м | 0,597–1,696 м |
| 2,0 м | −0,225–1,972 м |

Это только геометрическое поле зрения; оно не доказывает отсутствие
перекрытий. В ближнем объёме часть пола и headroom находится вне кадра.
Поэтому исключение напольного компонента не означает, что весь проход свободен.

## Проверки

Положительный контроль использует существующий camera-visible covered-wide
обзор с полным metric evidence и новым запросом высоты 1,85 м. Он проходит;
single-view, потеря upper bounds пола, дыры depth и relative units
отклоняются: **5/5 тестов прошли**. Окно этого контроля диагностическое;
current runtime freshness из него не меняется.

Для 12 новых static snapshots отдельно оцениваются геометрическая
наблюдаемость при diagnostic scan policy и строгая свежесть 100 мс.
Обзор длится 2 секунды в искусственных часах; строгая policy должна
отклонить earliest evidence как stale, даже при полном geometric coverage.
Геометрический и временной допуски проверяются независимо.

## Результат на тех же кадрах

| Метрика | MiDaS control | MiDaS + independent visible metric single |
| --- | ---: | ---: |
| Hazard `continueForward` | 0 | 0 |
| Hazard кадры со `stopNow` | 66/66 | 66/66 |
| Опасные последовательности с остановкой вовремя | 6/6 | 6/6 |
| False IMMINENT на проходимых кадрах движения | 0 | 0 |
| Остановки на проходимых кадрах движения | **55/55** | **55/55** |
| Остановки в неподвижном безопасном camera-pan | 11/11 | 11/11 |
| Применение полного passage proof | 0 | 0 |

«Вовремя» здесь означает объявленное окно 300 мс после появления опасности
в фиксированных replay-часах. Это функциональная проверка решения;
реальное время обработки и доставки в этой метрике не измеряется.

С независимой глубиной выполнено **265 сопоставлений tracks на кадрах**:
50 outside, 28 intersects, 187 unknown. Из 50 outside у **8** вся bounded
surface envelope лежит в допустимой полосе пола. Это повторные наблюдения
компонентов, а не 50 уникальных объектов. Motion/semantic priority сохранена
в 87 случаях, history/misses — в 51, неопределённые surface bounds — в 49.
Удаление отдельных ложных компонентов не снимает остановку при unknown body.

Все 66 опасных single-frame metric observations дали `blocked`; все
66 проходимых/безопасных observations остались `unavailable`. Static
snapshots также не дали полного clearance: 6 hazard snapshots blocked,
6 безопасных snapshots unavailable. На большинстве безопасных snapshots
из 1716 body cells подтверждены 1712, **4 остались unknown**. У `person-side`
unknown cells — 9. Пол хотя бы в одной секции остался без полного evidence:
минимальный floor observed fraction — 0. Неполное покрытие не округлялось
до «свободно». Строгая freshness policy отвергла **все 12** двухсекундных
обзоров как stale, отдельно от их геометрического результата.

Дополнительная локализация на `path-clear` нашла центры четырёх unknown
body cells на высоте **1,829 м**, в **0,275 м** впереди камеры, при lateral
x −0,225, −0,075, +0,075, +0,225 м. Неподтверждённые секции пола включают
0,2–0,35, 0,95–1,10, 1,55–1,85, 2,30–2,45 и 3,05–3,20 м. Их положения
совпадают со швами этой сцены; это диагностическое соответствие после
scoring, а не labels в producer. Артефакт:
`docs/_baseline_logs/blender_visible_body_gaps_v1.json`.

Это отрицательный результат для гипотезы «точной глубины одного кадра
достаточно, чтобы убрать ложные остановки». Причины лежат также в покрытии
ближнего объёма, whole-pixel surface bounds и времени наблюдения.

## Совместимость и повторяемость

Первый дополнительный прогон v1 не выполнял локализацию: все 265 tracks
отклонялись по несовпадению preprocess contract names. Этот результат и
receipt сохранены; все **60** исходников v1 архивированы побайтово.
`verify_body_preprocess_equivalence.py` выполнил actual preprocessing AST
обоих существующих путей на тех же RGB и подтвердил **побайтовое равенство
132 входных RGB01/CHW тензоров**. Только после этого v2 использует
каноническое имя. NCNN outputs, модель, crop и numerical preprocessing не
менялись. В v2 проверено 779702 optical pixel footprints; incompatible
identity/projection/pose/time rejects — **0**. Gate требует реально
исполненной геометрической локализации, отдельно от safety outcome.

Функциональный replay v2 и 5 contrasting controls прошли: **6/6 тестов**.
Новый source/output receipt v2 прошёл; в нём pinned **61 source**,
предыдущие receipts, tensor equivalence и optical packet admission.
Полная серийная Flutter suite: **1555 тестов прошли, один пропущен**;
`flutter analyze --no-pub` завершился без замечаний.
Полный серийный Core RC-прогон: **55/55 обязательных проверок прошли**,
включая два новых visible-body этапа и все прежние replay/model gates.
Это desktop software evidence; model correctness, Android build,
named-device runtime и controlled walking этим прогоном не установлены.
Итоговый receipt сохранён побайтово в
`docs/_baseline_logs/blender_visible_body_core_rc_v2.json`;
полный лог — `scratch/blender-visible-body-core-final.log`.

Текущие артефакты:
`docs/_baseline_logs/blender_visible_body_shadow_v2.json`,
`docs/_baseline_logs/blender_visible_body_contract_v2.json`,
`docs/_baseline_logs/blender_body_preprocess_equivalence_v1.json`.

## Скорость и следующий технический шаг

Отдельный desktop JIT compute replay (132 кадров на режим) дал p50/p95:
control **5,42/9,77 мс**, с metric packet — **76,89/103,54 мс**.
Замер включает detector/tracker, чтение и распаковку metric packet,
body proof и runtime; исключает декодирование/нормализацию raw NCNN,
новый neural inference, capture и delivery. Это не capture-to-alert и не
Android timing; p95 превышает 100 мс уже в этом частичном desktop замере.
Искусственные replay часы не доказали прохождение реального deadline.
Исходные измерения сохранены отдельно в
`docs/_baseline_logs/blender_visible_body_compute_v2.json`.

Следующий ограниченный шаг: закрыть недостающие ближние body cells и
подтвердить floor patch bounds на стыках поверхностей в stationary scan.
View selection должно опираться на intrinsics и unknown volume, без
scoring labels. После геометрического proof требуется отдельно решать
свежесть и обработку под совместной нагрузкой; старый обзор не должен
выдавать разрешение движения. Следующее обобщение проверяется на новой
непросмотренной выборке.

## Воспроизведение

```powershell
flutter test --no-pub --concurrency=1 --dart-define=BAGDAR_CHECK_BODY_REPORT=true test/blender_visible_body_replay_test.dart
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_visible_body.py
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-visible-body-final
```

[Протокол](blender-visible-body-protocol-2026-10-04.md) задаёт объём,
viewpoints и критерии до исполнения. Предыдущие результаты:
[confidence-authority correction](blender-paired-correction-evaluation-2026-10-04.md).

Обычная камера приложения не менялась. Metric provider включён только явной
конфигурацией benchmark; реальная metric calibration телефона не установлена.
Обзор замораживает движущиеся объекты и не доказывает dynamic safety.
`promotionAllowed=false`; named-device, controlled walking и активные
assistive подсказки не установлены.

Продолжение этого этапа записано в отдельном
[отчёте покрытия неподвижного обзора](blender-scan-coverage-evaluation-2026-10-04.md).
Новые ракурсы, независимые first-Z bounds и исправление численных стыков
закрыли body/floor coverage в 6/6 известных проходимых snapshots, сохранив
6/6 blocked hazards и strict stale rejection. Это отдельный frozen-state
результат; исходные moving false stops и ограничения этого отчёта сохранены.

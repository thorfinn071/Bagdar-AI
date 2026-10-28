# Покрытие неподвижного обзора — 2026-10-04

Работа продолжает visible-body эксперимент на том же известном корпусе.
Проверяется геометрическая наблюдаемость замороженных сцен. Это не проверка
живого Android и не снижение 55/55 moving false stops.

## Изменения

Ракурсы вычислены из intrinsics, optical height и запрошенного объёма,
без meshes или scoring labels: yaw −37/0/+37°, pitch −60/−25/10/45°.
Объём прежний: 0,9 м ширины, headroom 1,85 м, forward 0,2–3,5 м;
rise/drop пола 0,05 м. Предложение ракурса не является clearance proof.

Новый renderer разбивает всю площадь пикселя по проекциям непрозрачных
треугольников и границам ближайшего return. Дыры, щели и превышение бюджета
оставляют bounds unknown. Площадь перекрывающихся triangles не суммируется
как доказательство покрытия. Consumer не получает mesh, masks или labels.

Полные интервалы высоты учитывают связь конкретного луча с его глубиной;
независимый first-Z minimum устраняет излишнюю экстраполяцию частичного
треугольника. Body producer использует отдельное доказательство свободной
глубины; floor producer — интервал высоты первой видимой поверхности.
Уверенность пола не очищает unknown body.

## Сохранённое сравнение v1

Экспортированы 264 пакета: 120 прежних ракурсов с новыми upper bounds и
144 новых ракурса. На всех 120 прежних видах range/lower/validity
совпали побайтово. Дополнительные upper bounds появились в 262542
наблюдениях пикселей; это повторные пиксели на кадрах, не уникальные объекты.

| Исполнение | Passable measuredClear | Hazard blocked | Hazard incorrectlyClear | Strict stale rejected |
| --- | ---: | ---: | ---: | ---: |
| Прежние ракурсы и bounds | 0/6 | 6/6 | 0 | 12/12 |
| Прежние ракурсы, новые upper bounds | 0/6 | 6/6 | 0 | 12/12 |
| Новые ракурсы, новые upper bounds | 0/6 | 6/6 | 0 | 12/12 |

Новые ракурсы закрыли все 1716 body cells в пяти проходимых snapshots.
У person-side остались четыре ближние ячейки около высоты 1,260 м.
Проверка дальнего пола оставалась неполной из-за независимого смешивания
крайних Z и крайних ray coordinates. Цель полного прохода в v1 не достигнута;
отчёт и данные сохранены, **9/9 тестов** этого сравнения прошли.

Height-only renderer отдельно прошёл 1090 independent ray-height witnesses
и побайтовую проверку прежних четырёх массивов. Его экспорт остановлен
на 92/144 пакетов; неполный каталог сохранён, результатом полного replay
он не считается. Итоговый вариант добавляет также независимый first-Z bound.

## Проверка итогового варианта

Renderer проверен на 1090 noncentral ray witnesses для height/free-Z,
на hidden-geometry invariance и сохранение исходных четырёх массивов.
Тонкое препятствие, пропущенное centre rays, ограничивает независимый
free-Z в 82 пикселях. Проверки площади включают overlap с дырой, subpixel
gap, nearest crossing planes, hidden surfaces и exhaustion бюджета.

Полный export содержит 144 пакета, побайтово сохраняющих четыре массива
предыдущего renderer. Более точный независимый first-Z minimum улучшил
235781 наблюдение пикселей. Он закрыл body coverage во всех шести проходимых
сценах, но исходные интервалы высоты оставляли неизвестный дальний пол.
Это сохранённый контроль `originalHeightSummary`: 0/6 measuredClear,
6/6 blocked hazards; body cells проходимых сцен полностью покрыты.

Локализация path-clear, view 4, pixel (150,111) показала ложный интервал
высоты −0,16…0 м: плавающая арифметика создавала щель примерно 5e-12 пикселя
между треугольниками одной плиты. Через неё partition учитывал скрытое дно.
Canonical near-plane intersections и одинаковые коэффициенты общей границы
исправили эту причину. Первый отдельный height supplement добавил 13324
совместных floor proofs, но два проходимых scans сохраняли пробелы.

Второй отдельный supplement использует точную рациональную арифметику
для топологии разбиения, без snapping или отбрасывания малой площади.
Он добавил ещё 1714 совместных floor proofs. Предыдущие положительные
интервалы сохранены побайтово; depth/validity/axis-Z/free-Z не подменяются.
Отсутствие free-Z сохраняет пиксель unknown даже при доступной высоте.
Два supplement содержат по 144 height packets и не перезаписывают исходники.

Canonical projection проверена на 580 fractional Blender rays; exact topology
— ещё на 55 лучах. В обоих проверках сохранены hidden geometry invariance
и 50 пикселей смешанных first-return границ. **35/35 геометрических Python tests**
проходят, включая реальные щели до соседних представимых float около 0,5
пикселя, overlap с дырой, drops и исчерпание fragment budget.

Отдельный before/after контроль изолирует влияние единственного добавленного
препятствия толщиной 0,001 м. В 10 пикселях centre range не меняется, но
независимый whole-pixel free minimum фиксирует foreground. Ни один из этих
пикселей не был ошибочно certified as floor. Это отдельная Blender проверка
после Core, сохранённая в `blender_scan_floor_negative_witness_v1.json`;
она уточняет attribution прежнего mixed-boundary mask из 50 пикселей.

| Итоговый complete-envelope replay | Результат |
| --- | ---: |
| Проходимые snapshots, полный body и floor proof | **6/6** |
| Опасные snapshots, blocked | **6/6** |
| Опасные snapshots ошибочно cleared | **0** |
| Strict 100 ms: stale scans rejected | **12/12** |

У каждой проходимой сцены все 1716 body cells и все 22 floor sections
полностью наблюдаемы. **13/13 Flutter tests** итогового replay прошли,
включая отсутствие height/free-Z/depth, nonmetric units, mismatch pose/session,
неполный обзор и stale contrast. Отсутствие только floor height не объявляет
body data неисправными, но оставляет passage unavailable.

Функциональный отчёт и contract записаны однократно. Contract фиксирует
99 source hashes, предыдущие freezes, identities и все соответствия пакетов.
Полный `tool/verify_core.ps1 -Rc` прошёл **57/57 обязательных этапов**,
включая два новых. **1577 Flutter tests passed**, один skipped; analyzer
без замечаний. Итог сохранён однократно в
`docs/_baseline_logs/blender_scan_complete_core_rc_v1.json`, SHA256
`bed0a3fbf1b192bc0f2f8ace0a46abc8b5ab6aa08e0e3f704397caa719bdb3e0`.
Предыдущая квитанция 55/55 сохранена. Android build/runtime и controlled
walking в этом прогоне не выполнялись; software RC не является device gate.

## Свежесть и пределы

Новый обзор имеет 12 видов с интервалом 200 мс, всего 2,2 секунды.
Diagnostic policy 3 с оценивает геометрию отдельно. Strict policy 100 мс
обязана отклонять весь накопленный обзор, даже при полном покрытии.
TTL не повышен. Старый обзор не даёт разрешения идти.
Сам сбор 12 ракурсов занимает 2,2 с и превышает 100 мс ещё до обработки.
Следующий стенд должен отдельно измерять возраст полученных наблюдений
и вычислительную задержку. Получение актуального объёма потребует отдельного
решения по sensing/coverage; ускорение consumer сохраняет этот capture gate.

Normal camera, модели MiDaS/YOLO и их исходные 132 RGB не менялись.
Новый source включён только в явный synthetic harness; `runtimeWired=false`,
`promotionAllowed=false`. Объекты заморожены, motion safety и phone
calibration не установлены. Model correctness, Android timing и walking
не следуют из этих данных. Следующее обобщение требует новой unseen выборки.

Это **синтетические метрические измерения видимой геометрии Blender**, а не
новые результаты нейросети. Улучшение renderer не означает улучшение MiDaS.
Следующий ограниченный этап — измерить возраст данных и полное время
обработки при параллельном neural inference: отдельные missed-risk,
false-stop и unsafe-continue показатели, без увеличения freshness TTL.
После desktop измерения нужен отдельный Android replay; проверка вычислений
телефона также не заменяет camera calibration и controlled walking.

Сохранённый desktop JIT замер диагностического replay внутри общего Flutter
прогона имеет p50/p95 **1063,411/1171,820 мс** на 12 snapshots. Он включает чтение и проверку
пакетов, построение source и три получения observation: geometry, strict
policy и сбор отчёта. Он исключает capture, neural inference и delivery,
не является замером одной production decision или Android. Старый height
контроль выполнялся после остановки таймера. Числа показывают стоимость
этого диагностического процесса, а не выполнение realtime deadline.
Исходный write-once файл — `docs/_baseline_logs/blender_scan_complete_compute_v1.json`,
SHA256 `650666d56a9924489b5e963c2dd79e59c3580b45160e530c9a5e4d4cf05a79c2`.

## Артефакты и воспроизведение

- `docs/_baseline_logs/blender_scan_coverage_replay_v1.json` — первое сравнение.
- `docs/_baseline_logs/blender_scan_surface_bounds_v1.json` — renderer checks.
- `docs/_baseline_logs/blender_scan_complete_bounds_v1.json` — correlated bounds.
- `docs/_baseline_logs/blender_scan_complete_negatives_v1.json` — thin foreground.
- `docs/_baseline_logs/blender_scan_watertight_bounds_v1.json` — общие границы.
- `docs/_baseline_logs/blender_scan_exact_bounds_v1.json` — точная топология.
- `docs/_baseline_logs/blender_scan_floor_negative_witness_v1.json` — isolated thin floor foreground.
- `docs/_baseline_logs/blender_scan_complete_replay_v1.json` — итог и контроль высоты.
- `docs/_baseline_logs/blender_scan_complete_contract_v1.json` — 99 source freezes.
- `docs/_baseline_logs/blender_scan_complete_core_rc_v1.json` — полный desktop Core RC.

```powershell
flutter test --no-pub --concurrency=1 --dart-define=BAGDAR_CHECK_SCAN_COVERAGE=true --dart-define=BAGDAR_CHECK_SCAN_COMPLETE=true test/blender_scan_coverage_replay_test.dart test/blender_scan_complete_replay_test.dart
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_scan_complete.py
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-scan-complete-final
```

Протоколы: [ракурсы и поверхности](blender-scan-coverage-protocol-2026-10-04.md),
[height correlation](blender-scan-height-envelope-protocol-2026-10-04.md),
[полный first-return envelope](blender-scan-complete-envelope-protocol-2026-10-04.md).
[Canonical projection](blender-scan-watertight-protocol-2026-10-04.md) и
[точная топология](blender-scan-exact-partition-protocol-2026-10-04.md)
отдельно фиксируют диагностику и правила исправления численных щелей.
Предыдущий [visible-body отчёт](blender-visible-body-evaluation-2026-10-04.md)
сохранён как исходная диагностика.

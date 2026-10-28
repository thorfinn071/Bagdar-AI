# Исправление оценки риска на парных Blender-сценах — 2026-10-04

На неизменных 132 кадрах исправленная shadow-цепочка больше не разрешает
движение при опасности и не объявляет сомнительные компоненты пола
непосредственной опасностью. Обычные ложные остановки **не устранены**:
55/55 проходимых кадров при движении остаются остановленными. Положительное
движение требует независимого подтверждения объёма тела; видимого пола
и заполненной карты MiDaS недостаточно.

## Причина и изменение

В `camera-pan-approach/0` MiDaS создал центральный `broadSurface`:
proximity 0,510, confidence 0,150, overlap 0,552. Track ещё не был подтверждён,
поэтому не вносил риск, а качество кадра и видимый пол позволяли `continueForward`.
Теперь текущая центральная гипотеза учитывается с первого кадра: forward
остаётся unknown, решение — `stopNow / SPATIAL-P1-UNVERIFIED-OBSTRUCTION`.

Ложные `IMMINENT` на проходимых сценах вызывали главным образом `lowObstacle`
в нижней части изображения: confidence примерно 0,51–0,58, но proximity 1,0.
Адаптер использовал max(proximity, confidence) и передавал occupancy 1,0.
Относительный ранг близости теперь не повышает уверенность в наличии
препятствия: в новой политике occupancy берётся из confidence компонента.
Сомнительный объект остаётся причиной остановки для проверки, отдельно
от подтверждённого критического риска. Детектор и веса моделей не изменялись.

Отдельный `ConfidenceAuthoritySpatialRuntime` использует прежний runtime
для admission, сессий, часов и арбитража. Его scene model преобразует
generic evidence, а planner сохраняет остановку сомнительного объекта до
неподвижности и двух разных положительных ревизий. Несовпадающий planner
отклоняется. `CameraViewModel` включает этот модуль в существующей
shadow-цепочке камеры. Прежние общие файлы сохранены с исходными хэшами;
обычный `SpatialSafetyRuntime` остаётся контрольным режимом. Обе версии
реально выполняются при Core-проверке. Активные TTS/вибрация не включены.

## Те же сцены, новые результаты

| Метрика | Видимая глубина: до → после | MiDaS-relative: до → после |
| --- | ---: | ---: |
| Hazard `continueForward` | 0 → 0 | **1 → 0** |
| Опасные последовательности с остановкой в пределах 300 мс | 6/6 → 6/6 | **5/6 → 6/6** |
| Опасные кадры со `stopNow` | 66/66 → 66/66 | **62/66 → 66/66** |
| Ложные `IMMINENT` на проходимых кадрах движения | **32 → 0** | **25 → 0** |
| Остановки на проходимых кадрах движения | **55/55 → 55/55** | **55/55 → 55/55** |
| Применение passage proof | 0 → 0 | 0 → 0 |

В `camera-pan-approach` первая остановка с MiDaS сдвинулась с 800 мс на
первый кадр, 0 мс. Это метки искусственного replay, **не реальные времена
вычисления или доставки команды**. RGB, raw NCNN, нормализация, поза и
разметка идентичны исходному прогону; labels и маски не входят в perception.

Цена консервативной политики видна и в безопасном неподвижном
`camera-pan-clear`: остановки выросли с 9 до 10 из 11 кадров на видимой
глубине и с 9 до 11 на MiDaS. Этот контроль отдельно исключён из знаменателя
55 кадров движения, как было объявлено первоначально. Его ухудшение не скрыто.
Система пока не отличает такие гипотезы от реальных препятствий достаточно
хорошо для полезных разрешающих подсказок.

Уверенные препятствия сохраняют `IMMINENT`: после исправления он срабатывает
на 14 опасных кадрах с видимой глубиной и на одном с MiDaS. Независимые drop
и moving threat сохраняют emergency precedence; неизвестность и misses
не отменяют накопленный риск.

## Проверки и неизменный контроль

- До правки прошёл исходный source/output freeze. Все **47 оригинальных
  исходников** сохранены побайтово в `docs/_baseline_sources/blender_paired_v1`
  с суффиксом `.snapshot`; первые отчёты и corpus manifest не переписаны.
- 12 новых отрицательных/защитных тестов: первый слабый компонент, rank 1
  при слабой confidence, сильное препятствие, misses/history, drop, moving
  threat, пол без body proof, движение без proof, пропавшая глубина,
  stale/session admission, несовпадающая конфигурация planner и снятие
  остановки только после двух разных положительных ревизий при неподвижности.
- Полный серийный Flutter-набор: **1549 тестов прошли, 1 пропущен**.
  В него входят все 12 защитных тестов отдельного модуля. Старый и
  исправленный replay воспроизвелись также в отдельном Core-этапе.
- Новый source/output receipt с прежними нулевыми пределами quality gate
  прошёл; thresholds и TTL не ослаблены. Отдельный gate по-прежнему
  запрещает hazard continues, late/missed stops и false IMMINENT.
- Полный серийный Core RC-прогон: **52/53 обязательных проверок прошли**.
  Единственный отказ — lint `curly_braces_in_flow_control_structures`
  в новом модуле; все replay, hash, quality и модельные этапы прошли.
  Исходный receipt сохранён в
  `scratch/verification-blender-paired-correction-v3/core-verification.json`.
  Отсутствующие фигурные скобки добавлены без изменения поведения;
  результаты повторной проверки этой правки приведены ниже.

Успешные software/replay проверки не устанавливают model correctness.

После lint-правки `flutter analyze --no-pub` прошёл: **No issues found**.
Для изменившегося source hash создан отдельный receipt v4; повторные
replay/защитные проверки прошли **14/14** с прежним отчётом v3:
исходный replay, исправленный replay и 12 защитных тестов. Receipt v4
проверен повторно: `passed=true`, `failures=[]`.
Сравнение текста с нормализацией переводов строк и контрольных сумм подтвердило:
из 53 pinned sources изменились только фигурные скобки в новом runtime и
путь версии receipt в verifier; остальные 51 source hash и поведенческий
отчёт не изменились. На этом этапе повторный полный Core-прогон после
правки не выполнялся; его сохранённый результат 52/53 не переименован в 53/53.

На следующем [visible-body этапе](blender-visible-body-evaluation-2026-10-04.md)
полный Core выполнен заново: **55/55 обязательных проверок прошли**,
включая исходные проверки коррекции и два новых этапа. Новый receipt:
`docs/_baseline_logs/blender_visible_body_core_rc_v2.json`.
Исторический receipt с 52/53 сохранён.

Логи: `scratch/blender-paired-correction-core-v3.log`,
`scratch/blender-paired-correction-v4-analysis.log`,
`scratch/blender-paired-correction-v4-replays.log`,
`scratch/blender-paired-correction-v4-check.log`.

Новые результаты: `docs/_baseline_logs/blender_paired_correction_shadow_v3.json`;
текущий source/output receipt: `blender_paired_correction_contract_v4.json`.
Версия v4 фиксирует правку фигурных скобок; поведенческий отчёт v3 остаётся
тем же. Все 53 исходника до lint-правки сохранены побайтово в
`docs/_baseline_sources/blender_paired_correction_v3`; прежний receipt v3
не перезаписан. Первые результаты:
[исходный отчёт](blender-paired-scenes-evaluation-2026-10-04.md).
Правила этапа: [протокол](blender-paired-correction-protocol-2026-10-04.md).

## Воспроизведение

```powershell
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_paired_scene_correction.py --baseline-only
flutter test --no-pub --concurrency=1 --dart-define=BAGDAR_CHECK_PAIRED_REPORT=true --dart-define=BAGDAR_CHECK_CORRECTION_REPORT=true --dart-define=BAGDAR_CORRECTION_REPORT=docs/_baseline_logs/blender_paired_correction_shadow_v3.json test/blender_paired_scene_shadow_replay_test.dart test/blender_paired_scene_correction_replay_test.dart test/generic_geometry_confidence_authority_test.dart
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_paired_scene_correction.py
```

Старый `verify_paired_scene_baseline.py` продолжает проверять исходные live
хэши; они не изменились. Новый baseline-only дополнительно проверяет те же
исходные хэши против архивных байтов, не обновляя первый receipt.
Старый quality report остаётся красным историческим результатом;
текущий gate оценивает отдельный correction report с теми же пределами.

## Что остаётся

Следующий этап — уменьшать **55/55 ложных остановок** через наблюдаемое
подтверждение пространства для тела и разбор ложных компонентов пола.
Нельзя объявлять hidden/headroom свободными по заполненной относительной
карте. Нужны отдельно положительные и отрицательные body-volume случаи,
затем ещё одна непроверенная выборка для оценки обобщения.

Нейросети не обучались; YOLO остаётся отдельным контролем. Это известный
процедурный indoor-корпус с идеальными admission/alignment и искусственным
временем. Замеры скорости, телефона, нагрева, реальной камеры и ходьбы не
добавлены. `promotionAllowed=false`, device runtime и controlled walking
не установлены.

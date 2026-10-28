# Bagdar: многокадровая проверка детекторов на Blender

Дата: 2026-09-22. Статус: **software/shadow diagnostic**. Production-модель,
`GenericObstacleMode` и правила выдачи пользовательских предупреждений не
менялись.

## Зачем понадобился новый корпус

В `blender-egocentric-v1` низкий ящик расположен в 1,8 м от горизонтальной
грудной камеры и ниже её поля зрения. Его не видно на RGB, а semantic mask не
содержит класса `low`. Отсутствующую разметку нельзя исправить вручную,
нарисовав препятствие поверх невидимого объекта.

`tool/blender/generate_spatial_temporal_corpus.py` сохраняет исходный v1 и
создаёт отдельный `blender-temporal-v2`:

- 6 сцен: тонкий столб, низкий ящик, нависающее препятствие, пересекающий
  объект, проходимый пандус и дверной проём;
- 3 согласованных RGB/depth/semantic кадра на сцену, 256×192, шаг 300 мс;
- камера приближается на 0,12 м за кадр; объект в crossing-сцене смещается
  поперёк кадра;
- низкий ящик стоит в 2,8 м и проверяется генератором: класс `low` обязан
  присутствовать в центральной трети каждого кадра;
- SHA-256 закрепляет генераторы, Blender source, replay, каждый RGB/depth/mask
  файл; одинаковые кадры одной последовательности запрещены.

Это более подробный **синтетический** тест, но объекты всё ещё выглядят как
простые примитивы. Он не заменяет съёмку с согласия участников и не доказывает
качество на настоящей улице.

## Прямой spatial replay

Прямой replay с `--manifest` (команда ниже) прошёл все 6 последовательностей
и 18 временных кадров. Шесть safety-счётчиков равны нулю. После третьего
наблюдения препятствия planner
предлагает `left` только в shadow-данных; основное действие остаётся
`stopNow`.

Входные сектора replay заданы вручную по синтетическому состоянию сцены.
RGB/depth/semantic кадры привязаны к тому же timeline, но из них не
вычисляются occupancy и решения planner. Поэтому этот replay проверяет
политику на согласованных входах, а не точность цепочки восприятия.
[RC-отчёт replay](./_baseline_logs/blender_temporal_replay_rc.json) содержит
действие и shadow-предложение для каждого кадра.

Общий `--rc` по процедурному корпусу проверяет hash внешнего манифеста, но
сам по себе не исполняет внешний timeline. Теперь
`test/spatial_replay_harness_test.dart` и `tool/verify_core.ps1` отдельно
запускают кадры обоих Blender-корпусов.

## Результаты четырёх моделей

`tool/model_benchmark/evaluate_temporal_blender.py` использует те же
confidence 0.25, class-aware NMS 0.45 и RGB/255 letterbox, что и предыдущий
desktop-эксперимент. Все 12 кадров четырёх object-like сцен имеют центральные
пиксели опасности в маске. Совпадение означает хотя бы один пиксель пересечения
центральной рамки и маски; положительный результат всё равно потребовал бы
проверки класса и точности рамки.

| Модель | Кадры опасности с центральным пересечением | Центральные рамки на 6 проходимых кадрах | Всего рамок |
| --- | ---: | ---: | ---: |
| YOLOv8n 416 контроль | 0/12 | 3/6 | 3 |
| YOLO11n 320 | 0/12 | 1/6 | 1 |
| YOLO11n 416 | 0/12 | 0/6 | 0 |
| YOLO26n 416 | 0/12 | 0/6 | 0 |

У контрольной YOLOv8n все три рамки (`classId=60`) появились на проходимом
пандусе. У YOLO11n 320 рамка (`classId=25`) появилась только на третьем кадре
пандуса. Ни одна модель
не дала совпадения с центральной маской препятствия. Нулевое число изменений
присутствия детекции в опасных сценах означает **постоянный пропуск**, а не
хорошую временную стабильность.

Подробный [JSON-отчёт](./_baseline_logs/blender_temporal_detector_diagnostic.json)
содержит каждый кадр, score до порога, рамки, hashes, версии сред и причины
блокировки promotion. Рамка на пандусе является ложной находкой детектора,
**не** подтверждённым ложным речевым предупреждением Bagdar. Выходы YOLO не
превращались в occupancy и не подменяли решение planner.

## Offline shadow replay через штатную геометрию

`test/blender_temporal_shadow_replay_test.dart` связал предвычисленные рамки
четырёх моделей с RGB, проверенным по SHA-256, и raycast depth Blender с тем
же кадром. Depth PGM16 переведён из миллиметров в `DepthFrame.metricMeters`:
ненаблюдаемые пиксели имеют нулевую confidence. Далее выполняются штатные
`GenericObstacleDetector`, `GenericObstacleTracker` и `SpatialSafetyRuntime`
(scene fusion, planner, shadow arbiter). RGB-инференс выполнялся ранее на
desktop; этот replay не запускает `CameraImage`, NCNN depth provider или TTS.
Для поиска возможных semantic matches каждому YOLO box задано максимально
разрешающее `dist='close'`; это верхняя оценка числа совпадений, а не
воспроизведение дистанции из приложения.

Результат одинаков для четырёх моделей: **0 возможных semantic matches**.
Геометрия с идеальной Blender-глубиной приводит к `stopNow` на всех 12 кадрах
опасности, но только 10 раз по правилу imminent hazard. На первом кадре
низкого и нависающего препятствия остановка вызвана нехваткой подтверждения
геометрии. На **всех 6 кадров, размеченных как проходимые**, тоже выбран
`stopNow`, но ни один из них больше не классифицируется как imminent hazard:

| Сцена | Результат на трёх кадрах | Причина |
| --- | --- | --- |
| Дверной проём | 3/3 shadow `stopNow`, `SPATIAL-P0-DEGRADED-MOVING` | Структурированный центральный проём больше не сворачивается в ложный `broadSurface`; отдельный unknown floor не позволяет принять возможный depth dropout за свободный путь (`unknown=0.650`) |
| Пандус | 3/3 shadow `stopNow`, `SPATIAL-P0-DEGRADED-MOVING` | Поверхность передаётся как отдельное traversability evidence (`0.643–0.654`), но общий обзор остаётся недостаточным (`unknown=0.537`) |

Это [диагностический отчёт](./_baseline_logs/blender_temporal_shadow_replay.json),
а не метрика успешного распознавания 12/12. Все действия переданы арбитру как
`shadow` и не стали пользовательскими командами. Изменение исправляет ложную
причину остановки, но намеренно не превращает отсутствующий depth return в
«свободное пространство». Стоп на проходимом участке безопаснее пропуска
риска, но непригоден как рабочая навигация. Для снятия остановки нужен отдельный
наблюдающий источник свободного объёма/проходимости и затем реальные записи;
ослаблять `unknown` по этим 18 синтетическим кадрам нельзя.

Во время replay был найден и исправлен разрыв интеграции:
`DepthPipelineController` вычислял semantic match для `CollisionRiskEngine`,
но не сохранял его в `GenericObstacleTrack.last`, откуда семантику читает
`GenericGeometrySceneAdapter`. Теперь текущий match сохраняется в треке и
появляется в `sourceMask` spatial scene; исчезнувший match явно очищается,
чтобы метка прошлого кадра не оставалась активной. Regression-тест также
проверяет, что геометрический источник при этом сохраняется. На данном
Blender-корпусе фактических совпадений всё равно 0: исправление восстанавливает
канал данных, но не улучшает выходы моделей.

## Воспроизведение

```powershell
& 'C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe' `
  -b --python tool/blender/generate_spatial_temporal_corpus.py -- `
  --output test/fixtures/spatial_safety/blender-temporal-v2
dart run tool/build_spatial_corpus.dart --check
dart run tool/report_spatial_metrics.dart `
  --manifest test/fixtures/spatial_safety/blender-temporal-v2/replay-manifest.json `
  --rc --summary
flutter test --no-pub test/spatial_replay_harness_test.dart
python tool/model_benchmark/test_evaluate_temporal_blender.py
python tool/model_benchmark/evaluate_temporal_blender.py `
  --check docs/_baseline_logs/blender_temporal_detector_diagnostic.json
flutter test --no-pub --dart-define=BAGDAR_CHECK_SHADOW_REPORT=true `
  test/blender_temporal_shadow_replay_test.dart
powershell -NoProfile -File tool/verify_core.ps1 -Rc `
  -OutputDirectory scratch/verification-temporal
```

Проверка `verify_core -Rc` прошла: 14 этапов, без обязательных ошибок;
`flutter analyze` не нашёл замечаний, полный набор Flutter-тестов прошёл.
[Агрегированный отчёт](./_baseline_logs/blender_temporal_core_verification_rc.json)
отмечает `modelCorrectnessRc=not_established` и
`namedDeviceRuntime=not_run`. Его успешный результат относится к
software-контрактам и replay; он не отменяет 0/12 в детекторной диагностике,
которая выполняется отдельно.

Эксперимент запускался на Python 3.11.9, NumPy 2.4.3, Pillow 12.2.0,
ONNX Runtime 1.26.0, TensorFlow 2.21.0, Blender 5.2.2 LTS. Re-render на
другой версии Blender должен выпускать новый manifest/hash, а не незаметно
заменять этот corpus.

Следующий проверяемый шаг — многокадровый корпус с более правдоподобными
материалами, освещением, сложной геометрией и затем consent-controlled
реальные RGB/depth записи. Перед любым выводом о пригодности модели нужны
геометрический downstream replay и измерения на названном телефоне. Sonar
остаётся Research/shadow-only.

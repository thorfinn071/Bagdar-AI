# Bagdar: проверка детекторов на синтетических сценах препятствий

Дата: 2026-09-22. Статус: **диагностика детектора на desktop**, без решения о
замене production-модели или допуске к assistive-режиму.

## Что было проверено

На одних и тех же 21 сценах `blender-egocentric-v1` запущены:

| Модель | Артефакт | Среда запуска |
| --- | --- | --- |
| YOLOv8n 416, текущий контроль | `assets/yolov8n_int8.tflite` | TensorFlow Lite CPU/XNNPACK |
| YOLO11n 320 | `model_export/candidates/yolo11n_320.onnx` | ONNX Runtime CPU |
| YOLO11n 416 | `model_export/candidates/yolo11n_416.onnx` | ONNX Runtime CPU |
| YOLO26n 416 | `model_export/candidates/yolo26n_416.onnx` | ONNX Runtime CPU |

Скрипт `tool/model_benchmark/evaluate_blender_detectors.py` проверяет SHA-256
каждого RGB/depth/semantic файла, replay-манифеста и каждого артефакта модели.
Все модели получают RGB/255 после одинакового aspect-preserving letterbox с
билинейным resize и padding 114. Для TFLite подаётся NHWC, для ONNX — NCHW.
Порог confidence 0.25; class-aware NMS IoU 0.45. Порог и preprocessing здесь
служат **сопоставимому desktop-эксперименту**, а не доказательству паритета с
`flutter_vision` или Android camera pipeline.

TFLite-контроль возвращает нормализованные координаты рамок, ONNX-кандидаты —
координаты во входных пикселях. Преобразование проверено отдельным regression
test. На локальном проверочном изображении `bus.jpg` контроль нашёл пять
объектов с максимальным score 0.887603; каждый ONNX-кандидат тоже выдал пять
объектов. Это проверка работоспособности decoder, не часть корпуса Bagdar и не
оценка точности на препятствиях.

## Результат

`object-like` означает 10 сцен, где Blender ground truth пометил прямое
препятствие или движущийся объект. `forward box` означает рамку с центром в
средней трети изображения. `forward mask overlap` дополнительно требует
пересечения рамки с пикселями размеченной опасности в этой трети. Это
**диагностические признаки детектора**, а не фактическое предупреждение Bagdar.

| Модель | Forward box на object-like | Forward mask overlap | Forward box на двух проходимых сценах | Всего рамок |
| --- | ---: | ---: | ---: | ---: |
| YOLOv8n 416 контроль | 0/10 | 0/9 | 1/2 | 1 |
| YOLO11n 320 | 0/10 | 0/9 | 0/2 | 0 |
| YOLO11n 416 | 0/10 | 0/9 | 0/2 | 1 |
| YOLO26n 416 | 1/10 | 0/9 | 0/2 | 1 |

Поштучные результаты, scores, классы COCO, рамки, SHA-256 и причины блокировки
сохранены в `docs/_baseline_logs/blender_detector_diagnostic.json`.

Наблюдения:

- Контрольная YOLOv8n нарисовала рамку класса 60 на проходимом `blender-ramp`.
  Если считать любую центральную рамку командой остановиться, это создало бы
  ложный сигнал. Production-цепочка Bagdar так поступать не должна: риск
  пространства определяет геометрия.
- YOLO11n 416 нарисовала рамку класса 11 на боковой области
  `blender-narrow-passage`. Она пересекает semantic mask, но её центр лежит
  вне средней трети. Это не подтверждение обнаружения центральной опасности.
- YOLO26n нарисовала центральную рамку класса 59 на
  `blender-overhead-obstacle`, однако она не пересекает размеченное нависающее
  препятствие. Поэтому 1/10 по сырым рамкам превращается в 0/9 по
  mask-overlap на сценах с пригодной маской.
- У `blender-low-obstacle` ground truth требует `stopNow`, но его semantic
  mask не содержит пикселей опасности в средней трети. Scene-level результат
  сохранён; pixel-level оценка этой сцены заблокирована неполной разметкой.

Три drop-сцены (`curb-down`, `pothole`, `stairs-down`) требуют геометрического
анализа и исключены из оценки детектора. Шесть сцен с unknown/невалидной
ориентацией/недоступной камерой относятся к quality gate. По одному кадру
невозможно оценить направление движения объекта и temporal stability.

## Проверка planner и смысл результатов

`dart run tool/report_spatial_metrics.dart --rc` прошёл: шесть safety-счётчиков
равны нулю, внешний Blender-манифест найден и его hash совпал. Этот общий
запуск **не исполняет кадры внешнего корпуса**. Прямой запуск
`--manifest test/fixtures/spatial_safety/blender-egocentric-v1/replay-manifest.json`
проверяет 21 Blender-сцену; он использует **синтетические секторные значения,
заданные по состоянию сцены**, а не выход детекторов или расчёт из depth/mask.
Он подтверждает поведение planner на заданных входах, но не измеряет итоговые
команды от каждой модели. Рамки детектора
нельзя подменять геометрической occupancy: такая подмена нарушила бы принцип,
по которому семантика не уменьшает и не подтверждает геометрический риск.

На этих схематичных RGB 96×72 ни один кандидат не показал надёжного покрытия
центральных препятствий. Из этого **нельзя** вычислять полевой critical-recall,
false-alert rate или делать выбор новой production-модели. Нужны более
реалистичные и размеченные RGB/depth последовательности, проверка model-to-
geometry integration и затем измерения на именованном Android-устройстве.
`GenericObstacleMode` остаётся `shadow`.

## Воспроизведение

Проверенная среда: Python 3.11.9, NumPy 2.4.3, Pillow 12.2.0,
ONNX Runtime 1.26.0, TensorFlow 2.21.0 на Windows CPU. Скрипт по умолчанию
пишет JSON только в stdout; `--output` и `--check` задают явный файл.

```powershell
python tool/model_benchmark/test_evaluate_blender_detectors.py
python tool/model_benchmark/evaluate_blender_detectors.py `
  --check docs/_baseline_logs/blender_detector_diagnostic.json
dart run tool/report_spatial_metrics.dart --rc
dart run tool/report_spatial_metrics.dart `
  --manifest test/fixtures/spatial_safety/blender-egocentric-v1/replay-manifest.json `
  --rc --summary
```

Отдельный [многокадровый корпус v2](./blender-temporal-evaluation-2026-09-22.md)
помещает низкое препятствие в поле зрения и проверяет все четыре типа
препятствий на трёх кадрах. Дальше нужны более реалистичные сцены и записи с
подтверждённым provenance, геометрический downstream replay результатов
моделей и отдельный Android gate. Синтетический `continueForward`
не разрешает пользовательскую фразу «путь свободен».

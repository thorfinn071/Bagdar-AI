# Bagdar Spatial Safety — Model Bake-off Report

Дата: 2026-09-20

Статус: artifact/contract и desktop smoke slice выполнен; candidate promotion
заблокирован отсутствующими correctness, license и device gates.

## Решение

Production selection не изменён:

| Область | Выбор | Причина |
| --- | --- | --- |
| Detector | `yolov8n-int8-control-416` | единственный текущий runtime control; candidate correctness не доказана |
| Hardware-capable tier | `midas-small-ncnn` | aligned control from the Flutter frame; independent ARCore camera is Research-only until a shared owner exists |
| NCNN Vulkan/CPU depth | `midas-small-ncnn` | pinned relative-depth control |
| Focal-length tier | depth unavailable | нет валидированной geometry model; режим должен быть degraded |
| Traversability | deferred | нет converted artifact и boundary-labelled corpus |

YOLO11n и YOLO26n остаются `exportedExperiment`. Ни один candidate asset не
подключён в `pubspec.yaml`, `ModelService.loadYolo` или production selection.

## Зафиксированные controls

### YOLOv8n

- Artifact: `assets/yolov8n_int8.tflite`
- SHA-256:
  `3f5c681641e439321ec529c26995de18a910d62a25a49ccb02da2a0a771cae02`
- TFLite input: float32 NHWC `[1,416,416,3]`
- TFLite output: float32 BCN `[1,84,3549]`
- Runtime decoder: существующий `flutter_vision`, `modelVersion: yolov8`
- License/provenance: требует отдельной проверки; не считается закрытым gate.

### MiDaS Small NCNN

- Param SHA-256:
  `d618bb98777ff7e7adeeef1c8cf50ede79c97c754876681d6a0b26330708e8d3`
- Bin SHA-256:
  `324412b094f3309c0c7acd506a06ccdc60296749ac382dc58431efdde0f13242`
- Input: RGB CHW `[1,3,256,256]`, range `[0,1]`; ImageNet normalization
  находится внутри graph.
- Output: relative inverse depth `256×256`, larger means nearer.
- Native/reference parity всё ещё заблокирована отсутствующим
  `test/fixtures/ncnn_contract/reference_outputs.json`.
- Checkpoint license/provenance требует отдельной проверки.

`DepthFrame` теперь обязательно несёт `modelId`, `modelHash` и `preprocessId`.
Пустая identity отклоняется до использования frame downstream.

## Detector candidates

Все ONNX exports созданы локально через Ultralytics `8.4.41`, opset 17,
`dynamic=False`, `nms=False`, `simplify=True`.

| Candidate | Input | Output | SHA-256 | Decoder |
| --- | --- | --- | --- | --- |
| YOLO11n 320 | `[1,3,320,320]` | `[1,84,2100]` | `b9152829ad8ff26a0b2bd2b4a1482910c91c549d1cdcc4587fecf4444741dbe4` | BCN experiment |
| YOLO11n 416 | `[1,3,416,416]` | `[1,84,3549]` | `b9c6c86aa850523b970dff6aec9683dbafb363aa52051a449d4e1651c4a580ce` | BCN experiment |
| YOLO26n 416 | `[1,3,416,416]` | `[1,300,6]` | `b0db38ca8a0fe5c8ff00391b18206e07a423f218f5a8236e1f1dbe1b8a2e1332` | separate end-to-end BNC experiment |

Embedded metadata всех трёх candidates указывает `AGPL-3.0`. Это не
автоматическое разрешение на product promotion: способ распространения Bagdar
и необходимая лицензия должны быть проверены отдельно.

YOLO26 не использует YOLOv8/11 decoder. Добавлен изолированный parser
`Yolo26OutputDecoder`, который принимает только `[1,300,6]`, проверяет finite
coordinates, score, целочисленный COCO class ID и нормализует/clamps box. Parser
не подключён к runtime.

## Воспроизводимость

Pinned environment находится в `model_export/requirements-lock.txt`.

Экспорт и contract/hash verification:

```powershell
model_export\venv\Scripts\python.exe `
  model_export\export_candidates.py --export
```

Проверка уже созданных exports без повторной конвертации:

```powershell
model_export\venv\Scripts\python.exe `
  model_export\export_candidates.py
```

Manifest:

```text
model_export/candidates/manifest.json
```

Он содержит source/artifact hashes, exact export commands, tensor contracts,
decoder ID, Ultralytics version и embedded license metadata.

## Desktop synthetic smoke

Команда:

```powershell
model_export\venv\Scripts\python.exe `
  tool\model_benchmark\run_smoke.py --iterations 20
```

Host: Windows AMD64, AMD Family 25 Model 68, Python 3.11.9,
ONNX Runtime 1.30.0 CPU provider, один inference thread.

| Candidate | p50 | p95 | Результат |
| --- | ---: | ---: | --- |
| YOLO11n 320 | 23.709 ms | 28.154 ms | shape/finite smoke pass |
| YOLO11n 416 | 37.861 ms | 39.451 ms | shape/finite smoke pass |
| YOLO26n 416 | 31.522 ms | 46.068 ms | shape/finite/score/class smoke pass |

Это synthetic random-tensor smoke на laptop CPU. Числа не являются phone
latency, camera end-to-end latency, accuracy, recall, memory peak, battery или
thermal evidence. Полный JSON сохранён в
`docs/_baseline_logs/model_bakeoff_desktop.json`.

## Replay

Production control selection повторно прошла текущий procedural spatial RC:

```text
passed: true
unsafeGuidanceCount: 0
guidanceIntoUnknownCount: 0
staleActionEmissionCount: 0
expectedActionMismatchCount: 0
healthMismatchCount: 0
alertMismatchCount: 0
```

Candidate predictions в этом replay не использовались. Поэтому результат не
доказывает downstream equivalence YOLO11/YOLO26 и не может использоваться для
их promotion.

## Depth challengers

Depth Anything V2 Small 256/320 не конвертирован: checkpoint и зафиксированный
license/provenance artifact отсутствуют. Создавать фиктивные outputs или
называть MiDaS результат DA-V2 benchmark недопустимо. MiDaS остаётся control.

Нужны:

- exact DA-V2 checkpoint + hash/license;
- reproducible ONNX/NCNN conversion;
- одинаковые privacy-approved frames для reference/native;
- spatial rank correlation, edges, thin obstacle/drop response и flicker;
- downstream hazard/replay metrics;
- named-device latency/memory/thermal.

## Traversability

PP-LiteSeg-T, DeepLabV3-MobileNetV3-Small и PP-MobileSeg исследованы только как
матрица кандидатов плана. Выбор модели отложен, потому что в репозитории нет ни
одного converted artifact и нет масок с curb/stair/drop boundaries.

Segmentation по-прежнему не является safety authority и не может снижать
geometry risk.

## Exit gate Этапа 6

| Gate | Evidence | Статус |
| --- | --- | --- |
| один выбранный detector | pinned YOLOv8 production control | pass |
| control/selected depth per tier | explicit four-tier selection; focal tier fails degraded | pass policy-only |
| traversability selected или defer | documented defer with missing prerequisites | pass |
| reproducible exports/hashes | export script, lock file, manifest, Dart hash tests | pass |
| candidate tensor contracts | ONNX checker + pinned shapes + separate YOLO26 decoder | pass |
| desktop artifact smoke | deterministic seeded ORT run | pass smoke-only |
| recorded detector correctness | corpus отсутствует | blocked |
| candidate downstream replay | real candidate predictions отсутствуют | blocked |
| MiDaS native/reference parity | reference fixture отсутствует | blocked |
| DA-V2 comparison | checkpoint/conversion отсутствуют | blocked |
| license approval | control provenance и candidate distribution не утверждены | blocked |
| named-device performance | phone run не выполнялся | blocked |

## Выполненные проверки

На 2026-09-20 выполнены:

- `dart analyze` — no issues found;
- `flutter test` — 984 tests passed, 1 skipped после Stage 7 integration;
- `model_export/venv/Scripts/python.exe model_export/export_candidates.py` —
  три ONNX candidate artifacts и control contracts подтверждены;
- `model_export/venv/Scripts/python.exe tool/model_benchmark/run_smoke.py
  --iterations 20` — три candidate smoke-проверки пройдены;
- `dart run tool/build_spatial_corpus.dart --check` — 19 generated corpus
  files совпадают с генератором;
- `dart run tool/report_spatial_metrics.dart --rc --output
  docs/_baseline_logs/spatial_replay_rc.json` — production-control replay
  прошёл с нулём нарушений во всех шести safety counters;
- scoped `git diff --check` — whitespace errors отсутствуют.

Единственный skipped test — native/reference NCNN correlation: в репозитории
нет `test/fixtures/ncnn_contract/reference_outputs.json`. Это отражённый выше
blocked gate, а не подтверждённая parity.

Итог: инфраструктура bake-off и rollback-safe selection готовы, но полный
Этап 6 не закрыт. Переход на новую модель запрещён до закрытия blocked gates.

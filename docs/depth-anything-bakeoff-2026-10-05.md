# MiDaS → Depth Anything V2 Small: результат первого эксперимента

Дата: 2026-10-05. Цель — Android среднего класса с 6–8 ГБ RAM; физического телефона пока нет.

**Решение: текущую замену отклонить.** Все экспорты успешно воспроизводят исходную нейросеть, однако текущая геометрия/планировщик Bagdar хуже работает с её картами. Вариант 280 пропускает два первых опасных кадра, вариант 336 увеличивает ложные остановки. На desktop CPU оба существенно дороже MiDaS. Это результат настоящего inference, а не подставленных oracle-карт.

Рабочие модели приложения остаются YOLOv8n INT8 416 и MiDaS Small NCNN 256. Новые веса лежат вне `assets/`, новый offline-адаптер не зарегистрирован в `DepthProviderFactory`; camera/model selection и пороги существующего runtime не изменены. Все действия эксперимента имеют `delivery=shadow`, `promotionAllowed=false`.

## Сопоставимые результаты

Один CPU-поток, Windows, AMD Ryzen 5 7535HS, около 16 ГБ RAM. По 3 прогрева и 18 измеренных inference на вариант, один проход; очередность фиксирована. Это предварительное desktop-сравнение, не sustained benchmark телефона.

| Карта глубины | Остановки на опасных кадрах / 12 | Опасные кадры без остановки / 12 | `continueForward` на опасности | Ложные остановки / 6 | Desktop image→map p50 / p95, мс | Размер NCNN весов, MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MiDaS, контроль | 12 | 0 | 0 | 3 | 113.1 / 138.1 | 33.2 |
| DA-V2 Small 280, FP32 weights | 10 | 2 | 2 | 6 | 525.0 / 560.3 | 97.5 |
| DA-V2 Small 280, FP16 weights | 10 | 2 | 2 | 6 | 522.5 / 740.7 | 49.3 |
| DA-V2 Small 336, FP32 weights | 12 | 0 | 0 | 6 | 814.6 / 928.1 | 97.9 |
| DA-V2 Small 336, FP16 weights | 12 | 0 | 0 | 6 | 800.6 / 840.4 | 49.6 |

MB = 1,000,000 bytes; размер файла не равен RAM процесса. NCNN здесь исполняет FP32 на CPU для обеих версий весов. FP16 уменьшает файл примерно вдвое, но этот прогон не подтверждает ускорение ARM FP16, Vulkan или NPU. PSS, память мобильного процесса, нагрев, батарея и 30-минутная устойчивость — `not_run`.

У DA-V2 280 два опасных `continueForward`: `context-thin-pole/f0` и `context-overhead/f0`, правило `SPATIAL-P3-NO-CHANGE`. Регрессия одинакова для FP32 и FP16 весов. Порог допуска не ослаблен: ноль unsafe continue, число остановок не ниже контроля, число false stops не выше контроля. **Все четыре NCNN-кандидата провалили quality admission.** Диагностический тест успешно измеряет отказ; отдельный admission-test завершился с ошибкой, как и должен для этих результатов.

У контроля три false stop приходятся на дверной проход. DA-V2 сохраняет их и дополнительно останавливается на всех трёх кадрах рампы; правило в обоих случаях `SPATIAL-P0-DEGRADED-MOVING`. Это консервативные остановки существующей логики, а не шесть успешно распознанных опасных объектов. Высокая уверенность в плоскости земли сама по себе не доказывает свободный проход или headroom.

Это покадровые числа на шести коротких синтетических сценах, не точность на улице и не число независимых инцидентов. Остановка по неизвестной области учитывается в этих числах; 12/12 не означает, что модель распознала все препятствия. Обычный относительный runtime может принять `continueForward` на опасном кадре новой модели — поэтому одной проверки конечности/нормализации карты недостаточно для замены.

## Что именно было проверено

Корпус `blender-context-v3`: шесть сцен по три RGB-кадра, 256×192; тонкий столб, низкое препятствие, препятствие на уровне головы, пересекающий велосипедист, рампа и дверной проход. 12 hazard-кадров, 6 passable. SHA256 corpus manifest: `3c5e9398fe5d4ed72fa4950a8d30b478fb625abe06658661975a2f01e0ebb82c`.

Сохранены **180 результатов измеренных neural inference**: MiDaS NCNN; DA-V2 PyTorch 280/336/518; ONNX 280/336; NCNN FP32/FP16 weights 280/336. Прогрев и проверки при экспорте выполнялись дополнительно. Для каждого кадра сохранены raw float32 map, RGB SHA, map SHA, frame index, source timestamp и отдельные времена preprocessing/inference/alignment. SHA текущих production weights, `pubspec.yaml` и `model_service.dart` совпали с состоянием перед экспериментом.

В downstream проверке 90 карт — контроль и четыре NCNN-кандидата — прошли реальные `GenericObstacleDetector`, `GenericObstacleTracker`, semantic matcher и `SpatialSafetyRuntime`. Код этих компонентов в эксперименте не менялся. Использован один зафиксированный набор результатов YOLOv8n 416 для всех моделей. На данном корпусе у него **ноль detections** при установленном пороге 0.25: semantic enrichment не спасает геометрию. Это также не оценка скорости совместной работы YOLO и depth.

GT depth/semantic images используются только для независимого scoring после neural inference. Planner не получает oracle, metres, полную геометрию Blender или невидимые поверхности.

Общее соответствие порядку истинной обратной глубины (mean per-frame Spearman rho) улучшилось: MiDaS 0.7069 → DA-V2 280 0.7454 → DA-V2 336 0.7709. Но ordering на парах около границ ухудшился: 0.8940 → 0.8898 → 0.8856. Пример показывает, почему общий depth score не заменяет пропуски опасностей и ложные остановки.

PyTorch 518: rho 0.7319, boundary ordering 0.8981, desktop p50/p95 2931.4/3222.9 мс. Более крупный вход здесь не гарантировал лучший общий результат. ONNX 280: 462.9/536.6 мс; ONNX 336: 698.6/724.7 мс. Эти варианты проверены на numerical parity; отдельного Android ONNX runtime в Bagdar нет.

## Экспорт и контракт

Официальный источник: [Depth Anything V2](https://github.com/DepthAnything/Depth-Anything-V2), [Small checkpoint](https://huggingface.co/depth-anything/Depth-Anything-V2-Small). Source commit `a561b849ebae10a6f5ef49e26c83cbbcd36c71bf`; HF revision `03876f8651c73a60fe4c2c48294e09fcb6838fcf`; checkpoint SHA256 `715fade13be8f229f8a70cc02066f656f2423a59effd0579197bbf57860e1378`. Small/source — Apache-2.0 по официальным файлам. Оригинальные исходники и checkpoint не редактировались.

Preprocessing DA-V2 следует официальному `image2tensor`: RGB, ImageNet mean/std, aspect-preserving cubic resize, размеры кратны 14. Для этого корпуса short side 280 означает `[1,3,280,378]`, 336 — `[1,3,336,448]`. ONNX/TorchScript/NCNN exports имеют **фиксированные shapes**; они не являются готовым универсальным camera-provider для иных aspect ratio. DA-V2 выдаёт относительную обратную глубину: больше = ближе; это не метры. Карта восстанавливается в исходные размеры bilinear `align_corners=True`, затем приводится к общему 256×256 diagnostic grid. MiDaS сохраняет свой RGB/255 input с нормализацией внутри графа; двойной ImageNet normalization не вводится.

Для сопоставления использован полный FOV обеих моделей. В обычном Android-пути MiDaS есть crop; результат этого full-FOV эксперимента нельзя объявлять parity с реальной YUV/crop/rotation pipeline телефона. Downstream normalization у всех replay-кандидатов выполняет существующий `DepthMapOps`.

Первый прямой NCNN export успешно создавал файлы, но PNNX предупреждал о неподдерживаемых batch reshape/broadcast; карты не совпали с reference. Результаты отвергнуты и сохранены в `rejected-original-attention-*`. Исправлена только export-копия модели: attention выражен через эквивалентный `nn.MultiheadAttention`, коэффициенты LayerScale перенесены в строки весов и bias соседних Linear. Это следует равенству `gamma*(W*x+b)=(gamma*W)*x+gamma*b`; обучения или изменения порогов не было.

Итоговый рецепт `explicit-MHA-folded-LayerScale-equivalent-v2` не содержит unsupported-operation warnings. Проверены все **108** ONNX/NCNN-vs-PyTorch пары на одинаковых кадрах. Gate: rho ≥0.999, MAE нормализованной карты ≤0.002, p99 error ≤0.01. Фактически minimum rho 0.999804, maximum MAE 0.001258, maximum p99 0.006811. Numerical export gate прошёл; quality admission не прошёл.

Версии: Python 3.11.9, Torch 2.11.0 CPU, ONNX 1.22.0, ONNX Runtime 1.30.0, PNNX 20260526, NCNN 1.0.20260526. MiDaS и кандидат измерены одним NCNN CPU runtime с одинаковыми thread/FP32 execution options. Экспортные зависимости установлены в отдельном `conversion_env`; Android NCNN binary не обновлялся.

## Границы измерений

Image→map timer включает чтение/декодирование файла, preprocessing, inference, восстановление размеров и percentile normalization. Не включает камеру, ожидание scheduler, перенос в Dart, geometry/tracking, semantic fusion и предупреждения. Initialization записан отдельно. Фиксированная очередность и один 18-frame проход позволяют диагностировать порядок затрат, но не дают статистической уверенности для небольших различий FP32/FP16.

Shadow replay использует функциональное время capture+2 ms и diagnostic quality=1, чтобы сравнить модели при одинаковом входе. Это **не measured end-to-end latency**, не доказательство своевременности остановок и не проверка health Android-provider. Confidence coverage не превращается в сертификат наблюдаемости. Temporal screen-grid delta включает движение камеры; motion-compensated flicker здесь не измерен.

Offline-адаптер проверяет SHA, RGB association, размеры/float32 bytes, NaN/Inf, degenerate map, future/stale timestamp и возвращает собственные buffers. Ошибки не становятся пустой безопасной сценой. Существующие deadlines, fail-closed policy и shadow mode сохранены; fast-motion 100 ms не менялся.

## Воспроизведение

Запуск из корня Bagdar, PowerShell. Нужен уже существующий `model_export/venv` с указанными версиями Torch/ONNX/ORT/OpenCV/NumPy/Pillow. Большие generated models, maps и environment не добавляются в Git; manifests/scripts сохраняются. До первого запуска:

```powershell
python -m venv model_export/depth_anything_v2/conversion_env
& .\model_export\depth_anything_v2\conversion_env\Scripts\python.exe -m pip install --no-deps -r model_export/depth_anything_v2/requirements-conversion.txt
& .\model_export\venv\Scripts\python.exe model_export/prepare_depth_anything_v2.py
```

Для проверки уже подготовленных source/checkpoint и нового inference:

```powershell
& .\model_export\venv\Scripts\python.exe model_export/prepare_depth_anything_v2.py --check
& .\model_export\venv\Scripts\python.exe tool/model_benchmark/run_depth_anything_bakeoff.py
& C:\src\flutter\bin\flutter.bat test --no-pub --concurrency=1 --dart-define=BAGDAR_DEPTH_BAKEOFF_REQUIRED=true --dart-define=BAGDAR_WRITE_DEPTH_BAKEOFF=true test/experimental_relative_depth_replay_provider_test.dart test/depth_anything_shadow_bakeoff_test.dart
& .\model_export\venv\Scripts\python.exe tool/model_benchmark/verify_depth_anything_bakeoff.py
& .\model_export\venv\Scripts\python.exe -m unittest discover -s tool/model_benchmark -p test_depth_candidate_common.py -v
```

Отдельный quality gate ниже **ожидаемо FAIL** на текущих кандидатах. Не ослаблять его ради зелёного результата:

```powershell
& C:\src\flutter\bin\flutter.bat test --no-pub --concurrency=1 --dart-define=BAGDAR_DEPTH_BAKEOFF_REQUIRED=true --dart-define=BAGDAR_DEPTH_CANDIDATE_ADMISSION_REQUIRED=true test/depth_anything_shadow_bakeoff_test.dart
```

Evidence directory: `scratch/depth-anything-v2-bakeoff-2026-10-05/`. В нём `inference-report.json`, `shadow-runtime-report.json`, `verification-receipt.json`, `maps/`, conversion logs, rejected receipts и production controls. Export identity/hashes: `model_export/depth_anything_v2/source-manifest.json`, `export-manifest.json`. Software-check logs: `scratch/depth-anything-v2-flutter-final-targeted.log`, `depth-anything-v2-candidate-admission-gate.log`, `depth-anything-v2-flutter-full-suite.log`, `depth-anything-v2-final-analyze.log`.

Небольшая копия проверенного результата для Git/review: `docs/_baseline_logs/depth_anything_bakeoff_receipt_2026-10-05.json`. Она содержит hashes inference/shadow receipts, worst-case numerical parity и полный quality admission всех пяти вариантов; большие карты восстанавливаются указанными командами.

Финальные software checks:

- `flutter analyze --no-pub`: no issues, 158.5 s.
- Целевые Flutter tests: 5/5 PASS, включая 90 shadow frames и negative input/identity/age cases.
- Python helper tests: 5/5 PASS (hash/path admission, invalid maps, ties/direction, parity rejection, oracle boundary ordering).
- Полный `flutter test --no-pub --concurrency=1`: **1697 PASS, 1 skip**, 24 min 53 s, exit 0. Подготовленный DA-V2 diagnostic входит в этот прогон.
- Source/checkpoint hashes и verifier: PASS; 180 maps, 108 numerical comparisons, 90 shadow frames; production controls unchanged.
- Отдельный candidate quality admission: **FAIL / rejected**, exit 1. Это отказ допуска модели по установленным критериям, а не ошибка диагностического прогона.

Эти проверки не заменяют полный Core RC, Android build/runtime, named-device profile или controlled walking. В данном этапе новый Core RC и Android сборка не запускались: Android provider и production path не менялись. Статус и hashes локальных check logs: `docs/_baseline_logs/depth_anything_bakeoff_software_checks_2026-10-05.json`.

## Следующий ограниченный этап

Для комфортной работы среднего класса разумнее сохранить текущий control и закончить измерение совместной нагрузки, copies/preprocessing и scheduler по существующему `phone-performance-plan-2026-10-05.md`. Уже реализованные worker/feedback оптимизации не повторялись в этом эксперименте. Наличие 6–8 ГБ RAM само по себе не задаёт скорость CPU/GPU и доступность ускорителей.

Если возвращаться к Depth Anything, сначала нужен отдельный development-corpus для адаптации relative geometry, затем замороженный holdout с тонкими, низкими и верхними препятствиями, проходами и degraded входами. Калибровку нельзя подгонять на этих же шести сценах и называть независимым улучшением. Интеграция допустима лишь после отсутствия регрессий downstream и полноценного Android gate.

Без телефона можно проверять новые экспорты/INT8 calibration, input transforms и software failure paths. Phone latency/PSS/thermal/TalkBack/30-minute release behavior остаются `not_run`; device protocol уже подготовлен. Одновременная замена YOLO и depth не обоснована. Повышать freshness TTL или объявлять относительную глубину метрической ради новой модели нельзя.

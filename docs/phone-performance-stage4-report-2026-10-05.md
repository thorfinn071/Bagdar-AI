# Bagdar: независимый запуск YOLO и depth

Дата: 2026-10-05. Цель — Android среднего класса с 6–8 ГБ RAM.
Физического телефона для измерений пока нет. Работа начата 5 октября;
финальная compilation/RC проверка продолжена 6 октября после прерывания.

## Изменение runtime

Раньше `_onFrame` запускал depth только после завершения успешного YOLO.
Если YOLO занят, не готов или ещё не наступил его интервал, callback возвращался
до проверки depth. Поэтому кадр для depth уже успевал состариться во время YOLO,
а доступность depth зависела от другого распознавателя.

Теперь `PerceptionScheduler` выбирает запуск независимо для каждой модели.
За один callback стартует максимум одна модель. На следующем свежем callback
другая свободная модель может начать работу, пока первая ещё вычисляет результат.
Если обе готовы к запуску, приоритет чередуется. Существующие cadence и thermal
правила сохранены, включая редкий ground-safety проход при critical thermal.

Ограничения: один активный вызов на модель, максимум два одновременно,
**ноль кадров в очереди scheduler**. Busy callbacks не заменяют владельца
активного результата и не сохраняют пиксели для последующей обработки.
Существующий NCNN worker по-прежнему имеет собственный bounded admission
«один active + один newest pending»; screen scheduler не подаёт туда busy кадры.
Каждый async вызов освобождает свой ticket в `finally`.

Модели, backend, число threads, preprocessing и параметры распознавания не
менялись. Контроли остаются YOLOv8n INT8 и MiDaS Small NCNN. Depth Anything V2
остаётся offline-кандидатом, отклонённым предыдущим сравнением.

## Свежесть и совместимость

- YOLO проверяет поколение камеры, владельца ticket, полный elapsed age,
  размер кадра, rotation и mirror до native dispatch и перед применением.
  Размеры и номер кадра при обработке берутся из исходного callback.
- Background/dispose закрывает допуск новых callbacks. Старый native вызов
  удерживает screen slot до terminal Future reply; resume не открывает второй
  вызов поверх незавершённого Future. Результат старой сессии не применяется.
  Если provider deadline завершил Future раньше native inference, физическое
  владение сохраняет существующий NCNN worker до actual completion; его pending
  queue остаётся отдельно bounded. Screen timeout не отменяет native работу.
- Depth сохраняет существующие guards generation/frame/header/latency.
  Добавлена проверка текущего rotation/mirror перед fusion и release.
- YOLO semantic context для depth фиксируется при submission и принимается
  только при одинаковых размерах/transform и разнице source timestamps
  **от 0 до 150 мс**. Это существующий image-alignment budget CameraSession.
  Future timestamp и несовместимый старый контекст не используются.
  Дополнительный semantic freshness limit 1.5 с сохранён.
- Новая сессия очищает semantic и hazard-confidence caches.

Обычный controller/scheduler age limit — прежние **2 с**. Это защитный предел,
не цель комфортной задержки. Независимый fast-motion контракт **100 мс** не
менялся. Отсутствие подходящей семантики не означает отсутствие препятствия:
depth продолжает работать с геометрией и unknown.

Снижение зависимости от YOLO не доказывает улучшение hazard recall. При более
строгом alignment часть semantic enrichment может не пройти допуск; совместная
проверка предупреждений на движущейся camera recording и телефоне остаётся gate.

## Desktop сравнение с реальными моделями

`tool/model_benchmark/compare_core_scheduling.py` запускает настоящие
YOLO TFLite и MiDaS NCNN в двух постоянных процессах. По одному CPU thread на
модель, без GPU. 18 hash-verified Blender RGB кадров, 3 counterbalanced повтора,
54 trials для каждого из трёх режимов: **162 trials / 324 measured model calls**,
плюс 6 warm-up calls. Все raw tensors finite; их SHA-256 для одного кадра
побайтово совпали между режимами и повторами. Model errors: **0**.

| Режим | YOLO source→reply p50/p95, мс | MiDaS source→reply p50/p95, мс |
|---|---:|---:|
| YOLO, затем depth того же кадра | 82.6 / 97.7 | 218.5 / 254.9 |
| Depth на следующем callback | 97.0 / 111.8 | 147.8 / 162.9 |
| Одновременный старт обеих моделей, diagnostic | 109.0 / 119.2 | 156.7 / 172.0 |

В выбранном режиме age результата MiDaS уменьшился на **32% по p50** и
**36% по p95**; YOLO p50 вырос на **18%** из-за конкуренции за CPU.
Стоимость самого depth вызова выросла: dispatch→reply p50 137.2 → 147.7 мс.
Выигрыш в возрасте получен устранением ожидания YOLO и выбором нового callback,
а не ускорением нейросети.

В staggered trial следующий callback имитируется через 33 мс, и RGB повторяется
в пределах статического trial. Его clock начинается заново, как у свежего
callback; это **не новый реально снятый кадр**. Измерение включает desktop
IPC, чтение/подготовку RGB, inference, копирование и hash/reply. Оно исключает
Android YUV/crop, production Dart scheduler, geometry, UI, speech и thermals.
TensorFlow 2.21.0 и NCNN 1.0.20260114 на Windows отличаются от Android runtime.
Сравнение не является end-to-end latency, hazard benchmark или phone validation.

Raw trials и controls:
[`phone_performance_stage4_scheduling_2026-10-05.json`](_baseline_logs/phone_performance_stage4_scheduling_2026-10-05.json).

## Telemetry и проверки

В `perception_performance_window` добавлены `acceptedYoloFps`, rejected results,
pre-dispatch drops, staggered skips и callback→dispatch для обеих моделей.
Completed native calls продолжают учитываться отдельно от принятых результатов.
YOLO round-trip denominator включает поздние completed calls. Callback origin
по-прежнему Dart camera callback; sensor capture time неизвестно.
`callbackPreDispatch` описывает синхронный пролог, а `callbackWork` — wall time
callback с async ожиданиями; его нельзя трактовать как UI busy time.

Целевой frozen набор: **59/59 pass**. Добавлено 18 cases: pending YOLO и
независимый depth, 10 000 busy callbacks без очереди/superseding, fairness,
background/resume ownership, stale/future/transform guards, source alignment
на границах 150 мс, cache reset, current transform change во время inference,
различение completed/accepted/pre-dispatch drops. Existing worker/controller
negative cases и real-map MiDaS/Depth Anything shadow replay прошли.

Первый expanded targeted run не скомпилировал новый test fixture: отсутствовал
обязательный `confidence01`. Fixture исправлен; исходный failed log сохранён,
final 59-case run прошёл. Runtime для устранения этого сбоя не менялся.

Android Core **profile и release compilation прошли**:
`flutter build apk --flavor core --profile --target-platform android-arm64 --split-per-abi`
и `flutter build apk --flavor core --release --target-platform android-arm64 --split-per-abi`.
Profile APK после проверенной упаковки — 151249119 bytes; release APK —
**123898921 bytes / 118.16 MiB**.
В обоих APK только `arm64-v8a`; все три model assets побайтово совпадают с
исходными контролями. Android 11/API 30+ и существующая debug signing key
сохранены. APK не устанавливались и не запускались.

Profile compilation завершилась успешно, но первый capture wrapper ошибся
в порядке частей имени APK при копировании. Исправлен путь к уже собранному
artifact; повторный profile build не выдаётся за дополнительное подтверждение.
Release compilation прошла после этого отдельно. Raw build logs и metadata
сохранены в `scratch/phone-performance-stage4-2026-10-05`.

В повторном profile artifact обнаружен 11 MB промежуток между ZIP entries:
payload sizes не увеличились, но incremental APK занимал 162268104 bytes.
Автоматическая проверка отклонила очистку временных Gradle package files с
причиной `blocked by policy`; очистка не выполнялась. Вместо неё Android
build-tools 36.1.0 `zipalign -P 16 4` создал отдельный компактный APK, затем
`apksigner` подписал его существующим debug key. Все 643 non-signature entries
побайтово совпали; certificate совпал, signature и 16 KB ZIP alignment прошли.
Исходный APK сохранён. Это проверка ZIP alignment, не доказательство ELF/device
совместимости со всеми 16 KB телефонами. Release пересобран отдельно после
прерывания и прошёл signature/alignment checks без переупаковки.

Отдельный review diff по девяти code/test/tool files сохранён в
`scratch/phone-performance-stage4-2026-10-05/changes-from-before-snapshot.diff`.
Он построен относительно before copies этого этапа, чтобы не смешивать правки
с прежними незакоммиченными изменениями. SHA-256 выбранных 16 source/control files
фиксирует проверяемую версию; это не fingerprint всего dirty checkout.

Полный analyzer — **no issues**, 192.8 с. Serial full Flutter suite —
**1715 pass, 0 fail, 1 expected skip**, 27 мин 12 с. Strict legacy harness —
**23/23 pass**. Единый финальный `tool/verify_core.ps1 -Rc` —
**59/59 required stages, pass**, включая corpus integrity, frozen replay
reproducibility, настоящие NCNN/ONNX outputs, artifact/hash/decoder contracts,
ONNX↔NCNN parity и whitespace. `AndroidBuild=False` в aggregate receipt:
profile/release compilation подтверждены отдельными build logs выше.

После завершения совпали SHA-256 всех 16 выбранных source/control files;
ModelService, PerformanceThrottler и три model assets совпали также с before
hashes. Веса в обоих итоговых APK проверены повторно. Машинный итог:
[`phone_performance_stage4_receipt_2026-10-05.json`](_baseline_logs/phone_performance_stage4_receipt_2026-10-05.json).
`desktopSoftwareRc=pass`, `modelCorrectnessRc=not_established`,
`namedDeviceRuntime=not_run`, `controlledWalking=not_run`.

Первый aggregate остановлен после analyzer: 9 lint infos требовали фигурных
скобок в новых условиях. Добавлены блоки без изменения поведения, scoped
analyzer на восьми затронутых файлах — no issues, 59-case targeted suite
повторён успешно. Initial aborted log и исходные successful APK сохранены.
Итоговые сборки и полный RC повторены на новой source freeze успешно.

## Граница доказательств

Весовые файлы сохранены; controls записаны в raw benchmark и финальном receipt.
Relative depth не переводится в метры. Generic obstacle delivery остаётся
shadow, `promotionAllowed=false`. Native feedback и fast-motion promotion не
менялись. APK compilation не доказывает работу камеры, стабильность памяти,
нагрев, качество предупреждений или TalkBack на телефоне.

Для mobile performance gate нужны baseline и candidate на одном именованном
устройстве: camera→accepted result→feedback, missed hazards/false stops,
frame timing, PSS/heap и sustained thermal session. Протокол остаётся в
[`phone-performance-protocol-2026-10-05.md`](phone-performance-protocol-2026-10-05.md).

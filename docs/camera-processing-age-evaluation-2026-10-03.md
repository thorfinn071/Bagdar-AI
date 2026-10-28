# Задержки и возраст camera evidence — 2026-10-03

Реализован отдельный opt-in shadow этап: cached scale matcher, контроль возраста
до/после вычисления и перед применением, bounded latest-frame queue, проверка
истечения срока во время полного scene/planner решения. Прежние frozen sources,
models, labels и отчёты сохраняются. `promotionAllowed=false`.

## Реализация

`CameraCachedScaleMetricMotionSource` сохраняет алгоритм scale-motion-v1:
48 разнесённых признаков, то же окно ±32 pixels, порядок photometric суммирования,
uniqueness/reverse consistency и интервалы метрической скорости. Optical axes
и bounds повторно используются только в пределах пары immutable frames;
bilinear адресация вычисляется один раз для трёх каналов. Cache ограничен двумя
кадрами и уничтожается при новой обработке/инвалидации. Нет IO, labels, masks,
mesh или hidden geometry. Относительная MiDaS depth не становится метрами.

`CameraProcessingAgeGate` получает продвигающийся clock в capture domain.
Возраст текущего capture <=100 ms проверяется до compute, после него и при
single-use release. Срок oldest+400 ms не расширен. Session/identity/order,
future/clock rollback, compute failure и provider invalidation уничтожают
право применения и старую motion pair. Очередь хранит один newest pending
frame, сохраняет исходные timestamps и явно считает overwritten/expired frames.
Пропуск кадров не подменяется повтором: pair gap >300 ms остаётся unknown.

Новый harness использует настоящий detector/tracker/passage/scene/planner.
После runtime вычисления проверяется возраст всей цепочки. Просроченный clear
не выдаётся; existing `noteMissingObservation` переводит sensing в unknown
без сброса planner. Функциональные capture+2 ms, детерминированные задержки и
измеренные wall clocks публикуются раздельно.

## Evidence и ограничения

camera-scale-motion-v1 теперь известный regression corpus. Он не является
новым holdout этого этапа. Полные motion diagnostics сравниваются frozen/cached
на 109 decision inputs; 17 дополнительных invalid/ambiguous cases сравнивают
тот же контракт. Полная runtime цепочка сравнивается на прежних 67 test decisions.
Labels читаются scorer после решения. Тесты не устанавливают общую точность
на естественных телефонных RGB или пригодность controlled walking.

Warmed matcher profiling выполняется в Flutter tester / Dart JIT: один полный
прогрев, три измеренных traversal и чередующийся порядок frozen/cached. RGB,
depth и input construction вынесены в отдельный fixture preload. Это compute
comparison на одном стенде, не Android/AOT ускорение. Полная стадия inference
измеряется отдельно живым закреплённым NCNN CPU worker, num_threads=1 и десять
warmup inference. Каждый float32 output побайтно совпадает с pinned output.
Elapsed replay включает IPC/validation и фактическое старение, но исключает
phone capture/transport, rendering, TTS/haptics и preload synthetic depth.

При строгом возрасте данных safe stop из unavailable не считается успешным
наблюдением движения. Functional accuracy и elapsed utility различаются.
В частности, единственный достаточно наблюдаемый wide control может получить
ложную остановку, если все его packets просрочены. Нулевой unsafe continue
при постоянной неизвестности не подтверждает полезность системы.

## Результаты

Полные JSON motion diagnostics совпали с frozen source на 109/109 inputs;
на известных approach scenes сохранились 18/18 пар добавления риска.
67/67 runtime решений совпали по motion, action, planner state, passage status
и факту применения риска. Сохраняются 9/9 функциональных on-time stops,
zero unsafe continue/unjustified clear и 0/1 false stop/hold на wide control.
Это результаты fixed-clock regression, не measured reaction.

| Preloaded warmed matcher, 327 измерений на ветку | p50, ms | p95, ms |
|---|---:|---:|
| Frozen scale matcher | 279,00 | 312,29 |
| Cached scale matcher | 166,87 | 186,10 |

Ускорение p50 около 40%. Пороги и полные outputs сохраняются. Fixture preload
измеряется отдельно; ускорение всего phone pipeline не установлено.

| Новая preloaded functional цепочка, отдельно от NN | p50, ms | p95, ms |
|---|---:|---:|
| Relative normalization | 30,37 | 37,26 |
| Detector + tracker | 4,60 | 10,56 |
| Passage reconstruction | 33,61 | 105,34 |
| Motion, включая создание immutable input | 173,72 | 237,54 |
| Runtime association/fusion/planner | 26,89 | 38,24 |
| Фактическая сумма compute в одном traversal | 267,76 | 423,59 |

Хранится в `camera_processing_pipeline_profile.json`. Clock этого traversal
остаётся fixed для comparison, поэтому timings не являются capture-to-command.
Fixture preload всех test inputs занял 4023,87 ms вне compute. Новый harness
не повторяет standalone диагностическую оценку passage перед runtime: решение
контракта выполняет сам runtime. Сравнение с прежними отдельными stage timings
не доказывает ускорение всей цепочки из-за разных состава и условий замера.

| Живой pinned NCNN CPU elapsed replay, 67 кадров | p50, ms | p95, ms |
|---|---:|---:|
| Preprocessing predecoded RGB | 2,15 | 2,71 |
| Inference | 106,07 | 119,69 |
| Возраст текущего capture при выдаче unavailable decision | 112,56 | 127,03 |

Все **67/67** results просрочены уже после NN, до motion compute. Stale application,
unsafe continue и unjustified clear — **0**. Fresh hazard-evidence stops — **0**;
motion risk не применяется. На девяти опасных сценах есть 9/9 своевременных
функциональных stop/held-stop outcomes, но все они обусловлены unavailable
sensing, а не распознанным движением. Mixed onset учитывает уже действующую
остановку с holdAndScan; это не новая реакция на hazard. Wide control получает
**1/1 false stop** вместо functional continue. Полезность real-time режима
не подтверждена. NN сам превышает сохранённый budget на этом desktop стенде.

Детерминированные 500 ms overload сохраняют bounded queue: 29 processed packets,
19 overwritten и 19 expired pending frames. Применение stale motion/clear — 0.
Наблюдаемый wide остаётся holdAndScan, false hold 1/1. В отдельном runtime-overrun
эксперименте настоящая цепочка сначала выдаёт continueForward; добавленное
100 ms старение перед release отбрасывает **одно** такое решение и возвращает
unknown/hold. Положительный контроль проверяет именно поздний clear, а не
случай, где planner и до задержки уже остановился.

## Полная программная проверка

В одном полном aggregate запуске прошли **1512 Flutter tests**, **23 strict
legacy scenarios**, чистый analyzer и **44/44 обязательных gates Core RC**.
Прежние frozen sources, pinned model outputs и функциональные отчёты совпали;
`git diff --check` прошёл. Два обязательных gates нового этапа включают
write-once contract integrity и parity/deadline/overload/runtime-overrun replay.

Receipt: `scratch/verification-camera-processing-age/core-verification.json`.
Полный log: `scratch/core-camera-processing-age.log`.
`desktopSoftwareRc=pass`, `modelCorrectnessRc=not_established`;
`androidBuild`, `namedDeviceRuntime`, `controlledWalking` — `not_run`.
Этот результат подтверждает программные ограничения и воспроизводимость,
а не способность выдавать полезные активные подсказки в реальном времени.

## Воспроизведение

```powershell
dart run tool/model_benchmark/evaluate_camera_processing_age.dart --check
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_camera_processing_age.py --check
dart run tool/model_benchmark/evaluate_camera_processing_age.dart --measure
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-processing-age
```

Functional/parity/deadline reports и write-once contract находятся в
`docs/_baseline_logs/camera_processing_*`. Variable timings не входят в
reproducibility receipt. `--measure` обновляет только данные этого нового этапа.
Android build, calibration, named-device runtime и controlled walking не запускались.

Следующее архитектурное решение должно отделить свежую RGB/metric-depth/pose
ветку риска от медленного относительного NN пути и проверить исполнение вне
блокирующего UI потока. Для такого отделения потребуются собственные provider
identity/health/clock contracts и новые проверки; фиктивное обновление timestamps
или расширение TTL не решают текущую проблему.

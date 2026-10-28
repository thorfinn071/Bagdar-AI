# План производительности Bagdar на Android

Дата: 2026-10-05, Asia/Qyzylorda.

Статус: первый software-этап реализован — постоянный NCNN worker, контекст кадра, учёт callback-to-decision и ограниченная telemetry. Final analyze, 73 целевых tests и Core arm64 profile/release compilation прошли; первоначальный RC и адресные повторы описаны в `phone-performance-stage1-report-2026-10-05.md`. Native capture/output correlation и named-device baseline остаются незавершёнными частями P0. Device-протокол — в `phone-performance-protocol-2026-10-05.md`. Модель телефона, SoC, RAM и версия Android пока неизвестны. `adb devices -l` не показывает подключённых устройств. Целевой минимум определяется измерениями; текущая сборка требует Android 11 / API 30.

Второй software-этап реализован: отмена/свежесть TTS при async preparation,
один общий backend stop, bounded sentence timer, critical fallback и arm64 APK
без native libraries других архитектур. Финальные 80 целевых tests и analyze
прошли; две release-сборки подтвердили уменьшение 339.9 → 118.1 MiB при одинаковых
arm64/asset payloads. Core RC прошёл 59/59, 1677 Flutter tests + один skip до
последней правки critical fallback; после неё проверены целевые tests/analyze,
а новая Gradle-конфигурация проверена обеими сборками. Полный единый RC после
этих последних правок не повторялся. Evidence boundaries и артефакты —
в `phone-performance-stage2-report-2026-10-05.md`. Device runtime остаётся `not_run`.

Четвёртый software-этап реализует независимый запуск YOLO/depth на разных свежих
callbacks: один active на модель, без очереди screen scheduler, с проверкой
generation/age/transform и совместимости semantic context. Контроли MiDaS/YOLO
сохранены. Desktop scheduling diagnostic дал depth source→reply p50/p95
218.5/254.9 → 147.8/162.9 мс, при росте YOLO p50 82.6 → 97.0 мс.
Это статические RGB trials, а не mobile или hazard latency. 59 targeted cases,
1715 full-suite tests + один skip, 59/59 required Core RC stages и Core arm64
profile/release compilation прошли. Device boundaries и receipts — в
[`phone-performance-stage4-report-2026-10-05.md`](phone-performance-stage4-report-2026-10-05.md).

## Цель и область работы

Добиться устойчивой работы Core: отзывчивый интерфейс, своевременные решения по свежим кадрам, корректные предупреждения, отсутствие накопления очередей и памяти, приемлемые нагрев и расход батареи в длительной сессии. Производительность оценивается вместе с пропусками опасностей и ложными предупреждениями.

Основной путь: камера → качество кадра → YOLO / relative NCNN depth → tracking / geometry / safety arbitration → TTS / vibration. Проверяются также запуск, остановка, восстановление камеры, настройка речи, ручной SOS и fall countdown. Проверки SOS используют тестовый transport; реальные сообщения не отправляются.

Research-функции не включаются ради benchmark. Native fast motion, metric depth и сканирование проходов — отдельные условные этапы после основного Core. Generic obstacles и новые ветки сохраняют `shadow`; `promotionAllowed=false` остаётся действующим ограничением.

## Исходные наблюдения до реализации первого этапа

| Наблюдение | Значение для плана | Источник |
| --- | --- | --- |
| `NcnnDepthProvider.analyzeDetailed()` синхронно вызывает FFI inference; явного worker вокруг этого runtime-пути нет | Native inference блокирует вызывающий Dart isolate. `async` и `unawaited` сами по себе не выносят вычисления с UI-пути. Вклад в миллисекундах на телефоне ещё не измерен | `lib/services/ncnn_depth_provider.dart`, `lib/services/ncnn_depth_bridge.dart`, `lib/camera/depth_pipeline_controller.dart` |
| Depth запускается после завершения YOLO и обновления tracks | Есть последовательное ожидание. Убирать его нужно с контролем конкуренции за CPU/GPU и соответствия кадров | `lib/camera_screen.dart`, `_onFrame`, `_processDepthAnalysis` |
| `cameraTimestampUs` и `receivedAtUs` равны времени Dart callback; `producedAtUs` строится как это время + длительность provider | Нет настоящего sensor capture timestamp; предшествующее ожидание YOLO не входит в эту формулу. Сначала исправить учёт времени и границы измеряемого участка | `lib/camera/depth_pipeline_controller.dart`, `_buildPacket`, построение observation |
| `_finalizeFramePerf()` увеличивает `_detectionCompletions` также на ранних выходах; эти значения используются в `effective_fps` и общей EMA throttler | FPS callback нельзя выдавать за FPS распознавания. Общая EMA коротких и тяжёлых callbacks не описывает inference latency | `lib/camera_screen.dart`, `_finalizeFramePerf`, heartbeat; `lib/utils/performance_throttler.dart` |
| YOLO-плагин уже отправляет `DetectionTask` в `ExecutorService` | Не требуется повторный перенос самого YOLO inference в Dart isolate; отдельно измерить marshaling, native preprocessing, task queue и возврат результата | установленный `flutter_vision-2.0.0`, `FlutterVisionPlugin.java`, `yoloOnFrame()` |
| Camera использует `ResolutionPreset.low`; battery/thermal/memory throttling уже существуют | Снижение разрешения и добавление ещё одного throttler не являются автоматическим первым исправлением; проверить фактические размеры YUV и нынешнюю политику | `lib/camera_screen.dart`, `lib/services/battery_monitor.dart`, `lib/services/thermal_monitor.dart`, `lib/services/memory_monitor.dart` |
| По отчёту load motion: 30/30 известных тестовых рисков вовремя под NCNN; fresh-risk p95 78–82 мс, максимум 93.215 мс | Это известный Windows workload с заранее загруженными входами. Native matcher Windows x64, ветка отключена от телефона; запас до 100 мс небольшой | `docs/camera-fast-motion-load-evaluation-2026-10-04.md` |
| Indexed scan под NCNN имеет desktop p50/p95 391/640 мс и не проходит 100 мс | Не включать тяжёлый scan в каждый кадр основного Core. Отдельное исследование его вычислений, покрытия и устаревания | `docs/blender-scan-processing-evaluation-2026-10-04.md` |
| Core не инициализирует большую часть Research-сервисов; независимая ARCore-камера заблокирована в обычном depth factory | Не приписывать Core нагрузку всех сервисов репозитория и не создавать второго владельца камеры | `README.md`, `lib/services/depth_provider.dart` |

Таблица описывает исходное состояние, изученное при составлении плана. Desktop load-результаты взяты из сохранённых отчётов и не являются измерением телефона. Проверки первого этапа описаны отдельно в отчёте реализации. Прежние 0/30 для старой fast-motion ветки не описывают новую Windows-реализацию.

## Порядок реализации

### 1. P0 — достоверное измерение и воспроизводимый baseline

Изменяемые точки: `lib/models/frame_packet.dart`, `lib/camera/depth_pipeline_controller.dart`, `lib/camera_screen.dart`, `lib/services/field_logger.dart`; новый ограниченный collector в `lib/core/performance/`. Если публичный camera stream не передаёт нужный timestamp, создать адаптер/fork в репозитории и native trace bridge в `android/app/src/main/kotlin/com/example/bagdar/`. Не редактировать Pub cache.

Действия:

- Зафиксировать для каждого кадра generation, frameId, размеры/strides, transform и identity моделей.
- Получать capture timestamp из native camera metadata. Проверить clock domain камеры, преобразование к монотонным часам Android и ошибку сопоставления; не считать любые sensor nanoseconds автоматически `elapsedRealtimeNanos`.
- Если timestamp пока недоступен, честно именовать метрику `callback-to-decision`; capture-to-decision остаётся unavailable.
- Отдельно измерять capture → native receipt → Dart receipt → packing/queue → preprocess → inference → postprocess → accepted decision → output request → TTS onStart / haptic dispatch.
- Учитывать ранее потраченное ожидание YOLO и время до финального применения результата; не создавать production timestamp прибавлением отдельного inference stopwatch к старому receipt.
- Разделить camera callbacks, реальные YOLO/depth completions, принятые свежие решения, busy/skipped/superseded/invalid/stale кадры и первый своевременный сигнал в каждом эпизоде опасности.
- Собирать p50/p95/p99, max, denominators и deadline misses; не исключать timeout и отклонённые результаты из итогового качества доставки.
- Измерять UI/raster frame timing, event-loop lag, PSS/native/Dart memory, GC, CPU scheduling, thermal status и энергопотребление. Ограничить telemetry буферы; измерить её собственную стоимость.

Новые артефакты: `tool/device_performance/` для воспроизводимого протокола и сбора результатов, `integration_test/core_performance_test.dart`, `docs/phone-performance-baseline-<device>-<date>.md`, raw traces вне Git. Baseline сохраняет commit/tree identity, model hashes, build mode/flavor, backend/threads, ОС, экран, заряд, яркость, тепловое состояние и порядок trials. До появления телефона эти результаты остаются `not_run`.

Gate: метрики различают поток камеры и полезное распознавание; clocks и rejection counters покрыты программными проверками. На устройстве фиксируются независимые baseline до изменений, short trace и длительная сессия. Профилирование — Core profile build, итоговое подтверждение — release build; эмулятор используется только для smoke correctness.

### 2. P1 — убрать блокирующий NCNN из UI-пути

Файлы: `lib/services/ncnn_depth_provider.dart`, `lib/services/ncnn_depth_bridge.dart`, `android/app/src/main/cpp/bagdar_depth_ncnn.cpp`; новый persistent worker в `lib/services/ncnn_depth_worker.dart`; controller остаётся владельцем допуска результатов.

Действия:

- Один постоянный worker владеет NCNN init/infer/dispose и, по результатам профиля, тяжёлым чистым postprocessing. Assets извлекаются до запуска worker; `rootBundle` и UI остаются на главном isolate.
- Учесть, что native global state разделяется между Dart isolates: запрещены параллельные init/dispose/infer одного NCNN context. Shutdown ждёт подтверждения освобождения; исключения и restart инвалидируют старую generation.
- Передавать immutable numeric buffers с минимальными копиями. Native output view копируется/передаётся до следующего inference; живые `CameraImage`, настройки и UI-объекты не становятся worker state.
- Ввести ограничение: один active + один newest pending кадр, ограниченные input/output pools, без роста FIFO.
- Busy, exception, timeout и invalid output означают unavailable/unknown, а не пустую безопасную сцену.
- Не допустить starvation из-за безусловного superseding active на каждом новом callback; приём результатов следует явной политике generation/identity/age.

Gate: parity с текущими preprocessing/depth/downstream решениями; bounds и память ограничены; старый worker не может влиять на новую сессию; UI/timers/critical output работают во время вычисления. Программная responsiveness проверка отдельно от реального device trace.

### 3. P1 — планировщик совместной нагрузки и свежие кадры

Файлы: `lib/camera_screen.dart`, `lib/camera/depth_pipeline_controller.dart`, `lib/utils/performance_throttler.dart`, `lib/services/model_service.dart`, `lib/viewmodels/camera_view_model.dart`.

Действия:

- Разделить расписания UI, YOLO, depth и output. Запуск depth не должен автоматически ждать YOLO того же callback.
- Сравнить bounded sequential/staggered и controlled parallel scheduling на одинаковых сценах; выбрать по возрасту полезных решений и sustained latency, а не по числу одновременно работающих потоков.
- Сохранять frame/timestamp/transform association. Semantic fusion использует совместимые текущие tracks; несовпадение не прикрывается последним известным результатом.
- Throttler получает реальные времена стадий, backlog, свежесть и доступность; ранние callbacks не уменьшают искусственно inference EMA.
- Резервировать своевременное выполнение critical feedback, ручного SOS и fall countdown. Дополнительные задачи получают bounded budget и явное состояние отложенной/недоступной функции.
- Устаревание проверяется при входе, завершении и применении. Отдельно описать текущий default controller latency limit 2 с и 100 мс контракта fast motion; не смешивать их и не увеличивать сроки ради зелёного benchmark.

Gate: нет очередей и незаметного смешивания данных; under-load timer/output deadline tests проходят; useful completion rate и timely hazard episodes не ухудшаются при новой cadence.

### 4. P2 — подбор backend и снижение стоимости кадра

Файлы: `lib/services/model_service.dart`, `lib/services/device_capability.dart`, NCNN provider/bridge/native code и measured hotspots preprocessing/geometry.

Действия:

- Сначала сохранить текущие YOLOv8n и MiDaS controls. Сравнить CPU thread counts 1/2/3/4, YOLO GPU on/off и NCNN CPU/Vulkan на конкретном устройстве; полный перебор всех сочетаний не нужен — staged shortlist после профиля.
- Для GPU учитывать preprocessing, transfer, CPU fallback, thread affinity, startup и конкуренцию с rendering; наличие GPU/NPU не означает поддержку текущего graph.
- Проверить фактическую активацию ускорителя и восстановление при ошибке backend. Выбор capabilities не основывать только на бренде и Android SDK.
- Уменьшать измеренные аллокации, сериализацию, повторные resize/normalization, geometry passes и frame logging; применять preallocated buffers и bounded immutable caches.
- Меньшее разрешение, другой model precision или новая модель — отдельный candidate только при проверке маленьких/тонких объектов, ступеней, нижних препятствий, temporal stability и downstream предупреждений. Менять по одному фактору.

Gate: одинаковые входы и чередующийся порядок A/B, не менее трёх повторений; улучшение полезной latency и отсутствующая регрессия correctness. Сравнение только одного inference kernel не заменяет целую цепочку.

### 5. P2 — sustained режим, запуск и взаимодействие

Файлы: `lib/utils/performance_throttler.dart`, `lib/services/thermal_monitor.dart`, `lib/services/memory_monitor.dart`, `lib/services/battery_monitor.dart`, `lib/services/tts_service.dart`, `lib/safety/alerts/bagdar_feedback_output.dart`, `lib/camera_screen.dart`, `lib/viewmodels/camera_view_model.dart`.

Действия:

- Повторить full Core 30 минут с concurrent models, camera preview, речью и TalkBack. Сравнить минуты 5–10 и 25–30; начальную загрузку считать отдельно.
- Управлять нагрузкой по thermal state, memory pressure и свежести, с hysteresis. Температура батареи — дополнительный сигнал, не замена SoC/OS thermal status.
- Проверить low battery/power saver, memory pressure, camera errors, screen/background/resume, orientation, audio routes и восстановление после звонка. Не стрессовать телефон неконтролируемой нагрузкой.
- Запускать необходимый Core прежде deferred функций, разделить first UI / first camera / first YOLO / first accepted depth / operational readiness. Не объявлять полную готовность только по открытой камере.
- Профилировать rebuild/repaint, частоту overlays и native callbacks. TTS preemption/queue и haptic request измеряются отдельными стадиями.
- TTS onStart и вызов vibration API — software milestones; фактический первый звук/вибрация требуют отдельного наблюдаемого замера.

Gate: нет crash/ANR/утечек и роста очередей, degraded state своевременно сообщается, camera/resources освобождаются, критический вывод не теряется. Более низкая температура за счёт молчаливого выключения нужной функции не считается успехом.

### 6. Условный этап — Android fast motion и metric provider

Приступать после основных Core bottlenecks либо при доказанной необходимости fast-motion функции. Портировать `tool/model_benchmark/native/fast_motion_match.c` через Android CMake/NDK, начиная с arm64-v8a, с явным ABI и parity gates. Не переписывать frozen Windows controls и receipts.

Нужно одновременно доказать доступность настоящих synchronized RGB / metric depth / pose, calibration, intrinsics, shared camera ownership и исходного capture clock. MiDaS relative depth нельзя подставить вместо metres. Если целевой телефон не предоставляет validated metric source, ветка остаётся unavailable/shadow; ускорение matcher само по себе не устраняет эту зависимость.

Gate: Android build/ABI, native parity, immutability, bounds, shutdown, original 100 мс admission under actual concurrent models и complete useful-risk denominators. Затем отдельная проверка hazard/passable discrimination. Scan с несколькими видами не включается в основной цикл, пока не доказаны стоимость и свежесть всех составляющих доказательств.

## Предварительные критерии результата

Числа ниже — рабочие engineering targets, ещё не измеренные результаты и не доказательство безопасности при ходьбе. Наименования устройств и стабильные budgets фиксируются после baseline; изменение цели обязательно видно в отчёте.

| Область | Проверка |
| --- | --- |
| UI на 60 Гц | p95 UI и raster stage ≤16.7 мс; jank ≤1% в согласованном сценарии; на иной частоте используется её frame budget |
| Взаимодействие | p95 от жеста/нажатия до software acknowledgement ≤100 мс, также под neural load; отдельная проверка TalkBack |
| Основное восприятие | начальный ориентир capture-to-accepted-decision p95 ≤200 мс; capture-to-first feedback software milestone p95 ≤300 мс. Deadline для каждого класса опасности отдельно выводится из функции/сценария, движения и запаса остановки; процентиль не разрешает применять stale result |
| Fast metric motion, если доступен | исходный age limit 100 мс на release; каждый просроченный результат отклоняется. Доля своевременных ожидаемых рисков считается с полным denominator, не только по принятым результатам |
| Очереди | ≤1 active + 1 newest pending per heavy path; bounded output/telemetry; queue/starvation counters сохраняются |
| Устойчивость | 30 минут без crash/ANR; warmed p95 в последние 5 минут не хуже первых warmed 5 минут более чем на 20% — предварительный ориентир; пропуски и false stops контролируются одновременно |
| Память | после warm-up нет устойчивого роста PSS/native/Dart memory; 10 stop/resume циклов возвращают memory в воспроизводимый диапазон; абсолютный budget задаётся для телефона |
| Батарея и нагрев | измерены расход, charging state и thermal status; расход сравнивается при одинаковых условиях и полезном объёме работы. Допустимый бюджет задаётся после baseline, универсальный процент не придумывается |
| Корректность | software fixtures сохраняют решения и gates; отдельно missed / late hazards, false stops, unsafe continues, degraded availability и latency. Синтетическая parity не называется field accuracy |

Полный device gate требует baseline и candidate на том же телефоне, reproducible trials, raw trace/receipt, profile diagnosis и release confirmation. Проверка контролируемых сценариев на телефоне проводится с помощником после software gates; самостоятельная ходьба не является способом первоначального тестирования.

## Проверки и зависимости

Точечные meaningful tests: clock conversion и полный возраст; worker ownership / bounded queue / shutdown / stale generation; existing depth preprocess/output contracts и controller guards; scheduler under simulated load; thermal recovery и real completion counters; output priority/timeout. После изменений — analyzer, целевые tests, serial full Flutter suite и `tool/verify_core.ps1 -Rc`. Android Core profile/release builds подтверждаются отдельно. Старые receipts сохраняются.

Android build доказывает упаковку, software RC — regression correctness, on-device traces — latency/resources, controlled scenarios — поведение в измеренных условиях. Ни один из этих уровней не подменяет другой.

Первый bounded этап, который можно начать без телефона: P0 collector/counters/clock contracts + baseline harness, затем P1 persistent NCNN worker с parity/ownership проверками. До подключения устройства скорость на смартфоне остаётся неподтверждённой; backend winner, RAM/energy budgets и минимальный поддерживаемый SoC остаются открытыми.

## Официальные источники методики

- [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance): физическое устройство, profile mode, UI/raster budget; подтверждение итоговой release сборкой.
- [Flutter concurrency and isolates](https://docs.flutter.dev/perf/isolates): persistent workers для повторяемой работы, стоимость запуска/копирования, ограничения asset/UI доступа.
- [Android system tracing](https://developer.android.com/topic/performance/tracing): Perfetto/system trace для scheduling, jank и системной нагрузки; CPU profiler для конкретных методов.
- [LiteRT GPU delegates](https://developers.google.com/edge/litert/performance/gpu): graph partitioning, стоимость преобразований и выбор backend по измерениям. Эти сведения не доказывают performance текущего Bagdar graph.

## Выполненный этап 3: доставка предупреждений

Android speech request IDs, защита от старых callbacks, bounded platform waits,
явная недоступность и безопасное восстановление, native request cancellation,
software delivery timings и haptic failure health реализованы. Проверены 40
целевых cases, 1692 Flutter tests (1 skip), analyzer, остальные 58 обязательных
RC stages, 2 JVM tests и arm64 Core release compilation. Flutter stage повторён
после обновления старого onboarding platform double; исходный failed aggregate
сохранён. Полный разбор и receipts — в
[отчёте этапа 3](phone-performance-stage3-report-2026-10-05.md).

Named-device runtime, фактические звук/вибрация, sustained память/нагрев/батарея
и controlled scenarios остаются следующими gates. Для автоматического выбора
GPU/NPU и подключения metric depth подготовлен
[план условной аппаратной интеграции](optional-hardware-plan-2026-10-05.md);
новые hardware backends на этом этапе не включены.

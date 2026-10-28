# Протокол измерения Core на телефоне

Дата: 2026-10-05. Подготовлены инструменты; named-device runtime ещё не выполнен.

## 1. Сохранить исходное состояние

Нужен физический Android 11+ с известными моделью, SoC, RAM и версией ОС.
Начать с самого слабого предполагаемого поддерживаемого телефона. Эмулятор
пригоден для smoke, но не для измерения скорости телефона.

Записать яркость, частоту экрана, battery saver, заряд/зарядку, температуру и
фоновые приложения. Зарядка по USB влияет на тепловые условия; у каждого A/B
должно быть одинаковое подключение. Не сравнивать холодный baseline с прогретым
candidate. Сохранить APK/hash, исходники, model hashes и backend/threads.

```powershell
powershell -NoProfile -File tool/device_performance/collect_metadata.ps1 -Serial SERIAL -OutputDirectory scratch/device-performance-baseline
```

Скрипт читает device metadata и hashes, не запускает камеру, не изменяет настройки
и не отправляет SOS. Без единственного выбранного телефона сохраняет `not_run` и
завершается с ненулевым статусом. Его metadata receipt не является runtime proof.
Исходные снимки выбранных основных runtime-файлов сохранены в
`scratch/phone-performance-before-2026-10-05`; это частичный source snapshot,
не полный снимок дерева и не готовая baseline APK.

## 2. Отдельный probe настоящей NCNN

```powershell
flutter drive --profile --flavor core -d SERIAL --driver test_driver/perception_performance_driver.dart --target integration_test/core_ncnn_worker_profile_test.dart --dart-define=BAGDAR_PROFILE_THREADS=2
```

Это отдельная тестовая сборка с generated YUV и живой bundled NCNN на устройстве.
Она не запрашивает камеру/геолокацию, не включает guidance или SOS. Тестовый target
использует тот же application ID; после probe снова запустить обычный Core target.
Эмулятор и неназванное устройство отклоняются. Проверяются init, worker processing,
round trip, доступность output, UI/raster и event-loop lag. Один warmup оплачен и
исключён из измеряемого окна; потом выполняются до 20 запросов. Отказы входят в
отдельный denominator; они не превращаются в мгновенный успешный inference.

Результат driver: `scratch/device-worker-probe/integration-response.json`, включая
данные при неуспехе теста. Это **generated-input worker probe**, а не измерение
capture-to-command, scene accuracy, полноценного Core с YOLO или thermal endurance.
Полноценное A/B с native outputs требует одного и того же исходного input corpus.

## 3. Обычный Core и полная нагрузка

```powershell
flutter run --profile --flavor core -d SERIAL --target lib/main.dart
```

Пройти обычный onboarding/readiness, включить доступный пользователю field logging,
открыть camera Core и повторить одинаковую последовательность сцен/жестов.
Собирать DevTools и Perfetto, а также обычные field logs через предусмотренный
пользователю экспорт/доступ. Не менять приватные prefs через shell ради обхода gates.
Не тестировать реальную отправку SOS; transport остаётся тестовым.

`perception_performance_window` отдельно показывает:

- `cameraCallbackFps`, `yoloCompletionFps`, `acceptedDepthFps`;
- busy/cadence/quality/unavailable и rejected outcomes;
- `depthRejections` с stale/timeout/busy/superseded/clock/mismatch;
- YOLO call round trip, callback-to-YOLO tracks, depth provider round trip,
  callback-to-depth decision, worker processing, UI build/raster и event-loop lag;
- p50/p95/p99, full-window max, total/sample count и overwritten samples.

Percentiles относятся к последним максимум 256 samples на стадию в окне; maximum
и outcome counts охватывают всё окно. Для полной временной картины нужен trace.
`acceptedDepth` означает допущенный текущий и согласованный depth frame, который
может иметь degraded/low-confidence health. Это не число распознанных опасностей
и не подтверждение свободного безопасного пути.
YOLO round trip включает marshaling/native queue/compute/return и не называется
чистым временем neural kernel. Worker processing включает NCNN preprocessing,
inference и ground analysis, а provider round trip добавляет transport/queue.
Пересекающиеся длительности не складываются как независимые этапы.

Истинный sensor timestamp ещё не передаётся публичным camera API. Поэтому
`latencyOrigin=dart_camera_callback` и `captureToDecisionAvailable=false` остаются
явными. Callback age включает ожидание YOLO перед depth и owner postprocessing;
он не включает неизвестную задержку sensor → native → Dart. TTS onStart и haptic
dispatch пока не связаны с perception samples общим идентификатором решения.
Отдельные события output уже содержат action/hazard ID; это не делает их
измерением sensor capture → first sound.

### Доставка речи и вибрации

Собирать `feedback_delivery_window` и события `tts_delivery`. Сохранять counts
всех запросов, start/terminal, timeout/ignored events и successful/failed haptic
reply, даже когда start отсутствует. Percentiles стартов сравнивать вместе с
числом запросов: пропавший start не должен исчезать из оценки доступности.
В окне сохраняется не более 256 samples каждой стадии; overwritten samples
отмечаются отдельно.

Проверить system TTS и native kk/fallback отдельно:

- Прервать обычную речь критическим предупреждением, затем сделать stop и
  новый запрос. Сопоставить ID в логах: старые start/done/error не меняют состояние
  нового запроса. Повторить с 30 быстрыми stop/replacement.
- Проверить ответы подготовки/запуска/stop при отказе платформы. Engineering
  deadline 2 секунды завершает caller и объявляет unavailable; он не разрешает
  начать новую речь, пока старый native call всё ещё владеет backend.
- После завершения прежних calls повторить явное восстановление. Сервис должен
  либо восстановить настройки и подтвердить readiness, либо оставаться unavailable.
- Проверить complete до speak acknowledgement, отмену без callback, background/
  resume, TalkBack, наушники, Bluetooth и возвращение после звонка. Фокус не
  удерживается завершённым запросом и не освобождается событием старого запроса.
- Проверить отказ вибрации: неуспешная попытка делает канал unavailable;
  cooldown не объявляет его исправным, успешная следующая попытка восстанавливает.

Android `onStart` и первая принятая native PCM запись — software milestones.
`actualFirstSoundMeasured=false` и `actualVibrationMeasured=false` сохраняются
до отдельного наблюдения физического вывода. Для capture → звук нужен единый
capture/action clock и внешний либо подтверждённый аппаратный замер; нельзя
вычислять его сложением независимых percentile окон.

## 4. Сравнение и длительная сессия

После short trace выбрать backend/thread shortlist по полной полезной latency.
Сделать минимум три A/B с чередованием порядка и одинаковыми моделью, transform,
входами, зарядом, температурой, частотой экрана и выводом. Сохранять пропуски,
поздние сигналы, false stops и unsafe continues отдельно от FPS и процентилей.

Длительный Core run — 30 минут. Сравнить минуты 5–10 с 25–30: p95/p99, принятые
свежие результаты, пропуски, PSS/native/Dart memory, OS thermal status и расход.
Повторить 10 stop/resume циклов, camera restart, screen/background, TalkBack,
смену audio route и low-power режим. Сначала software-controlled проверки;
сценарии движения — с помощником после этих gates.

Последнее подтверждение — обычный release Core на том же телефоне. APK build,
desktop tests и generated-input worker probe не подменяют этот этап.

## 5. Software checks

```powershell
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-phone-performance
flutter build apk --profile --flavor core --target-platform android-arm64 --split-per-abi
flutter build apk --release --flavor core --target-platform android-arm64 --split-per-abi
```

Flutter tests запускаются последовательно. Существующие frozen model/replay
receipts не заменяются. Generic geometry остаётся shadow; fast-motion 100 мс и
обычный controller 2 с — разные существующие admission contracts. Ни один не
расширяется ради benchmark. Изменение backend/cadence требует своих device и
correctness сравнений.

Для arm64 `--split-per-abi` исключает библиотеки других архитектур из пакета.
Release output: `build/app/outputs/flutter-apk/app-arm64-v8a-core-release.apk`.
Architecture целевого телефона проверяется до установки; эти команды не
подтверждают поддержку неизвестного устройства. В проверке 2026-10-05 размер
release уменьшился с 339.9 до 118.1 MiB при побайтово одинаковых arm64/asset
payloads. Это packaging result, не runtime speedup.

Для переключения profile/probe → обычный release не пропускать Flutter pub/tooling
refresh: registrant и native dev-plugin metadata должны соответствовать build mode.
При проверке 2026-10-05 stale registrant с `integration_test` сломал release с
`--no-pub`; dependency версии не требуется обновлять ради восстановления generation.

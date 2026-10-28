# Bagdar: первый этап производительности на Android

Дата: 2026-10-05, Asia/Qyzylorda.

В основной Core-путь подключён постоянный NCNN worker. Синхронный native inference,
подготовка luma, нормализация depth и анализ ground plane выполняются в отдельном
Dart isolate. Главный isolate принимает результат и выполняет существующую
generic geometry / arbitration. Время transport и этого postprocessing ещё нужно
измерить на телефоне.

## Изменения

- `lib/services/ncnn_depth_worker.dart`: один native owner, один активный вход и
  максимум один ожидающий свежий вход. Новый pending заменяет прежний pending;
  активный запрос не вытесняется каждым callback. Deadline включает очередь и
  проверяется по elapsed clock при dispatch и release. Поздний результат остаётся
  unavailable; таймаут не убивает выполняющийся FFI и не освобождает его память.
- `ncnn_depth_worker_types.dart`: snapshot YUV в TransferableTypedData, проверка
  размеров/strides и ограничение transport до 16 MiB на вход. Исходный CameraImage
  не передаётся worker. Returned depth/luma buffers не ссылаются на повторно
  используемые mutable buffers worker; выход передаётся обычным isolate message.
- `ncnn_depth_processor.dart`: перенесён существующий NCNN/ground-analysis путь.
  Model assets, native kernels, относительная семантика depth и пороги не заменены.
- `ncnn_depth_provider.dart`, `ncnn_depth_bridge.dart`, `model_service.dart`:
  lifecycle guard, единая инициализация, ожидание shutdown перед новым владельцем,
  идемпотентное освобождение buffers. Native disposal подтверждается worker;
  ошибка освобождения/неожиданный exit не разрешает новый production owner.
- `lib/core/performance/perception_performance.dart`, `camera_screen.dart`:
  callbacks, YOLO calls, skipped и depth admission считаются отдельно. Throttler
  получает длительность YOLO call round trip. UI build/raster, event-loop lag,
  worker processing и callback-to-decision имеют отдельные bounded samples.
- `depth_pipeline_controller.dart`, `field_logger.dart`:
  возраст depth включает предыдущее ожидание YOLO и проверяется после owner
  postprocessing. Ошибка diagnostic sink не меняет safety outcome.
  Numeric YOLO tracks, confidence зон, pose/motion и winter context фиксируются
  при submission: новые callbacks не переписывают контекст ожидающего результата.
  Это snapshot на стороне Dart, не timestamp/pose настоящего sensor capture.

YOLO уже использует native executor; его вычисления повторно не переносились.
Depth всё ещё запускается после YOLO. Выбор backend, threads и cadence требует
измерений совместной нагрузки на конкретном устройстве.

## Границы измерения и безопасности

Источник latency — получение Dart camera callback и monotonic elapsed age.
Истинный sensor capture timestamp пока недоступен. Поэтому capture-to-decision
и capture-to-command не заявляются. TTS onStart / haptic dispatch пока не связаны
общим decision ID с новым collector.

Percentiles используют последние максимум 256 samples на стадию в окне;
full-window maximum/count и число overwritten samples сохраняются отдельно.
Отказы, таймауты и stale outcomes входят в counters и отдельные reasons.
`acceptedDepth` означает admission текущего согласованного frame, включая
возможный low-confidence frame; это не hazard recall и не свободный путь.

Generic obstacles сохраняют shadow. Unknown-space rules не ослаблены. Существующие
100 ms fast-motion и 2 s обычного depth controller — отдельные contracts, оба
сохранены. `promotionAllowed=false` не изменён. Новые метрики не дают разрешения
на активное использование экспериментальных результатов.

## Проверка

Статическая проверка финального дерева: `flutter analyze --no-pub` — без замечаний.
Финальный целевой набор: **73/73** tests (worker, timing, admission, semantic fusion,
session disable, exceptions, NCNN preprocessing/output contracts, throttler).

Первый полный `tool/verify_core.ps1 -Rc` выполнил **59 обязательных этапов**:
56 прошли, три завершились source-hash drift. Во Flutter software suite прошёл
**1661 тест**, один пропущен. Причина трёх связанных drift — изменённый комментарий
в `lib/models/frame_packet.dart`, входящем в frozen source closure. Этот файл
восстановлен побайтно из pre-change snapshot. Данные, frozen receipts, outputs
и previews не переписывались. Все три этапа повторены: **3/3 pass**.

Исходный RC receipt сохраняет `passed=false`, а результаты повторов находятся
отдельно в `scratch/verification-phone-performance-2026-10-05/core-retries.json`.
После RC добавлена защита контекста асинхронного запроса; она проверена финальным
набором 73 tests и новым полным analyze. Полная software suite после этой последней
правки повторно не запускалась. Это составное software evidence, не утверждение
об одном полностью зелёном RC-запуске финального дерева.

Android Core для arm64: **profile и release собраны**.

| Режим | APK в `scratch/phone-performance-2026-10-05/` | Размер |
| --- | --- | --- |
| Profile | `app-core-profile-arm64.apk` | 384 022 877 bytes / 366.23 MiB |
| Release | `app-core-release-arm64.apk` | 356 387 768 bytes / 339.88 MiB |

В обоих APK Flutter engine имеет ABI arm64; native libs остальных трёх ABI также
пакуются существующим Gradle config. Состав пакета не оптимизировался в этом этапе.
NCNN param/bin внутри APK проверены по SHA-256 против source assets; arm64 CMake
compile metadata содержит `BAGDAR_HAVE_NCNN=1`. Это compilation/packaging evidence,
не запуск native модели на Android. Release использует существующий local debug
signing config; публикация и установка не выполнялись.

Первый release с `--no-pub` завершился Java compile error: stale generated registrant
содержал `IntegrationTestPlugin`, исключённый из release dependencies. Повторный
обычный `flutter build apk --release --flavor core --target lib/main.dart
--target-platform android-arm64` обновил tooling и собрал APK. `pubspec.lock`
сохранился побайтно. Generated registrant вручную не редактировался; шаг исправлен
в device-протоколе.

Машинный итог с APK hashes, source/model identity, исходным RC, повторами и
границами доказательств: `scratch/phone-performance-2026-10-05/stage1-evidence.json`.

Новые worker unit tests используют fake backend с числовыми картами и блокирующей
нагрузкой. Они проверяют transport, responsiveness, latest pending, deadlines,
неизменность предыдущего output, malformed inputs, отказ init, неожиданное
завершение, ошибку disposal, session disable и поздний результат после shutdown.
Дополнительные regression tests меняют YOLO во время заблокированного provider
в обе стороны: новый объект не может усилить старую depth-команду, а новая пустая
сцена не стирает исходный YOLO-контекст ожидающего результата. Проверена также
неизменность semantic snapshot после мутации исходного `Track`.
Сравнение inline processor с worker подтверждает transport parity при rotations
и mirror; оно не измеряет neural accuracy или скорость NCNN на телефоне.

## Проверка телефона

Физический телефон не подключён, его модель/SoC/RAM пока неизвестны. Runtime,
совместная нагрузка camera/YOLO/NCNN, thermal endurance, расход батареи, memory
trend, TalkBack/audio и controlled walking остаются `not_run`.

Подготовлены:

- `integration_test/core_ncnn_worker_profile_test.dart`: физический Android,
  настоящая bundled NCNN, generated YUV, warmup и до 20 запросов, UI/raster и
  event-loop telemetry. Guard отклоняет emulator; тест требует валидный output,
  одной длительности FFI-вызова для успеха недостаточно.
- `test_driver/perception_performance_driver.dart`: сохранение JSON результатов,
  включая данные при провале. Probe не запускает камеру, guidance или SOS.
- `tool/device_performance/collect_metadata.ps1`: read-only device metadata и
  source/model hashes; отсутствие телефона явно записывается как `not_run`.
- [Протокол измерения](phone-performance-protocol-2026-10-05.md): short profile,
  последовательные A/B, 30 минут нагрузки, 10 stop/resume циклов и обычный release.

Следующий этап — named-device baseline обычного Core и probe worker, затем выбор
самого тяжёлого участка по trace. Конкретное ускорение в миллисекундах, допустимые
телефоны и комфорт длительного использования пока не установлены.

Перед началом сохранены выбранные основные runtime-файлы в
`scratch/phone-performance-before-2026-10-05`; это частичный source snapshot,
не полный снимок дерева и не baseline APK.
Репозиторий был dirty до работы, посторонние изменения сохранены.

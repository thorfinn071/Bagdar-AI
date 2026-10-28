# Bagdar: подготовка реального захвата RGB/depth

Дата: 2026-10-11. Этап подготовки к первому физическому телефону завершён.
Модель телефона пока неизвестна; ADB обнаружил 0 авторизованных устройств.
Запись камеры, lifecycle на устройстве, физическое выравнивание, точность
глубины и задержка решений имеют статус **not_run / not_established**.

Создан Research-only нативный рекордер с одним ARCore Session, собственным
worker/GL и отдельной Activity без Flutter engine. По явному старту он сохраняет
локально RGB YUV, raw depth, confidence, pose, оба набора intrinsics, crop/strides,
исходные timestamps и текущую сетку IMAGE_PIXELS → TEXTURE_NORMALIZED.
Есть ограничения записи, явные пропуски, остановка по lifecycle и защита от
перекрытия двух recorder workers при пересоздании Activity.

Raw depth не заполняется интерполяцией. Устаревшая/повторная глубина сохраняется
для диагностики и не получает статус нового same-frame кандидата. Для старта
Session PAUSED/NotTracking считается недоступностью, чтобы не обрывать обычный
прогрев ARCore. Неожиданные ошибки и откат source clock завершают запись с failed.
Запрос остановки повторно проверяется после native update; уже начатая упаковка
кадра может завершиться до teardown. Реальное время освобождения камеры ещё
не измерено. Предел 10 секунд проверяется между native-вызовами и не является
watchdog для зависшего SDK.

Отдельный binary exporter выгружает явно выбранный capture в новый каталог вне
Git, проверяет tar paths/links/duplicates/bounds и не удаляет данные на телефоне.
Офлайн-аудит сверяет hashes, plane sizes/strides, frame/session/order/clocks,
intrinsics/pose/pairStatus; показывает причины missing/unavailable и статистику
ненулевых native depth/confidence пикселей, включая 4×4 карту. Эта статистика
описывает доступность пикселей, без доказательства свободного объёма тела.

## Фактическая проверка

| Проверка | Результат |
| --- | --- |
| Новые Kotlin-тесты pairing | 10/10 pass |
| Новые Kotlin-тесты stride/padding/byte packing | 6/6 pass |
| Существующие SpeechRequestGate JUnit | 2/2 pass, вне нового знаменателя |
| Python: integrity/unknown/clock/fault/export cases | 27/27 pass |
| `assembleResearchDebug` и `testResearchDebugUnitTest` | pass, включая финальную правку cancellation |
| `assembleCoreDebug` | pass |
| Capture Activity/package в Research manifest/dex | присутствуют |
| Capture Activity/package в Core manifest/dex | отсутствуют |
| Прежний closed-volume-control verifier | integrity и все 7 gates pass |
| Реальный export/camera runtime | not_run: нет устройства |

Python использует синтетические contract fixtures. Он проверяет программные
отказы, а не качество реальной камеры или глубины. Предыдущий синтетический
контроль сохранил 14/14 clear preconditions и 7/7 hazard STOP; его source/payload
hashes прошли прежний verifier. Это не новая проверка полевых опасностей.
Полный Flutter RC в этом этапе не запускался: Dart/runtime не менялись;
проверены native unit tests, обе APK и прежний sealed synthetic verifier.

Сохранённые результаты:

- `scratch/research-capture-2026-10-11/build-verification.json`: обе APK, hashes,
  flavor isolation, новые JUnit suites и hashes исходников;
- `scratch/research-capture-2026-10-11/python-tests.log`: финальные 27 тестов;
- `scratch/research-capture-2026-10-11/gradle-build.log`, `core-build.log`,
  `research-final-build.log`: успешные сборки;
- `scratch/research-capture-2026-10-11/device-export-receipt.json`: zero devices,
  `deviceRuntime=not_run`, никакой записи/выгрузки не выполнялось.

Research APK: `build/app/outputs/apk/research/debug/app-research-debug.apk`,
632590650 bytes, SHA256
`d5b24cc75cb92a19c38adb94268f580da5c51c9b2edba53618490e7c09995cba`.
Это полная debug Research сборка с несколькими native ABI и существующими assets,
а не компактный отдельный recorder APK. Она не подтверждает RAM/thermal/FPS.
Core APK SHA256:
`199fc6cc7218e9c39e8c2a620e49e3578386af39fedbf4c0dc98d4b5640fc29b`.

## Открытые доказательства

ARCore явно не определяет временную базу Frame timestamp. Исходный clock
сохранён отдельно от elapsedRealtime, `clockBindingValidated=false`;
captureAge/captureToDecision не вычисляются по несопоставленным часам.
Подробности в [контракте ARCore Frame](https://developers.google.com/ar/reference/java/com/google/ar/core/Frame#getTimestamp()).

RGB/depth имеют разные координатные пространства; сохранённый transform grid
ещё не доказывает физическую корректность. По [контракту Raw Depth](https://developers.google.com/ar/develop/java/depth/raw-depth)
глубина разрежена и может быть reprojection прежних измерений. Совпадение
timestamps, ненулевая confidence и успешный hash audit не заменяют калибровку,
error bounds, floor reference или current body-volume coverage.

Флаги сохранены: `physicalAlignmentValidated=false`, `metricErrorBoundsValidated=false`,
`floorReferenceValidated=false`, `bodyVolumeCoverageEstablished=false`,
`safetyReplayReady=false`, `ordinaryCameraWired=false`, `promotionAllowed=false`.
Core stop/unknown, TTL 100 ms, модели, planner и история STOP не менялись.

Следующий конкретный шаг — выполнить один согласованный неподвижный capture
на названном телефоне и изучить unavailable reasons/native pixel availability.
Затем отдельно проверять часы, RGB/depth projection и метрические ошибки на
известной геометрии; только после этого готовить адаптер в safety replay и
размеченные метрики пропусков опасностей, ложных STOP и задержки.
Инструкция: [research-capture-guide-2026-10-11.md](research-capture-guide-2026-10-11.md).

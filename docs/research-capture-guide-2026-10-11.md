# Bagdar Research: запись реальных данных камеры

Дата: 2026-10-11. Модель телефона неизвестна. Подключённых авторизованных
ADB-устройств на момент подготовки: 0. Инструкция подготовлена; запись на
телефоне и измерение задержки ещё не выполнены.

## Назначение и граница эксперимента

Нативная `SingleOwnerCaptureActivity` существует только в варианте `research`.
Она создаёт ARCore Session в отдельном процессе `:capture`, без Flutter engine,
и сохраняет YUV RGB, raw depth, confidence, intrinsics изображения и текстуры,
позу, timestamps и текущую сетку преобразования IMAGE_PIXELS → TEXTURE_NORMALIZED.
Это подготовка первого варианта camera-owner spike. Сравнение SHARED_CAMERA,
проверка матрицы ToF/no-ToF и выбор production-архитектуры остаются открытыми.

Старт требует видимой Activity, разрешения CAMERA, явного согласия на экране
и отдельного нажатия «Начать». Возврат из запроса разрешения/установки ARCore
сам запись не запускает. Сворачивание запрашивает остановку; автоматического
возобновления нет. Новый захват в том же процессе ждёт освобождения предыдущей
Session/GL, включая пересоздание Activity.

Целевые пределы: 30 кадров, 10 секунд с начала инициализации, минимум 200 мс
между выбранными кадрами, максимум 64 MiB payload. Native update, упаковка,
запись и освобождение Image/Session/GL выполняются одним worker. Предел времени
проверяется между native-вызовами; это не watchdog на случай зависшего SDK.
Реальные lifecycle/ресурсные свойства ещё требуют проверки на телефоне.

Отсутствующие данные остаются `null`. PAUSED tracking и NotTracking/NotYetAvailable
для depth/confidence сохраняются как недоступность, чтобы начало Session не
обрывало запись. Неожиданная ошибка, откат source timestamp, превышение payload
или ошибка teardown завершают запись с `failed`. Незавершённая запись имеет
только pending metadata; частичный набор не проходит финальный аудит.

## Почему отдельный формат

`bagdar-native-capture-v1` сохраняет исходные ARCore наносекунды с доменом
`arcore_camera_ns_unverified`. `receivedElapsedNs` снимается после `Session.update`;
`payloadsReadyElapsedNs` — после сохранения payload, перед добавлением JSONL-строки.
Разность последних двух показывает стоимость получения/упаковки/записи payload
после update, а не capture-to-decision или durable-write latency.

ARCore не задаёт временную базу `Frame.getTimestamp`; поэтому рекордер не выдаёт
её за elapsedRealtime. Camera2 timestamp-source сохраняется как диагностическая
характеристика и не доказывает преобразование часов ARCore. Старый импорт
spatial-recording-v2 требует elapsedRealtimeUs: адаптер пока не создан, такая
запись не допускается в safety replay. [Контракт ARCore Frame](https://developers.google.com/ar/reference/java/com/google/ar/core/Frame#getTimestamp()).

Raw depth разрежен, имеет собственное GPU aspect ratio и native orientation.
RGB intrinsics нельзя просто масштабировать до depth без проверки crop/transform.
Нулевые depth/confidence остаются неизвестными. Равенство timestamps текущего
Frame и raw depth используется только для `same_frame_candidate`; несовпадение
отмечается как `depth_not_new_for_frame`. Это консервативный признак нового depth,
а не проверка метрической точности или физического выравнивания.
[Официальный Raw Depth пример](https://developers.google.com/ar/develop/java/depth/raw-depth).

Каждый plane сохраняется как row-major samples без padding. Depth — uint16 LE,
миллиметры до плоскости камеры; confidence — uint8; RGB — три Y/U/V plane.
Исходные row/pixel strides и cropRect сохранены. SHA256 вычисляется для каждого
plane и `frames.jsonl`. JSONL содержит строгие frameId/index и один sessionGeneration.

Все записи и отчёты сохраняют `clockBindingValidated=false`,
`physicalAlignmentValidated=false`, `metricErrorBoundsValidated=false`,
`floorReferenceValidated=false`, `bodyVolumeCoverageEstablished=false`,
`captureToDecisionAvailable=false`, `ordinaryCameraWired=false`,
`promotionAllowed=false`. Проценты ненулевых depth-пикселей не устанавливают
покрытие объёма тела или свободный проход.

## Подготовка телефона и запуск

Нужен физический Android API 30+ с ARCore и поддержкой RAW_DEPTH_ONLY.
Если поддержки нет, рекордер сохранит отказ и не заменит его MiDaS-метрами.
Дебажный APK нужен для `adb run-as`. Research использует тот же applicationId
`com.example.bagdar`, что и Core; установка заменяет установленный вариант Bagdar.
Не удаляйте приложение для обхода ошибки подписи: удаление стирает локальные записи.

Откройте PowerShell в `C:\Users\Nurik\Desktop\bagdar_app`.
После подключения и авторизации USB debugging подставьте serial из `devices -l`:

```powershell
$taskAdb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $taskAdb devices -l
$taskSerial = 'PHONE_SERIAL'
& $taskAdb -s $taskSerial install -r 'C:\Users\Nurik\Desktop\bagdar_app\build\app\outputs\apk\research\debug\app-research-debug.apk'
& $taskAdb -s $taskSerial shell am force-stop com.example.bagdar
& $taskAdb -s $taskSerial shell am start -n com.example.bagdar/.capture.SingleOwnerCaptureActivity
```

Force-stop здесь завершает прежний Flutter-процесс, чтобы он не владел камерой.
Во время записи не открывайте обычный экран Bagdar. Отдельный capture process
сам по себе не доказывает отсутствие других владельцев камеры на устройстве;
это предстоит проверить по фактическому запуску и логам.

Первый опыт: стойте на месте в согласованной закрытой сцене без посторонних.
Направьте заднюю камеру на текстурированную поверхность и известное препятствие.
Подтвердите checkbox и нажмите «Начать». Если запрошено разрешение или установка
ARCore, вернитесь и нажмите «Начать» ещё раз. Допустимо осторожно изменить положение
телефона руками, оставаясь на месте. Подсказки движения рекордер не выдаёт.
Нулевая доступность глубины — результат опыта, а не повод заполнять её.

По завершении UI покажет `capture-UUID` и причину. Отдельно выполните короткие
проверки: stop button, сворачивание, поворот экрана, возврат, повторный start.
Зафиксируйте фактические ошибки, завершение camera lease и отсутствие записи
после ухода с экрана. Пока эти проверки имеют статус `not_run`.

## Экспорт и аудит

Список локальных записей читается без запуска камеры:

```powershell
& '.\tools\ncnn\.venv\Scripts\python.exe' '.\tool\research_capture\pull_capture.py' --serial $taskSerial
```

Для экспорта явно выберите recordingId и новый абсолютный каталог вне Git:

```powershell
$taskCaptureId = 'capture-UUID_FROM_PHONE'
$taskCaptureOutput = "C:\Users\Nurik\Documents\BagdarCaptures\$taskCaptureId"
& '.\tools\ncnn\.venv\Scripts\python.exe' '.\tool\research_capture\pull_capture.py' --serial $taskSerial --recording $taskCaptureId --output $taskCaptureOutput
```

Exporter получает binary tar через `adb exec-out run-as`, проверяет пути,
типы/размеры/дубли членов архива и отказывается перезаписывать существующий каталог.
Он не удаляет запись с телефона. После извлечения автоматически выполняется аудит,
который сверяет `recordingId` из manifest с явно выбранным `--recording` и создаёт
`audit.json`. Несовпадение завершает экспорт с кодом 2 даже при корректных hashes:
другая запись не принимается под выбранным ID. При ошибке извлечённый каталог сохраняется для разбора;
используйте новое имя для повторной попытки. Сырые кадры не добавляйте в репозиторий.

Повторный офлайн-аудит:

```powershell
& '.\tools\ncnn\.venv\Scripts\python.exe' '.\tool\research_capture\audit_capture.py' $taskCaptureOutput --expected-recording-id $taskCaptureId --output "$taskCaptureOutput\audit.json"
```

Аудит проверяет hash/размеры/strides, порядок frame/session/source timestamps,
монотонность receive/payload clocks, intrinsics, позу и заявленный pairStatus.
Выводит число same-frame кандидатов, причины unavailable, нулевые depth/confidence,
долю совместно ненулевых пикселей, confidence histogram и 4×4 карту native depth.
Незаполненные ячейки не интерполируются. Отдельно указывает наличие RGB→texture grid;
наличие grid не валидирует её физически. Поля captureAge/captureToDecision остаются null.
Код возврата 0 означает целостную финальную непустую запись; он допускает ноль
same-frame кандидатов и не является gate готовности perception. Код 2 означает
отказ/пустую/нефинальную запись или отсутствие телефона.

При экспорте выбранный ID проверяется обязательно. Для отдельного офлайн-аудита
`--expected-recording-id` берётся из выбранной записи, а не копируется из проверяемого
manifest. Без этого параметра аудит проверяет целостность и явно сохраняет
`expectedRecordingId=null`, `recordingSelectionMatched=false`. Совпадение ID
предотвращает ошибочное сопоставление; оно не удостоверяет происхождение,
точность глубины, часы или физическое выравнивание.

## Воспроизведение программных проверок

```powershell
& '.\tools\ncnn\.venv\Scripts\python.exe' -m unittest discover -s tool/research_capture -p 'test_*.py'
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
Push-Location android
.\gradlew.bat :app:assembleResearchDebug :app:testResearchDebugUnitTest :app:assembleCoreDebug --console=plain -Ptarget-platform=android-arm64
Pop-Location
& '.\tools\ncnn\.venv\Scripts\python.exe' '.\tool\research_capture\verify_build.py' --output scratch/research-capture-2026-10-11/build-verification.json
```

Gradle/Flutter запускать последовательно. `verify_build.py` проверяет merged manifests
и наличие capture package в dex обеих APK, а также 16 новых Kotlin-тестов.
Он записывает hashes APK и исходников; этот отчёт описывает локальные build artifacts.

Следующий этап после получения реальной записи: отдельно доказать временную базу,
проверить RGB/depth crop и проекцию на известной геометрии, измерить ошибки глубины,
floor reference и наблюдаемость объёма тела, затем построить адаптер к существующим
replay-контрактам. Пропущенные опасности, ложные STOP и реальную задержку решений
нужно измерять отдельно на размеченных последовательностях. Сам рекордер не запускает
YOLO/NCNN/runtime, поэтому этих метрик здесь ещё нет.

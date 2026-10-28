# Bagdar: идентификаторы и доставка предупреждений

Дата: 2026-10-05. Software validation, JVM tests и release compilation завершены.
Аппаратные измерения отсутствуют: физический телефон не подключён.

## Изменения

- Android system TTS получает уникальный ID запроса. Callback start/complete/error/
  cancel обрабатывается только для текущего ID; события предыдущего запроса и
  старые события без ID не завершают и не запускают новую подсказку.
- Казахский native TTS передаёт тот же контракт. Russian fallback получает новый
  ID, сохраняя action/hazard контекст исходного SpeechJob. Повторный start одного
  ID не переустанавливает watchdog и не удваивает количество стартов.
- После native error критическое предупреждение сохраняет защиту от другого
  critical без barge во время Russian fallback; следующий hazard ожидает
  завершения текущего предупреждения.
- Runtime platform preparation и acknowledgement имеют engineering deadline
  2 секунды на операцию. Он не является целевой задержкой предупреждения и не
  заменяет TTL. По таймауту текущий запрос инвалидируется, очередь очищается,
  waiters завершаются, `isReady=false`, фиксируется недоступность/stall callback.
- Таймаут Future не отменяет native call. Его ownership сохраняется до реального
  завершения; новая речь заблокирована. Общий stop остаётся один, даже если его
  ответ запаздывает. Восстановление через `retryPlayback`/`init`/новую camera
  preclaim возможно только после завершения прежних calls и восстановления
  настроек. Долго не завершившийся call оставляет сервис явно unavailable.
- Ограничены также ожидания release/reacquire аудиофокуса. Отдельные audio-route
  и физические latency проверки на телефоне остаются обязательными.
- Валидный complete до acknowledgement освобождает фокус после ответа speak;
  explicit stop освобождает фокус без ожидания callback отменённого запроса.
- Нативная PCM синтезация сериализована: один active + один newest pending.
  Request cancellation никогда не сбрасывается новым запросом. Stop больше
  не делает 60 ms join на UI thread. Worker владеет release AudioTrack; старый
  запрос теряет ownership, проверяет его перед PCM и не публикует callbacks
  после отмены. Уже выполняющийся JNI/write не считается отменённым мгновенно;
  физическое прерывание воспроизведения требует проверки на телефоне.
  Состояние engine защищено lock.
- Native complete ожидает playback head с конечным drain deadline, вместо
  принятия завершения streaming writes за завершение воспроизведения.
- Ошибка платформенного vibration reply теперь возвращает false, а не успешную
  доставку. Прежний публичный `vibrate` сохраняет fire-and-forget API.
- Неуспешная попытка haptic delivery делает канал unavailable. Пропуск из-за
  cooldown не снимает эту ошибку; успешный последующий reply восстанавливает
  available. Запросы, истёкшие до dispatch, не обращаются к output.

## Что измеряется

`feedback_delivery_window` — bounded collector, 256 samples на каждую timing
метрику. Есть counts запросов/стартов/терминальных исходов, таймаутов, игнорируемых
событий, а также p50/p95/p99/max и количество перезаписанных samples.
Отсутствующий start остаётся в denominator counts; latency percentiles описывают
только наблюдённые milestones, их нельзя выдавать за долю своевременных сигналов.

Speech: enqueue → request и request/enqueue → software start. События
`tts_delivery` содержат request/action/hazard ID, backend и Dart elapsed clock.
Для system TTS start означает Android onStart; для native PCM — первую принятую
запись PCM. Native elapsed timestamp не смешивается с Dart clock для percentiles.

Арбитрованные FeedbackCommand: dispatch → haptic request/reply, action ID и
counts успешного/неуспешного software reply. Запрос вибрации и его reply не
доказывают физическое начало вибрации.

`actualFirstSoundMeasured=false`, `actualVibrationMeasured=false`. Origin —
Dart dispatch/enqueue; sensor capture → first sound пока не измеряется.

## Зависимости и проверка

В `third_party/flutter_tts` сохранена исходная версия 4.2.5 и LICENSE.
Локальный fork добавляет Android `bagdarSpeak`/`bagdar.speechEvent` и Dart API;
остальные платформенные implementations сохранены. Pub cache не редактировался.
Tagged Android requests отвергают unready engine вместо deferred speak queue,
чтобы старый request не прозвучал после caller timeout. Для tagged path не
сохраняется растущая таблица текстов. Pub lock меняет только источник flutter_tts
с hosted на path той же версии. Native tests добавляют JUnit test dependency.

14 cases в четырёх новых Flutter test files: ID isolation, critical protection, задержанные start и
ack, таймауты rate/focus/language/speak/stop, безопасное explicit recovery,
fallback ID, bounded metrics/denominator, failed vibration reply, состояние
haptic канала, dispatch timing и два порядка освобождения аудиофокуса.
Ещё один новый case в существующем `tts_playback_scheduling_test.dart`
проверяет critical protection после native error/fallback. Итого 15 новых cases.
Два JVM tests проверяют cancellation старого запроса при возобновлении worker
и последовательные replacements/stop. Android compile проверяет API wiring.

Финальный целевой набор — **40/40**, включая audio release и haptic health.
Обновлённый onboarding набор — **4/4**. Повторный analyzer — **no issues**,
включая исходные strict analysis options локальной зависимости.

Полный повторный Flutter suite — **1692 pass, 0 fail, 1 skip**. Все остальные
**58 обязательных этапов Core RC** прошли. Таким образом, все 59 required
software stages подтверждены с отдельным повтором Flutter stage; это
consolidated validation, а не один полностью зелёный aggregate запуск.

В исходном завершённом aggregate Flutter stage было 1690 pass, 2 fail, 1 skip.
Оба сбоя — в `onboarding_native_speech_test.dart`: прежний platform double
обрабатывал только `speak` и legacy events. Double обновлён для
`bagdarSpeak`/`bagdar.speechEvent`; ожидания error/retry и подтверждения
воспроизведения сохранены. Runtime code не менялся. Затем отдельно повторены
этот набор, analyzer и полный Flutter suite. Исходный aggregate receipt
с `passed=false` сохранён; successful rerun записан отдельным receipt.

Два более ранних aggregate запуска остановлены до завершения, поскольку код
ещё менялся; они не считаются RC-pass. Ранние failed targeted logs также
сохранены. Frozen SHA-256 manifest включает проверяемые runtime файлы и tests,
в том числе обновлённый onboarding double.

Первый release `--no-pub` остановился на stale GeneratedPluginRegistrant,
ссылающемся на integration_test в release. Обычная сборка с Flutter pub/tooling
refresh прошла; registrant вручную не редактировался, package versions не
обновлялись. Сохраняется прежняя версия flutter_tts 4.2.5.

JVM `:app:testCoreReleaseUnitTest`: **2 pass, 0 failures/errors/skip**.
Android Core release: **успешно собран**, только `arm64-v8a`, Android 11/API 30+,
с существующей локальной debug signing key. Установка и запуск не выполнялись.

APK: `scratch/phone-performance-stage3-2026-10-05/app-core-release-arm64.apk`.
Размер: **123898921 bytes / 118.16 MiB**.
SHA-256: `4969e6ac23e320a6e0e56cd8dc092dcbc4e5eb6431f01b10ef3fe0442037a6fa`.
В DEX подтверждены `bagdarSpeak`, `bagdar.speechEvent` и новый native worker.
Все три model assets в APK побайтово совпадают с контролями.
После сборки совпадают SHA-256 всех 22 выбранных source/test/config files из
`final-source-hashes.json`; это выбранный manifest, не fingerprint всего checkout.
В локальном flutter_tts изменены только два source files из 24 сверенных
upstream files; исходные strict analysis options и другие платформы совпадают.

Machine receipt: `scratch/phone-performance-stage3-2026-10-05/stage3-evidence.json`.
Raw logs, failed aggregate и successful rerun сохранены в том же каталоге.

## Границы

Новые Flutter тесты используют platform doubles, JVM tests — pure request gate.
Они не запускают акустику/вибромотор и не доказывают телефонную latency,
TalkBack, audio routes, расход батареи, нагрев или controlled walking.
Более широкий Core RC содержит отдельные model-output/replay проверки;
это также desktop software evidence, не field accuracy.

100 ms / 2 s perception contracts, unknown rules, model weights, shadow и
`promotionAllowed=false` сохраняются. На не-Android платформах system TTS
использует прежние callbacks; Android ID-контракт на них не заявляется.
Проверка NPU/LiDAR/ToF вынесена в `optional-hardware-plan-2026-10-05.md`:
существующие GPU hooks обследованы, новые hardware backends не включены.

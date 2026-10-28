# Bagdar: речь под нагрузкой и размер Android APK

Дата: 2026-10-05, Asia/Qyzylorda.

Второй ограниченный этап касается вывода предупреждений. Постоянный NCNN worker
и учёт callback-to-decision из первого этапа сохранены. Теперь TTS запускает
одну подготовку речи за раз, объединяет одновременно ожидающие остановки
движка и повторно проверяет срок действия сообщения после асинхронных настроек.

## Исправленные сценарии

В прежней реализации остановка могла завершиться, пока старый `_pump` ещё ждал
аудиофокус или настройку скорости. После ожидания старый код продолжал `speak`,
даже если сообщение отменено новым критическим сигналом либо пользовательской
остановкой. Срок действия проверялся до подготовки. Поток из 30 критических
сообщений отправлял 30 одновременно ожидающих `stop`. Повторные обращения к
очереди во время паузы между предложениями создавали отдельные timers.

Изменения в `lib/services/tts_service.dart`:

- Generation инвалидируется синхронно при остановке и прерывании. Проверка
  после каждого ожидаемого шага подготовки запрещает отменённому запросу
  продолжить запуск. Новые запросы ждут завершения текущей подготовки и stop.
- Одновременно существует одна подготовка, одна общая backend-stop future,
  максимум четыре ожидающих SpeechJob и один timer паузы между предложениями.
  Приоритеты, замена по identity, сохранение независимых критических сообщений,
  barge для SOS/countdown и прежние queue bounds сохранены.
- Новый запрос, пришедший после начала stop, не удаляется его поздним завершением:
  очередь очищается при начале остановки. При dispose сервис уже недоступен.
- Проверяются явный `expiresAt` и прежние пределы возраста: четыре секунды для
  critical, пять для остальных. Проверка повторяется непосредственно до вызова
  speech API, включая смену языка после отказа native Kazakh backend.
- После отменённой настройки скорости cache инвалидируется. Следующий запрос
  восстанавливает нужную скорость, даже если старая platform operation успела
  изменить движок.
- Прежний stall watchdog запускается при speech request и переустанавливается
  при `onStart`. Отсутствующий `onStart` больше не оставляет очередь занятой
  без watchdog; recovery использует тот же общий stop для обоих backend.
- Callback во время stop/подготовки/после dispose не меняет состояние речи.
  Завершение предыдущего сообщения не снимает аудиофокус следующего.
- При native error → Russian fallback восстанавливается critical priority.
  Следующий независимый critical без barge ждёт окончания текущей речи.
- Если вся очередь истекла, waiter получает завершение вместо зависания.

Новые `test/tts_playback_scheduling_test.dart` запускают production queue через
реальный Dart `FlutterTts` с подменённым MethodChannel. Аудиофокус подменяется
отдельным port double. Clock injection используется только в test constructor;
в production TTL сохраняет прежнюю семантику DateTime, без нового clock mapping.

## Проверка

Все **15 новых tests** прошли на финальной реализации. Они проверяют
preemption во время настройки скорости/аудиофокуса, задержанный speak reply,
поток critical, stop и новый запрос, TTL, native rejection → Russian fallback,
rate cache, исключение настройки, отмену timer, stall recovery, аудиофокус
и восстановление critical protection после native error. Финальный набор:
**80/80 целевых tests** TTS, countdown, native bridge, haptics, feedback policy
и alert regressions.

Полный `tool/verify_core.ps1 -Rc` прошёл **59/59 обязательных этапов**; в его
Flutter suite прошло **1677 tests**, один пропущен. Analyzer и Flutter stage
этого прогона выполнены до последней правки critical fallback и её нового test.
После неё целевой набор 80/80 проверен заново; frozen perception sources и
model assets не изменились. Единого полного RC после последней правки не было.

Пять основных scheduling tests дополнительно выполнены на сохранённом исходном
TTS с добавлением только test constructor/clock injection. **Все пять обнаружили
соответствующие ошибки**. Candidate того этапа после этого восстановлен
byte-for-byte, SHA-256:
`8f675ef751c78d80456d4f11728ebf3f93df3254574716a58415c3b4ab1fdcc7`.
Первый exploratory запуск имел ошибку test seam и неверную предпосылку о rate
warning; эти логи сохранены отдельно и не используются как regression control.
Дополнительный native-error test выполнен с удалением только строки
восстановления priority: он обнаружил два stop вместо одного. Финальный candidate
восстановлен byte-for-byte, SHA-256:
`19afce6cb3cffc644672a820db11ab14e11891c8efe51e72d70ca4b7e28355db`.

В test burst из 30 critical запросов одновременно ожидающий вызов backend stop
сократился с **30 до 1**. Это число платформенных вызовов в воспроизводимом
software scenario, не измерение FPS, p95 речи или энергопотребления телефона.

Финальная `flutter analyze --no-pub` — без замечаний. Android build configuration
изменена после Core RC и проверена двумя отдельными release-сборками. Raw logs,
исходный snapshot, control с test seam и hash
receipt находятся в `scratch/phone-performance-stage2-2026-10-05/`.

## APK для arm64

При `--target-platform android-arm64` прежняя обычная сборка содержала Flutter
engine для arm64, но native libraries сразу для четырёх ABI. Примерно 221.8 MiB
пакета приходилось на библиотеки других архитектур.

Первый `--split-per-abi` завершился явным AGP conflict между четырьмя
`ndk.abiFilters` проекта и ABI splits Flutter. В `android/app/build.gradle.kts`
добавлена условная конфигурация: при splits набор архитектур задаёт Flutter;
без splits остаются прежние filters. Failed log сохранён отдельно.

Оба варианта затем успешно собраны из одного финального Dart source:

| Release Core | Размер | Native ABI |
| --- | ---: | --- |
| Без splits | 356,387,768 bytes / 339.9 MiB | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Arm64 split | 123,833,385 bytes / 118.1 MiB | arm64-v8a |

Уменьшение: **232,554,383 bytes / 221.8 MiB / 65.253%**. Все **61** общих
payload files в `assets/` и `lib/arm64-v8a/` совпадают побайтово, включая Dart
AOT program, NCNN/native libraries, YOLO/MiDaS, speech/OCR data и fonts.
Исходные model hashes проверены отдельно. `pubspec.lock` не изменился.

Артефакт для измерения на arm64: `scratch/phone-performance-stage2-2026-10-05/app-core-release-arm64.apk`.
Это Core release с существующей локальной debug signing key, Android 11/API 30+.
Телефон пока не определён; совместимость конкретного устройства не проверена.
Compilation/packaging подтверждены, установка и запуск не выполнялись.
Уменьшение APK означает меньший размер пакета; FPS, RAM, startup latency и расход
батареи этим сравнением не измеряются.

## Границы результата и следующий этап

Физического Android-устройства пока нет. Реальный звук, вибрация, TalkBack,
audio routes, ANR, sustained latency, память, нагрев и расход батареи не проверены.
Подмена platform transport не запускает нейросети и не воспроизводит scheduling
Android. Это проверка очереди и состояния предупреждений под заданными задержками.

Новый guard может задержать следующий speech request до завершения уже ожидающей
platform preparation/reply. Critical barge инициирует stop сразу; haptic path
остаётся самостоятельным. Отдельного deadline для зависшей настройки аудиофокуса
или скорости этот этап не вводит. Гарантия времени до первого звука не заявляется.

FlutterTts 4.2.5 передаёт start/complete без utterance ID; нынешние native Kazakh
callbacks тоже не содержат ID запроса. Guard отвергает callbacks в неактивных
фазах, но поздний callback предыдущей речи после dispatch новой речи нельзя
однозначно сопоставить. Native request IDs и command → onStart/haptic correlation
остаются отдельной незавершённой частью P0. Фактический первый звук/вибрация
потребует независимого наблюдаемого замера.

Backend/threads/cadence моделей не выбирались без измерения. Depth всё ещё идёт
после YOLO; scheduler A/B остаётся следующим отдельным этапом. Model assets,
unknown rules, 100 ms fast-motion / 2 s ordinary-depth contracts,
`GenericObstacleMode.shadow` и `promotionAllowed=false` сохранены. Отчёт первого
этапа и его failed/retry receipts не переписаны.

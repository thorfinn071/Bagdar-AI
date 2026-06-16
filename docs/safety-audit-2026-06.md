# Safety-аудит Bagdar — июнь 2026

Аудит цепочки безопасности по направлениям: **A** — каскады отказов, **B** — пороги, **C** — FSM, **D** — граничные случаи детекции, **E** — надёжность SOS. Только отчёт; код не менялся.

## Методология

- **Охват**: `lib/` (Dart) + `android/app/src/main/kotlin/`. Полностью прочитаны: `camera_screen.dart` (2970 строк), `camera/alert_manager.dart` (1418), конвейер глубины (`model_service` → `depth_provider` → `ncnn_depth_provider` → `depth_pipeline_controller`), `tracker/`, `alert_filter`, `fusion_engine`, `tts_service` (1113), `fall_detector`, `fall_countdown_controller`, `sos_service`, `performance_throttler`, мониторы (thermal/memory), сторожа (`stall_watchdog`, `misalignment_watchdog`, `phone_abandoned_detector`, `frame_quality_guard`), `camera_lifecycle_controller`, `MainActivity.kt`.
- **Перекрёстная проверка** с фиксами прошлых аудитов (маркеры «Safety audit N.N», «V1.x–V5.x», «H5–H9», «S-2», «M12») и тестами (`safety_audit_fixes_test.dart`, `alert_system_audit_fixes_test.dart`, `tts_service_test.dart`, `sos_service_test.dart` и др.). Уже исправленное не повторяется; **недоделки этих фиксов** оформлены отдельными находками.
- **Формат**: Файл:строка → Сценарий → Последствие → Серьёзность → Исправление.

### Рубрика серьёзности

| Уровень | Критерий |
|---|---|
| **КРИТИЧЕСКАЯ** | Молчаливая потеря предупреждений об опасности или отказ SOS без уведомления (false negative = угроза жизни) |
| **ВЫСОКАЯ** | Задержанное/деградированное предупреждение в правдоподобном сценарии |
| **СРЕДНЯЯ** | Узкий граничный случай либо деградация *с* уведомлением |

---

## Фактическая карта пайплайна

```
CameraImage → camera_screen._onFrame (1384–1719)
  ├─ StallWatchdog.notifyFrameArrived ── нет кадров 2–4 с → onStall → earcon + TTS warning (cooldown 15 с street/cane)
  ├─ FrameQualityGuard.evaluate ── AE / blocked / frozen / droplet / smear / weather
  │    └─ aePipelineFrozen → ранний return: YOLO НЕ выполняется  ← D-1
  ├─ BlurDetector ── blurry → только tracker.predict(), алертов нет
  ├─ MotionPreAlert.feed (street/cane) → _handleMotionIntrusion → AlertFilter → TTS/haptic
  ├─ detect gate: интервал throttler (140–500 мс) + _isDetecting + _models.yoloLoaded  ← A-1
  ├─ YOLO → _buildRawDets (whitelist, per-class conf, low-light −0.08)
  ├─ Tracker.update (Kalman + Hungarian + appearance, graveyard 3 с)
  ├─ AlertManager.processFrame
  │    ├─ _handleApproaching / _handleVeryClose (прямой TTS critical + noteCritical) / _handleCloseFar / _handleNavHint
  │    └─ AlertFilter.flushMulti (макс. 2 победителя разных категорий) → TTS / earcon / haptic
  └─ DepthPipelineController.shouldRun (≥800 мс) → analyze
       ├─ NCNN MiDaS / HardwareDepth → GroundPlaneAnalyzer (RANSAC)
       ├─ FusionEngine (EMA 0.30, 3 кадра) → промоция в critical
       └─ alertMgr.handleDepthHazard → AlertFilter.flush → TTS
Параллельно: FallDetector (accel/gyro 50 мс) → FallCountdownController → SosService → MethodChannel bagdar/sms → MainActivity.kt (SmsManager) → fallback sms:/tel:
Kill-switch'и: thermal FSM (dwell 60/30 с), memory (400/250 МБ), battery, stationary gate (300 мс / MiDaS off), MiDaS-pause (анонсируется), ground-safety burst (1/5 с при critical thermal).
Каналы: TTS (очередь приоритетов) → earcon → haptic; native watchdog (ping 2 с, аларм через 6 с — только foreground).
```

---

# A. Цепочки отказов

## A-1. Отказ перезагрузки YOLO при thermal-переключении: детекция объектов молча выключается навсегда — КРИТИЧЕСКАЯ

- **Файл:строка**: `lib/services/model_service.dart:152-175` (`adjustForThermal`); следствие — `lib/camera_screen.dart:1507`.
- **Сценарий**: нагрев до hot/critical → `adjustForThermal` ставит `_yoloLoaded = false` и вызывает `_loadYoloAtTier` (старая модель уже выгружена `closeYoloModel()`). Если `loadYoloModel` бросает (нехватка памяти при critical thermal вероятна), `catch` пишет в debugPrint и выходит; `_yoloLoaded` остаётся `false`. Следующие вызовы `adjustForThermal` выходят на первой строке `if (!_yoloLoaded || _yoloReloadBusy) return;` — **самоблокировка, ретраев нет**.
- **Последствие**: `_onFrame` каждый кадр уходит в ветку `!_models.yoloLoaded` → только `tracker.predict()`; `alertMgr.processFrame` не вызывается: ни алертов, ни «путь свободен». `_finalizeFramePerf` при этом исполняется → `effective_fps` высокий → low-FPS-предупреждение НЕ срабатывает; кадры идут → StallWatchdog молчит; heartbeat-earcon продолжает играть. Пользователь идёт с мёртвой детекцией объектов и «исправно звучащей» системой (MiDaS продолжает работать, усиливая иллюзию).
- **Исправление**: в `catch` — откат `_loadYoloAtTier(tier: _currentYoloTier, …)`; при повторном провале — колбэк `onYoloUnavailable` → TTS critical «Распознавание объектов недоступно» + повтор каждые 30 с; в `_onFrame` — голосовое предупреждение, если `!yoloLoaded` дольше N с в street/cane. Тест: исключение из `loadYoloModel` → ожидать ретрай + уведомление хоста.

## A-2. Session-disable NCNN молчалив: `onSessionDisabled` никем не подписан; «провайдер не готов» не двигает статус-машину — КРИТИЧЕСКАЯ

- **Файл:строка**: `lib/services/ncnn_depth_provider.dart:35,322-343`; `lib/camera/depth_pipeline_controller.dart:127-131`.
- **Сценарий**: 3 невалидных выхода NCNN (NaN/Inf) за 5 минут → `_permanentlyDisabled = true`, `isReady=false`. Колбэк `onSessionDisabled` объявлен и вызывается, но grep по `lib/` даёт ровно 2 совпадения — объявление и вызов: **никто не подписан**. В `analyze` контроллера ветка `provider == null || !provider.isReady` делает ранний `return []` **без** инкремента degraded-счётчиков — статус остаётся `ok`.
- **Последствие**: ступени вниз, ямы, glass door, near-field выключаются до перезапуска приложения; `onStatusChanged` не срабатывает → нет TTS `depth_degraded`; `MisalignmentWatchdog.isDepthBlindAt` тоже не подтверждается (D-5). Пользователь не узнаёт, что идёт к лестнице без подстраховки.
- **Исправление**: подписать `ncnn.onSessionDisabled` при создании провайдера с пробросом в `DepthPipelineController._setStatus(lowConfidence)`; ветку «не готов» в `analyze` считать degraded-кадром (после `_kDegradedFramesToAnnounce` — переход статуса). Тест: 3 invalid-выхода → ожидать TTS-переход.

## A-3. `DepthPipelineController.analyze`: catch глотает исключения без учёта в статус-машине (недоделка фикса 3.2/3.3) — ВЫСОКАЯ

- **Файл:строка**: `lib/camera/depth_pipeline_controller.dart:214-218`.
- **Сценарий**: фикс 3.2/3.3 добавил статусы для «тихих» путей, но ветка исключений осталась: `catch (e) { _inFlight=false; debugPrint; return []; }`. Реальный источник перманентных исключений: `RangeError` в `HardwareDepthProvider._extractLuma` (`depth_provider.dart:283-303` — индекс `rowStart + sx` не проверяется против `yBytes.length`; при смене разрешения/stride после фонового резюма бросается на каждом кадре).
- **Последствие**: перманентный сбой анализа = вечный статус `ok` и тишина — тот же класс отказа, который фикс 3.2 должен был закрыть.
- **Исправление**: в `catch` инкрементировать `_consecutiveAnalyzeFailures` → после 3 подряд переводить в `lowConfidence`; в `_extractLuma` — границевый guard. Тест: провайдер-мок, бросающий из `analyze`, → ожидать `onStatusChanged`.

## A-4. Дегенеративный выход глубины (confidence = 0) классифицируется как «здоровый» — ВЫСОКАЯ

- **Файл:строка**: `lib/camera/depth_pipeline_controller.dart:134-135` (`lastConfidenceScore > 0 && < 0.4`); `lib/services/ncnn_depth_provider.dart:219-222` (degenerate → confidence 0 **без** `_recordFailure`), `:231-233` (catch в analyze тоже без `_recordFailure`).
- **Сценарий**: модель выдаёт плоскую карту глубины (известная деградация INT8-моделей при экстремальной экспозиции/перегреве) → `degenerate` → confidence 0, hazards `[]`. Условие контроллера `score > 0` не выполняется → lowConfidence не инкрементируется; degenerate не идёт и в окно отказов → session-disable не наступит.
- **Последствие**: глубинные опасности молча не детектируются неограниченно долго; ни статуса, ни TTS, ни автоотключения.
- **Исправление**: трактовать `score == 0` (после первых кадров) как low-confidence; в NCNN считать degenerate и исключение в `analyze` отказами (`_recordFailure()`).

## A-5. TTS-дедуп для critical (4 с) шире safety-cooldown'а фильтра (2 с): разрешённый повторный critical молча гасится — ВЫСОКАЯ

- **Файл:строка**: `lib/services/tts_service.dart:674` (`_kCriticalDedupWindow = 4s`), `:722-726` (drop по `_lastSpokenByText` **до** учёта `barge`); против `constants.dart:196` (`kCriticalRepeatCooldownSafety = 2s`) и `alert_filter.dart:156-183`.
- **Сценарий**: повторная критическая опасность с тем же текстом — типично для фиксированных фраз: depth-хазарды (`hazard_stairs_down`), synth-events, cane-режим, Verbosity.minimal, некалиброванный режим (без метров в тексте). AlertFilter после 2 с разрешает повтор; `say()` дропает его в окне 2–4 с.
- **Последствие**: повторное critical-предупреждение приходит вдвое позже задокументированного (через 4 с ≈ 2.6 м пути к лестнице вместо 1.3 м).
- **Исправление**: для critical сократить дедуп-окно до ≤2 с либо пропускать text-dedup (очередь уже дедуплицирует через `_queue.any`). Тест: два `say(criticalText)` с Δt=2.5 с → второй в очереди.

## A-6. Исключение в `_initCamera`: ни TTS, ни хаптики; затем ложное «Система готова»; первый звук — через ~60 с — ВЫСОКАЯ

- **Файл:строка**: `lib/camera_screen.dart:1373-1381` (catch — только `setStatus`); `:854-856` (`system_ready` безусловно).
- **Сценарий**: `availableCameras()`/`initialize()` бросает (камера занята, HAL-сбой). Ветки «нет камер» озвучены critical, ветка исключения — нет. `_initAll` продолжает и говорит «Система готова». StallWatchdog не запущен (start только в успешной ветке), `isCameraReady=false` держит его пассивным. Единственное уведомление — heartbeat `effFps<3` (со 2-го тика, ~60 с, только street/cane).
- **Последствие**: минута «уверенной» ходьбы без какой-либо детекции; затем лишь warning «камера остановилась».
- **Исправление**: в catch — TTS critical + `kHapticTtsStallPattern` + цикл повторной инициализации (паттерн `_speakCameraPermissionDeniedLoop`); не объявлять `system_ready` при `!_isCameraReady`.

## A-7. Тёплый резюм: асинхронная ошибка `startImageStream` не ловится — СРЕДНЯЯ

- **Файл:строка**: `lib/camera/camera_lifecycle_controller.dart:183-192`.
- **Сценарий**: `ctrl.startImageStream(...)` возвращает Future; синхронный try/catch ловит только синхронные броски. Камеру перехватили в фоне → `isCameraReady=true`, кадров нет.
- **Последствие**: слепое окно до StallWatchdog (2–4 с; активен) → earcon+TTS. Деградация **с** уведомлением, но без автоматического cold-restart (cold-путь его делает, warm — нет).
- **Исправление**: `await`/`.catchError` с переходом в cold-путь (dispose + `initCamera`).

## A-8. Отказ канала thermal/memory → severity «normal»: защита снимается на горячем устройстве — СРЕДНЯЯ

- **Файл:строка**: `lib/services/thermal_monitor.dart:160-163`; `lib/services/memory_monitor.dart:96-99`.
- **Сценарий**: канал `bagdar/device_info` начинает падать на устройстве в committed critical → raw «normal» → через recovery-dwell 30 с (`performance_throttler.dart:75-85`) троттлинг снимается; для памяти — риск OOM-kill (для пользователя = внезапная полная тишина).
- **Последствие**: kill-switch при сбое датчика деградирует в «выключено», а не в «осторожно».
- **Исправление**: при N подряд сбоях канала удерживать последний уровень (минимум `warm`) + лог `sensor_unavailable`.

## A-9. Floor-защита хаптики не покрывает основной критический паттерн — СРЕДНЯЯ

- **Файл:строка**: `lib/services/haptic_service.dart:42-48` — `identical` только с `kHapticTtsStallPattern` и `kHapticCriticalCooldownPattern`; `kHapticCriticalAlertPattern` (constants.dart:255) отсутствует.
- **Сценарий**: множитель вибрации 0.3 → критические алерты (`_handleVeryClose`, `handleDepthHazard`) шлют именно `kHapticCriticalAlertPattern`: 150 мс→45 мс, 255→77.
- **Последствие**: тактильный канал критического алерта слабеет — floor-механизм, созданный ровно для этого, к нему не применяется.
- **Исправление**: добавить паттерн в критический список; лучше — флаг `isCritical` параметром вместо `identical`.

## A-10. Прочие наблюдения (вне таблицы)

- `camera_screen.dart:899-900` — пустой блок `if (!recentAnyAlert) { }`: потерянное намерение, мёртвый код.
- `tts_service.dart:922-938` — `stop()` чистит всю очередь, включая critical; вызывается из `setLanguage` (смена языка голосом во время опасности теряет queued critical). Рекомендация: сохранять critical.
- Положительное: путь «TTS не готов» (`say:690-711`) даёт haptic + `onTtsUnavailable` → re-init; `_pruneStaleCriticals` без maxAge — no-op (закреплено тестом 1.2); очередь ограничена 4 с вытеснением только info/warning.

---

# B. Анализ порогов

## B-1. Межкатегорийная связка approachingVehicle↔obstacleClose блокирует critical другой природы на 2 с — ВЫСОКАЯ

- **Файл:строка**: `lib/utils/alert_filter.dart:366-388` (`_updateCategoryState` помечает обе категории), `:156-183` (critical-ветка `_isAllowed`).
- **Сценарий**: t=0 — critical «ступени вниз» (obstacleClose; `noteCritical` через linked-категории ставит метку и approachingVehicle); t=0.8 — машина из арки → critical approachingVehicle → `_isAllowed` видит свежий `_lastCriticalByCat` → отказ до t=2.0. Дистанционная эскалация (`:172-182`) внутри окна не работает: требует `now-lastSameAt >= 2 с` (для safety-категорий ветка недостижима) и ненулевых `distanceM` у обоих.
- **Последствие**: предупреждение о машине задерживается до 2 с в сценарии «лестница + двор-арка»: связка, введённая фиксом 3.2 против дабл-файра, гасит **разные** опасности друг другом.
- **Исправление**: связку применять только к не-critical кандидатам; critical другой категории пропускать (или связанное окно ≤800 мс = `kCriticalCooldown`). Тест к группе 1.4: obstacleClose(depth) → approachingVehicle с Δt=1 c должен пройти.

## B-2. Бег ускоряет YOLO, но не MiDaS/fusion: подтверждение depth-critical = 2.4 с = 7+ м пробега — ВЫСОКАЯ

- **Файл:строка**: `lib/utils/performance_throttler.dart:274-276` (детекция ÷2 при running) против `:283-308` (`midasInterval` — только thermal/load); `constants.dart` (`kMidasInterval=800ms`, `kFusionTemporalFrames=3`).
- **Сценарий**: V1.2 учитывает бег для YOLO (~70 мс) и говорит «вы бежите», но яма/люк с пограничным score (0.50–0.65) подтверждаются fusion-цепочкой: 3 кадра × 800 мс = 2.4 с. На 3 м/с это 7.2 м — яма уже под ногами. Прямой critical (score ≥0.65 в центре) срабатывает с первого кадра — закрывает только уверенные случаи.
- **Последствие**: систематически запаздывающая промоция depth-опасностей именно в режиме максимального риска.
- **Исправление**: при `MotionState.running` делить `midasInterval` на 2 (пол ~400 мс) и/или `kFusionTemporalFrames=2`. Тест в `performance_throttler_test.dart`: running → `midasInterval` ≤ 400 мс.

## B-3. Сводная таблица порогов

| Константа / inline | Значение | Анализ | Вердикт |
|---|---|---|---|
| `kClassMinConf[person/car/bus/truck]` | 0.40; low-light −0.08, пол 0.20 (`camera_screen.dart:1943-1951`) | FN-защита в темноте целевая (V5.2); шум гасится 2-кадровым подтверждением | OK |
| `person far + conf<0.50` отсев (`camera_screen.dart:1968-1970`) | — | Дальний пешеход в сумерках теряется до трекера; low-light floor не помогает (фильтр после) | Спорно: при weatherDegraded снижать до ~0.42 |
| `kCriticalCooldown` | 800 мс | Глобальный gate very-close критиков; второй ближайший объект ждёт ≤0.8 с, haptic в else-ветке сохранён | OK |
| `kCriticalRepeatCooldownSafety` | 2 с | **Фактически 4 с из-за TTS-дедупа** — A-5 | Дефект |
| `kHazardWarningCooldown` | 4 с | `_lastWarningAt` в FusionEngine глобальный: два разных warning-хазарда подряд (яма → бордюр) — второй ждёт 4 с | Спорно: сделать per-type |
| `kPersonCooldown` / close-person / indoor | 15 / 6 / 15 с | isClose-гистерезис (`_trackIsClose`) удерживает быстрый канал | OK |
| `kCrowdAlertCooldown` | 10 с | Breakaway-исключение (approaching) прорывается | OK (фикс 2.4) |
| `kFusionTemporalFrames`×`kMidasInterval` | 3×800 мс | См. B-2 (running не компенсируется) | Дефект |
| `kFusionEmaAlpha` | 0.30, seed первым значением | Инерции первого кадра нет | OK |
| `kConfEmaAlpha` | 0.20 | После ghost-decay (×0.5/кадр) avgConf <0.50 → при возвращении объекта восстановление ~6-7 матчей (~1 с) до `kMinAlertConf` | Принять (см. D-6) |
| `kEscalationDistanceFraction` 0.70 / sustained 0.70 | — | **При `distanceM == null` эскалации нет вовсе**: `alert_filter.dart:172-178` и `alert_manager.dart:973-978` требуют обе дистанции >0; классы без `kRealDims` (chair, potted plant…) и некалиброванные дистанции не эскалируются | Дефект (СРЕДНЯЯ, B-3a): fallback-эскалация по росту bbox-площади |
| `kVehApproachAreaRateT` 0.22; ego-boost ×1.8 (`tracker.dart:361-364`) | При ходьбе порог 0.396/с | Медленно ползущая машина при идущем пользователе может не набрать rate; страховки: `kVehBboxDangerAreaRatio` 0.35, kinematicThreat (distM≤8), motion prealert, AWM | Принять с оговоркой (СРЕДНЯЯ, B-3b): подтвердить полевыми логами `near_miss_buffer` |
| `_kCriticalCenterScore` 0.65 / nearField 0.55 / slippery 0.50 | — | Периферийные ямы — warning by design (тест 3.1 закрепляет) | OK |
| `deadZone <0.65` / `slippery <0.55` отсев (`depth_pipeline_controller.dart:181-184`) | — | deadZone не critical — приемлемо | OK |
| FallDetector: freefall 3.5 / impact 30 / tumble 25+8 рад/с | — | Падение «мягкое» без удара уходит в Class B (19.62, sustain 200 мс) | OK; см. C-4 (частота сэмплов) |
| `kDetectIntervalSafetyCeilingMs` | 500 мс | Потолок соблюдён во всех ветках `detectInterval`, включая thermal burst и memory-critical | OK |
| `kStationaryGateMidasOff` | 1 ч | Выход через `signalActivity`; `noteCriticalAlert` блокирует гейт 5 с | OK |
| `_kQualityEventCooldown` | 30 с (`camera_screen.dart:191`) | Повторное `cameraBlocked` critical раз в 30 с — для непрерывной блокировки повтор есть; для повторных AE-переходов см. D-1 | OK/частично |
| `MisalignmentWatchdog` | 10/35/15 с | Ужато с 20/60/30 — хорошо; вербальный канал зависит от depth-blind (D-5) | Частично |
| `focalDistM('person')` рост 1.70 м / плечи 0.48 м (`distance_utils.dart:39-52`) | — | Ребёнок (1.1 м) на 2 м читается как ~3.1 м → «close» вместо «very close»; сидячий человек — аналогично. Страхуют MiDaS cross-check (только при калибровке) и near-field | Дефект (СРЕДНЯЯ, B-3c): per-class минимум из height/width оценок уже есть только для person; добавить детский прайор нельзя — честно полагаться на bbox-категорию `distByBox` при конфликте |

---

# C. Корректность FSM

## C-1. FallDetector: смерть/отсутствие гироскопа структурно отключает падения класса A — без уведомления — ВЫСОКАЯ

- **Файл:строка**: `lib/services/fall_detector.dart:96-115` (`init`: `_ready=true` по одному акселерометру; сбой gyro — debugPrint), `:206-214` (stillness требует `gyroStill`), `:216-258` (подтверждение требует `_postImpactGyroPeak ≥ 2.5`, иначе `aborted_no_rotation`; при peak<1.0 без freefall — `aborted_phone_drop`).
- **Сценарий A (нет гироскопа)**: бюджетные устройства целевого сегмента без gyro существуют. `gyroscopeEventStream` бросает → `_lastGyroMagnitude` навсегда 0 → каждый Class A-кандидат отбраковывается как `aborted_phone_drop`/`aborted_no_rotation`. Работает только Class B («медленное оседание при ходьбе»).
- **Сценарий B (стрим завис на ненулевом значении)**: HAL перестал слать события при последнем |ω|>0.5 рад/с → `gyroStill` вечно false → `_stillFrames` обнуляется → stillness недостижим → **оба** класса падений мертвы.
- **Последствие**: `camera_screen.dart:741-747` объявляет `fall_detector_unavailable` только при сбое акселерометра; пользователь с нерабочим gyro уверен в подстраховке, которой нет.
- **Исправление**: (1) при недоступном gyro — деградированный профиль Class A (freefall+impact без rotational-критерия, повышенный `_stillFramesRequired`) + TTS о сниженной точности; (2) staleness-watchdog: нет gyro-событий >2 с при живом акселерометре → считать gyro мёртвым, перейти в профиль (1), залогировать. Тест: симулировать отсутствие gyro-событий → tumble подтверждается по деградированному профилю.

## C-2. `AlertManager.reset()` — мёртвый код: ни одного вызова в `lib/` — СРЕДНЯЯ

- **Файл:строка**: `lib/camera/alert_manager.dart:184-201`; grep по `lib/` — только определение.
- **Сценарий**: смена режима идёт через `markModeSwitch` (частичный сброс «clear»-логики); полный сброс фильтра/движка не выполняется никогда. `_lastAnnouncedDistM` растёт неограниченно (track id монотонны за сессию); `_suppressUntilByCategory`/`_lastCriticalByCat` переживают переключения street↔cane↔scan.
- **Последствие**: (а) утечка памяти за многочасовую сессию; (б) stale-cooldown'ы после возврата из scan-режима могут отложить первый алерт (время-базированность смягчает).
- **Исправление**: вызывать `alertMgr.reset()` в `CameraViewModel.setMode`; чистить `_lastAnnouncedDistM` по `presentIds` (аналогично `_trackIsClose`, `alert_manager.dart:473-474`).

## C-3. FallCountdownController: одиночное касание экрана мгновенно отменяет отсчёт SOS — СРЕДНЯЯ

- **Файл:строка**: `lib/camera/fall_countdown_controller.dart:147-150` (`notifyTouch` → `cancel()`); `lib/camera_screen.dart:946-951` (`_handleTap`).
- **Сценарий**: телефон после падения скользит по асфальту / пользователь судорожно хватает его — ёмкостный экран регистрирует tap → отсчёт отменён одним касанием, без подтверждения. Контраст: голосовая отмена требует двухфазного подтверждения (`requestVoiceCancel` + тач/тап-корроборация).
- **Последствие**: SOS не уходит после реального падения; повторного события не будет — человек уже лежит неподвижно. Смягчение: отмена озвучивается critical-фразой `sos_fall_cancelled`.
- **Исправление**: для отмены — double-tap или удержание ≥400 мс (паттерн корроборации уже есть: `kDeliberateTapThresholdMps2`); на одиночный tap — «коснитесь ещё раз для отмены».

## C-4. FallDetector: окна на счётчиках кадров зависят от фактической частоты сенсора — СРЕДНЯЯ

- **Файл:строка**: `lib/services/fall_detector.dart:55` (`_stillFramesRequired=40`), `:69` (`_classBStillFramesRequired=100`); `samplingPeriod: 50ms` — для Android это hint, реальная частота 5–200 Гц по вендорам.
- **Сценарий**: на 200 Гц stillness-окно Class A сжимается с 2 с до 0.4 с; на 10 Гц Class B требует 10 с неподвижности при таймауте `_classBPostImpactTimeout=10 с` — подтверждение становится недостижимым.
- **Последствие**: на части устройств Class B молча не работает.
- **Исправление**: перевести окна со счётчиков кадров на `DateTime`-интервалы (как уже сделано для `_classBSustainMin`).

## C-5. Проверенные FSM без существенных дефектов (+ одна оговорка)

- **Thermal tier FSM** (`performance_throttler.dart:60-86`): эскалация мгновенна; recovery требует 30 с непрерывного снижения (`_thermalDropStartedAt` сбрасывается при равенстве) — осцилляции и deadlock'и исключены. Отказобезопасность канала — A-8.
- **MiDaS-pause**: вход/выход анонсируются однократно через `onMidasPauseChanged` → TTS с cooldown 30 с (`camera_screen.dart:1799-1818`); memory-critical входит в `isOverheating` → пауза анонсируется. Корректно.
- **Tracker lifecycle**: tentative→confirmed (2 кадра), ghost decay ×0.5 с 4-го predict-only кадра, смерть при age>6; graveyard-наследование approaching ограничено vehicle+IoU≥0.15+TTL 3 с — направление false-positive, не FN. Длинная blur-серия: треки живут до ~24 кадров, но ghost-decay глушит conf — алертов от «призраков» нет (закреплено V1.5).
- **DepthPipelineStatus**: выход из lowConfidence только через успешный кадр; если провайдер не вернётся — статус остаётся объявленным (деградация **с** уведомлением). Дыры «не готов»/«исключение» — A-2/A-3.
- **FallCountdown × CameraLifecycle**: таймер отсчёта и `sendSos` не зависят от камеры/фона; foreground-service удерживает процесс. Конфликт TTS отсчёта с critical-алертами — D-4.
- **C-5a (оговорка, СРЕДНЯЯ)**: `camera_lifecycle_controller.dart:131-132,148-149` — повторные предупреждения «приложение в фоне» только при `MotionState.walking`: **бегущий** пользователь получает предупреждение один раз. Исправление: условие `state != stationary`.

---

# D. Граничные случаи детекции

## D-1. AE-переход (выход из подземного перехода на свет): полная сенсорная слепота до 30 кадров + 1.5 с; ветка motion-prealert-страховки — мёртвый код — ВЫСОКАЯ

- **Файл:строка**: `lib/camera_screen.dart:1433-1449` — при `aePipelineFrozen` вызывается `_vm.motionPreAlert.feed(..., aeTransitioning: true, ...)`; `lib/services/motion_prealert.dart:92` — `if (aeTransitioning) return null;` **до** какой-либо обработки. Окно: до 30 кадров перехода + 1.5 с post-guard (`frame_quality_guard.dart:98-100,151-156`).
- **Сценарий**: выход из тёмного перехода к проезжей части — ровно момент AE-переэкспозиции. YOLO не выполняется (ранний return), depth не вызывается, а «страховочный» вызов motion prealert гарантированно возвращает null: фикс «Safety audit 5.3» отрезал AE-кадры внутри `feed` (закреплено тестом), а вызов с литеральным `aeTransitioning: true` в camera_screen остался. Уведомление — только earcon `cameraBlocked` на старте перехода с cooldown 30 с: второй переход за 30 с вообще беззвучен.
- **Последствие**: до ~2.5–3 с слепоты в систематически опасной точке маршрута; код создаёт ложное впечатление наличия страховки.
- **Исправление**: либо удалить мёртвую ветку и расширить уведомление (earcon на каждый AE-старт длительностью >N кадров), либо реализовать настоящую AE-устойчивую страховку: motion prealert на нормированной (per-frame mean-subtracted) сетке, которой глобальный сдвиг яркости не страшен. Тест: AE-кадры с вторгающимся блобом → событие генерируется.

## D-2. Две одновременные критические опасности одной категории: вторая теряется без следа — СРЕДНЯЯ

- **Файл:строка**: `lib/utils/alert_filter.dart:285-300` (`flushMulti`: второй победитель обязан быть из **другой** категории), `:302` (`_candidates.clear()`).
- **Сценарий**: две машины одновременно — слева и справа (перекрёсток). Оба кандидата critical категории approachingVehicle: первый произносится, второй отбрасывается; его повтор на следующем кадре блокируется `_lastCriticalByCat` на 2 с (затем ещё TTS-дедуп — A-5, если текст совпал). Направленная информация («справа») теряется на 2–4 с.
- **Последствие**: пользователь делает шаг от первой машины — в сторону второй. Смягчение: haptic/earcon первого алерта предупреждают об опасности как таковой.
- **Исправление**: в `flushMulti` разрешить второго critical-победителя той же категории при разных знаках `pan` (разные стороны) либо склеивать тексты («Стоп. Машины слева и справа»).

## D-3. FusionEngine: одно-зонная история — чередующиеся хазарды в разных зонах бесконечно сбрасывают темпоральное подтверждение — СРЕДНЯЯ

- **Файл:строка**: `lib/utils/fusion_engine.dart:31-36` — единственный `_lastZoneIdx`; |Δzone|≥2 чистит **всю** историю и EMA.
- **Сценарий**: сброс задуман против разворота на 180° (легитимно), но при двух устойчивых опасностях (яма слева zone 0, бордюр в центре zone 2) вызовы чередуются 0,2,0,2 → каждый сбрасывает накопление → fusion-промоция в critical не наступает никогда. Прямые критерии `_isHazardCritical` (score ≥0.65 в центре) продолжают работать.
- **Последствие**: пограничные (score 0.50–0.65) множественные опасности остаются warning.
- **Исправление**: per-zone история с TTL вместо глобального сброса; глобальный сброс — по компасу/гироскопу (реальный разворот), а не по чередованию зон.

## D-4. Падение на лестнице: critical-алерты (stairsDown) вытесняют warning-анонсы отсчёта SOS из TTS-очереди — СРЕДНЯЯ

- **Файл:строка**: `lib/services/tts_service.dart:738` (critical → `_queue.removeWhere(priority != critical)`); `lib/camera/fall_countdown_controller.dart:222-236` (отметки «осталось N секунд» — `SpeechPriority.warning`).
- **Сценарий**: пользователь упал на лестнице, камера продолжает видеть ступени → каждые 2–4 с приходит critical `hazard_stairs_down`, каждый раз выбрасывая из очереди запланированные warning-отметки отсчёта. Стартовое «Обнаружено падение» — critical и прозвучит; счёт «10…5…3-2-1» может быть полностью съеден.
- **Последствие**: пользователь не знает, сколько осталось до отправки SOS, и не успевает осознанно отменить/подтвердить. Fail-safe направление сохранено: SOS уходит.
- **Исправление**: на время `fallCountdown.active` поднимать отметки отсчёта до critical либо гейтить выдачу depth-хазардов в `alertMgr`, оставив haptic.

## D-5. MisalignmentWatchdog: вербальное предупреждение зависит от depth-blind-подтверждения, которое при «тихих» отказах глубины не наступает; `running` исключён — СРЕДНЯЯ

- **Файл:строка**: `lib/services/misalignment_watchdog.dart:110` (`walking` строго), `:138` (`isDepthBlindAt` гейтит обе вербальные ветки).
- **Сценарий**: (а) телефон у бегущего пользователя свисает к земле — `_motion == running` → сторож не активируется вовсе; (б) depth-канал отказал по A-2/A-4 (статус застрял в `ok`) → `_depthLowSinceAt == null` → вербального «поднимите телефон» не будет никогда; остаётся только периодическая хаптика (она, к чести модуля, depth-условием не гейтится).
- **Последствие**: главный механизм против «камера смотрит в землю, всё молчит» наследует слепые зоны статус-машины глубины.
- **Исправление**: (а) `_motion != stationary`; (б) дополнительный вербальный триггер «нет YOLO-детекций ≥20 с при ходьбе + pitch не optimal» без depth-условия.

## D-6. Устойчивые граничные случаи (положительные проверки)

- **Объект >80% кадра**: `distByBox` даёт `very close` по area/height (`distance_utils.dart:99-106`); клиппинг bbox у края завышает pixelSize → `focalDistM` занижает дистанцию (fail-safe направление). Для машин — абсолютный триггер `kVehBboxDangerAreaRatio=0.35`; для людей — `sizeSanityEscalation` (bboxFrac ≥0.75 → critical, `alert_manager.dart:980-989`). При развале YOLO-класса на сверхблизкой дистанции страхуют near-field depth (`nearFieldIntrusion`, critical при score ≥0.55) и motion prealert. Слоистая защита присутствует.
- **Камера закрыта пальцем/в кармане**: `cameraBlocked` (30 кадров низкой яркости) → critical TTS + haptic каждые 30 с; частичное перекрытие — warning; «телефон оставлен» (M12) корректно требует stationary+frozen+normal-luma. Идущий пользователь с телефоном в кармане получает повторяющийся critical. OK.
- **Разворот на 180°**: stale-YOLO 1600 мс зануляет вклад YOLO в fusion; ghost-decay глушит «призраков за спиной»; fusion-сброс по |Δzone|≥2 работает (с побочкой D-3). Graveyard может на ≤3 с воскресить `approaching` на новом объекте в той же области экрана — направление FP, допустимо.
- **`_handleVeryClose` прямой TTS**: регистрируется в фильтре через `noteCritical` (фикс 3.2) — дабл-файра с `flushMulti` нет; глобальный gate 800 мс между very-close критиками разных треков — приемлемый компромисс (haptic `kHapticCriticalCooldownPattern` в else-ветке сохраняется, см. однако A-9).
- **Blur-серия**: алерты не генерируются (predict-only), но `shake_warning` приходит после 15 кадров + cooldown 6 с; короткие смазы покрыты preserveApproaching (gap ≤3, закреплено тестом 2.5). Принято.

---

# E. Надёжность SOS

Полная трасса: `FallDetector.onFallDetected` → `FallCountdownController` (15/30 с, winter ×0.7, dazed-check) → `SosService.sendSos` → `Permission.sms` → MethodChannel `bagdar/sms` → `MainActivity.kt` (SmsManager) → fallback `sms:` URI → финальный `tel:`; параллельно H7 follow-up (`queueFollowUpFall`, ретраи S-2) и H9-контекст (шаги/азимут/Wi-Fi/cell, max age 10 мин).

## E-1. Kotlin `sendSms` без `sentIntent`/`deliveryIntent`: `success(true)` = «поставлено в очередь», а не «отправлено» — в радио-мёртвой зоне SOS теряется молча — КРИТИЧЕСКАЯ

- **Файл:строка**: `android/app/src/main/kotlin/com/example/bagdar/MainActivity.kt:298-312` — `sendTextMessage(phoneNumber, null, message, null, null)` / `sendMultipartTextMessage(..., null, null)`, сразу `result.success(true)`.
- **Сценарий**: пользователь упал в подвале/метро/вне покрытия. `SmsManager` принимает сообщение в очередь без исключения → Kotlin возвращает true → Dart (`sos_service.dart:207-213`) трактует как `sent` → `FallCountdownController._sendFallSos` вызывает `onSosSent` (20-с lockout детектора) и произносит «SOS отправлен». Радио-результат (`RESULT_ERROR_NO_SERVICE`, `RESULT_ERROR_GENERIC_FAILURE`, блокировка короткого номера оператором) не наблюдается вовсе. Плановый вопрос «SMS на 112 в Казахстане не доставляется у части операторов» усугубляется: для 112 enqueue тоже «успешен», и фолбэк-цепочка (`sms:` URI → `tel:`) **не активируется**, потому что первый шаг отчитался успехом.
- **Последствие**: ложное подтверждение жизненно важной отправки; реальный контакт ничего не получил; пользователь прекращает попытки.
- **Исправление**: PendingIntent + BroadcastReceiver на SENT (и DELIVERED, где поддерживается):
  ```kotlin
  val sentPi = PendingIntent.getBroadcast(this, reqId,
      Intent(ACTION_SMS_SENT).setPackage(packageName),
      PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  // receiver: resultCode == RESULT_OK → result.success(true); иначе success(false)
  // таймаут 10 с (Handler) → success(false), чтобы Dart не завис
  ```
  В Dart различать `enqueued`/`confirmedSent`; без подтверждения за таймаут — TTS «SOS поставлен в очередь, доставка не подтверждена, продолжаю попытки» и переход по фолбэк-цепочке. Тест: канал-мок false/таймаут → ожидать `sms:`-fallback и честный TTS.

## E-2. `launchUrl(sms:)` и `tel:` маппятся в `sent`/`sentFallback`: «SOS отправлен» звучит, когда лишь открылся композер SMS или набиратель (без звонка) — КРИТИЧЕСКАЯ

- **Файл:строка**: `lib/services/sos_service.dart:215-227` (`_tryDeliver`: успешный `launchUrl(smsUri)` → `sent`/`sentFallback`), `:188-198` (`tel:`-fallback; `buildTelUri` открывает набиратель — ACTION_DIAL, вызов **не** начинается).
- **Сценарий**: SEND_SMS отозван/запрещён (политика MIUI/вендора) → нативный путь false → открывается чужое SMS-приложение с заполненным телом. Незрячему, возможно лежащему после падения, нужно найти кнопку «Отправить» в **невизуально незнакомом** интерфейсе. При этом `_triggerSos`/`_sendFallSos` уже произнесли `sos_sent`/`sos_fall_sent` и (для падения) вызвали `onSosSent` → lockout. То же для `tel:`: открыт набиратель, звонка нет, отчёт — «отправлено».
- **Последствие**: подтверждение без действия; follow-up-цепочка (H7) дальше шлёт SMS тем же ложноположительным путём.
- **Исправление**: ввести исходы `SosResult.composerOpened`/`dialerOpened` с отдельными фразами: «Открыто окно сообщения. Кнопка „Отправить“ — внизу справа» + направляющая хаптика; не вызывать `onSosSent` для этих исходов; для звонка рассмотреть `ACTION_CALL` + CALL_PHONE permission (для 112 ACTION_DIAL законодательно надёжнее — но тогда явная инструкция «нажмите зелёную кнопку»).

## E-3. `Permission.sms.request()` в момент ЧП: системный диалог поверх отсчёта — СРЕДНЯЯ

- **Файл:строка**: `lib/services/sos_service.dart:379-385` (внутри `_sendSmsDirect`).
- **Сценарий**: разрешение не выдано заранее (онбординг пропущен/система отозвала). В момент падения всплывает диалог, который незрячий должен найти и подтвердить; TalkBack может перехватить фокус; отказ → `permanentlyDenied` → весь нативный путь мёртв, остаётся композер (см. E-2).
- **Последствие**: критический путь зависит от интерактивного диалога в наихудший момент.
- **Исправление**: запрашивать SEND_SMS в онбординге на шаге SOS-контакта (и повторно при сохранении номера); при старте сессии — фоновая проверка с TTS-предупреждением «SMS-разрешение отозвано, SOS будет медленнее».

## E-4. Dual-SIM: `SmsManager.getDefault()` без выбора подписки — СРЕДНЯЯ

- **Файл:строка**: `MainActivity.kt:299`.
- **Сценарий**: двухсимочное устройство, default-SMS-подписка «спрашивать каждый раз» или SIM1 без баланса/сети. `getDefault()` использует дефолтную подписку; диалога выбора в headless-пути нет — отправка может тихо уйти в никуда (в связке с E-1 ошибка не видна).
- **Исправление**: `SubscriptionManager.getActiveSubscriptionInfoList()` → при недоставке по дефолтной SIM ретрай по второй; на API 31+ использовать `context.getSystemService(SmsManager::class.java)`.

## E-5. `_resolvePosition`: `getLastKnownPosition` без ограничения возраста — СРЕДНЯЯ (частично смягчено)

- **Файл:строка**: `lib/services/sos_service.dart:484-489`.
- **Сценарий**: свежий fix не получен за 5 с → берётся lastKnown без проверки давности (кэш `_cachedPosition` имеет cap 2 мин, lastKnown — нет): координаты могут быть многочасовой давности (вчерашняя поездка).
- **Смягчение**: `buildMessageText` помечает позицию «данные N мин назад» (закреплено тестом «stale position»), помощник видит давность.
- **Исправление**: при age >30 мин предпочитать `sos_no_gps` + Wi-Fi/cell-контекст (H9) вместо координат, ведущих в неверное место.

## E-6. H9-контекст: шаги/азимут привязываются только при активной навигации — СРЕДНЯЯ

- **Файл:строка**: `lib/services/sos_service.dart:90-95` (`updateCachedPosition` устанавливает `_stepsAtCachedPosition`); единственный вызов — `nav.onPositionUpdated` (`lib/viewmodels/camera_view_model.dart:457-459`).
- **Сценарий**: пользователь ходит без запущенной навигации (большинство сессий) → `_cachedPosition == null` → «шагов с последней точки: N, направление X» в SMS отсутствует; остаётся только Wi-Fi/cell-снимок, собираемый в момент SOS.
- **Исправление**: периодически (раз в 2–3 мин при движении) обновлять кэш-позицию из дешёвого `getLastKnownPosition` + шагомер, независимо от навигации.

## E-7. Устойчивые элементы SOS-цепочки (положительные проверки)

- **Отказ TTS не блокирует SOS**: `sendSos` не зависит от TTS; подтверждение дублируется хаптикой (`fall_countdown_controller.dart:330-352` — `kHapticTtsStallPattern` при недоступном TTS).
- **Ретраи и follow-up**: 3 попытки × 2 цели (контакт, затем 112 — `_kEmergencyNumber`), пауза 2 с; H7 follow-up SMS через 10 мин с ретраями S-2 (закреплено тестами).
- **Позиция резолвится один раз** на серию попыток — нет накопления 5-с таймаутов GPS.
- **Лимит «не более 5 SOS SMS за 10 мин»** (`_kMaxSosPerWindow`) защищает от спама при дребезге детектора; критический путь при превышении честно озвучивает `sos_rate_limited`.
- **Native watchdog** (`MainActivity.kt:200-260`): ping каждые 2 с из Dart; 6 с тишины в foreground → системный аларм-звук + вибрация — покрывает зависание Dart-изолята. Корректно отключается в `onPause` (фоновая пауза — не зависание).
- **Нормализация номера** (`_normalizePhoneNumber`): пробелы/скобки/дефисы вычищаются, `+` сохраняется; формат `8702…` уходит как есть (валидно для КЗ).

---

# Сводная таблица находок (по серьёзности)

| № | Серьёзность | Находка | Файл:строка | Тест-покрытие |
|---|---|---|---|---|
| A-1 | КРИТИЧЕСКАЯ | Отказ thermal-перезагрузки YOLO → детекция объектов выключена навсегда, без уведомления; самоблокировка ретраев | `model_service.dart:152-175`; `camera_screen.dart:1507` | **Нет** (`model_service_tier_test.dart` покрывает только маппинг tier) |
| A-2 | КРИТИЧЕСКАЯ | `onSessionDisabled` NCNN никем не подписан; «провайдер не готов» не двигает статус-машину → depth молча мёртв | `ncnn_depth_provider.dart:35,322-343`; `depth_pipeline_controller.dart:127-131` | **Нет** |
| E-1 | КРИТИЧЕСКАЯ | SMS без sentIntent/deliveryIntent: success = enqueue; SOS теряется в мёртвой зоне с ложным «SOS отправлен» | `MainActivity.kt:298-312`; `sos_service.dart:207-213` | **Нет** (`sos_service_test.dart` — только формирование сообщений/URI) |
| E-2 | КРИТИЧЕСКАЯ | Открытие SMS-композера/набирателя маппится в `sent`/`sentFallback` — подтверждение без действия | `sos_service.dart:188-198,215-227` | **Нет** |
| A-3 | ВЫСОКАЯ | catch в `analyze` глотает исключения мимо статус-машины (недоделка фикса 3.2); `RangeError` в `_extractLuma` | `depth_pipeline_controller.dart:214-218`; `depth_provider.dart:283-303` | **Нет** |
| A-4 | ВЫСОКАЯ | Degenerate-выход (confidence=0) классифицируется как здоровый: `score > 0` в фильтре; `_recordFailure` не вызывается | `depth_pipeline_controller.dart:134-135`; `ncnn_depth_provider.dart:219-233` | **Нет** |
| A-5 | ВЫСОКАЯ | TTS-дедуп critical 4 с > safety-cooldown 2 с: разрешённый повтор critical молча гасится | `tts_service.dart:674,722-726`; `constants.dart:196` | **Нет** (`tts_service_test.dart` дедуп-окно не проверяет) |
| A-6 | ВЫСОКАЯ | Исключение `_initCamera`: без TTS/хаптики + ложное «Система готова»; первый звук через ~60 с | `camera_screen.dart:1373-1381,854-856` | **Нет** |
| B-1 | ВЫСОКАЯ | Связка категорий approachingVehicle↔obstacleClose блокирует critical другой природы на 2 с | `alert_filter.dart:156-183,366-388` | Частично (тест 1.4 проверяет несвязанные категории) |
| B-2 | ВЫСОКАЯ | Бег не ускоряет MiDaS/fusion: подтверждение depth-critical 2.4 с = 7+ м | `performance_throttler.dart:283-308` | Частично (`performance_throttler_test.dart` — только detect-интервалы) |
| C-1 | ВЫСОКАЯ | Смерть/отсутствие гироскопа отключает падения Class A без уведомления; `isReady` отражает только акселерометр | `fall_detector.dart:96-115,206-258` | **Нет** (`fall_detector_lockout_test.dart` — только lockout) |
| D-1 | ВЫСОКАЯ | AE-переход: слепота до 30 кадров + 1.5 с; ветка motion-prealert-страховки — мёртвый код | `camera_screen.dart:1433-1449`; `motion_prealert.dart:92` | Частично (тест 5.3 закрепляет подавление, не страховку) |
| A-7 | СРЕДНЯЯ | Warm-resume: async-ошибка `startImageStream` не ловится (смягчено StallWatchdog) | `camera_lifecycle_controller.dart:183-192` | Частично (`stall_watchdog_test.dart`) |
| A-8 | СРЕДНЯЯ | Сбой канала thermal/memory → severity normal: снятие троттлинга на горячем устройстве | `thermal_monitor.dart:160-163`; `memory_monitor.dart:96-99` | **Нет** |
| A-9 | СРЕДНЯЯ | Floor хаптики не покрывает `kHapticCriticalAlertPattern` | `haptic_service.dart:42-48` | **Нет** |
| B-3a | СРЕДНЯЯ | Эскалация по дистанции требует `distanceM > 0` у обоих алертов — классы без `kRealDims` не эскалируются | `alert_filter.dart:172-178`; `alert_manager.dart:973-978` | **Нет** |
| B-3b | СРЕДНЯЯ | Ego-boost ×1.8 поднимает approach-порог при ходьбе — подтвердить полевыми логами | `tracker.dart:361-364` | Частично (`tracker_test.dart`) |
| B-3c | СРЕДНЯЯ | `focalDistM('person')` с ростом 1.70 м завышает дистанцию до детей/сидячих | `distance_utils.dart:39-52` | **Нет** |
| C-2 | СРЕДНЯЯ | `AlertManager.reset()` — мёртвый код; `_lastAnnouncedDistM` растёт неограниченно | `alert_manager.dart:184-201` | **Нет** |
| C-3 | СРЕДНЯЯ | Одиночный tap мгновенно отменяет отсчёт SOS | `fall_countdown_controller.dart:147-150` | **Нет** (`fall_countdown_dazed_test.dart` — только dazed) |
| C-4 | СРЕДНЯЯ | Окна FallDetector на счётчиках кадров зависят от частоты сенсора | `fall_detector.dart:55,69` | **Нет** |
| C-5a | СРЕДНЯЯ | Paused-повторы «приложение в фоне» только при walking — running исключён | `camera_lifecycle_controller.dart:131-132,148-149` | **Нет** |
| D-2 | СРЕДНЯЯ | Вторая critical той же категории теряется в `flushMulti` | `alert_filter.dart:285-302` | **Нет** |
| D-3 | СРЕДНЯЯ | Одно-зонная история fusion: чередующиеся зоны бесконечно сбрасывают подтверждение | `fusion_engine.dart:31-36` | **Нет** |
| D-4 | СРЕДНЯЯ | Critical-алерты вытесняют warning-анонсы отсчёта SOS из TTS-очереди | `tts_service.dart:738`; `fall_countdown_controller.dart:222-236` | **Нет** |
| D-5 | СРЕДНЯЯ | Вербальный канал MisalignmentWatchdog зависит от depth-blind; running исключён | `misalignment_watchdog.dart:110,138` | Частично (`misalignment_watchdog_test.dart` — закрепляет текущее поведение) |
| E-3 | СРЕДНЯЯ | `Permission.sms.request()` в момент ЧП | `sos_service.dart:379-385` | **Нет** |
| E-4 | СРЕДНЯЯ | Dual-SIM `SmsManager.getDefault()` без выбора подписки | `MainActivity.kt:299` | **Нет** |
| E-5 | СРЕДНЯЯ | `lastKnownPosition` без age-cap (смягчено stale-меткой) | `sos_service.dart:484-489` | Частично (stale-метка покрыта) |
| E-6 | СРЕДНЯЯ | H9-контекст (шаги/азимут) только при активной навигации | `sos_service.dart:90-95`; `camera_view_model.dart:457-459` | **Нет** |

**Итого**: 4 КРИТИЧЕСКИХ, 8 ВЫСОКИХ, 18 СРЕДНИХ (включая под-находки таблицы порогов и оговорки C-5a).

---

# Находки без тест-покрытия — рекомендованные регрессионные тесты

Приоритет 1 (КРИТИЧЕСКИЕ):

- **A-1**: `model_service_yolo_reload_failure_test.dart` — мок `FlutterVision.loadYoloModel`, бросающий на перезагрузке: ожидать (а) попытку отката на прежний tier, (б) колбэк `onYoloUnavailable`, (в) `yoloLoaded == true` после успешного отката.
- **A-2**: расширить `depth_pipeline_controller`-тесты: провайдер с `isReady == false` N кадров подряд → `onStatusChanged(lowConfidence)`; NCNN-мок с 3 invalid-выходами → колбэк session-disable доходит до контроллера.
- **E-1**: канал-мок `bagdar/sms`, возвращающий false/таймаут → `sendSos` обязан перейти к `sms:`-fallback и вернуть результат ≠ `sent`; результат `enqueued` без подтверждения не должен озвучиваться как «отправлено».
- **E-2**: `_tryDeliver` с заглушкой `launchUrl == true` → результат должен быть `composerOpened` (после фикса), `onSosSent` не вызывается.

Приоритет 2 (ВЫСОКИЕ):

- **A-3/A-4**: провайдер-мок, бросающий из `analyze` / возвращающий confidence 0 → статус-переход после 3 кадров.
- **A-5**: `tts_service_test.dart` — два critical с одинаковым текстом, Δt = 2.5 с → второй в очереди (после выравнивания окна).
- **A-6**: `_initCamera`-исключение → critical TTS + отсутствие `system_ready`.
- **B-1**: тест в группе 1.4 — critical obstacleClose(depth) при t=0, critical approachingVehicle при t=1 с → второй разрешён.
- **B-2**: `performance_throttler_test.dart` — `midasInterval` при running ≤ 400 мс.
- **C-1**: `fall_detector`-тест без gyro-событий → Class A подтверждается по деградированному профилю + флаг деградации.
- **D-1**: `synthetic_event_camera_test.dart` — AE-кадры с вторгающимся блобом → событие генерируется (после реализации AE-устойчивой сетки).

Приоритет 3 (СРЕДНИЕ): D-2 (две critical одной категории с разным `pan` → обе/склейка), D-3 (чередование зон 0/2 → промоция наступает), C-3 (одиночный tap не отменяет; double-tap отменяет), A-8 (N сбоев канала → severity удерживается), A-9 (floor применяется к `kHapticCriticalAlertPattern`), B-3a (эскалация по росту bbox при `distanceM == null`).

---

# Заключение

Архитектура каналов уведомления (TTS-очередь с приоритетами, earcon, haptic, native watchdog) и слоистая детекция (YOLO + MiDaS + motion prealert + acoustic) спроектированы грамотно, прошлые аудит-фиксы (1.x–5.x, H5–H9, V1–V5, M12, S-2) реальны и закреплены тестами. Главный остаточный риск — **молчаливые деградации инфраструктуры детекции** (A-1, A-2, A-3, A-4: модель/провайдер умирает, а статус-машины и heartbeat продолжают сигнализировать «всё хорошо») и **ложные подтверждения SOS** (E-1, E-2: «SOS отправлен» при фактическом enqueue/открытии композера). Обе группы нарушают базовый принцип проекта: false negative дороже false positive. Рекомендуемый порядок работ: E-1/E-2 (подтверждение отправки) → A-1/A-2 (наблюдаемость отказов детекции) → A-3/A-4/A-5/A-6 → остальное по таблице.


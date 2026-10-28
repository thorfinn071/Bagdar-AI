# Промты для ИИ — фиксы проблем safety-аудита (июнь 2026)

Промты сгруппированы по фазам согласно правилам проекта:
1. **Safety-critical** (Critical) — Phase 1
2. **Broken declared features** (High) — Phase 2
3. **Latency/UX** (Medium/Low) — Phase 3

Каждый промт самодостаточен: содержит точные file:line, описание проблемы, требуемое исправление, ограничения (что НЕ трогать), тесты и локализацию.

---

## Phase 1 — Safety-Critical (Critical)

### Промт A-2: Session-disable NCNN молчалив

```
Ты работаешь над проектом Bagdar AI — офлайн-ассистент для незрячих пользователей на Android.

ПРОБЛЕМА (Critical): NcnnDepthProvider при 3 невалидных выходах (NaN/Inf) за 5 минут
устанавливает _permanentlyDisabled = true и вызывает колбэк onSessionDisabled.
Однако этот колбэк НИКЕМ НЕ ПОДПИСАН — grep по lib/ даёт только объявление
(ncnn_depth_provider.dart:35) и вызов (:348). В DepthPipelineController.analyze
(depth_pipeline_controller.dart:128-131) ветка "provider == null || !provider.isReady"
делает ранний return [] БЕЗ инкремента degraded-счётчиков — статус остаётся ok.

ПОСЛЕДСТВИЕ: ступени вниз, ямы, glass door, near-field выключаются до перезапуска
приложения; нет TTS depth_degraded; пользователь не знает, что идёт к лестнице
без подстраховки.

ФАЙЛЫ:
- lib/services/ncnn_depth_provider.dart:35 — объявление onSessionDisabled
- lib/services/ncnn_depth_provider.dart:348 — вызов onSessionDisabled?.call()
- lib/camera/depth_pipeline_controller.dart:128-131 — ранний return без статуса

ИСПРАВЛЕНИЕ:
1. В DepthPipelineController (или в месте создания NcnnDepthProvider — найти через
   grep "NcnnDepthProvider(") подписаться на onSessionDisabled:
   ```dart
   ncnnProvider.onSessionDisabled = () {
     _setStatus(DepthPipelineStatus.lowConfidence);
   };
   ```
2. В analyze() ветку "provider == null || !provider.isReady" (строки 128-131)
   изменить: инкрементировать _consecutiveLowConfidenceFrames и при достижении
   _kDegradedFramesToAnnounce вызывать _setStatus(DepthPipelineStatus.lowConfidence).
   НЕ возвращать [] молча — считать это degraded-кадром.
3. Убедиться, что onStatusChanged пробрасывается в TTS через существующий механизм
   (проверить _setStatus → onStatusChanged → camera_screen TTS depth_degraded).

ЧТО НЕ ТРОГАТЬ:
- Не менять логику _recordFailure / _permanentlyDisabled в ncnn_depth_provider.dart
- Не менять порог 3 failures / 5 min (safety inviolable: NCNN auto-disable)
- Не менять _kDegradedFramesToAnnounce

ТЕСТ:
- В test/ создать/обновить тест: мок NcnnDepthProvider, вызвать 3 раза с NaN выходом
  → ожидать onSessionDisabled → ожидать DepthPipelineStatus.lowConfidence
  → ожидать что onStatusChanged вызван.
- Имя файла: test/depth_pipeline_session_disable_test.dart

ЛОКАЛИЗАЦИЯ:
- Строка depth_degraded уже существует в strings.dart — проверить наличие во всех
  3 языках (ru/kk/en). Если нет — добавить.
```

---

### Промт A-6: Исключение в _initCamera — нет TTS/haptic, ложное "Система готова"

```
Ты работаешь над проектом Bagdar AI — офлайн-ассистент для незрячих пользователей.

ПРОБЛЕМА (Critical): В camera_screen.dart метод _initCamera (строки ~1370-1402)
в catch-блоке (строка 1394) только вызывает _fieldLog.logCameraInit и
_vm.setStatus('Ошибка камеры: $e'). Нет TTS critical, нет haptic, нет retry.
При этом _initAll (строки ~865-866) безусловно говорит "system_ready" через TTS,
Даже если _isCameraReady == false (оно устанавливается только в успешной ветке
_initCamera, но _initAll не проверяет его перед system_ready).

ПОСЛЕДСТВИЕ: при сбое камеры (HAL-сбой, камера занята) пользователь идёт с мёртвой
детекцией и слышит "Система готова". StallWatchdog не запущен (start только в
успешной ветке). Единственное уведомление — heartbeat effFps<3 через ~60 с.

ФАЙЛЫ:
- lib/camera_screen.dart:1394-1402 — catch в _initCamera (только setStatus)
- lib/camera_screen.dart:865-866 — system_ready без проверки _isCameraReady
- lib/camera_screen.dart:868-890 — catch в _initAll (для сравнения паттерна)

ИСПРАВЛЕНИЕ:
1. В catch-блоке _initCamera (строка 1394) добавить:
   - TTS critical с barge: true (использовать существующий паттерн из _initAll catch)
   - HapticService.vibrate(kHapticTtsStallPattern, ...)
   - EarconService.play(Earcon.cameraBlocked)
   - Запустить цикл повторной инициализации (паттерн _speakCameraPermissionDeniedLoop
     уже существует в коде — найти через grep "PermissionDeniedLoop")
2. В _initAll (строка 865) обернуть system_ready в проверку:
   ```dart
   if (_isCameraReady) {
     _vm.setStatus(S.get('system_ready'));
     _vm.tts.say(S.get('system_ready'), SpeechPriority.info, pan: 0.0);
   }
   ```
3. Если камера не готова — сказать критическое сообщение вместо system_ready.

ЧТО НЕ ТРОГАТЬ:
- Не менять успешную ветку _initCamera (строки 1370-1393)
- Не менять StallWatchdog.start() — он должен оставаться в успешной ветке
- Не менять _initAll catch (строки 868-890) — он уже корректен

ТЕСТ:
- В test/ обновить/создать тест: мок availableCameras() бросает исключение
  → ожидать TTS critical + haptic + earcon cameraBlocked
  → ожидать что system_ready НЕ произносится
  → ожидать что _isCameraReady == false

ЛОКАЛИЗАЦИЯ:
- Добавить строку 'camera_init_failed_critical' в strings.dart для всех 3 языков
  (ru/kk/en), если подходящей нет. Текст: "Ошибка камеры. Распознавание
  недоступно. Перезапустите приложение." / "Камера қатесі..." / "Camera error..."
- Проверить что init_failed уже есть во всех 3 языках.
```

---

### Промт C-1: FallDetector — смерть/отсутствие гироскопа отключает Class A без уведомления

```
Ты работаешь над проектом Bagdar AI — офлайн-ассистент для незрячих пользователей.

ПРОБЛЕМА (Critical): В fall_detector.dart init() (строки 96-113) сбой гироскопа
только пишет debugPrint. _ready устанавливается true по одному акселерометру.
При отсутствии gyro: _lastGyroMagnitude навсегда 0 → каждый Class A-кандидат
отбраковывается как aborted_phone_drop / aborted_no_rotation (строки 206-258:
stillness требует gyroStill, подтверждение требует _postImpactGyroPeak >= 2.5).
При зависании стрима на ненулевом значении: gyroStill вечно false → _stillFrames
обнуляется → stillness недостижим → ОБА класса падений мертвы.
camera_screen.dart:741-747 объявляет fall_detector_unavailable только при сбое
акселерометра.

ПОСЛЕДСТВИЕ: пользователь с нерабочим gyro уверен в подстраховке, которой нет.

ФАЙЛЫ:
- lib/services/fall_detector.dart:96-113 — init (gyro сбой = debugPrint)
- lib/services/fall_detector.dart:206-214 — stillness требует gyroStill
- lib/services/fall_detector.dart:216-258 — подтверждение требует gyro peak
- lib/camera_screen.dart:741-747 — объявление fall_detector_unavailable

ИСПРАВЛЕНИЕ:
1. Добавить поле bool _gyroAvailable = false; устанавливать true при успешной
   подписке на gyroSub (строка 100), false в onError (строка 102) и catch (107).
2. Добавить staleness-watchdog: отслеживать _lastGyroEventAt (DateTime). Если
   нет gyro-событий > 2 секунд при живом акселерометре → считать gyro мёртвым,
   установить _gyroAvailable = false.
3. Реализовать деградированный профиль Class A при !_gyroAvailable:
   - freefall + impact БЕЗ rotational-критерия (пропустить проверку
     _postImpactGyroPeak >= 2.5)
   - Повышенный _stillFramesRequired (например ×1.5) для компенсации
   - Пропустить gyroStill в stillness-проверке (заменить на accel-only stillness)
4. При переходе в деградированный профиль — вызвать колбэк onGyroUnavailable
   (новый), который camera_screen подписывает и произносит TTS warning:
   "Точность определения падений снижена" (с cooldown 60 с).
5. В camera_screen.dart:741-747 расширить условие: объявлять
   fall_detector_unavailable также при !_gyroAvailable (но с другим текстом —
   "сниженная точность", не "недоступно").

ЧТО НЕ ТРОГАТЬ:
- Не менять пороги freefall 3.5 / impact 30 (safety inviolable: Fall detection FSM)
- Не менять Class B логику (она не зависит от gyro)
- Не менять samplingPeriod 50ms

ТЕСТ:
- test/fall_detector_gyro_unavailable_test.dart:
  1. Симулировать отсутствие gyro-событий → подтвердить tumble по деградированному
     профилю (freefall + impact без gyro peak)
  2. Симулировать зависание gyro на |ω|>0.5 → подтвердить переход в деградированный
     профиль через 2 с
  3. Подтвердить onGyroUnavailable вызывается

ЛОКАЛИЗАЦИЯ:
- Добавить 'fall_detector_degraded' в strings.dart для всех 3 языков:
  ru: "Точность определения падений снижена. Гироскоп недоступен."
  kk: "Құлауды анықтау дәлдігі төмендетілді. Гироскоп қолжетімсіз."
  en: "Fall detection accuracy reduced. Gyroscope unavailable."
```

---

### Промт D-4: Critical stairsDown вытесняет warning-отметки отсчёта SOS из TTS-очереди

```
Ты работаешь над проектом Bagdar AI — офлайн-ассистент для незрячих пользователей.

ПРОБЛЕМА (Critical): В tts_service.dart:736-739 при поступлении critical задания
очередь очищается от всех non-critical: _queue.removeWhere(j.priority != critical).
FallCountdownController (fall_countdown_controller.dart:222-236) отправляет
отметки отсчёта "осталось N секунд" с приоритетом SpeechPriority.warning.
Сценарий: пользователь упал на лестнице → critical hazard_stairs_down каждые 2-4 с
→ каждый раз выбрасывает запланированные warning-отметки отсчёта из очереди.
Стартовое "Обнаружено падение" (critical) прозвучит, но счёт "10...5...3-2-1"
может быть полностью съеден.

ПОСЛЕДСТВИЕ: пользователь не знает, сколько осталось до отправки SOS, и не успевает
осознанно отменить. Fail-safe направление сохранено (SOS уходит), но UX критичен.

ФАЙЛЫ:
- lib/services/tts_service.dart:736-739 — critical preemption removeWhere
- lib/camera/fall_countdown_controller.dart:222-236 — отметки отсчёта (warning)

ИСПРАВЛЕНИЕ (выбрать один подход, первый предпочтительнее):
ВАРИАНТ A (промоция приоритета):
1. В FallCountdownController добавить флаг bool _active (уже есть).
2. При отправке отметок отсчёта проверять _active: если true, отправлять с
   SpeechPriority.critical вместо warning.
3. Это сделает отметки неуязвимыми для critical-preemption.
4. Добавить barge: true для отметок отсчёта, чтобы они произносились немедленно.

ВАРИАНТ B (гейтинг depth-хазардов):
1. В AlertManager (или camera_screen) добавить проверку: если
   fallCountdown.active → не отправлять depth-hazard critical в TTS,
   только haptic (vibration сохраняется для индикации опасности).
2. Это освобождает TTS-канал для отсчёта.

ЧТО НЕ ТРОГАТЬ:
- Не менять саму логику removeWhere для critical (safety inviolable:
  TTS critical preemption) — меняется ПРИОРИТЕТ отправителя, не логика очереди
- Не менять таймер отсчёта (15/30 с, winter ×0.7)
- Не менять onSosSent lockout

ТЕСТ:
- test/fall_countdown_tts_preemption_test.dart:
  1. Запустить fallCountdown → отправить critical hazard_stairs_down во время
     отсчёта → ожидать что отметка отсчёта "осталось N секунд" всё ещё
     произносится (либо как critical, либо depth-hazard заглушён)
  2. Проверить что "Обнаружено падение" (critical) не теряется

ЛОКАЛИЗАЦИЯ:
- Существующие строки sos_countdown_* уже во всех 3 языках — проверить.
- Если выбран вариант A с barge — убедиться что barge не конфликтует с
  onboarding-блокировкой (barge: true разрешён для real-danger).
```

---

## Phase 2 — Broken Declared Features (High)

### Промт A-3: DepthPipelineController.analyze catch глотает исключения

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В depth_pipeline_controller.dart:214-218 catch-блок только
пишет debugPrint и возвращает []. Не инкрементирует _consecutiveAnalyzeFailures
(или аналогичный счётчик) → статус остаётся ok при перманентных исключениях.
Bounds-guard в _extractLuma (depth_provider.dart) уже исправлен (.clamp), но
catch в analyze не отслеживает повторные сбои.

ФАЙЛЫ:
- lib/camera/depth_pipeline_controller.dart:214-218 — catch без учёта статуса

ИСПРАВЛЕНИЕ:
1. Добавить поле int _consecutiveAnalyzeFailures = 0; (если нет).
2. В catch-блоке (строка 214) инкрементировать _consecutiveAnalyzeFailures++.
3. После 3 подряд (константа _kAnalyzeFailuresToAnnounce = 3) вызвать
   _setStatus(DepthPipelineStatus.lowConfidence).
4. В успешной ветке (после provider.analyze без исключения) сбрасывать
   _consecutiveAnalyzeFailures = 0.
5. Сбрасывать также при _consecutiveLowConfidenceFrames = 0 (строка 150).

ЧТО НЕ ТРОГАТЬ:
- Не менять _extractLuma (уже исправлен)
- Не менять _kDegradedFramesToAnnounce
- Не менять успешную ветку analyze

ТЕСТ:
- test/depth_pipeline_analyze_exception_test.dart:
  Мок-провайдер, бросающий из analyze → 3 вызова → ожидать
  DepthPipelineStatus.lowConfidence → ожидать onStatusChanged.
```

---

### Промт B-1: Межкатегорийная связка approachingVehicle↔obstacleClose блокирует critical

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В alert_filter.dart _updateCategoryState (строки ~372-383)
помечает ОБЕ категории (approachingVehicle и obstacleClose) при срабатывании
любой из них. Окно подавления 2000 мс (строка ~382). В _isAllowed critical-ветка
(строки 156-183) видит свежий _lastCriticalByCat → отказ до t=2.0.
Сценарий: t=0 critical "ступени вниз" (obstacleClose) → t=0.8 critical "машина"
(approachingVehicle) → отказ до t=2.0. Связка гасит РАЗНЫЕ опасности друг другом.

ФАЙЛЫ:
- lib/utils/alert_filter.dart:372-383 — _updateCategoryState (связка)
- lib/utils/alert_filter.dart:156-183 — _isAllowed critical-ветка

ИСПРАВЛЕНИЕ:
1. В _updateCategoryState: применять связку [approachingVehicle, obstacleClose]
   ТОЛЬКО для non-critical кандидатов. Для critical — помечать только свою
   категорию.
   ```dart
   final categoriesToUpdate =
       (urgency != AlertUrgency.critical) &&
       (category == AlertCategory.approachingVehicle ||
        category == AlertCategory.obstacleClose)
       ? [AlertCategory.approachingVehicle, AlertCategory.obstacleClose]
       : [category];
   ```
2. Альтернативно: для critical сократить связанное окно до ≤800 мс
   (kCriticalCooldown).
3. Проверить что дистанционная эскалация (строки 172-182) не сломалась.

ЧТО НЕ ТРОГАТЬ:
- Не менять _isAllowed для non-critical (safety inviolable: AlertFilter
  deduplication and cooldown logic) — только critical-ветку
- Не менять kCriticalCooldown = 800 мс
- Не менять temporal filtering 4-of-5

ТЕСТ:
- Обновить test/safety_audit_fixes_test.dart (группа 1.4):
  obstacleClose(depth critical) → approachingVehicle(critical) с Δt=1 с
  → ожидать что ОБА произносятся.
- Проверить что non-critical связка всё ещё работает (дабл-файр подавляется).
```

---

### Промт B-2: Бег ускоряет YOLO, но не MiDaS/fusion

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В performance_throttler.dart running делит YOLO-интервал на 2
(строки 274-276), но midasInterval() (строки 283-308) не имеет running-логики.
При running: YOLO ~70 мс, но MiDaS остаётся 800 мс × 3 кадра fusion = 2.4 с
подтверждения. На 3 м/с это 7.2 м — яма уже под ногами.

ФАЙЛЫ:
- lib/utils/performance_throttler.dart:274-276 — YOLO running ÷2
- lib/utils/performance_throttler.dart:283-308 — midasInterval (нет running)
- lib/models/constants.dart — kMidasInterval, kFusionTemporalFrames

ИСПРАВЛЕНИЕ:
1. В midasInterval() (строка ~283) после расчёта base интервала добавить:
   ```dart
   if (_motionState == MotionState.running) {
     intervalMs = math.max(200, intervalMs ~/ 2);
   }
   ```
   Это даёт ~400 мс при running (вместо 800 мс).
2. Опционально: при running сократить kFusionTemporalFrames с 3 до 2 через
   параметр (но это меняет safety inviolable — требуется отдельное одобрение).
   Предпочтительно: только midasInterval, без изменения kFusionTemporalFrames.

ЧТО НЕ ТРОГАТЬ:
- Не менять kFusionTemporalFrames = 3 (safety inviolable) без явного одобрения
- Не менять thermal multiplier логику
- Не менять kMidasInterval = 800 (базовое значение)

ТЕСТ:
- test/performance_throttler_test.dart:
  MotionState.running → midasInterval() ≤ 400 мс
  MotionState.walking → midasInterval() == 800 мс (базовый)
  ThermalSeverity.hot + running → midasInterval() ≤ 800 мс (thermal ×2, running ÷2)
```

---

### Промт C-2: AlertManager.reset() — мёртвый код

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): AlertManager.reset() (alert_manager.dart:184-201) существует,
но НИ РАЗУ не вызывается в lib/. При смене режима (street↔cane↔scan) через
CameraViewModel.setMode вызывается только markModeSwitch (частичный сброс).
_lastAnnouncedDistM растёт неограниченно, _suppressUntilByCategory /
_lastCriticalByCat переживают переключения.

ФАЙЛЫ:
- lib/camera/alert_manager.dart:184-201 — reset() (мёртвый код)
- lib/viewmodels/camera_view_model.dart — setMode (найти через grep "setMode")

ИСПРАВЛЕНИЕ:
1. В CameraViewModel.setMode (после markModeSwitch) добавить:
   ```dart
   alertMgr.reset();
   ```
2. В AlertManager.reset() добавить очистку _lastAnnouncedDistM по presentIds
   (аналогично как _trackIsClose чистится в строках 473-474):
   ```dart
   _lastAnnouncedDistM.removeWhere((id, _) => !presentIds.contains(id));
   ```
   Или просто _lastAnnouncedDistM.clear() в reset().
3. Убедиться что reset() также чистит: _suppressUntilByCategory,
   _lastCriticalByCat, _candidates (через AlertFilter), fusion engine.

ЧТО НЕ ТРОГАТЬ:
- Не менять markModeSwitch (он делает частичный сброс — оставить)
- Не менять AlertFilter cooldowns (safety inviolable)
- reset() должен ПОЛНОСТЬЮ сбрасывать состояние менеджера алертов

ТЕСТ:
- test/alert_manager_reset_test.dart:
  1. Создать алерты → вызвать reset() → проверить что все maps/cooldowns пусты
  2. Вызвать setMode(street→cane) → проверить что reset() вызван
  3. Проверить что после reset() первый алерт в новом режиме не подавляется
```

---

### Промт C-3: Одиночное касание мгновенно отменяет отсчёт SOS

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В fall_countdown_controller.dart:147-150 notifyTouch() сразу
вызывает cancel() при _active. Один случайный tap (телефон скользит по асфальту,
пользователь судорожно хватает его) отменяет SOS без подтверждения.
Контраст: голосовая отмена требует двухфазного подтверждения
(requestVoiceCancel + тап-корроборация).

ФАЙЛЫ:
- lib/camera/fall_countdown_controller.dart:147-150 — notifyTouch → cancel()
- lib/camera_screen.dart:946-951 — _handleTap (вызывает notifyTouch)

ИСПРАВЛЕНИЕ:
1. В notifyTouch() реализовать double-tap или hold-подтверждение:
   ```dart
   void notifyTouch() {
     final now = DateTime.now();
     _lastTouchAt = now;
     if (!_active) return;
     if (_lastCancelTapAt != null &&
         now.difference(_lastCancelTapAt!) < kDeliberateTapThreshold) {
       // Второй tap в окне → подтверждение отмены
       cancel();
       _lastCancelTapAt = null;
     } else {
       // Первый tap → запрос подтверждения
       _lastCancelTapAt = now;
       tts.say(
         S.get('sos_cancel_confirm'),
         SpeechPriority.critical,
         pan: 0.0,
         barge: true,
       );
       // Таймер сброса ожидания второго tap (например 3 с)
       _cancelConfirmTimer?.cancel();
       _cancelConfirmTimer = Timer(kDeliberateTapWindow, () {
         _lastCancelTapAt = null;
       });
     }
   }
   ```
2. Добавить поля: DateTime? _lastCancelTapAt; Timer? _cancelConfirmTimer;
3. Использовать существующую константу kDeliberateTapThresholdMps2 как референс
   для порога; добавить kDeliberateTapWindow = Duration(seconds: 3) в constants.dart.

ЧТО НЕ ТРОГАТЬ:
- Не менять requestVoiceCancel (уже двухфазный)
- Не менять таймер отсчёта (15/30 с)
- Не менять onSosSent / onSosCancelled колбэки

ТЕСТ:
- test/fall_countdown_cancel_test.dart:
  1. Активировать отсчёт → одиночный tap → ожидать sos_cancel_confirm TTS,
     отсчёт ПРОДОЛЖАЕТСЯ
  2. Двойной tap в окне 3 с → ожидать cancel(), sos_fall_cancelled TTS
  3. Один tap, затем ждать 3 с, затем tap → ожидать sos_cancel_confirm снова
     (первый tap устарел)

ЛОКАЛИЗАЦИЯ:
- Добавить 'sos_cancel_confirm' в strings.dart для всех 3 языков:
  ru: "Коснитесь ещё раз для отмены SOS."
  kk: "SOS-ты болдырмау үшін тағы бір рет түртіңіз."
  en: "Tap again to cancel SOS."
```

---

### Промт D-1: AE-переход — motion prealert страховка мёртвый код

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В camera_screen.dart:1454-1469 при aePipelineFrozen вызывается
motionPreAlert.feed(..., aeTransitioning: true, ...). Но в motion_prealert.dart:92
первая строка: if (aeTransitioning) return null; — ДО любой обработки.
Результат: до ~2.5-3 с слепоты в опасной точке (выход из перехода к проезжей части),
код создаёт ложное впечатление страховки. Уведомление — только earcon cameraBlocked
на старте с cooldown 30 с (второй переход за 30 с беззвучен).

ФАЙЛЫ:
- lib/camera_screen.dart:1454-1469 — вызов с aeTransitioning: true
- lib/services/motion_prealert.dart:92 — if (aeTransitioning) return null;

ИСПРАВЛЕНИЕ (выбрать один подход):
ВАРИАНТ A (удалить мёртвую ветку + расширить уведомление):
1. Удалить вызов motionPreAlert.feed с aeTransitioning: true из camera_screen.dart.
2. Расширить уведомление: earcon cameraBlocked на КАЖДЫЙ AE-старт длительностью
   >N кадров (сейчас cooldown 30 с). Для AE-переходов использовать отдельный
   cooldown (например 5 с) или убрать cooldown для AE.
3. Добавить TTS warning "Камера адаптируется к свету. Будьте осторожны." при
   AE-старте (cooldown 10 с).

ВАРИАНТ B (реализовать AE-устойчивую страховку):
1. В motion_prealert.dart вместо return null — реализовать обработку на
   нормированной (per-frame mean-subtracted) сетке. Глобальный сдвиг яркости
   при AE не повлияет на relative-дифференс:
   ```dart
   if (aeTransitioning) {
     // Вычесть среднюю яркость кадра перед diff — устойчиво к AE-сдвигу
     return _feedNormalized(image, now);
   }
   ```
2. Это сложнее, но даёт реальную страховку.

ЧТО НЕ ТРОГАТЬ:
- Не менять FrameQualityGuard (aePipelineFrozen detection — корректна)
- Не менять ранний return в _onFrame при aePipelineFrozen (YOLO не выполняется —
  это правильно для AE-слепоты)
- Не менять _kQualityEventCooldown без анализа

ТЕСТ:
- test/motion_prealert_ae_test.dart:
  AE-кадры с вторгающимся блобом → если вариант B: ожидать событие
  → если вариант A: ожидать TTS/earcon на каждый AE-старт

ЛОКАЛИЗАЦИЯ (вариант A):
- Добавить 'camera_ae_transition' в strings.dart для всех 3 языков:
  ru: "Камера адаптируется к свету. Будьте осторожны."
  kk: "Камера жарыққа бейімделуде. Сақ болыңыз."
  en: "Camera adjusting to light. Be careful."
```

---

### Промт D-2: Две одновременные критические опасности одной категории — вторая теряется

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В alert_filter.dart:293-295 flushMulti: второй победитель обязан
быть из ДРУГОЙ категории (cand.category != first.category). Два critical одной
категории (две машины слева и справа на перекрёстке) — второй отбрасывается,
его повтор на следующем кадре блокируется _lastCriticalByCat на 2 с.
Направленная информация ("справа") теряется на 2-4 с.

ФАЙЛЫ:
- lib/utils/alert_filter.dart:293-295 — second = cand only if different category

ИСПРАВЛЕНИЕ:
1. В flushMulti разрешить второго critical-победителя той же категории при
   разных знаках pan (разные стороны):
   ```dart
   } else if (second == null) {
     final sameCatDiffSide = cand.category == first.category &&
         cand.priority == AlertPriority.critical &&
         first.priority == AlertPriority.critical &&
         (cand.pan * first.pan < 0); // разные стороны
     if (cand.category != first.category || sameCatDiffSide) {
       second = cand;
       break;
     }
   }
   ```
2. Альтернативно: склеивать тексты ("Стоп. Машины слева и справа") — но это
   сложнее и требует изменения формата алертов.

ЧТО НЕ ТРОГАТЬ:
- Не менять _isAllowed (cooldown logic — safety inviolable)
- Не менять сортировку _candidates (priority → urgency)
- Не менять _candidates.clear() (строка 302)

ТЕСТ:
- test/alert_filter_same_category_critical_test.dart:
  1. Два critical approachingVehicle с pan=−0.5 и pan=+0.5 → ожидать ОБА
     произносятся
  2. Два critical approachingVehicle с pan=−0.5 и pan=−0.3 (та же сторона)
     → ожидать только первый (второй подавляется — та же сторона)
  3. critical + warning одной категории → ожидать только critical
```

---

### Промт D-5: MisalignmentWatchdog — running исключён, depth-blind гейт

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В misalignment_watchdog.dart:110 условие _motion == walking
строго — бегущий пользователь со свисающим телефоном не получает предупреждение.
В :138 isDepthBlindAt гейтит обе вербальные ветки — при "тихом" отказе глубины
(A-2/A-4, статус застрял в ok) вербального "поднимите телефон" не будет никогда.

ФАЙЛЫ:
- lib/services/misalignment_watchdog.dart:110 — walking строго
- lib/services/misalignment_watchdog.dart:138 — isDepthBlindAt гейтит вербальные

ИСПРАВЛЕНИЕ:
1. Заменить walking на _motion != stationary (строка 110):
   ```dart
   final moving = _motion == MotionState.walking ||
       _motion == MotionState.running;
   final sustainedNow = misaligned && moving && noRecentDetections;
   ```
2. Добавить дополнительный вербальный триггер БЕЗ depth-условия:
   "нет YOLO-детекций ≥20 с при ходьбе + pitch не optimal":
   ```dart
   final longNoDetections = now.difference(_lastDetectionAt) >
       const Duration(seconds: 20);
   final pitchBad = !_pitchOptimal;
   if (moving && longNoDetections && pitchBad && !_longNoDetectionAnnounced) {
     tts.say(S.get('misalign_no_detections'), SpeechPriority.warning, ...);
     _longNoDetectionAnnounced = true;
     // cooldown через таймер
   }
   ```
3. Сохранить depth-blind триггер как дополнительный (не заменять).

ЧТО НЕ ТРОГАТЬ:
- Не менять тайминги 10/35/15 с (safety inviolable: MisalignmentWatchdog)
- Не менять haptic-триггер (он не гейтится depth — оставить как есть)
- Не менять pitch-optimal логику

ТЕСТ:
- test/misalignment_watchdog_test.dart:
  1. MotionState.running + misaligned → ожидать вербальное предупреждение
  2. MotionState.walking + no detections 20с + pitch bad + depth ok
     → ожидать misalign_no_detections TTS
  3. MotionState.stationary → НЕ ожидать предупреждение

ЛОКАЛИЗАЦИЯ:
- Добавить 'misalign_no_detections' в strings.dart для всех 3 языков:
  ru: "Давно нет распознавания объектов. Поднимите телефон вертикально."
  kk: "Ұзақ уақыт нысандар танылмай жатыр. Телефонды тіктеп ұстаңыз."
  en: "No object detection for a while. Hold phone upright."
```

---

### Промт E-2: launchUrl(sms:) и tel: — ложное "SOS отправлен"

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High, частично исправлена): SosResult.dialerOpened уже возвращается
для tel: (sos_service.dart:218). SosResult.composerOpened объявлен в enum
(строка 38), но в _tryDeliver для sms: URI (строки 238-253) возвращается
SosResult.pendingEnqueued, а НЕ composerOpened. Нужно различать:
- pendingEnqueued: native SMS channel вернул false, sms:// URI как fallback
- composerOpened: SEND_SMS запрещён, открылся чужой SMS-композер

Также нужно проверить: вызывается ли onSosSent для composerOpened/dialerOpened
(НЕ должен — это не реальная отправка).

ФАЙЛЫ:
- lib/services/sos_service.dart:238-253 — sms: URI fallback (pendingEnqueued)
- lib/services/sos_service.dart:218 — tel: (dialerOpened — уже исправлено)
- lib/services/sos_service.dart:492-494 — проверка результата для onSosSent

ИСПРАВЛЕНИЕ:
1. Различить сценарии в _tryDeliver:
   - Если _sendSmsDirect вернул false И launchUrl(sms:) успешно → это
     composerOpened (открылся композер, пользователь должен нажать "Отправить")
   - Если _sendSmsDirect вернул false И launchUrl(sms:) НЕуспешно → launchFailed
   Заменить return SosResult.pendingEnqueued на return SosResult.composerOpened
   в строке 253 (или добавить отдельную ветку).
2. В обработке результата (строки ~492-494) убедиться что onSosSent НЕ вызывается
   для composerOpened и dialerOpened (только для sent/sentFallback).
3. Добавить направляющую TTS для composerOpened:
   "Открыто окно сообщения. Кнопка отправки — внизу справа."
   И для dialerOpened: "Открыт набиратель. Нажмите зелёную кнопку для звонка."
4. Добавить направляющую хапатику для помощи в навигации по чужому UI.

ЧТО НЕ ТРОГАТЬ:
- Не менять _sendSmsDirect (native channel — уже исправлен в E-1)
- Не менять buildSmsUri / buildTelUri
- Не менять fallback-цепочку (native → sms: → tel:)

ТЕСТ:
- test/sos_service_composer_test.dart:
  1. _sendSmsDirect false + launchUrl(sms:) true → ожидать composerOpened
  2. composerOpened → onSosSent НЕ вызывается
  3. dialerOpened → onSosSent НЕ вызывается
  4. sent → onSosSent вызывается

ЛОКАЛИЗАЦИЯ:
- Добавить 'sos_composer_opened' и 'sos_dialer_opened' в strings.dart:
  ru: "Открыто окно сообщения. Кнопка отправки — внизу справа."
      "Открыт набиратель. Нажмите зелёную кнопку для звонка."
  kk: "Хабарлама терезесі ашылды. Жіберу батырмасы — төменде оң жақта."
      "Нөмір тергіш ашылды. Қоңырау шалу үшін жасыл батырманы басыңыз."
  en: "Message window opened. Send button — bottom right."
      "Dialer opened. Press green button to call."
```

---

### Промт E-3: Permission.sms.request() в момент ЧП

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (High): В sos_service.dart:408-411 Permission.sms.request() вызывается
ВНУТРИ _sendSmsDirect — в момент падения. Системный диалог поверх отсчёта:
незрячий должен найти и подтвердить его; TalkBack может перехватить фокус;
отказ → permanentlyDenied → весь нативный путь мёртв.

ФАЙЛЫ:
- lib/services/sos_service.dart:408-411 — request внутри _sendSmsDirect
- lib/onboarding_screen.dart — шаг SOS-контакта (найти через grep "sos" в onboarding)

ИСПРАВЛЕНИЕ:
1. В onboarding_screen.dart на шаге SOS-контакта (при сохранении номера):
   запрашивать Permission.sms.request() заранее:
   ```dart
   if (await Permission.sms.status.isDenied) {
     await Permission.sms.request();
   }
   ```
2. При старте сессии (camera_screen._initAll или CameraViewModel.init) —
   фоновая проверка:
   ```dart
   final smsStatus = await Permission.sms.status;
   if (smsStatus.isPermanentlyDenied || smsStatus.isDenied) {
     tts.say(S.get('sos_sms_permission_missing'), SpeechPriority.warning, ...);
   }
   ```
3. В _sendSmsDirect (строка 408) оставить request как last-resort fallback,
   но с TTS: "Требуется разрешение на SMS. Подтвердите диалог." перед запросом.

ЧТО НЕ ТРОГАТЬ:
- Не менять саму логику _sendSmsDirect (отправка SMS)
- Не менять fallback-цепочку
- Не менять onSosSent

ТЕСТ:
- test/sos_permission_test.dart:
  1. Onboarding сохранение SOS-номера → ожидать Permission.sms.request()
  2. Старт сессии с denied → ожидать TTS warning sos_sms_permission_missing
  3. _sendSmsDirect с granted → ожидать отправку без диалога

ЛОКАЛИЗАЦИЯ:
- Добавить 'sos_sms_permission_missing' в strings.dart:
  ru: "Разрешение на SMS отсутствует. SOS будет работать медленнее."
  kk: "SMS рұқсаты жоқ. SOS баяурақ жұмыс істейді."
  en: "SMS permission missing. SOS will be slower."
- Добавить 'sos_permission_dialog' (для last-resort в _sendSmsDirect):
  ru: "Требуется разрешение на SMS. Подтвердите диалог."
  kk: "SMS рұқсаты қажет. Диалогты растаңыз."
  en: "SMS permission required. Confirm the dialog."
```

---

## Phase 3 — Medium/Low

### Промт A-8: Отказ канала thermal/memory → severity "normal"

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium, частично исправлена): thermal_monitor.dart:160-162 и
memory_monitor.dart:96-98 при сбое канала возвращают unavailable (лучше чем
raw "normal"), но нет удержания последнего уровня при N подряд сбоях.
При recovery-dwell 30 с троттлинг может сняться на горячем устройстве.

ФАЙЛЫ:
- lib/services/thermal_monitor.dart:160-162 — _setCurrent(unavailable)
- lib/services/memory_monitor.dart:96-98 — аналогично
- lib/utils/performance_throttler.dart:75-85 — recovery-dwell

ИСПРАВЛЕНИЕ:
1. В thermal_monitor и memory_monitor добавить счётчик подряд сбоев канала:
   int _consecutiveChannelFailures = 0;
2. При N=3 подряд сбоях — удерживать последний известный уровень (минимум warm
   для thermal, минимум lowMemory для memory), не сбрасывать в normal/unavailable:
   ```dart
   if (_consecutiveChannelFailures >= 3) {
     // Удерживать последний уровень (минимум warm)
     _setCurrent(_lastReadings.copyWith(severity: ThermalSeverity.warm));
     return;
   }
   ```
3. Логировать через field_logger: 'sensor_unavailable'.
4. Сбрасывать _consecutiveChannelFailures при успешном чтении.

ЧТО НЕ ТРОГАТЬ:
- Не менять recovery-dwell 30 с в performance_throttler
- Не менять thermal tier FSM
- Не менять пороги 400/250 МБ для memory

ТЕСТ:
- test/thermal_monitor_channel_fail_test.dart:
  3 подряд сбоя канала → ожидать удержание warm (не normal)
  Успешное чтение → сброс счётчика
```

---

### Промт A-9: Haptic floor-защита не покрывает kHapticCriticalAlertPattern

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium): В haptic_service.dart:42-43 floor-protection проверяет только
kHapticTtsStallPattern и kHapticCriticalCooldownPattern. kHapticCriticalAlertPattern
(constants.dart:255) отсутствует. При множителе 0.3 критические алерты
(_handleVeryClose, handleDepthHazard) шлют именно kHapticCriticalAlertPattern:
150мс→45мс, 255→77 — тактильный канал слабеет.

ФАЙЛЫ:
- lib/services/haptic_service.dart:42-43 — isCriticalPattern список
- lib/models/constants.dart:255 — kHapticCriticalAlertPattern определение

ИСПРАВЛЕНИЕ (минимальное, 1 строка):
```dart
final isCriticalPattern = identical(pattern, kHapticTtsStallPattern) ||
    identical(pattern, kHapticCriticalCooldownPattern) ||
    identical(pattern, kHapticCriticalAlertPattern);
```

Альтернатива (лучше): заменить identical-список на параметр bool isCritical = false
в методе vibrate(), передавать явно из вызовов.

ЧТО НЕ ТРОГАТЬ:
- Не менять _kCriticalFloorMultiplier
- Не менять сам паттерн kHapticCriticalAlertPattern
- Не менять логику scaling

ТЕСТ:
- test/haptic_service_test.dart:
  vibrate(kHapticCriticalAlertPattern, multiplier=0.3) → ожидать
  effectiveMultiplier >= _kCriticalFloorMultiplier (не 0.3)
```

---

### Промт A-10: Пустой if-блок и TTS stop() чистит critical

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Low): camera_screen.dart:910-911 пустой блок if (!recentAnyAlert) {}
— мёртвый код. tts_service.dart:937 stop() чистит всю очередь включая critical
— вызывается из setLanguage (смена языка голосом во время опасности теряет
queued critical).

ФАЙЛЫ:
- lib/camera_screen.dart:910-911 — пустой if
- lib/services/tts_service.dart:937 — _queue.clear() в stop()

ИСПРАВЛЕНИЕ:
1. Удалить пустой блок if (!recentAnyAlert) {} в camera_screen.dart:910-911.
2. В tts_service.dart stop() — сохранять critical-задания:
   ```dart
   void stop() {
     _currentJob = null;
     _queue.removeWhere((j) => j.priority != SpeechPriority.critical);
     // critical остаются в очереди для воспроизведения после смены языка
   }
   ```
   Или: если stop() вызывается для полной остановки (не для смены языка) —
   разделить на stop() (полная) и stopForLanguageChange() (сохраняет critical).

ЧТО НЕ ТРОГАТЬ:
- Не менять _currentJob логику
- Не менять приоритеты очереди

ТЕСТ:
- test/tts_service_test.dart:
  1. Поставить critical в очередь → stop() → critical остаётся
  2. stopForLanguageChange() → critical остаётся, warning/info удалены
```

---

### Промт E-4: Dual-SIM — SmsManager.getDefault() без выбора подписки

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium): В MainActivity.kt:302 SmsManager.getDefault() использует
дефолтную подписку без выбора. На двухсимочном устройстве с default "спрашивать
каждый раз" или SIM1 без баланса — отправка может тихо уйти в никуда.

ФАЙЛЫ:
- android/app/src/main/kotlin/com/example/bagdar/MainActivity.kt:302

ИСПРАВЛЕНИЕ (Kotlin):
1. Получить список активных подписок:
   ```kotlin
   val sm = getSystemService(SubscriptionManager::class.java)
   @Suppress("MissingPermission")
   val subs = sm.activeSubscriptionInfoList ?: emptyList()
   ```
2. При недоставке по дефолтной SIM — ретрай по второй:
   ```kotlin
   if (subs.size > 1) {
     val subId = subs[1].subscriptionId
     val smsMan = getSystemService(SmsManager::class.java)
       .createForSubscriptionId(subId)
     // повторить отправку
   }
   ```
3. На API 31+ использовать context.getSystemService(SmsManager::class.java).

ЧТО НЕ ТРОГАТЬ:
- Не менять PendingIntent логику (E-1 fix)
- Не менять fallback sms:/tel: цепочку

ТЕСТ:
- Unit-тест на Kotlin сложен; проверить вручную на двухсимочном устройстве.
- Или: мок SubscriptionManager в инструментальном тесте.
```

---

### Промт E-5: getLastKnownPosition без ограничения возраста

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium, частично смягчено): В sos_service.dart:517-530
getLastKnownPosition() берётся без проверки давности. Кэш _cachedPosition имеет
cap 2 мин, но lastKnown — нет. Координаты могут быть многочасовой давности.
Смягчение: buildMessageText помечает "данные N мин назад", но помощник видит
это в SMS — пользователь НЕ слышит предупреждения.

ФАЙЛЫ:
- lib/services/sos_service.dart:517-530 — getLastKnownPosition без age check

ИСПРАВЛЕНИЕ:
1. После getLastKnownPosition() проверить возраст:
   ```dart
   final lastKnown = await Geolocator.getLastKnownPosition();
   if (lastKnown != null) {
     final age = DateTime.now().difference(lastKnown.timestamp);
     if (age > const Duration(minutes: 30)) {
       // Слишком старая позиция — не использовать
       return null; // → переход на sos_no_gps + Wi-Fi/cell контекст (H9)
     }
   }
   ```
2. При age > 30 мин — предпочитать sos_no_gps (текст без координат) +
   Wi-Fi/cell-контекст вместо координат, ведущих в неверное место.
3. Добавить TTS предупреждение пользователю: "Точное местоположение неизвестно.
   SOS отправлен без координат."

ЧТО НЕ ТРОГАТЬ:
- Не менять _cachedPosition (cap 2 мин — корректен)
- Не менять buildMessageText (уже помечает давность)
- Не менять H9 context сборку

ТЕСТ:
- test/sos_position_age_test.dart:
  1. lastKnown age 10 мин → используется
  2. lastKnown age 40 мин → НЕ используется, возвращается null
  3. lastKnown null + нет fresh fix → sos_no_gps

ЛОКАЛИЗАЦИЯ:
- Добавить 'sos_no_gps_voice' в strings.dart:
  ru: "Точное местоположение неизвестно. SOS отправлен без координат."
  kk: "Нақты орналасу белгісіз. SOS координаттарсыз жіберілді."
  en: "Exact location unknown. SOS sent without coordinates."
```

---

### Промт E-6: H9-контекст только при активной навигации

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium): В sos_service.dart:90-95 updateCachedPosition устанавливает
_stepsAtCachedPosition. Единственный вызов — nav.onPositionUpdated
(camera_view_model.dart:457-459). Без навигации _cachedPosition == null →
"шагов с последней точки: N, направление X" в SMS отсутствует.

ФАЙЛЫ:
- lib/services/sos_service.dart:90-95 — updateCachedPosition
- lib/viewmodels/camera_view_model.dart:457-459 — единственный вызов

ИСПРАВЛЕНИЕ:
1. Добавить периодическое обновление кэш-позиции независимо от навигации:
   в CameraViewModel.init (или отдельный таймер):
   ```dart
   Timer.periodic(const Duration(minutes: 2), (_) async {
     if (_motionState == MotionState.stationary) return;
     final pos = await Geolocator.getLastKnownPosition();
     if (pos != null) {
       sos.updateCachedPosition(pos);
     }
   });
   ```
2. Условие: только при движении (walking/running) — не тратить батарею в покое.
3. Шагомер обновляется через stepService — убедиться что _stepsAtCachedPosition
   обновляется вместе с позицией.

ЧТО НЕ ТРОГАТЬ:
- Не менять nav.onPositionUpdated (остаётся основной путь)
- Не менять buildMessageText
- Не менять H9 context структуру

ТЕСТ:
- test/sos_context_no_nav_test.dart:
  1. Без навигации + движение → через 2 мин _cachedPosition != null
  2. Без навигации + stationary → _cachedPosition остаётся null
  3. С навигацией → updateCachedPosition вызывается из обоих путей
```

---

### Промт D-3: FusionEngine — одно-зонная история сбрасывает подтверждение

```
Ты работаешь над проектом Bagdar AI.

ПРОБЛЕМА (Medium, частично исправлена): В fusion_engine.dart:31-36 единственный
_lastZoneIdx; |Δzone|>=2 чистит ВСЮ историю и EMA. Per-zone EMA существует
(_emaScore[zoneIdx]), но _history.clear() глобален. При чередовании зон 0,2,0,2
каждый сбрасывает накопление → fusion-промоция в critical не наступает.

ФАЙЛЫ:
- lib/utils/fusion_engine.dart:31-36 — глобальный сброс

ИСПРАВЛЕНИЕ:
1. Заменить глобальный сброс на per-zone TTL:
   ```dart
   // Вместо _history.clear() — удалить только устаревшие записи
   _history.removeWhere((key, value) =>
       now.difference(value) > const Duration(seconds: 5));
   ```
2. Глобальный сброс оставить только для реального разворота (по компасу/гироскопу):
   ```dart
   if (_compassHeadingChangedBy180Degrees) {
     _history.clear();
     _emaScore.clear();
   }
   ```
3. Если компаса нет — оставить |Δzone|>=2 как fallback, но чистить только
   текущую зону, не все.

ЧТО НЕ ТРОГАТЬ:
- Не менять kFusionEmaAlpha = 0.30
- Не менять kFusionTemporalFrames = 3 (safety inviolable)
- Не менять _isHazardCritical пороги

ТЕСТ:
- test/fusion_engine_multi_zone_test.dart:
  1. Чередование zone 0,2,0,2 с score 0.55 → ожидать промоцию в critical
     после 3 кадров (а не бесконечный сброс)
  2. Разворот 180° (compass) → ожидать полный сброс
  3. Одна зона с score 0.55 → ожидать промоцию через 3 кадра (как раньше)
```

---

## Порядок выполнения

```
Phase 1 (Critical, safety-inviolable):
  1. A-2  — подписка onSessionDisabled + degraded-счётчик
  2. A-6  — TTS/haptic/retry в _initCamera catch + гейтинг system_ready
  3. C-1  — деградированный профиль fall detection без gyro
  4. D-4  — промоция отсчёта SOS в critical или гейтинг depth-hazards

Phase 2 (High, broken declared features):
  5. A-3  — catch в analyze инкрементирует failures
  6. B-1  — связка только для non-critical
  7. B-2  — running делит midasInterval
  8. C-2  — вызов reset() в setMode
  9. C-3  — double-tap для отмены SOS
  10. D-1 — удалить мёртвую ветку AE + расширить уведомление
  11. D-2 — второй critical той же категории с разным pan
  12. D-5 — running в misalignment + триггер без depth
  13. E-2 — composerOpened для sms: + направляющая TTS
  14. E-3 — запрос SMS-разрешения в onboarding

Phase 3 (Medium/Low):
  15. A-8  — удержание уровня при сбое канала
  16. A-9  — kHapticCriticalAlertPattern в floor-protection
  17. A-10 — удалить пустой if + сохранять critical в stop()
  18. D-3  — per-zone TTL в fusion
  19. E-4  — dual-SIM retry
  20. E-5  — age limit на getLastKnownPosition
  21. E-6  — периодическое обновление кэш-позиции
```

---

## Общие правила для всех промтов

- Соблюдай конвенции проекта: `k`-префикс для констант, `_` для private, single quotes
- Все новые user-facing строки → `strings.dart` для ru/kk/en ДО изменения кода
- Все новые tunable числа → `constants.dart` с `k`-префиксом
- Не инлайн magic numbers
- Маркер в комментарии: `// Safety audit 2026-06 fix <ID>: <краткое описание>`
- Commit format: `fix(scope): description` (conventional commits, lowercase)
- Каждый фикс — отдельный commit
- Тесты обязательны для каждого фикса
- Pipeline order НЕ менять (safety inviolable)
- Не трогать safety inviolables без явного одобрения
```

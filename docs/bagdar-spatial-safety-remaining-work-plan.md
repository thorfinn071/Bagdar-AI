# Bagdar Spatial Safety — план завершения работ

Дата: 2026-09-20

Статус исходной точки: software/shadow-архитектура в основном реализована;
`assistive` не разрешён. Этот документ продолжает
`docs/bagdar-spatial-safety-implementation-plan.md` и описывает только
незавершённые работы.

## 1. Цель

Довести текущий набор модулей до проверяемой цепочки:

```text
camera/depth/model observations
  -> LocalSceneModel
  -> Corridor Planner / Guidance FSM
  -> единый AlertArbiter
  -> FeedbackDispatcher
  -> TTS / earcon / haptics
```

До завершения всех software, device и controlled-walking gates цепочка
остаётся в `shadow`. Успешная компиляция, unit-тесты или APK build сами по себе
не разрешают `GenericObstacleMode.assistive`.

## 2. Неподвижные safety-инварианты

Эти правила нельзя ослаблять ради прохождения тестов или уменьшения числа
предупреждений:

1. Неизвестное или протухшее пространство не считается свободным.
2. Relative depth не создаёт метры, точное расстояние или фразу «путь
   свободен».
3. Семантическая модель не может уменьшить риск, подтверждённый геометрией.
4. Результат старой camera session, старого frame или несовместимого transform
   не меняет scene и не попадает в alerts.
5. Потеря sensing во время движения приводит к `stopNow`; у остановившегося
   пользователя — к `holdAndScan`.
6. Боковая инструкция допустима только для наблюдаемого коридора с
   положительными geometry/traversability evidence и после temporal
   confirmation.
7. P0-команда прерывает менее срочную речь; очередь остаётся ограниченной и
   очищает expired commands.
8. Вибрация не кодирует left/right одним мотором и соблюдает cooldown и
   duty-cycle budget.
9. Sonar остаётся Research/shadow и не влияет на risk до отдельного полного
   gate.
10. Любая promotion привязана к конкретным build, device, model hashes и
    mount; глобального разрешения по одному удачному запуску нет.

## 3. Текущий доказанный baseline

На момент составления плана:

- `dart analyze` проходит;
- полная Flutter suite: 995 passed, 1 skipped;
- 115 целевых spatial/model/sonar тестов проходят;
- procedural spatial RC проходит с нулём по шести safety-счётчикам;
- corpus generator подтверждает 19 файлов;
- строгий legacy RC падает на `A6`: random/noisy depth ошибочно получает
  `planeFitOk=true` и создаёт ложные `stepDown`;
- NCNN native/reference correlation пропущена из-за отсутствующего
  `test/fixtures/ncnn_contract/reference_outputs.json`;
- новый planner подключён к camera runtime, но все его actions принудительно
  переводятся в `shadow`;
- действующие object/depth/emergency предупреждения ещё не проходят через один
  общий arbiter/dispatcher;
- recorded corpus, device evidence и controlled walking отсутствуют.

## 4. Определение завершённой задачи

Задача считается выполненной только когда одновременно существуют:

1. реализация с fail-closed поведением;
2. тест, который падает на старой реализации;
3. положительные и отрицательные сценарии;
4. машинный результат или bounded diagnostic trace;
5. обновлённый validation report;
6. явно пройденный exit gate.

Комментарий, интерфейс, placeholder, skipped test или desktop smoke не являются
завершением функции.

---

## 5. Этап R1 — исправить noisy-depth admission

**Приоритет:** блокирующий. Выполнить первым.

### Проблема

`GroundPlaneAnalyzer` принимает случайную depth-карту как плоскость при 20%
inliers и относительной ошибке до 15%. При менее чем десяти валидных точках
метод возвращается до обновления `lastPlaneFitOk`, поэтому новый frame может
унаследовать состояние предыдущего.

### Файлы

- `lib/utils/ground_plane_analyzer.dart`;
- `lib/services/depth_provider.dart`;
- `lib/services/ncnn_depth_provider.dart`;
- `lib/camera/depth_pipeline_controller.dart`;
- `test/harness/scenario_harness_test.dart`;
- новый `test/ground_plane_quality_test.dart` либо тематические тесты в
  существующем файле.

### Работы

1. Ввести immutable `PlaneFitQuality`:
   - `validPointFraction`;
   - `inlierFraction`;
   - median/p90 normalized residual;
   - spatial coverage inliers по строкам и колонкам;
   - degeneracy flag;
   - temporal-consistency score, если есть предыдущий fit;
   - итоговый `accepted` и machine-readable rejection reason.
2. В начале каждого `analyze()` сбрасывать состояние текущего frame в
   fail-closed значение. Любой early return обязан публиковать актуальный
   rejected result.
3. Не выбирать пороги по одному A6. Построить детерминированную матрицу:
   - ровная поверхность;
   - наклонная поверхность;
   - ступень/бордюр;
   - частичная окклюзия;
   - NaN/zero holes;
   - uniform noise;
   - structured noise;
   - отражение/низкий свет;
   - малая spatial coverage.
4. При rejected fit переводить generic geometry в
   `ObstacleRejectReason.planeUnreliable`, health — в degraded, scene — в
   unknown. Не подменять rejected fit пустым healthy scene.
5. Проверить, что изменение не снижает recall для cliff, step-down, stairs и
   near-field intrusion на существующих сценариях.
6. Сделать A6 обычным assertion-тестом, а не диагностическим `partial`.

### Exit gate R1

- strict `BAGDAR_RC=true` harness проходит без `partial`;
- random/noisy maps не получают healthy plane;
- frame с недостатком точек не наследует прошлый `lastPlaneFitOk`;
- flat/ramp/curb/stairs regressions проходят;
- provider health и spatial scene становятся degraded/unknown;
- обычная полная suite остаётся зелёной.

---

## 6. Этап R2 — time-driven spatial runtime

**Зависит от:** R1.

### Проблема

Сейчас `SpatialSafetyRuntime` вызывается после завершения depth analysis. Если
inference зависла, была отключена throttling-ом или перестала выдавать frames,
TTL scene может истечь без нового вызова planner.

### Файлы

- `lib/safety/runtime/spatial_safety_runtime.dart`;
- `lib/camera_screen.dart`;
- `lib/camera/stall_watchdog.dart`;
- `lib/camera/camera_lifecycle_controller.dart`;
- `lib/core/core_health_coordinator.dart`;
- `test/spatial_safety_runtime_test.dart`;
- `test/stall_watchdog_test.dart`;
- `test/camera_lifecycle_controller_test.dart`.

### Контракт

Добавить API наподобие:

```dart
SpatialRuntimeResult tick({
  required DateTime now,
  required bool userMoving,
  required bool orientationValid,
});
```

`tick()` не создаёт observations. Он только:

- применяет decay/TTL к существующей scene;
- обновляет provider health;
- переводит протухшую scene в unknown;
- повторно запускает FSM при значимом изменении состояния;
- пишет bounded trace;
- не накапливает одинаковые actions чаще cooldown.

### Работы

1. Ввести монотонный runtime cadence с bounded частотой.
2. Отделить capture timestamp, inference completion и decision time.
3. Запускать `tick()` независимо от успешного завершения модели.
4. На pause/stop session останавливать cadence и очищать session-owned state.
5. На resume начинать новую generation до первого camera callback.
6. Не выполнять тяжёлую inference внутри tick и не блокировать UI isolate.
7. Добавить сценарии:
   - accepted scene, затем полная тишина provider;
   - hanging inference;
   - thermal throttling;
   - pause/resume;
   - orientation invalidation;
   - repeated ticks без новых revisions;
   - восстановление после свежего observation.

### Exit gate R2

- движущийся пользователь получает shadow `stopNow` после expiry даже без
  нового inference callback;
- остановившийся получает shadow `holdAndScan`;
- старый action не сохраняется после TTL;
- repeated ticks не создают speech/action storm;
- pause/resume не принимает state старой generation;
- trace различает `observation`, `expiry_tick`, `provider_loss` и `recovery`.

---

## 7. Этап R3 — единый safety feedback authority

**Зависит от:** R2. Всё остаётся shadow для spatial guidance.

### Проблема

`AlertArbiter`, `FeedbackDispatcher` и production output adapter существуют,
но текущие camera/object/depth alerts продолжают обращаться к TTS/earcon/
haptics через старые пути. Поэтому межисточниковая preemption пока не
доказана.

### Файлы

- `lib/safety/alerts/alert_arbiter.dart`;
- `lib/safety/alerts/feedback_command.dart`;
- `lib/safety/alerts/feedback_policy.dart`;
- `lib/safety/alerts/feedback_dispatcher.dart`;
- `lib/safety/alerts/bagdar_feedback_output.dart`;
- новый `lib/safety/runtime/safety_feedback_runtime.dart`;
- `lib/camera/alert_manager.dart`;
- `lib/camera_screen.dart`;
- `lib/services/tts_service.dart`;
- `lib/services/earcon_service.dart`;
- `lib/services/haptic_service.dart`;
- `lib/viewmodels/camera_view_model.dart`.

### Архитектурная граница

`SafetyFeedbackRuntime` должен владеть:

- единственным `AlertArbiter` для safety/health/emergency actions;
- единственным `FeedbackDispatcher`;
- lifecycle активной команды;
- completion callback и promotion следующей pending команды;
- interrupt/replace/expiry semantics;
- bounded trace доставки.

TTS остаётся исполнительным queue/audio слоем и не пересчитывает риск.
Обычная on-demand речь может иметь отдельный typed source, но не должна
обходить P0 preemption.

### Работы

1. Инвентаризировать прямые `_tts.say`, `earcon.play` и
   `HapticService.vibrate` в camera/safety потоках.
2. Перевести в typed commands минимум:
   - YOLO/object proximity;
   - depth hazards;
   - spatial planner;
   - provider/core-health degradation;
   - camera stall/misalignment;
   - fall/SOS emergency;
   - explicit user repeat/on-demand.
3. Сохранить локализацию через keys, не передавать произвольный текст в
   arbiter.
4. Связать `emitted/replaced` event с dispatcher.
5. При `interruptCurrent=true` действительно останавливать менее срочную TTS,
   earcon и заменяемую haptic sequence.
6. После completion/failed delivery вызвать `completeCurrent()` и обработать
   ровно одну следующую команду.
7. При недоступном TTS использовать policy-defined haptic fallback и обновить
   health; отсутствие обоих каналов должно быть явным состоянием.
8. Оставить spatial actions в `shadow`: они проходят arbiter simulation, но
   dispatcher их не исполняет.
9. Удалять старые direct safety paths только после parity-тестов.

### Обязательные сценарии

- информационная речь -> внезапный P0 `stopNow`;
- depth P0 во время object warning;
- fall/SOS P0 во время spatial hold;
- два независимых P0 с разными ответами;
- повтор одного hazard с растущей urgency;
- TTS unavailable, vibrator available;
- TTS и vibrator unavailable;
- expired command ожидает в очереди;
- camera session restart с pending commands старой generation;
- 10 одновременных объектов, но bounded итоговый feedback.

### Exit gate R3

- все safety-critical user outputs имеют один admission point;
- repo-wide проверка не находит прямого critical TTS/haptic path вне явно
  перечисленных emergency escape hatches;
- P0 preemption доказана между разными источниками;
- dispatcher используется production runtime, а не только тестами;
- active + pending queue ограничена;
- каждый emit/suppress/replace/drop/delivery result имеет reason;
- spatial guidance всё ещё не слышна пользователю.

---

## 8. Этап R4 — расширить corpus до perception-to-action replay

**Можно выполнять параллельно с R2–R3 после фиксации schema.**

### Проблема

Текущий corpus проверяет procedural relative sectors и planner/arbiter, но не
реальные RGB/depth outputs моделей. Blender и consent-controlled recorded
corpora отсутствуют.

### Файлы и каталоги

- `test/fixtures/spatial_safety/manifest.json`;
- `test/harness/spatial_replay_fixture.dart`;
- `test/harness/spatial_scenario_runner.dart`;
- `tool/build_spatial_corpus.dart`;
- `tool/report_spatial_metrics.dart`;
- `docs/spatial-corpus-contract.md`;
- новый `tool/import_spatial_recording.*`;
- raw/private media вне Git по умолчанию;
- разрешённые derived fixtures и hashes — в versioned manifest.

### Dataset tiers

1. **Procedural:** быстрые unit/replay проверки.
2. **Blender/synthetic sensor:** RGB, depth, segmentation masks, camera pose и
   точный ground truth.
3. **Public recorded:** только с проверенной лицензией и provenance.
4. **Private controlled:** только с explicit consent, retention policy и
   запретом случайного commit raw media.
5. **Named-device:** отдельный device gate, не смешивать с desktop RC.

### Минимальная матрица сцен

- тонкий столб и ветка;
- прозрачная/отражающая дверь;
- низкое препятствие и подвесное препятствие;
- curb up/down, pothole, stairs up/down, ramp;
- узкий проход, дверной проём и тупик;
- толпа и частичная окклюзия;
- велосипед/самокат, пересекающий траекторию;
- darkness, blur, rain-like degradation и random depth noise;
- чрезмерный roll/pitch и camera obstruction;
- obstacle появляется во время инструкции;
- provider исчезает и восстанавливается.

### Аннотации

Для каждого timeline нужны:

- observed/unknown ground truth;
- obstacle/drop/moving-threat regions;
- traversability boundary, если доступна;
- allowed и forbidden actions;
- latest acceptable alert time;
- model/preprocess/transform identity;
- source/license/consent/handling;
- completeness и `requiredForRc`.

### Метрики

- critical hazard recall;
- false-stop rate;
- missed/late stop count;
- unsafe guidance count;
- guidance into unknown count;
- stale action emission count;
- action churn/oscillation;
- alert latency от evidence timestamp;
- model-to-planner regression по scene class.

### Exit gate R4

- есть минимум один Blender perception-to-action corpus;
- реальные model outputs проходят тот же runner, что procedural fixtures;
- missing required corpus блокирует RC;
- corpus order и wall clock не меняют результат;
- provenance/hash/annotation revision проверяются автоматически;
- отчёт разделяет software, public-recorded, private и device evidence.

---

## 9. Этап R5 — завершить model bake-off

**Зависит от:** R4 для correctness/downstream сравнения.

### Detector track

Контроль: текущий YOLOv8n. Кандидаты: уже экспортированные YOLO11n и YOLO26n.

1. Зафиксировать одинаковый preprocess/postprocess и class mapping.
2. Запустить кандидаты на одном versioned corpus.
3. Сравнить не только mAP, но critical recall, thin/low/overhead obstacles,
   flicker, tracker stability и downstream planner metrics.
4. Проверить decoder parity и malformed-output fail-closed behavior.
5. Не менять production model при улучшении скорости ценой critical recall.

### Depth track

Контроль: MiDaS Small NCNN.

1. Создать `reference_outputs.json` из закреплённого reference runtime.
2. Проверить native/reference rank correlation, edges, NaN/Inf, scale/order и
   preprocess parity.
3. Получить точный DA-V2 Small checkpoint, hash и лицензию.
4. Сделать воспроизводимый ONNX/NCNN export.
5. Сравнить temporal flicker, thin obstacles, curb/drop edges и downstream
   actions на тех же frames.

### Traversability track

1. Зафиксировать typed provider interface и masks contract.
2. Сравнить PP-LiteSeg-T, DeepLabV3-MobileNetV3-Small и PP-MobileSeg либо
   документированно сузить список.
3. Оценивать boundary recall для curb/stair/drop/opening, а не только mIoU.
4. Segmentation не уменьшает geometry risk; конфликт повышает unknown.
5. Если ни один кандидат не проходит, оставить формальный `deferred` с
   перечисленными отсутствующими prerequisites.

### License и reproducibility

- источник checkpoint;
- SHA-256 source и artifact;
- export command/environment;
- embedded и distribution license;
- decoder/preprocess IDs;
- rollback artifact.

### Exit gate R5 без телефона

- NCNN reference parity test больше не skipped;
- каждый кандидат имеет real-output correctness report;
- downstream replay сравнивает реальные predictions;
- выбран production control/challenger outcome без скрытого переключения;
- license status явно `approved`, `rejected` или `blocked`;
- traversability selected либо честно deferred.

Device latency, memory, battery и thermal остаются отдельным gate R8.

---

## 10. Этап R6 — sonar DSP только в Research

**Приоритет:** после R1–R5. Не блокирует vision-first MVP.

### Файлы

- `lib/services/sonar_service.dart`;
- `android/app/src/main/kotlin/com/example/bagdar/SonarPlugin.kt`;
- `lib/services/sensor_session_coordinator.dart`;
- `test/sonar_service_test.dart`;
- новый offline DSP/reference harness;
- `docs/sonar-research-report.md`.

### Работы без физического chirp output

1. Создать offline waveform fixtures с известными delay/multipath/noise.
2. Реализовать loopback/direct-path estimation и cancellation.
3. Реализовать matched filtering и multipath-aware peak selection.
4. Добавить route/sample-rate/timestamp identity.
5. Сравнить multi-chirp consensus с ground truth.
6. Проверить false-near, missed-near, spread и out-of-order reset.
7. Сохранить native acoustic output заблокированным.

### Exit gate R6 software

- synthetic DSP fixtures проходят;
- direct-path peak не объявляется препятствием;
- multipath не выбирается оптимистично как свободный проход;
- malformed/unknown capability fail closed;
- sonar не подключён к LocalSceneModel или user alerts;
- physical chirp по-прежнему невозможен без acoustic/device approval.

---

## 11. Этап R7 — CI, отчёты и честный release signal

**Выполнять по мере R1–R6, закрыть до device validation.**

### Работы

1. Обновить противоречивые документы:
   - удалить старое утверждение, что planner не подключён к camera runtime;
   - исправить число procedural scenarios;
   - разделить `implemented`, `tested`, `blocked`, `device-only`.
2. Сделать test/report tools read-only по умолчанию. Generated JSON писать
   только при явном `--output` либо во временный каталог.
3. Включить в один локальный/CI gate:

```text
dart analyze
flutter test --no-pub
flutter test --no-pub --dart-define=BAGDAR_RC=true \
  test/harness/scenario_harness_test.dart
dart run tool/build_spatial_corpus.dart --check
dart run tool/report_spatial_metrics.dart --rc
model artifact/hash/decoder checks
NCNN reference parity
```

4. Разделить результаты:
   - desktop software RC;
   - model correctness RC;
   - Android build check;
   - named-device runtime;
   - controlled-walking evidence.
5. Не позволять старому baseline JSON выдавать себя за результат текущего
   commit: сохранять commit SHA, dirty flag, command и tool/schema version.

### Exit gate R7

- одна команда даёт честный pass/fail software status;
- A6 и отсутствующий required fixture нельзя скрыть skip/partial;
- тесты не меняют рабочее дерево без явного запроса;
- reports не противоречат текущему wiring;
- APK build маркируется только как compilation evidence.

---

## 12. Этап R8 — named Android device validation

**Требует реального Android-телефона. Начинать после R1–R7.**

### Зафиксировать reference target

- точная модель и hardware revision;
- Android/API version;
- ABI/GPU/NNAPI/NCNN backend;
- camera ID, resolution, rotation, FOV;
- наличие ARCore raw depth;
- speaker/mic/vibrator/TTS engine;
- способ крепления телефона;
- build commit и hashes моделей.

### Проверки

1. Cold start и permissions deny/revoke/regrant.
2. Camera start, pause/resume, background/foreground, lock/unlock.
3. Rotation, mirror, crop, excessive pitch/roll и obstruction.
4. Inference stall, provider exception, model unload/reload.
5. Входящий звонок, Bluetooth/headphones и смена audio route.
6. Фактическая TTS/haptic/earcon latency и P0 interruption.
7. 30-минутный thermal/memory/battery run.
8. Latest-frame-wins и отсутствие роста queue/memory.
9. ARCore shared-owner/alignment/parity либо явный permanent defer.
10. TalkBack, Scanner/Switch Access, крупный текст и экран onboarding/session
    gate.
11. Named-device corpus replay/recording с consent и privacy controls.

### Exit gate R8

- no crash/ANR;
- нет второго camera owner;
- нет silent provider loss или ложного `operational`;
- latency измерена от evidence до реального начала output;
- 30-minute run не создаёт unbounded memory/queue/thermal degradation;
- accessibility walkthrough пройден;
- все ограничения привязаны к конкретному устройству и mount.

---

## 13. Этап R9 — controlled walking и supervised promotion

**Требует реального телефона, безопасной площадки, sighted supervisor и
отдельного протокола.**

### Последовательность

1. **A — stationary bench:** устройство неподвижно, пользователь не идёт.
2. **B — carried, no user reliance:** телефон перемещает зрячий тестировщик.
3. **C — sighted supervised walking:** пользователь видит сцену и не полагается
   на приложение.
4. **D — controlled blindfold simulation:** только на закрытой площадке с
   физическим страхующим человеком.
5. **E — ограниченный supervised assistive:** только после review результатов
   A–D.

Каждый уровень имеет отдельный stop rule. Любой missed critical hazard,
unsafe direction, поздний stop, speech storm, непонятная вибрация или silent
provider loss возвращает проект в shadow и открывает incident item.

### Promotion artifact

Отдельный подписанный отчёт должен содержать:

- commit/build ID;
- device и mount;
- model/preprocess hashes;
- corpus и replay reports;
- device performance report;
- accessibility report;
- controlled-walking report;
- known limitations и запрещённые среды;
- rollback/kill switch;
- privacy и near-miss procedure;
- явное решение `approved` или `rejected`.

### Exit gate R9

- нет unresolved safety-critical findings;
- canonical replay и device gates проходят на той же сборке;
- пользовательские инструкции соответствуют реальной способности системы;
- rollback проверен;
- promotion ограничена названным build/device/mount;
- public/unsupervised assistive остаётся запрещённым до отдельного решения.

---

## 14. Порядок выполнения

```text
R1 noisy-depth integrity
  -> R2 time-driven runtime
  -> R3 unified feedback authority
  -> R7 software RC consolidation

R4 perception corpus
  -> R5 model bake-off
  -> R7 model correctness RC

R6 sonar research может идти отдельно после R1, но не задерживает vision MVP

R1–R7 complete
  -> R8 named-device validation
  -> R9 controlled walking / supervised promotion
```

## 15. Ближайший исполнимый backlog без телефона

Порядок задач для следующих итераций:

- [ ] **RW-01:** сделать failing unit regression для `<10 valid points` и
  stale `lastPlaneFitOk`.
- [ ] **RW-02:** заменить A6 `partial` на обязательный rejected-noise contract.
- [ ] **RW-03:** ввести `PlaneFitQuality` и propagation rejection reason.
- [ ] **RW-04:** добиться зелёного strict legacy RC без потери hazard recall.
- [ ] **RW-05:** добавить `SpatialSafetyRuntime.tick()` и fake-clock tests.
- [ ] **RW-06:** подключить bounded cadence к camera lifecycle.
- [ ] **RW-07:** реализовать `SafetyFeedbackRuntime` поверх существующих
  arbiter/dispatcher/output contracts.
- [ ] **RW-08:** перенести depth/object/health/emergency safety alerts в общий
  admission path, сохраняя spatial shadow.
- [ ] **RW-09:** добавить cross-source preemption и delivery lifecycle tests.
- [ ] **RW-10:** создать первый Blender perception-to-action corpus.
- [ ] **RW-11:** добавить NCNN reference fixture и убрать единственный skip.
- [ ] **RW-12:** прогнать реальные YOLO candidate predictions через replay.
- [ ] **RW-13:** подготовить DA-V2 artifact либо зафиксировать блокирующие
  license/checkpoint причины.
- [ ] **RW-14:** выбрать traversability candidate либо подтвердить defer на
  данных.
- [ ] **RW-15:** сделать verify/report pipeline read-only и commit-aware.
- [ ] **RW-16:** синхронизировать validation/runtime/model/sonar reports.

## 16. Что сознательно не делать до телефона

- не включать spatial `assistive`;
- не заявлять поддержку ARCore depth без shared camera owner и timestamp
  parity;
- не считать laptop latency телефонной производительностью;
- не снимать sonar acoustic block;
- не объявлять TalkBack или haptic UX проверенными по widget/unit tests;
- не считать APK build доказательством runtime safety;
- не публиковать формулировки «безопасный путь» или «можно идти».

## 17. Финальный критерий проекта

Работа завершена только тогда, когда один и тот же именованный build проходит:

1. строгий software RC без skip/partial safety gates;
2. model correctness и downstream replay;
3. named-device lifecycle/performance/accessibility matrix;
4. controlled-walking protocol;
5. review всех известных ограничений;
6. проверенный rollback;
7. отдельное явное решение о supervised promotion.

До этого момента корректный статус продукта: **research/shadow spatial safety,
не разрешённая для самостоятельного assistive использования**.

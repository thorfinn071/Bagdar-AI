# Bagdar Spatial Safety — план реализации восприятия, обхода препятствий и предупреждений

Дата: 2026-09-18  
Статус: утверждённое техническое направление; реализация и device-валидация не завершены  
Связанные документы:

- `docs/bagdar-core-focused-execution-plan.md`
- `docs/bagdar-core-hardening-master-plan.md`
- `docs/bagdar-core-health-contract.md`
- `docs/bagdar-core-alert-policy.md`
- `docs/generic-obstacle-validation-report.md`

Этот документ определяет реализацию трёх основных возможностей Bagdar:

1. обнаружение известных объектов и неизвестных физических препятствий;
2. построение локальной модели пространства и выбор консервативного действия;
3. выдача коротких, приоритетных и прерываемых предупреждений через речь,
   earcon и вибрацию.

План дополняет общий Core-план и имеет приоритет для spatial-safety контура.
Он не разрешает самостоятельное использование Bagdar как средства навигации и
не переводит `GenericObstacleMode` из `shadow` в `assistive`.

---

## 1. Продуктовая граница

### 1.1 Обещание первого релиза

Bagdar Core должен:

- замечать вероятную физическую угрозу в наблюдаемой области перед человеком;
- определять, пересекает ли она текущую траекторию пользователя;
- при достаточных доказательствах предлагать простое корректирующее действие;
- немедленно требовать остановки при близкой угрозе или потере надёжного
  пространственного анализа;
- честно сообщать, когда безопасное направление определить невозможно.

Bagdar Core не должен обещать:

- что путь свободен только потому, что объект не распознан;
- что предложенный коридор абсолютно безопасен;
- точное расстояние при использовании относительной monocular depth;
- полноценную самостоятельную навигацию без белой трости, собаки-проводника
  или навыков ориентирования;
- надёжность на устройствах и сценариях, которые фактически не проверены.

### 1.2 Основной принцип

`Object detection` и `obstacle detection` — разные задачи.

- Detector отвечает: «на изображении, вероятно, человек/машина/велосипед».
- Geometry отвечает: «эта область занимает пространство и пересекает путь».
- Traversability отвечает: «поверхность наблюдаема и пригодна для движения».
- Motion отвечает: «объект приближается или пересекает траекторию».
- Planner отвечает: «какое одно действие сейчас наименее рискованно».
- Alert arbiter отвечает: «нужно ли сообщить это действие и каким каналом».

Класс объекта может повысить риск или уточнить фразу, но отсутствие класса не
может понизить геометрический риск.

### 1.3 Поддерживаемый режим ношения

Надёжная непрерывная навигация требует известного положения камеры
относительно тела. Целевой Core-режим:

- задняя камера закреплена на груди, поясе или другом фиксированном креплении;
- известны примерная высота, pitch и направление камеры;
- приложение отслеживает pitch/roll, резкие повороты и перекрытие объектива;
- при выходе из допустимого положения guidance блокируется.

Handheld-режим поддерживает сканирование сцены и предупреждение о наблюдаемой
угрозе, но не должен выдавать уверенные команды обхода, если yaw камеры нельзя
связать с направлением тела.

---

## 2. Safety-инварианты

Ни один этап реализации не может нарушать следующие правила.

1. Низкая уверенность не уменьшает риск автоматически. Низкая уверенность в
   центральной зоне сама является причиной `holdAndScan` или `stopNow`.
2. Невалидный, stale или unaligned depth не означает пустую сцену.
3. Отсутствие bounding box не является доказательством свободного пространства.
4. Свободный коридор требует положительного доказательства поверхности,
   clearance и наблюдаемости по всей ширине.
5. Относительная depth не переводится в метры и не используется для метрических
   фраз.
6. YOLO может повысить риск, но не отменить геометрическую угрозу.
7. Старая модельная выдача не применяется к новому кадру.
8. Результат из предыдущей camera session generation отбрасывается.
9. Планировщик не рекомендует движение за пределы недавно наблюдавшегося поля.
10. При близкой угрозе пользователь сначала останавливается; обход строится уже
    после остановки или при достаточном запасе времени.
11. Только один компонент формирует пользовательское действие —
    `GuidanceStateMachine`.
12. Только один компонент управляет каналами обратной связи — `AlertArbiter`.
13. Любая произнесённая команда имеет `actionId`, `sceneRevision`, правило,
    исходные доказательства и срок годности.
14. VLM/LLM, scene narration и open-vocabulary описание не участвуют в
    критическом safety loop.
15. Sonar не может самостоятельно доказать свободный коридор.
16. При отказе обязательного канала приложение сообщает о деградации, а не
    продолжает молча.

---

## 3. Целевая архитектура

```text
Camera owner + IMU + optional ARCore depth
  -> FrameSynchronizer
      -> FramePacket + SensorHealth
          -> QualityAndOrientationGate
              -> DepthProvider
              -> SemanticObjectDetector
              -> TraversabilitySegmenter
              -> MotionEstimator
              -> OptionalAcousticRangeProvider
                  -> LocalSceneModel
                      -> HazardTracker
                      -> CorridorPlanner
                          -> GuidanceStateMachine
                              -> SafetyAction
                                  -> AlertArbiter
                                      -> TTS
                                      -> Earcon
                                      -> Haptic

CoreHealthCoordinator gates every stage and owns the user-visible run state.
```

### 3.1 Composition roots

Core и Research должны иметь разные composition roots.

Core создаёт только:

- camera/session/lifecycle;
- frame quality and orientation;
- выбранные depth/detection/traversability providers;
- local scene, risk, planner and alert runtime;
- TTS, earcon, haptic;
- manual SOS;
- минимальные настройки и диагностику.

Research дополнительно может создавать:

- sonar;
- экспериментальные модели;
- VLM/scene narration;
- расширенный debug HUD;
- dataset capture tooling.

Проверка feature flag после создания объекта недостаточна. Deferred-сервисы не
должны конструироваться в Core.

---

## 4. Контракты данных

### 4.1 Расширенный `FramePacket`

Текущий файл: `lib/models/frame_packet.dart`.

Добавить или связать через вложенные immutable-структуры:

```text
FramePacket
  sessionGeneration
  frameId
  cameraTimestampUs
  receivedAtUs
  sensorRotationDeg
  mirrored
  sourceSize
  uprightSize
  cropTransform
  cameraIntrinsics
  exposureState
  blurScore
  illuminationScore
  pitchDeg / rollDeg
  angularVelocity
  motionState
```

Требования:

- один timestamp-domain либо явное преобразование между domain;
- transforms применяются одинаково к RGB, luma, depth, masks и boxes;
- packet immutable;
- очередь кадров bounded: `latest-frame-wins`;
- на один provider не более одной тяжёлой inference одновременно;
- поздний результат возвращает исходные `sessionGeneration`, `frameId` и
  timestamp и проверяется до fusion.

### 4.2 `PerceptionObservation`

Новая папка: `lib/safety/perception/`.

Общий заголовок каждого результата:

```text
ObservationHeader
  providerId
  modelId
  modelHash
  sessionGeneration
  frameId
  sourceTimestampUs
  producedAtUs
  transformId
  confidence
  health
```

Провайдеры возвращают типизированные payload, но используют один header.

### 4.3 `LocalSceneSnapshot`

Новая папка: `lib/safety/world/`.

```text
LocalSceneSnapshot
  revision
  at
  coordinateMode: metric | relative
  poseQuality
  observedField
  cells / polarSectors
  hazardTracks
  movingThreats
  sensorHealth
```

Каждая cell/sector содержит:

```text
occupancyProbability
traversabilityProbability
dropProbability
unknownProbability
confidence
sourceMask
lastObservedAt
motionVector / closingRate
```

Metric и relative представления не смешиваются. При смене provider либо
создаётся новая карта, либо выполняется явное преобразование с маркировкой
неопределённости.

### 4.4 `CorridorCandidate`

Новая папка: `lib/safety/planning/`.

```text
CorridorCandidate
  id
  sceneRevision
  direction
  observedFraction
  minimumClearance
  surfaceContinuity
  dropRisk
  collisionRisk
  movingThreatRisk
  unknownRisk
  requiredHeadingChange
  validUntil
  rejectionReasons
```

Отсутствующее значение остаётся unknown; оно не заменяется оптимистичным
default.

### 4.5 `SafetyAction`

```text
SafetyActionKind
  continueForward
  adjustLeft
  adjustRight
  holdAndScan
  stopNow

SafetyAction
  actionId
  kind
  cause
  priority
  sceneRevision
  hazardIds
  evidenceSummary
  direction
  confidence
  createdAt
  validUntil
  ruleId
```

`continueForward` означает лишь отсутствие команды изменить текущее действие.
Его нельзя озвучивать как «путь свободен» или «идти безопасно».

### 4.6 `FeedbackCommand`

Новая папка: `lib/safety/alerts/`.

```text
FeedbackCommand
  actionId
  speechKey
  earcon
  hapticPattern
  priority
  canInterrupt
  replaceKey
  expiresAt
```

Детекторы, tracker, world model и planner не вызывают TTS или vibration.

---

## 5. Стек восприятия

### 5.1 Семантические объекты

Контроль:

- текущий `assets/yolov8n_int8.tflite`;
- существующий `ModelService` и текущий decoder.

Кандидаты:

1. YOLO11n INT8, input 320 и 416;
2. YOLO26n INT8/NCNN после реализации отдельного `[1,300,6]` decoder;
3. при лицензионном или runtime-блокере — PicoDet-S/другой permissive mobile
   detector как отдельный challenger.

Решение:

- сначала benchmark YOLO11n против YOLOv8n;
- YOLO26n не интегрировать в production decoder до отдельного contract test;
- COCO-классы использовать как enrichment;
- позже fine-tune только на классах, которые меняют safety action;
- неизвестные препятствия всегда остаются задачей geometry/depth.

Классы первого custom dataset:

- person/group;
- car/bus/truck;
- bicycle/motorcycle/scooter;
- pole/bollard/barrier;
- trash bin/box/chair;
- door/glass-door marker;
- hanging branch/sign;
- construction obstacle.

Не добавлять десятки описательных классов без доказательства, что они меняют
риск или действие.

### 5.2 Depth providers

Provider interface должен возвращать:

- `DepthFrame`;
- semantics: `metricMeters` или `relativeProximity`;
- per-pixel confidence;
- alignment metadata;
- timestamp;
- capability health;
- provider/model hash.

Порядок кандидатов:

1. ARCore Raw Depth на поддерживаемом reference phone;
2. MiDaS Small NCNN как текущий monocular control;
3. Depth Anything V2 Small как challenger;
4. компактный distilled student для low-end tier, если DA-V2 не проходит
   latency/thermal gate.

Правила:

- не заменять detector и depth в одном эксперименте;
- DA-V2 Small считать relative, пока отдельный metric benchmark не доказал
  обратное для конкретного checkpoint/domain;
- использовать confidence и finite coverage;
- отклонять weak dynamic range, noisy/random plane, stale и unaligned results;
- при provider switch очищать temporal state, который зависит от scale.

### 5.3 Traversability segmentation

Кандидаты:

- PP-LiteSeg-T;
- DeepLabV3 + MobileNetV3-Small;
- PP-MobileSeg как low-end challenger.

Минимальные классы:

```text
traversableSurface
nonTraversableSurface
verticalObstacle
stepOrDropBoundary
roadOrVehicleZone
unknownOrOccluded
```

Модель не является единственным safety-authority. Она:

- подтверждает поверхность;
- повышает drop/road risk;
- маркирует unknown;
- не отменяет depth geometry.

### 5.4 Motion

На первом этапе не добавлять тяжёлую нейросеть optical flow.

Использовать:

- существующий temporal tracker;
- sparse optical flow или feature tracking;
- IMU для компенсации движения камеры;
- metric velocity, если доступна metric depth;
- relative approach trend, если depth относительная.

Для динамической угрозы хранить:

- closing rate;
- lateral crossing rate;
- predicted corridor intersection;
- time-to-collision только при валидной scale/time base;
- uncertainty.

### 5.5 Стекло, отражения и плохое освещение

Отдельные failure classes:

- прозрачная дверь;
- зеркало;
- блестящий пол;
- глубокая тень;
- пересвет;
- дождь/снег на объективе;
- полное или частичное закрытие камеры.

Если geometry и segmentation расходятся, система не выбирает оптимистичный
результат. Она повышает `unknownRisk` и сообщает о деградации.

---

## 6. Local Scene Model

### 6.1 Coordinate modes

#### Metric mode

Доступен только при валидном metric provider и calibration.

- egocentric x/z occupancy grid;
- cell resolution выбирается после device benchmark;
- body corridor моделируется как swept volume с запасом;
- старые cells компенсируются pose update и постепенно теряют confidence.

#### Relative mode

- фиксированные angular/polar sectors;
- относительная близость и approach trend;
- никаких метрических width/distance;
- planner может рекомендовать только coarse action;
- строгий gate на critical и guidance.

### 6.2 Fusion policy

Fusion не должен быть простым средним confidence.

- подтверждение источников повышает уверенность;
- любой надёжный источник может повысить collision/drop risk;
- источник с низкой уверенностью не имеет права отменить надёжную угрозу;
- конфликт источников повышает unknown risk;
- stale source перестаёт влиять после TTL;
- каждое решение хранит source mask.

### 6.3 Temporal rules

- новый обычный obstacle требует N-of-M confirmation;
- imminent центральная угроза может использовать более быстрый asymmetric gate;
- disappearing track живёт короткий bounded grace period;
- receding track понижает action только после устойчивого тренда;
- moving crossing threat сохраняется до выхода из swept corridor;
- scene revision увеличивается при каждом значимом update.

---

## 7. Corridor Planner

### 7.1 Кандидаты движения

Для Core 1.0 генерировать ограниченный набор:

- прямо;
- немного левее;
- немного правее.

Широкие повороты, разворот, обход сзади, переход дороги и лестничные манёвры не
входят в первый planner.

### 7.2 Оценка кандидата

Каждый corridor получает независимые оценки:

```text
hardReject:
  confirmed obstacle inside swept volume
  drop/stair boundary
  moving threat intersection
  insufficient observed width
  stale scene
  invalid phone orientation

softCost:
  low clearance
  partial observability
  low surface confidence
  unknown cells
  large heading change
  temporal instability
  proximity to people/vehicles
```

Hard reject нельзя компенсировать хорошим значением другого признака.

### 7.3 Выбор действия

1. Если текущий corridor имеет imminent hard risk — `stopNow`.
2. Если пользователь движется, а scene health недостаточен — `stopNow`.
3. Если пользователь стоит и сцена недостаточна — `holdAndScan`.
4. Если текущий corridor заблокирован, выбрать альтернативу можно только при
   полном прохождении positive-evidence gates.
5. Если обе альтернативы недоказаны — `holdAndScan`.
6. Если текущий corridor приемлем — внутренний `continueForward` без фразы
   «путь свободен».

### 7.4 Stability and hysteresis

- direction должна сохраняться несколько revisions;
- новый corridor должен быть заметно лучше текущего;
- left/right не должны чередоваться на соседних кадрах;
- после `stopNow` требуется отдельное условие release;
- action имеет короткий TTL и пересчитывается по latest scene;
- устаревшее guidance не ставится в речь.

### 7.5 Запрещённые команды первого релиза

- «Путь свободен»;
- «Можно безопасно идти»;
- «Перешагните препятствие»;
- «Спуститесь по ступеньке»;
- «До препятствия N метров» при relative depth;
- команда двигаться в частично невидимую область;
- команда обхода, построенная только по отсутствию YOLO boxes.

---

## 8. Guidance State Machine

### 8.1 Состояния

```text
stopped
observing
movingStable
correctionPending
holdingForScan
emergencyStop
degraded
recovering
```

### 8.2 Переходы

- `observing -> movingStable`: обязательные sensing/output channels healthy;
- `movingStable -> correctionPending`: устойчивый лучший альтернативный
  corridor и достаточный lead time;
- `* -> emergencyStop`: imminent collision/drop либо потеря обязательного
  spatial sensing во время движения;
- `emergencyStop -> holdingForScan`: пользователь остановился, imminent risk
  больше не растёт;
- `holdingForScan -> correctionPending`: альтернативный corridor положительно
  подтверждён;
- `holdingForScan -> degraded`: получить пригодную сцену не удалось;
- `degraded -> recovering`: обязательные каналы восстановлены и устойчивы;
- `recovering -> observing`: новая сцена собрана без использования stale state.

### 8.3 Примеры

#### Близкий мусорный бак по центру

```text
confirmed geometry + central overlap + near/approaching
  -> stopNow
  -> прервать текущую речь
  -> critical haptic
  -> «Стой. Препятствие впереди.»
```

Название «мусорный бак» добавлять только если оно помогает после остановки.

#### Центр заблокирован, слева доказан проход

```text
stop/slow first if lead time is short
  -> rebuild scene
  -> left corridor passes every gate for N revisions
  -> adjustLeft
  -> «Возьми немного левее.»
```

#### Центр заблокирован, альтернативы неизвестны

```text
stopNow
  -> holdAndScan
  -> «Стой. Проход не определён.»
```

#### Низкая освещённость или stale depth

```text
moving -> stopNow + degraded reason
already stopped -> holdAndScan + degraded reason
```

#### Автомобиль пересекает траекторию

```text
moving track + corridor intersection
  -> stopNow
  -> «Стой. Автомобиль справа.»
```

---

## 9. Alert Arbiter

### 9.1 Один вход

`AlertManager` постепенно заменить/сузить до адаптера над `AlertArbiter`.
Новый arbiter принимает только:

- `SafetyAction`;
- `CoreHealthSnapshot`;
- подтверждённые emergency/SOS events;
- явные on-demand user requests.

Он не должен повторно вычислять scene risk.

### 9.2 Приоритеты

```text
P0 emergencyStop / imminent collision / drop
P1 corrective guidance
P2 degraded/unavailable health
P3 informational and on-demand
```

Если sensing потерян во время движения, health event создаёт P0 stop action.
Если пользователь уже стоит, тот же health event остаётся P2.

### 9.3 Preemption matrix

| Текущее | Новое | Поведение |
| --- | --- | --- |
| P3 | P0 | немедленно остановить речь, удалить stale P1-P3, выдать P0 |
| P2 | P0 | немедленно заменить на P0 |
| P1 | P0 | немедленно заменить на P0 |
| P0 | новый независимый P0 | сохранить самый срочный; второй допускается только если меняет действие/направление |
| P0 | обновление того же hazard | заменить queued/current phrase только при росте риска или смене действия |
| P1 | новый P1 | заменить по `replaceKey`, не накапливать очередь |
| любой | expired action | удалить без произнесения |

### 9.4 Speech policy

- действие произносится первым;
- critical phrase короткая;
- не перечислять объекты;
- object label использовать только если он меняет смысл;
- `trackId/hazardId` участвует в dedup;
- повтор разрешён при росте риска, смене направления или истечении cooldown;
- после recovery не произносить «всё безопасно»;
- последний critical доступен через явную кнопку повтора.

### 9.5 Queue contract

Исправить `lib/services/tts_service.dart`:

- общий bounded размер, включая critical;
- TTL для каждого job;
- stale cleanup при каждом enqueue и перед speech start;
- replace по `actionId`/`hazardId`;
- причина каждого drop/replace логируется;
- critical не теряется при TTS stall или audio route change;
- engine unavailable вызывает haptic fallback и health transition;
- software preemption измеряется отдельно от фактической audio latency.

### 9.6 Haptics

Core использует не более трёх семантик:

1. немедленная остановка;
2. sensing degraded/unavailable;
3. подтверждение пользовательского действия.

Направление left/right не кодировать сложными паттернами одного вибромотора до
пользовательской валидации. Направление передаётся речью или stereo-earcon.

Ограничения:

- duty-cycle budget;
- cooldown;
- повтор только при сохранении/росте critical risk;
- strength scaling не опускает critical ниже perceptual floor;
- устройство без amplitude control получает отдельный fallback pattern.

---

## 10. Sonar / активная акустика

Sonar остаётся Research-only до завершения всех vision/planner Core gates.

### 10.1 Допустимая роль

- подтвердить близкую фронтальную поверхность;
- повысить risk при плохом освещении;
- дополнить vision на стекле/однотонной стене;
- никогда не создавать свободный corridor;
- никогда не понижать подтверждённый vision/depth risk.

### 10.2 Необходимые изменения

Файлы:

- `lib/services/sonar_service.dart`;
- `android/app/src/main/kotlin/com/example/bagdar/SonarPlugin.kt`;
- `lib/services/device_capability.dart`;
- `lib/services/audio_capture_broker.dart`;
- `lib/services/sensor_session_coordinator.dart`.

Добавить:

- проверки `SUPPORT_MIC_NEAR_ULTRASOUND`;
- проверку `SUPPORT_SPEAKER_NEAR_ULTRASOUND`;
- проверку/использование unprocessed audio source, если поддерживается;
- измерение реального sample rate и input/output route;
- direct-path cancellation;
- device-specific loopback latency calibration;
- устойчивое background/noise profile;
- multipath-aware peak selection;
- confidence из нескольких chirps, а не одного correlation peak;
- interruption при call/TTS/headphones/audio-route change;
- capability health и telemetry;
- допустимый акустический уровень и проверку слышимости сигнала.

### 10.3 Shadow gates

- ни одного user alert в первой реализации;
- запись range/confidence рядом с vision ground truth;
- отдельные отчёты по phone model и orientation;
- стены, стекло, ткань, человек, открытый проход, угол, улица, транспортный шум,
  чехол телефона;
- false-near и missed-near rates;
- repeatability после restart и route change;
- пользовательская проверка, что chirp не раздражает и не маскирует окружение.

---

## 11. Dataset и replay infrastructure

### 11.1 Источники данных

До появления телефона:

- SANPO Real/Synthetic и другие лицензированно совместимые egocentric clips;
- собственные видео с любой доступной камерой для логики replay;
- Blender synthetic scenes из имеющихся assets;
- процедурные depth/noise fixtures;
- adversarial transforms: blur, exposure, crop, rotation, mirror, stale offset.

После появления reference phone:

- данные только при явном согласии;
- фиксированное camera mount;
- синхронные RGB/depth/IMU;
- named device/build/model hashes;
- privacy-safe crops либо локальное хранение;
- отдельный consent для любых сырых camera dumps.

### 11.2 Corpus schema

Новая структура:

```text
test/fixtures/spatial_safety/
  manifest.json
  scenes/
    <scene-id>/
      frames.jsonl
      rgb/                # optional/private
      depth/              # compact binary or npy-compatible export
      segmentation/       # optional labels
      annotations.json
```

Manifest содержит:

- schema version;
- source/license/consent class;
- mount and camera parameters;
- expected model/preprocess hash;
- allowed public/private handling;
- scene tags;
- annotation revision;
- required/optional RC status.

### 11.3 Annotation schema

Для каждого сценария:

- наблюдаемая область;
- obstacle masks/boxes;
- unknown/unobserved regions;
- traversable surface;
- drop/stair boundary;
- moving trajectories;
- допустимые действия во времени;
- запрещённые действия во времени;
- expected health transitions;
- expected alert transitions.

Главная метка planner-теста — не object class, а множество разрешённых и
запрещённых `SafetyAction` для каждого временного участка.

### 11.4 Обязательные сценарии

#### Положительные препятствия

- широкая стена;
- столб/bollard;
- коробка/стул/мусорный бак;
- низкая преграда;
- нависающая ветка/знак;
- частично перекрытый объект;
- объект без известного semantic class.

#### Поверхность

- бордюр вверх/вниз;
- лестница вверх/вниз;
- яма;
- край платформы;
- наклон;
- трава/тротуар/дорога;
- отражающий и однотонный пол.

#### Динамика

- человек навстречу;
- человек пересекает путь;
- велосипед/самокат;
- автомобиль приближается;
- stopped/receding vehicle;
- толпа и временный проход.

#### Деградация

- темнота;
- пересвет;
- blur;
- lens occlusion;
- сильный roll/pitch;
- stale depth;
- RGB/depth misalignment;
- camera stall;
- model exception;
- TTS unavailable;
- thermal throttling.

#### Planner

- центр заблокирован, слева доказан проход;
- центр заблокирован, справа доказан проход;
- обе стороны неизвестны;
- широкий YOLO gap над ямой;
- свободные boxes, но непроходимая поверхность;
- corridor выходит за недавно наблюдавшееся поле;
- left/right alternation;
- препятствие возникает во время guidance.

---

## 12. Метрики

### 12.1 Perception

- critical obstacle event recall;
- central thin-obstacle recall;
- overhead recall;
- drop/stair recall;
- false critical per annotated hour;
- track fragmentation;
- direction/zone accuracy;
- moving-threat intersection recall;
- health rejection precision/recall;
- model latency p50/p95;
- end-to-end decision latency p50/p95.

COCO mAP и segmentation mIoU записываются, но не являются release gates сами
по себе.

### 12.2 Planner

- `unsafeGuidanceCount`;
- `guidanceIntoUnknownCount`;
- correct stop rate;
- unnecessary stop rate;
- direction correctness;
- action oscillation count;
- time from hazard visibility to `stopNow`;
- time from stable alternative corridor to correction action;
- stale action emission count.

Главный гейт canonical corpus:

```text
unsafeGuidanceCount == 0
guidanceIntoUnknownCount == 0
staleActionEmissionCount == 0
```

Этот результат относится только к названному корпусу и не доказывает
универсальную безопасность.

### 12.3 Alerts

- critical action to software-preemption time;
- actual ear-to-audio latency на устройстве;
- dropped critical count;
- unbounded queue growth count;
- stale speech count;
- duplicate speech count;
- haptic fallback success;
- alerts per minute;
- доля alerts, которые не изменили действие пользователя.

### 12.4 Device runtime

- camera FPS;
- provider/model FPS;
- dropped-frame age;
- p50/p95 end-to-end latency;
- RSS/native heap/GPU memory;
- battery drain;
- thermal state;
- recovery time after pause/call/lock/camera stall;
- 30-minute sustained run.

---

## 13. Model bake-off protocol

Каждая замена модели проходит один и тот же pipeline.

### 13.1 Detector experiment matrix

```text
control:    YOLOv8n INT8 current input/runtime
candidate1: YOLO11n INT8 320
candidate2: YOLO11n INT8 416
candidate3: YOLO26n INT8/NCNN with dedicated decoder
```

Фиксировать:

- exact checkpoint/export command;
- license;
- input/output tensor contract;
- preprocessing;
- quantization dataset;
- model hash;
- desktop correctness;
- replay metrics;
- named-device latency/memory/thermal позже.

### 13.2 Depth experiment matrix

```text
control:    current MiDaS Small NCNN
candidate1: Depth Anything V2 Small 256
candidate2: Depth Anything V2 Small 320
candidate3: distilled mobile student if required
```

Сравнивать:

- spatial rank correlation;
- edge preservation;
- ground-plane stability;
- thin obstacle response;
- drop boundary response;
- temporal flicker;
- weak-texture and reflective scenes;
- invalid/low-confidence rejection;
- native/reference parity;
- downstream hazard metrics.

### 13.3 Segmentation experiment matrix

```text
candidate1: PP-LiteSeg-T
candidate2: DeepLabV3-MobileNetV3-Small
candidate3: PP-MobileSeg
```

Сравнивать не только mIoU, но boundary recall для curb/stair/drop и downstream
изменение unsafe guidance.

### 13.4 Выбор победителя

Модель выбирается только если:

- не ухудшает canonical critical recall;
- не повышает unsafe planner decisions;
- проходит output/preprocess contract;
- проходит latency/memory/thermal на reference phone;
- имеет приемлемую лицензию;
- имеет воспроизводимый export;
- предыдущая контрольная модель сохраняется для rollback.

---

## 14. Этапы реализации

### Этап 0 — зафиксировать безопасный baseline

Файлы:

- `lib/utils/distance_utils.dart`;
- `lib/utils/decision_engine.dart`;
- `lib/camera/alert_manager.dart`;
- `lib/services/tts_service.dart`;
- `lib/models/strings.dart`;
- соответствующие tests.

Работы:

1. Отключить в Core текущие free-corridor voice hints.
2. Удалить произнесение pixel-derived метров.
3. Оставить исследовательскую telemetry старой логики только под Research.
4. Ограничить critical queue и добавить TTL/replace semantics.
5. Добавить regression tests на отсутствие «путь свободен» и metric speech
   при relative depth.
6. Зафиксировать baseline replay/test отчёт.

Exit gate:

- Core не рекомендует обход по YOLO gaps;
- relative path не произносит метры;
- critical queue bounded;
- обычная software suite зелёная либо все unrelated failures явно записаны.

### Этап 1 — контракты и чистая архитектурная граница

Новые файлы:

- `lib/safety/perception/observation_header.dart`;
- `lib/safety/world/local_scene_snapshot.dart`;
- `lib/safety/planning/corridor_candidate.dart`;
- `lib/safety/planning/safety_action.dart`;
- `lib/safety/alerts/feedback_command.dart`.

Изменить:

- `lib/models/frame_packet.dart`;
- `lib/camera/camera_session.dart`;
- `lib/camera/depth_pipeline_controller.dart`.

Работы:

1. Ввести immutable contracts.
2. Протащить generation/frame/timestamp/transform через pipeline.
3. Отбрасывать late/stale/mismatched результаты.
4. Добавить serialization только для privacy-safe diagnostics/replay.
5. Не менять пользовательское поведение кроме безопасных отказов.

Exit gate:

- unit tests для rotation/mirror/crop;
- late inference не изменяет current scene;
- session restart не принимает старые results;
- все observations имеют model/preprocess identity.

### Этап 2 — replay corpus и строгий harness

Новые файлы:

- `test/harness/spatial_replay_fixture.dart`;
- `test/harness/spatial_scenario_runner.dart`;
- `test/fixtures/spatial_safety/manifest.json`;
- `tool/build_spatial_corpus.*`;
- `tool/report_spatial_metrics.*`;
- `docs/spatial-corpus-contract.md`.

Работы:

1. Реализовать schema и manifest validation.
2. Перенести synthetic scenarios в общий runner.
3. Любой `partial` в RC превращать в failure.
4. Отдельно маркировать missing external/private corpus.
5. Добавить deterministic seed и model/hash checks.
6. Создать первые synthetic Blender/procedural scenarios.

Exit gate:

- runner воспроизводим;
- reports не зависят от порядка tests;
- RC падает при отсутствии обязательного corpus;
- expected/forbidden actions проверяются по timeline.

### Этап 3 — Local Scene Model

Новые файлы:

- `lib/safety/world/local_scene_model.dart`;
- `lib/safety/world/metric_occupancy_grid.dart`;
- `lib/safety/world/relative_polar_grid.dart`;
- `lib/safety/world/scene_fusion_policy.dart`;
- `test/local_scene_model_test.dart`;
- `test/scene_fusion_policy_test.dart`.

Работы:

1. Интегрировать generic geometry observations.
2. Добавить observed/unknown field.
3. Добавить time decay и source masks.
4. Подключить moving tracks.
5. Подготовить traversability input interface.
6. Реализовать metric/relative separation.

Exit gate:

- неизвестная зона не становится free;
- stale cells теряют authority;
- geometry survives YOLO absence;
- source conflict повышает unknown;
- deterministic replay snapshot tests проходят.

### Этап 4 — Corridor Planner и Guidance FSM

Новые файлы:

- `lib/safety/planning/corridor_generator.dart`;
- `lib/safety/planning/corridor_evaluator.dart`;
- `lib/safety/planning/guidance_state_machine.dart`;
- `test/corridor_planner_test.dart`;
- `test/guidance_state_machine_test.dart`.

Работы:

1. Генерировать три bounded corridor candidates.
2. Добавить hard rejects и soft costs.
3. Добавить positive-evidence gate.
4. Добавить hysteresis и anti-oscillation.
5. Реализовать пять `SafetyActionKind`.
6. Подключить motion/health state.
7. Оставить output в shadow telemetry.

Exit gate:

- `unsafeGuidanceCount == 0` на текущем canonical corpus;
- нет guidance в unknown/unobserved area;
- imminent risk всегда даёт `stopNow`;
- degraded while moving даёт `stopNow`;
- relative mode не создаёт metric claims.

### Этап 5 — Alert Arbiter

Новые файлы:

- `lib/safety/alerts/alert_arbiter.dart`;
- `lib/safety/alerts/feedback_policy.dart`;
- `lib/safety/alerts/haptic_policy.dart`;
- `test/alert_arbiter_test.dart`;
- `test/feedback_policy_test.dart`.

Изменить:

- `lib/camera/alert_manager.dart`;
- `lib/services/tts_service.dart`;
- `lib/services/haptic_service.dart`;
- `lib/services/earcon_service.dart`.

Работы:

1. Перевести spatial safety на единый arbiter.
2. Реализовать preemption matrix.
3. Добавить action/hazard replacement.
4. Добавить TTL и stale purge.
5. Ограничить критическую очередь.
6. Упростить haptic vocabulary.
7. Добавить RU/KK/EN copy contract tests.

Exit gate:

- P0 прерывает P1-P3 в software path;
- ни один expired action не произносится;
- independent P0 не исчезает без причины;
- повтор одного hazard bounded;
- TTS unavailable вызывает haptic fallback и health update;
- журнал содержит emit/suppress/replace/drop reason.

### Этап 6 — Model bake-off

Новые/изменённые области:

- `model_export/`;
- `tool/model_benchmark/`;
- `lib/services/model_service.dart`;
- `lib/services/depth_provider.dart`;
- `lib/services/ncnn_depth_provider.dart`;
- model-contract tests;
- `docs/model-bakeoff-report.md`.

Работы:

1. Зафиксировать YOLOv8n control.
2. Экспортировать и проверить YOLO11n variants.
3. Добавить YOLO26n decoder как независимый experiment.
4. Конвертировать DA-V2 Small candidates.
5. Сравнить downstream spatial metrics.
6. Исследовать lightweight segmentation candidates.
7. Не менять production selection без полного отчёта.

Exit gate:

- один выбранный detector;
- один control и один выбранный depth provider per tier;
- один выбранный traversability model либо документированный defer;
- воспроизводимые export commands/hashes;
- desktop parity и replay gates;
- device performance остаётся отдельным blocked gate.

### Этап 7 — runtime integration

Файлы:

- `lib/camera/depth_pipeline_controller.dart`;
- `lib/viewmodels/camera_view_model.dart`;
- `lib/camera_screen.dart`;
- `lib/core/core_health_coordinator.dart`;
- Android camera owner implementation.

Работы:

1. Создать отдельный `SpatialSafetyRuntime`.
2. Один camera owner раздаёт синхронные frames/providers.
3. Подключить local scene -> planner -> arbiter.
4. Ввести bounded scheduling и latest-frame-wins.
5. Удалить старый parallel navigation hint path.
6. Добавить health transitions для каждого provider.
7. Сохранить новый planner в `shadow`.

Exit gate:

- один user-action authority;
- старый corridor engine не влияет на Core UI/TTS;
- provider failure не блокирует UI thread;
- no silent empty scene;
- debug telemetry показывает полный action trace.

### Этап 8 — sonar research

Начинать только после прохождения desktop spatial/planner/alert gates.

Exit gate до подключения к risk:

- capability checks;
- calibration contract;
- multi-chirp confidence;
- shadow corpus;
- named-device repeatability;
- ноль direct user alerts.

### Этап 9 — device validation

Выбрать один reference phone. Не объявлять широкую поддержку до прохождения
всех тестов на нём.

Проверить:

- cold start;
- camera ownership;
- pause/resume;
- lock/unlock;
- rotation/misalignment;
- permission revoke/regrant;
- incoming call/audio route change;
- camera/model stall;
- ARCore support and confidence;
- TTS/haptic/earcon latency;
- 30-minute thermal/memory run;
- TalkBack/Scanner/Switch Access;
- controlled walking Stages A-E.

Exit gate:

- no crash/ANR;
- no false `operational`;
- no silent provider loss;
- no unbounded memory/queue growth;
- canonical device corpus gates pass;
- actual alert latency measured;
- user-visible wording matches factual capability.

### Этап 10 — supervised assistive promotion

Promotion из `shadow` возможен только после отдельного подписанного отчёта.

Требования:

- named build/device/model hashes;
- canonical replay report;
- device matrix report;
- accessibility report;
- controlled walking report;
- known limitations;
- rollback switch;
- incident/near-miss capture without raw private media by default;
- explicit supported mount and environments;
- no unresolved safety-critical finding.

---

## 15. План работ без физического Android-телефона

Полностью выполнимо сейчас:

1. Этап 0: убрать unsafe corridor claims и исправить очередь.
2. Этап 1: контракты данных и stale/session guards.
3. Этап 2: replay schema, procedural/Blender corpus и RC harness.
4. Этап 3: Local Scene Model.
5. Этап 4: Corridor Planner и Guidance FSM в shadow.
6. Этап 5: Alert Arbiter и property/scenario tests.
7. Desktop model exports и reference inference.
8. UI/widget/accessibility semantics tests.
9. APK/AAB build, manifest и permission checks.

Частично выполнимо:

- YOLO/depth/segmentation comparison на desktop recordings;
- Android Emulator lifecycle/UI tests;
- NCNN/TFLite functional integration;
- sonar DSP simulation на записанных WAV/impulse responses.

Требует реального телефона:

- native/reference mobile parity;
- ARCore camera/depth ownership;
- latency, memory, battery and thermal;
- camera stalls and sensor timing;
- real TTS/audio route latency;
- haptic distinguishability;
- near-ultrasound capability and calibration;
- TalkBack walkthrough;
- controlled walking and user study.

---

## 16. Definition of Done для каждого изменения

Изменение не считается завершённым без:

1. сформулированного пользовательского/safety-инварианта;
2. теста или corpus-сценария, который до изменения его нарушал;
3. кода с bounded memory/queue/time behavior;
4. telemetry с rule/reason/source;
5. проверки stale/session/health failure;
6. RU/KK/EN copy, если меняется пользовательский текст;
7. `dart format`, `dart analyze`, focused tests и полная Flutter suite;
8. `git diff --check`;
9. обновления соответствующего evidence report;
10. честной маркировки blocked device gates.

Нельзя считать изменение готовым только потому, что оно компилируется или
проходит synthetic happy-path.

---

## 17. Запрещённые shortcuts

- полный rewrite больших safety-файлов без поэтапных regression tests;
- одновременная замена detector и depth model;
- подбор threshold по одному synthetic примеру;
- использование VLM-ответа как stop/go decision;
- перевод pixels/relative depth в метры через константу;
- inference queue без upper bound;
- усреднение confidence, позволяющее слабому источнику отменить угрозу;
- включение assistive до factual device/corpus evidence;
- запись сырых пользовательских кадров по умолчанию;
- заявление о поддержке Android вообще вместо named devices;
- скрытая деградация до пустой сцены;
- длинная фраза перед словом «Стой».

---

## 18. Рекомендуемый первый implementation slice

Первый узкий slice должен занимать только software path и давать проверяемый
результат без телефона.

Scope:

1. отключить старые Core corridor hints и pixel-derived metres;
2. добавить `SafetyAction` и `FeedbackCommand`;
3. ограничить critical queue, добавить TTL и replace-by-hazard;
4. создать минимальный `RelativePolarGrid`;
5. построить три corridor candidates;
6. разрешать только `stopNow` и `holdAndScan`, оставив adjust left/right в
   shadow telemetry;
7. добавить canonical scenarios:
   - center obstacle;
   - unknown center;
   - center blocked/left observed;
   - center blocked/left unobserved;
   - critical appears during info speech;
   - stale depth during motion;
8. выпустить первый `docs/spatial-safety-validation-report.md`.

Exit gate первого slice:

```text
0 unsafe guidance
0 guidance into unknown
0 stale spoken action
0 metric speech from relative depth
bounded critical queue
every action has traceable rule and evidence
```

После этого можно добавлять left/right guidance в shadow, затем model bake-off,
и только в самом конце — device-supervised assistive validation.

---

## 19. Основные технические источники

- Ultralytics YOLO11: https://docs.ultralytics.com/models/yolo11/
- Ultralytics YOLO26: https://docs.ultralytics.com/models/yolo26/
- Ultralytics licensing: https://www.ultralytics.com/license
- Depth Anything V2: https://github.com/DepthAnything/Depth-Anything-V2
- ARCore Raw Depth: https://developers.google.com/ar/develop/java/depth/raw-depth
- ARCore Depth overview: https://developers.google.com/ar/develop/depth
- Android near-ultrasound capabilities:
  https://developer.android.com/reference/android/media/AudioManager
- ObstacleWatch acoustic ranging paper: https://arxiv.org/abs/2106.01838
- Google Project Guideline:
  https://research.google/blog/project-guideline-enabling-those-with-low-vision-to-run-independently/
- SANPO egocentric dataset:
  https://research.google/blog/sanpo-a-scene-understanding-accessibility-navigation-pathfinding-obstacle-avoidance-dataset/


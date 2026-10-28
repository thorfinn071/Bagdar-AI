# Bagdar Spatial Safety — validation report

Дата: 2026-09-20

Срез: первый software/shadow implementation slice + Этапы 1–7, при этом
Stage 6 закрыт только на artifact/contract/desktop-smoke уровне

Статус: desktop software и shadow-runtime gates пройдены;
recorded-corpus/device/assistive gates не пройдены

## Реализованная граница

- Старый Core-маршрут corridor hints отключён. Он остаётся доступен только в
  `BuildProfile.research`, потому что строит проход по YOLO gaps и переводит
  ширину изображения в псевдометрическую ширину.
- Добавлена минимальная относительная spatial-модель из трёх секторов:
  `left`, `forward`, `right`. Все величины нормализованы; метров в контракте
  нет.
- Добавлены три `CorridorCandidate` и hard-reject причины для obstacle, drop,
  moving threat, unknown, stale scene, плохой ориентации и нездорового sensing.
- Добавлен консервативный `GuidanceStateMachine`. Пользовательский output
  первого среза ограничен `stopNow`, `holdAndScan` и безмолвным внутренним
  `continueForward`. `adjustLeft`/`adjustRight` остаются только shadow-данными.
- Добавлены immutable `SafetyAction` и `FeedbackCommand` с `actionId`,
  `sceneRevision`, `ruleId`, evidence, hazard identity и TTL.
- Добавлен единый bounded `AlertArbiter` для `SafetyAction`, health, emergency и
  on-demand inputs: полная P0 preemption matrix, cooldown/repeat policy,
  replace-by-hazard/action, TTL purge, `lastCritical` и ограниченный trace.
- Очередь `TtsService` теперь ограничивает также critical jobs: максимум четыре
  ожидающих critical-сообщения, явный TTL каждого job, stale cleanup при
  enqueue/start и replacement по `trackId`/`actionId`/`hazardId`.
- Добавлены `FeedbackDispatcher` и production output adapter. При недоступном
  TTS software path использует haptic fallback и обновляет `CoreHealthSnapshot`.
- Core haptic vocabulary ограничен тремя недирекционными семантиками; добавлены
  cooldown, duty-cycle budget и fallback для устройств без amplitude control.
- Тики fall-SOS countdown используют одну replacement identity. Новый тик
  заменяет устаревший, не удаляя независимую critical-угрозу.

Новый planner/arbiter пока не подключён к camera runtime. Это намеренно:
runtime integration выполняется только после контрактов и replay/world-model
слоёв. `GenericObstacleMode` остаётся `shadow`; assistive promotion не выполнен.

## Этап 1 — contracts и stale/session guards

- `FramePacket` теперь несёт `sessionGeneration`, монотонный `frameId`, camera и
  receipt timestamps в одном явно названном domain, единый `FrameTransform`,
  intrinsics/exposure/quality slots, ориентацию и motion state.
- `FrameTransform` фиксирует единственный порядок geometry operations:
  sensor rotation -> mirror -> crop. Есть отдельные преобразования в full
  upright и cropped upright space; transform identity детерминирован и не
  использует runtime `hashCode`.
- Добавлены общие `ObservationHeader` и `PerceptionObservation<T>`. Header
  требует provider/model/hash/preprocess identity, исходный generation/frame/
  timestamp/transform, confidence и health.
- Для текущего MiDaS NCNN закреплены SHA-256 обоих model assets и versioned
  preprocess identity. Platform и legacy adapters получают явную, не
  маскирующуюся под криптографический hash identity.
- `CameraSession` выдаёт frame IDs и проверяет latest-frame-wins. Новая camera
  generation создаётся до `startImageStream`, поэтому первый callback уже
  принадлежит новой сессии.
- `DepthPipelineController` допускает только одну тяжёлую inference. Result
  проверяется по generation/frame/header/latency/timestamp/rotation/mirror/crop
  до изменения health, tracker, fusion или alerts.
- Restart сессии не запускает вторую inference параллельно: старая завершается,
  но её payload отбрасывается. Superseded и late results также не меняют
  current scene state.
- Добавлен immutable `LocalSceneSnapshot`; metric cells и relative polar
  sectors физически разделены и не могут быть смешаны в одном snapshot.
- Diagnostics/replay serialization содержит только contract metadata и
  агрегаты: pixels, raw depth, coordinates, speech и payload не сериализуются.

## Canonical software scenarios

| Сценарий | Ожидаемый результат | Результат |
| --- | --- | --- |
| Center obstacle | `stopNow`, P0, rule/evidence/hazard trace | pass |
| Unknown center, пользователь стоит | `holdAndScan`, без side guidance | pass |
| Unknown center, пользователь движется | `stopNow` | pass |
| Center blocked, left observed | left proposal виден, но один revision не создаёт shadow action | pass |
| Center blocked, left unobserved | нет guidance в unknown | pass |
| Stable left alternative | `adjustLeft` появляется только после трёх revisions и остаётся shadow | pass |
| Critical появляется во время info speech | P0 немедленно прерывает info | pass |
| Stale scene во время движения | `stopNow`, не empty/clear scene | pass |
| Expired action | drop до active speech | pass |
| Независимые P0 | bounded buffer, причина eviction записана | pass |
| Relative mode speech | нет метров и нет path-clear claims | pass |

## Exit gate первого среза

| Gate | Evidence | Статус |
| --- | --- | --- |
| 0 unsafe guidance | FSM не выдаёт left/right как user action | pass на canonical software suite |
| 0 guidance into unknown | unknown/stale дают hold или stop | pass |
| 0 stale spoken action | action/command TTL проверяется до dispatch | pass |
| 0 metric speech from relative depth | relative feedback использует только non-metric copy keys | pass |
| bounded critical queue | arbiter total buffer <= 4; TTS critical queue <= 4 | pass |
| traceable rule and evidence | каждый `SafetyAction` требует rule, cause и evidence | pass |

## Выполненные проверки

```text
dart analyze
No issues found!

flutter test --no-pub \
  test/fall_countdown_tts_preemption_test.dart \
  test/tts_service_test.dart \
  test/spatial_safety_first_slice_test.dart
29 passed

flutter test --no-pub \
  test/core_logic_test.dart \
  test/alert_manager_critical_cooldown_test.dart \
  test/alert_manager_crowd_escalation_test.dart \
  test/alert_manager_reset_test.dart \
  test/alert_system_audit_fixes_test.dart \
  test/alert_filter_same_category_critical_test.dart \
  test/generic_obstacle_alert_test.dart \
  test/core_feature_policy_test.dart
132 passed

flutter test --no-pub --machine
success: true

flutter test --no-pub \
  test/camera_session_test.dart \
  test/depth_pipeline_observation_guard_test.dart \
  test/local_scene_snapshot_contract_test.dart
13 passed

flutter test
965 passed, 1 skipped, 0 failed
```

Полная suite сохраняет один ожидаемый skip: отсутствует внешний NCNN reference
fixture `test/fixtures/ncnn_contract/reference_outputs.json`. Это не считается
успешной native/reference parity-проверкой.

## Exit gate Этапа 1

| Gate | Evidence | Статус |
| --- | --- | --- |
| rotation/mirror/crop contract | deterministic geometry unit tests | pass |
| late inference does not mutate scene | controlled pending-provider test | pass |
| session restart rejects old result | generation restart test | pass |
| every accepted depth observation has identity | required header + MiDaS asset/preprocess assertions | pass |
| metric/relative scene data cannot mix | constructor invariant test | pass |
| ordinary software regression | `dart analyze`; full Flutter suite | pass |

## Этап 2 — replay corpus и строгий harness

- Добавлен versioned manifest и девять детерминированных procedural scenes в
  `test/fixtures/spatial_safety/`.
- Manifest фиксирует seed, source/license/consent, camera mode, model/preprocess
  identity, annotation revision, RC requirement и SHA-256 обоих scene-файлов.
- Parser отклоняет неизвестную schema, path traversal, duplicate IDs, неверные
  probabilities, hash mismatch, model/preprocess mismatch, смешение camera
  generations и немонотонные frame IDs.
- Timeline annotations задают expected/forbidden actions, health, alert event,
  shadow direction и preemption. Каждый frame обязан попасть ровно в один
  непересекающийся интервал.
- Runner сортирует scenes/frames, использует фиксированный UTC origin и выдаёт
  стабильный JSON независимо от test order.
- `partial`/`missing` для `requiredForRc` допускаются как явно видимый
  developer-status, но блокируют строгий RC run.
- Старый layered diagnostic harness теперь также отклоняет любой `partial` при
  `--dart-define=BAGDAR_RC=true`. Проверка намеренно блокируется на известном
  `A6`: случайный noisy depth всё ещё может дать ложный `planeFitOk=true`.
- Missing Blender corpus и private recorded corpus показаны отдельными полями и
  не маскируются под pass. В текущем software RC они ещё не обязательны.
- Generator имеет read-only `--check`; report tool имеет developer и `--rc`
  режимы.

Проверки Этапа 2:

```text
dart run tool/build_spatial_corpus.dart --check
Spatial corpus matches generator (19 files).

flutter test --no-pub test/spatial_replay_harness_test.dart
10 passed

dart run tool/report_spatial_metrics.dart --rc \
  --output docs/_baseline_logs/spatial_replay_rc.json
passed: true
unsafeGuidanceCount: 0
guidanceIntoUnknownCount: 0
staleActionEmissionCount: 0

flutter test --no-pub --dart-define=BAGDAR_RC=true \
  test/harness/scenario_harness_test.dart
expected failure: partial scenario A6 blocks RC
```

## Exit gate Этапа 2

| Gate | Evidence | Статус |
| --- | --- | --- |
| runner reproducible | generator `--check`; repeated and reversed-order report test | pass |
| reports independent of test order | canonical sort + byte-equivalent JSON test | pass |
| RC fails on required `partial` | explicit developer/RC mode regression | pass |
| RC fails on required `missing` | missing-fixture regression | pass |
| legacy harness rejects `partial` in RC | `A6` produces an intentional failing RC test | pass (strictness); overall RC blocked |
| expected/forbidden action timeline | every frame matched; temporal two-frame scenario | pass |
| model/preprocess identity | mismatch regression fails all affected scenes | pass |
| canonical safety metrics | all three primary counters equal zero | pass on procedural v1 corpus |

## Этап 3 — Local Scene Model

- Добавлен pure-Dart `LocalSceneModel`, который единолично владеет mutable
  spatial state и публикует только immutable `LocalSceneSnapshot`.
- `SpatialEvidence` использует nullable probabilities: отсутствие мнения
  источника не превращается в оптимистичный ноль.
- Fusion повышает risk по максимуму, не позволяет semantic/low-risk evidence
  отменить geometry threat, повышает `unknownProbability` при конфликте и
  сохраняет полный source mask.
- Bounded time decay уменьшает authority старых risk/free observations,
  увеличивает unknown и полностью удаляет cell после TTL.
- Relative snapshot всегда содержит `left/forward/right`; отсутствующий сектор
  создаётся как `unknown=1`, `traversability=0`, а не как свободный.
- Generic geometry adapter подключает существующие N-of-M tracks, сохраняет
  geometry при полном отсутствии YOLO и допускает fast path только для
  imminent центральной угрозы.
- Подключены moving track snapshots и relative approach trend.
- Подготовлен typed `TraversabilityEvidenceSource`; segmentation provider не
  получает права отменять geometry risk.
- Metric grid требует явный `MetricGridCalibration`, валидные `cell:x:z` IDs и
  сохраняет calibration ID в snapshot. Device-independent resolution не
  выбрана и не заявлена.
- Generic adapter вынесен из pure-Dart world model, чтобы `dart run` replay
  tools не зависели от `dart:ui`.
- Stage 2 runner теперь строит каждый planner frame через `LocalSceneModel` и
  `RelativePolarGrid.fromSnapshot`, поэтому canonical replay проверяет новый
  world-model path.

Проверки Этапа 3:

```text
dart analyze lib/safety/world ...
No issues found!

flutter test --no-pub \
  test/local_scene_model_test.dart \
  test/local_scene_snapshot_contract_test.dart \
  test/scene_fusion_policy_test.dart \
  test/spatial_replay_harness_test.dart \
  test/spatial_safety_first_slice_test.dart
35 passed

dart run tool/report_spatial_metrics.dart --rc \
  --output docs/_baseline_logs/spatial_replay_rc.json
passed: true; primary safety counters: 0/0/0
```

## Exit gate Этапа 3

| Gate | Evidence | Статус |
| --- | --- | --- |
| unknown never becomes free | default-sector and stale-expiry tests | pass |
| stale cells lose authority | traversability/risk decay plus TTL removal | pass |
| geometry survives YOLO absence | generic adapter test without semantic match | pass |
| source conflict raises unknown | reliable occupancy disagreement regression | pass |
| moving tracks connected | approach trend creates sector risk + moving snapshot | pass |
| traversability boundary prepared | typed evidence interface; geometry remains authoritative | pass |
| metric/relative separation | calibrated metric IDs + relative conversion rejection | pass |
| deterministic replay snapshots | repeated snapshot diagnostics + order-independent RC report | pass |

## Этап 4 — Corridor Planner и Guidance FSM

- Добавлен отдельный pure-Dart `CorridorEvaluator`. Он независимо формирует
  hard rejects и разложенный soft cost для clearance, observability, surface,
  unknown, heading change, temporal instability, collision/drop proximity и
  moving threat.
- `CorridorGenerator` всегда возвращает только три bounded candidates:
  `left`, `forward`, `right`. Hard reject нельзя компенсировать soft score.
- Positive-evidence gate требует достаточные observed width, clearance,
  traversability, confidence, низкий unknown и непустой source mask.
- `GuidanceStateMachine` подтверждает боковое направление только после трёх
  разных scene revisions. Повторная оценка одного revision не продвигает
  hysteresis.
- При смене направления применяются incumbent preference, минимальное улучшение
  soft cost и cooldown. Неподтверждённый challenger не вызывает left/right
  oscillation.
- Поддержаны `emergencyStop`, `holdingForScan`, `correctionPending`, `degraded`
  и `recovering` transitions. После `stopNow` пользователь должен остановиться,
  затем нужны две свежие положительные сцены для release.
- Реализованы все пять `SafetyActionKind`, но `adjustLeft`/`adjustRight` имеют
  typed delivery `shadow`. `FeedbackPolicy` подавляет такие actions даже при
  ошибочной передаче в feedback pipeline.
- Primary action остаётся только `stopNow`, `holdAndScan` или безмолвным
  `continueForward`. Relative evidence не создаёт метров или path-clear claims.
- Canonical corpus получил трёхкадровую сцену
  `stable-left-shadow-correction`: shadow direction отсутствует на первых двух
  revisions и появляется только на третьем. После добавления Stage 5 cooldown
  expectations corpus обновлён до annotation revision 3.

Проверки Этапа 4:

```text
dart analyze
No issues found!

flutter test --no-pub \
  test/corridor_planner_test.dart \
  test/guidance_state_machine_test.dart \
  test/spatial_safety_first_slice_test.dart \
  test/spatial_replay_harness_test.dart
35 passed

dart run tool/build_spatial_corpus.dart --check
Spatial corpus matches generator (19 files).

dart run tool/report_spatial_metrics.dart --rc \
  --output docs/_baseline_logs/spatial_replay_rc.json
passed: true; all six replay counters: 0

flutter test --no-pub
936 passed, 1 skipped, 0 failed
```

## Exit gate Этапа 4

| Gate | Evidence | Статус |
| --- | --- | --- |
| `unsafeGuidanceCount == 0` | strict replay RC report | pass |
| no guidance into unknown | positive-evidence gate + immediate invalidation + replay metric | pass |
| imminent risk always `stopNow` | occupancy/drop/moving-threat tests | pass |
| degraded while moving gives `stopNow` | unknown/health/stale regressions | pass |
| relative mode creates no metric claims | contract and multilingual copy regression | pass |
| direction hysteresis | three distinct revisions required; duplicate revision ignored | pass |
| anti-oscillation | challenger margin, confirmation streak and cooldown | pass |
| post-stop release is bounded | stationary gate + two fresh healthy revisions | pass |
| left/right remain shadow-only | typed delivery + feedback suppression | pass |

## Этап 5 — Alert Arbiter и feedback delivery

- `AlertArbiter` стал единой admission boundary для spatial `SafetyAction`,
  `CoreHealthSnapshot`, подтверждённых emergency событий и on-demand запросов.
  Сам arbiter не пересчитывает scene risk.
- P0 немедленно вытесняет active P1–P3 и очищает stale lower-priority pending.
  Независимый P0 с тем же ответом объединяет hazard identities; более срочный
  ответ вытесняет active P0 с сохранением предыдущего в bounded queue.
- Один hazard не накапливает одинаковые сообщения: обновление заменяет current
  или pending только при росте urgency, смене action/direction либо после
  cooldown. `lastCritical` доступен для явного пользовательского повтора.
- Потеря mobility sensing во время движения создаёт P0 `stopNow`; то же
  состояние у остановившегося пользователя остаётся P2 degraded feedback.
- `SpeechJob` имеет конечный TTL и `actionId`/`hazardId`. `TtsService` очищает
  expired jobs при enqueue и перед speech start, а critical queue остаётся
  ограниченной четырьмя jobs.
- `FeedbackDispatcher` фиксирует состояние TTS/haptics в
  `CoreHealthCoordinator`. При недоступном TTS P0 получает haptic fallback;
  cooldown haptic policy не объявляет исправный вибромотор недоступным.
- Haptic policy использует только `immediateStop`, `sensingDegraded` и
  `confirmation`, без кодирования left/right одним вибромотором. Есть
  duty-cycle budget, critical perceptual floor и timing-only fallback.
- RU/KK/EN copy tests запрещают metric/path-clear/«всё безопасно» claims для
  critical spatial сообщений.
- `AlertManager` получил узкий `admitSpatialAction` adapter над arbiter. Полное
  подключение planner -> dispatcher к camera runtime оставлено Этапу 7.
- Replay corpus обновлён до annotation revision 3: одинаковый active hazard в
  пределах cooldown теперь ожидаемо `suppressed`, а не искусственно `replaced`.

Проверки Этапа 5:

```text
dart analyze
No issues found!

flutter test \
  test/alert_arbiter_test.dart \
  test/haptic_policy_test.dart \
  test/feedback_policy_test.dart \
  test/tts_service_test.dart \
  test/spatial_safety_first_slice_test.dart
54 passed

dart run tool/build_spatial_corpus.dart --check
Spatial corpus matches generator (19 files).

dart run tool/report_spatial_metrics.dart --rc \
  --output docs/_baseline_logs/spatial_replay_rc.json
passed: true; all six replay counters: 0

flutter test
965 passed, 1 skipped, 0 failed
```

## Exit gate Этапа 5

| Gate | Evidence | Статус |
| --- | --- | --- |
| P0 прерывает P1–P3 | parameterized preemption regression | pass |
| expired action/job не произносится | arbiter, dispatcher и TTS TTL tests | pass |
| independent P0 не исчезает без причины | merge/preserve/drop trace tests | pass |
| повтор hazard bounded | replaceKey, escalation и cooldown tests | pass |
| TTS unavailable -> haptic + health | fake output/health transition test | pass software-only |
| trace имеет emit/suppress/replace/drop reason | bounded trace regression | pass |
| не более трёх haptic semantics | enum/cooldown/duty/fallback tests | pass software-only |
| RU/KK/EN critical copy contract | multilingual no-metric/no-safety-claim test | pass |

## Этап 7 — runtime integration

- `SpatialSafetyRuntime` подключён к accepted output
  `DepthPipelineController` и владеет цепочкой local scene -> planner ->
  arbiter.
- Runtime повторно отклоняет cross-session, repeated/out-of-order и expired
  observations. Новый camera session очищает scene, hysteresis и arbiter.
- Planner actions принудительно переводятся в `shadow` перед admission;
  feedback policy не допускает их до UI/TTS/haptics.
- Старый direct generic-obstacle alert loop удалён. YOLO-gap corridor hints
  остаются только Research path и не влияют на Core.
- Missing provider/result создаёт explicit unknown scene, а не пустую
  «свободную» сцену.
- Core не запускает независимую ARCore camera session. Hardware-capable tier
  временно использует aligned MiDaS/NCNN из Flutter frame; shared ARCore owner
  остаётся blocked.
- Полная детализация и gate matrix находятся в
  `docs/spatial-runtime-integration-report.md`.

## Непройденные и заблокированные gates

- `blender-egocentric-v1` и consent-controlled private camera corpus отсутствуют;
- общий RC остаётся заблокирован `A6`: noisy/random depth принимается как
  валидная plane fit; это нельзя считать здоровой геометрией;
- Android APK compilation проверена; physical-device runtime integration не
  проверялась;
- нет named-device latency, memory, battery или thermal evidence;
- нет shared ARCore ownership/alignment/parity evidence; independent session
  безопасно исключена из Core;
- нет TalkBack walkthrough и controlled walking Stages A-E;
- нет основания переводить generic/spatial guidance из `shadow` в `assistive`.

Stage 6 artifact contracts, reproducible exports и desktop synthetic smoke
описаны в `docs/model-bakeoff-report.md`. Candidate promotion остаётся
заблокирован recorded correctness corpus, depth parity, license и named-device
evidence. Runtime integration Этапа 7 не маскирует эти незакрытые
модельные/device gates и остаётся `shadow`.

## Этап 8 — sonar research contracts

- Удалён direct путь от одного sonar correlation peak к `AlertManager`.
  Sonar публикует только `SonarShadowObservation`; user alerts выключены.
- Native capability report проверяет near-ultrasound mic/speaker,
  unprocessed input, 48 kHz и известные input/output routes. Unknown fail
  closed.
- Versioned calibration admission требует восемь chirps, direct-path
  cancellation, multipath selection, акустическую валидацию и bounded
  repeatability MAD.
- Multi-chirp consensus требует пять последовательных samples, четыре usable,
  bounded spread/age и монотонные timestamps.
- Текущий single-peak Android DSP не удовлетворяет требованиям. Physical chirp
  output намеренно заблокирован до DSP и acoustic-safety evidence.
- TTS route interruption, headphones и active call останавливают research
  session и освобождают audio leases.

Software/build gates проходят, но Этап 8 не закрыт: нет synchronized sonar +
vision shadow corpus, named-device repeatability, direct-path/multipath DSP и
пользовательской проверки акустического уровня. Подробности —
`docs/sonar-research-report.md`.

# Одновременный обзор: первый desktop этап — 2026-10-04

На новом synthetic rig полное покрытие получается в одном состоянии сцены.
При CPU NCNN обработка имеет p50/p95 **68.774/97.060 ms**, но один из 18
static batches превысил срок T+100 ms и был отклонён. Гарантированная свежесть
и возможность получить такой packet обычным телефоном не установлены.
`promotionAllowed=false`, `runtimeWired=false`; всё остаётся shadow-only.

## Что проверено

Blender 5.2.2 LTS. Новые размеры комнаты, позиции и геометрия: три static пары
(свободная комната/коробка, высокий/низкий проход, ровный пол/ступень вниз),
два состояния анимированного объекта через 40 ms. Прежние 12 scan snapshots
не используются как новый обзор и не retimestamped.

У room-clear и floor-flat один и тот же geometry digest: это общий положительный
контроль двух paired families. Итого **5 уникальных static geometries** и
2 уникальные dynamic states, а не 8 независимых геометрических сцен.
Из трёх положительных controls уникальных геометрий **2**. Повторные trials и
этот общий контроль не увеличивают число независимых примеров.

12 отдельных optical camera identities с идеальным общим центром, 160×120
pixels/channel, lens 26 mm/sensor 36 mm, height 1.47 m. Grid выбрана до scoring
по intrinsics и прежнему объёму тела: yaw -37/0/37°, pitch
-60/-25.667/8.667/43°. Single control — центральный канал с pitch -25.667°.
Одна Blender scene.frame и один geometry digest для каждого batch;
разброс capture time **0 µs**. Это объявление состояния synthetic scene,
не измеренный capture/transport pipeline физического устройства.

Consumer получает visible first-return optical bounds и calibration. Mesh,
scoring labels и невидимые поверхности не поступают в consumer. Общий
reference frame запроса согласован с reference frame нового rig.
Projection, pixel indexes, subdivision, occupancy/conflict и coverage math
побуквенно совпадают с frozen indexed source; admission каналов отдельный.

| Geometry в момент T | Один канал | 12 synchronized channels |
| --- | ---: | ---: |
| Static passable с полным body/floor proof | 0/3 | **3/3** |
| Static hazards blocked | **3/3** | **3/3** |
| Incorrect clear | **0** | **0** |
| Dynamic batches conservatively unavailable | **2/2** | **2/2** |

Все три положительных batch observations имеют bodyObservedFraction=1 и
floorObservedFraction=1 в каждой секции. Один канал сохраняет unknown вместо
полного clearance. Динамика отклоняется даже в первом, геометрически свободном
состоянии: motion/error bound для момента доставки отсутствует.
Это не measured moving-hazard recognition.

## Timing и safety outcomes

Windows x64, Dart 3.11.1 AOT; пакеты предварительно прочитаны, распакованы и
проверены. Один untimed warmup, три измеряемых раунда с чередованием single/batch
порядка внутри scene. Ниже 18 static measurements на режим/implementation;
6 быстрых dynamic rejections исключены из timing percentiles. Возраст delivery
на 2 ms больше pipeline: каждый независимый replay anchored на capture T+2 ms,
Stopwatch движется. Capture timestamps неизменны, completion — реальный.

| Режим | Single p50/p95, ms | Batch p50/p95, ms | Batch maximum, ms |
| --- | ---: | ---: | ---: |
| Без NN | 7.543 / 11.594 | 59.271 / 76.427 | 113.974 |
| Непрерывный CPU NCNN | 10.011 / 14.709 | **68.774 / 97.060** | **113.802** |

Batch age at dispatch с NCNN: p50/p95 **70.774/99.060 ms**, maximum
**115.802 ms**. В обоих режимах **17/18** batches уложились в deadline,
один отклонён после compute. p95 ниже 100 ms при малой выборке не является
гарантией срока. Cross-mode запуск последовательный, CPU clocks/thermal/affinity
не контролировались. Прямое сравнение с прежним 391 ms некорректно: изменены
разрешение и сцены; этот этап не доказывает ускорение прежнего workload.

| Strict shadow scoring, на implementation/режим | Single | Batch |
| --- | ---: | ---: |
| Hazard decisions в пределах срока | 9/9 | **9/9** |
| Missed timely geometric hazard decisions | 0 | **0** |
| Fallback stops на static hazards | 0 | **0** |
| False stops на static passable trials | 9/9 | **1/9** |
| Admitted clear на static passable trials | 0/9 | **8/9** |
| Unsafe continue | **0** | **0** |
| Dynamic unavailable | 6/6 | **6/6** |

`continueForward`, `stopBlocked`, `stopUnavailable` — scoring mapping harness,
без active planner, scene mutation, TTS/haptics. Deadline не повышался.
Расчёт включает source construction, один observation, strict evaluator,
age gate и single-use release. Physical capture, packet transport, decode/hash
loading, alert arbitration/audio/haptics и Android execution исключены.
Preload занимает 1.679 s без NN / 1.701 s перед NN режимом и измерен отдельно.

NCNN выполнил **11 measured inferences** после 10 warmup calls. Каждый raw
float32 output побайтово совпал с pinned output. По кругу использованы три
прежних RGB camera-scale-motion frames, не новые 96 rig images. Нейросеть —
реальная конкурирующая нагрузка, её relative depth не является metric input.
Model accuracy нового корпуса и on-phone inference здесь не установлены.

## Исправления и воспроизводимость

Первый optical export оставил 15 пикселей с exact height interval, но без
согласованного first-Z. Consumer отклонил такие envelopes; их короткие времена
не считаются успешной обработкой. Отдельный v2 export заново вычислил все четыре
связанные границы этих 15 пикселей через exact visible first-return partition.
При неполном footprint весь bundle остаётся unknown. RGB/range/free-Z/validity,
scene geometry, pose и capture time сохранены побайтово.

Затем fixed-clock evaluation выявила неверную привязку reference frame запроса
к старому corpus. Исправлена привязка harness к новому synthetic rig frame;
порог и геометрия не менялись. Первые rejected receipts и точные source
snapshots сохранены. Официальные timing/geometry receipts — v3.

Независимая Blender ray_cast проверка: **12 939 sampled first-return witnesses**
на новых каналах, включая центр и дробные позиции пикселей. Это sampled optical
validation вместе с frozen polygon contracts, не доказательство field accuracy.

**45/45 focused Flutter tests** проходят: 22 новых rig + 23 прежних age-gate.
Проверяются missing/duplicate/reordered/foreign channels, 1 µs skew, frame/session,
model/transform/reference, metric units, valid wrong rotation/optical centre/focal,
failed provider, broken envelopes, unknown pixels, dynamic rejection, expiry,
repeated observation и сохранение отказа frozen sequential source.
Analyzer и прежний scan-processing integrity contract проходят; **99** предыдущих
source freezes сохранены. Полный Flutter-прогон завершён: **1636 passed,
1 skipped**, общий `dart analyze` без замечаний; 7 frozen exact-polygon unit tests
также проходят. Новый integrity stage добавлен в Core; новый полный Core RC не запускался.
Прежняя 58/58 квитанция остаётся неизменной, её SHA256
`c1e1dfcfc789f9daf426a1290ecef00f1219713ce645325cbb190b95ec8bf081`.

Артефакты:

- `test/fixtures/spatial_safety/blender-synchronized-rig-v1/manifest.json`: original export.
- `test/fixtures/spatial_safety/blender-synchronized-rig-v2/manifest.json`: coherent bundle.
- `docs/_baseline_logs/blender_synchronized_rig_elapsed_v3.json`: AOT без NN.
- `docs/_baseline_logs/blender_synchronized_rig_elapsed-nn_v3.json`: AOT с NCNN.
- `docs/_baseline_logs/blender_synchronized_rig_contract_v3.json`: write-once integrity.
- `docs/_baseline_logs/blender_synchronized_rig_validation_v3.json`: test/analysis evidence.
- `scratch/synchronized-rig-focused-v3.log`: focused tests.
- `scratch/synchronized-rig-full-flutter-v3.log`: полный Flutter-прогон.

## Практический вывод

На идеальном synthetic rig одновременность устраняет прежний 2.2 s capture span;
эта небольшая unseen geometry выборка даёт полное покрытие. Compute deadline
достижим в части измерений, но tail latency ещё вызывает отказ.
Идеальные co-located 12-channel optics с такими calibrated metric envelopes не
установлены на обычном телефоне. Следующий практический gate — проверить
доступный Android camera/depth sensing contract и отдельно processing replay
на названном устройстве. Только затем можно оценивать переносимость метода;
этот этап не разрешает assistive promotion или controlled walking.

Протокол: `docs/blender-synchronized-rig-protocol-2026-10-04.md` и bundle supplement.
Команды: `tool/verify_core.md`. Android build/runtime и controlled walking не запускались.

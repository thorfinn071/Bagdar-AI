# Обработка обзора и свежесть под NCNN — 2026-10-04

Ограниченный desktop этап выполнен: добавлены отдельный indexed producer,
реальные elapsed measurements и single-use age gate для synthetic shadow.
Полное свежее покрытие и 100 ms compute deadline пока **не достигнуты**.
Обычная камера и активные команды приложения не подключены к этому producer.

## Результат текущего сравнения

Windows x64, Dart 3.11.1 AOT. Одно untimed geometry/warmup traversal и три
измеряемых раунда на тех же 12 frozen snapshots. В каждом snapshot порядок
двух implementations чередуется между раундами. Пакеты предварительно
прочитаны, распакованы и проверены. По 36 pipeline measurements на implementation
в каждом режиме; сохранённый предыдущий Flutter/JIT timer здесь не сравнивается.

| Режим и implementation | p50 pipeline, мс | p95 pipeline, мс |
| --- | ---: | ---: |
| Без NN, frozen complete-envelope | 685,260 | 1122,859 |
| Без NN, indexed envelope | 325,081 | 741,322 |
| Непрерывный CPU NCNN, frozen | 878,740 | 1504,770 |
| Непрерывный CPU NCNN, indexed | **391,170** | **640,124** |

Под текущей neural workload медиана снизилась примерно на **55,5%**, p95 —
на **57,5%**. Числа характеризуют этот Windows workload, не Android. Без-NN
и NN режимы выполнены последовательно, поэтому разница между ними не изолирует
эффект только нейросети от состояния CPU; сравнение implementations ведётся
внутри каждого режима на одинаковых входах с чередованием порядка. Даже без NN
ни один из 36 indexed samples не уложился в 100 ms. CPU affinity, clocks и
thermal conditions не контролировались; результаты не являются гарантией latency.

Pipeline здесь включает construction (validation/index/coverage), один
observation, strict evaluator и shadow dispatch guard. Загрузка пакетов
отдельна: 9660 ms без NN, 9904 ms перед NN режимом. Physical capture,
transport, active planner, audio/haptics и phone delivery не измеряются.
Neural inference выполняется непрерывно параллельно в отдельном subprocess,
а не добавляется как выдуманная задержка или источник metric depth.

## Что ускорено

Контроль сначала вычислял прежний floor proof в body source, после чего wrapper
заменял его height proof и повторял height calculation при каждом observation.
Новый отдельный producer сразу вычисляет окончательные body/floor sections
один раз. Он сохраняет occupancy и проверку temporal conflicts.

Проверки whole-pixel predicates индексированы: точная integer prefix sum
отклоняет прямоугольник с любым неизвестным/невалидным пикселем; minimum free-Z
использует полностью включённые tiles и явно проверяет boundary pixels.
Ray norms, envelope admission и pixel indexing объединены в один проход.
Projection сохраняет порядок scalar arithmetic, уменьшая временные allocations.
Thresholds, размеры объёма, subdivision, first-return bounds и freshness TTL
не менялись. Старые source files и write-once receipts сохранены.

В indexed samples под NCNN остаточная стоимость распределилась так:

| Внутренняя стадия | p50, мс | p95, мс |
| --- | ---: | ---: |
| Metadata/scan identity admission | 0,022 | 0,028 |
| Envelope admission и pixel indexes, 12 × 320 × 240 pixels | 218,693 | 250,090 |
| Occupancy/conflict и whole-volume coverage | 177,818 | 395,863 |

Это отдельные распределения стадий; их процентили не суммируются в pipeline
percentile. Pixel traversal и coverage остаются compute bottlenecks. До выбора
нового sensing contract дальнейшее ускорение этих 12 старых видов не решает
получение актуального полного объёма.

## Геометрия и нейросеть

Все observation fields нового producer совпали с frozen source на **12/12**
snapshots. Diagnostic geometry сохранила **6/6** passable measuredClear,
**6/6** blocked hazards, **0** incorrect clear. Negative observation comparisons
проверяют отсутствующие и испорченные данные, units/pose/session, order, incomplete
scans и отверстия на tile/image boundaries. Repeated observation не пересчитывает
coverage и не обновляет capture time.

One-thread CPU MiDaS NCNN выполнил **293 measured inferences**, после отдельного
warmup из 10 calls. Каждый raw float32 output побайтово совпал с pinned output.
Использовались по кругу три прежних camera-scale-motion RGB frames, с проверкой
их hash/decoded pixels, модели и expected output. Эти RGB не являются новыми
12 ракурсами scan. Нейросеть создаёт реальную конкурирующую нагрузку CPU;
её relative inverse depth не используется для metric body/floor proof.
Это проверка timing под NN, не новое измерение model accuracy.

## Freshness остаётся отдельным blocker

Исходные captures разделены 200 ms, oldest→latest = **2200 ms**. Реальные часы
движутся во время обработки; capturedAt каждого пакета сохранён. Completion
timestamp отражает завершение observation. Каждый timed sample — независимое
offline воспроизведение, anchored на исходном последнем capture+2 ms.

Для indexed producer под NCNN:

- Возраст oldest evidence перед shadow dispatch: p50/p95 **2593,171/2842,124 ms**.
- Возраст последнего capture перед dispatch: **393,171/642,124 ms**.
- Strict 100 ms отклонил **36/36** full scans; ни один observation/decision
  не вышел из admission gate. Обработка уже stale scan разрешена только raw
  diagnostic benchmark для измерения. Admission gate отклоняет scan до вызова
  compute.

В 100 ms окне остаётся **один** исходный ракурс. Во всех **6/6** passable
snapshots его независимое geometry evaluation остаётся unavailable. Значит,
мгновенный consumer тоже не получает достаточного свежего body/floor proof.
Кеш вычислений не может обновлять возраст старых наблюдений или стирать hazard.

| Strict shadow outcomes, за три раунда, каждый implementation | Результат |
| --- | ---: |
| Hazard snapshots без своевременного geometric blocked decision | 18/18 |
| Fail-closed fallback stops на hazards | 18/18 |
| False stops на passable snapshots | 18/18 |
| Unsafe continue | **0** |

`stopUnavailable` в этой таблице — явное scoring mapping harness, без вызова
normal runtime planner/TTS/haptics. Геометрические пропуски по времени и
защитные fallback stops учитываются отдельно; остановка из-за unknown не
выдаётся за своевременное распознавание опасности. Moving false stops и динамика
в этом этапе не переизмерялись.

## Проверки и артефакты

**37/37 focused Flutter tests** прошли после окончательного изменения producer.
Age tests включают expiry before/after compute и перед dispatch, точную 100 ms
границу, rollback, failure, session change/backgrounding и повторный release.
Contract проверяет оба measured reports, их arithmetic, все **99** предшествующих
frozen sources, модели, исходный Core receipt и новые source hashes.

- `docs/_baseline_logs/blender_scan_processing_elapsed_v1.json` — current AOT без NN.
- `docs/_baseline_logs/blender_scan_processing_elapsed-nn_v1.json` — AOT с непрерывным NCNN.
- `docs/_baseline_logs/blender_scan_processing_contract_v1.json` — write-once admission.
- `docs/_baseline_logs/blender_scan_processing_core_rc_v1.json` — write-once квитанция Core.

Полный Flutter-прогон: **1614 passed, 1 skipped**; общий analyzer без замечаний.
Полный `tool/verify_core.ps1 -Rc` завершился успешно: **58/58 обязательных stages**,
включая новый integrity stage. Write-once Core receipt имеет SHA256
`c1e1dfcfc789f9daf426a1290ecef00f1219713ce645325cbb190b95ec8bf081`.
Предыдущая квитанция Core 57/57 сохранена. Android replay, camera calibration,
unseen/dynamic evaluation и controlled walking не выполнялись.
`runtimeWired=false`, `promotionAllowed=false`.

## Следующий ограниченный шаг

Выбранное направление следующего desktop эксперимента — **одновременный
multi-view packet с явно объявленным синтетическим sensing rig**. Он позволяет
проверить предел полного покрытия, когда 2.2 s сбор действительно устранён.
Это исследовательский вариант sensing, не заявка на поддержку такой съёмки
обычным телефоном и не выбор готового устройства.

Контракт следующего этапа:

1. Новые unseen сцены и новые Blender renders: все оптические каналы одного
   batch видят одно состояние в момент T. Прежние 12 packets не retimestamped
   и не используются как новое свежее измерение.
2. Для начала строго нулевой capture skew, отдельные camera/channel identities,
   общий калиброванный reference frame и объявленные extrinsics. Ненулевой skew,
   missing channel, неправильные pose/session/time и отставание batch — negative
   cases; допуск ненулевого skew потребует отдельного motion contract.
3. Source получает только новые visible first-return bounds/height/validity,
   без mesh, annotations и скрытых поверхностей. Body/floor coverage и freshness
   считаются отдельно; новый rig contract не ослабляет старые producers/gates.
4. Сравнение одного канала и synchronized batch: body/floor completeness,
   missed hazards, false stops, unsafe continues и actual pipeline latency
   с/без CPU NCNN. Delivery всё ещё shadow-only, срок T+100 ms не повышается.
5. Динамические сцены проверяют conservative rejection: одновременность captures
   сама по себе не доказывает clearance через время после T. Без отдельно
   подтверждённого motion/error bound они не дают разрешения идти.

Этот выбор даёт проверяемый верхний предел sensing и отдельный compute gate.
Даже положительный результат rig не установит возможность получить такой
packet на телефоне. Android processing replay и измерение доступного phone
sensing остаются отдельными gates, затем calibration и controlled walking.

Воспроизведение и exit gates: [протокол](blender-scan-processing-protocol-2026-10-04.md),
команды — в `tool/verify_core.md`. Прежний
[геометрический отчёт](blender-scan-coverage-evaluation-2026-10-04.md) сохранён.

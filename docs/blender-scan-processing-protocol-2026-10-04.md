# Свежесть и стоимость обработки обзора — протокол v1

## Ограниченный этап

Продолжение frozen complete-envelope v1. Проверяются те же 12 неподвижных
snapshots, без обучения или подгонки на scoring labels. Контроль — неизменённый
`CameraHeightEnvelopePassageSource`; эксперимент — отдельный
`CameraIndexedHeightEnvelopePassageSource`. Прежние sources, exports, contracts
и write-once квитанции не перезаписываются.

Новый producer вычисляет coverage один раз на immutable frames/request.
Пиксельные условия совпадают с контролем: first-Z для body; исходные axis bounds
и независимые height intervals для floor. Индекс rejected pixels проверяет
каждый пиксель прямоугольника через точную целочисленную сумму. Минимум free-Z
использует только целиком включённые tiles; края проверяются по отдельным
пикселям. Подразделение объёма, whole-pixel bounds, occupied returns и temporal
conflict остаются консервативными. Ни averaging, ни filling не дают proof.

## Отдельные часы и измерения

1. Пакеты читаются, распаковываются и проверяются до таймера; стоимость загрузки
   фиксируется отдельно. Это preloaded desktop experiment, не camera-to-command.
2. Geometry warmup сравнивает все observation fields двух producers побуквенно;
   diagnostic 3 s используется только для геометрии и не даёт admission.
3. Один AOT sample — source construction, один observation, strict evaluator
   и single-use shadow dispatch guard. Stopwatch реально движется. Completion
   timestamp отражает время получения observation; capture timestamps сохранены.
4. Возраст oldest evidence, возраст последнего кадра и вычислительная задержка
   публикуются отдельно. Каждый sample — независимое offline воспроизведение,
   anchored на последнем исходном capture, а не повторная съёмка или обновление
   capture time. Исходный capture span равен 2 200 000 мкс.
5. Production-like age gate отдельно отклоняет stale scan до compute. Raw
   diagnostic computation выполняется только для измерения и сравнения, без
   admission, active planner, scene mutation, TTS или haptics.

Один untimed warmup traversal и три измеряемых раунда. Порядок implementations
чередуется между раундами, в каждой паре обрабатывается один и тот же snapshot.
Режимы: без NN и с непрерывным one-thread CPU MiDaS NCNN. Независимый subprocess
подтверждает start до samples и stop после них, вычисляет по кругу три frozen
RGB camera-scale-motion frames, проверяет каждый raw float32 output побайтово.
Это отдельная competing workload, не inference новых 12 ракурсов. Его relative
depth не поступает в metric source и не превращается в метры. Neural warmup,
process startup/shutdown и output validation не входят в source timer; реальная
CPU competition во время samples входит. Режимы запускаются последовательно.

## Admission и негативные случаи

`CameraScanAgeGate` использует неизменяемые 100 000 мкс для самого старого
contributing capture; проверяет clock domain, identity, session, completion,
single-use dispatch, rollback и invalidation. Compute errors/missing observations,
unverified/relative data, mismatch и unknown coverage не дают clear authority.
Admission этой ветки остаётся synthetic shadow-only и не подключён к телефону.

Тесты: полнота/точное совпадение 12 scenes; missing depth/axis-Z/height/first-Z;
ошибочный first-Z; units/pose/session; неполные/reordered/empty scans;
tile/image-edge holes; repeated observation; срок до/после compute и перед
dispatch; 100 ms boundary; clocks; exception; backgrounding и устаревшие handles.

Отдельный coverage contrast оставляет только исходные виды, которым не более
100 ms относительно последнего capture+2 ms. При интервале 200 ms остаётся
один вид. Даже если processing станет мгновенным, его incomplete coverage
не может подменяться старым накопленным body/floor proof.

## Метрики и exit gates

- Geometry: 6/6 passable clear, 6/6 hazards blocked, 0 incorrect clears;
  каждый observation field совпадает с frozen контролем.
- Strict: весь полный обзор stale, 12/12 snapshots обязаны быть rejected;
  нет возвращённых observations/decisions и 0 unsafe continues.
- Отдельно: missed timely geometric hazard decisions; fail-closed fallback
  stops на hazards; false stops на passable; p50/p95 source/pipeline и возрастов.
  `stopUnavailable` — только явное отображение результата в этом harness;
  реальные runtime planner/audio commands здесь не вызываются.
- Performance улучшение сравнивается внутри одного текущего AOT прогона;
  прежний Flutter/JIT diagnostic timer с тремя observations несопоставим.
- Полный Core RC, все прежние freezes и source identities сохранены.

Достижение compute deadline и свежего полного покрытия — независимые gates.
Ни ускорение, ни программные проверки не снимают capture gate 2.2 s.
После desktop нужен Android replay, затем независимые calibration/visibility,
unseen/dynamic scenes и controlled walking. `runtimeWired=false`,
`promotionAllowed=false`, phone/model correctness не установлены.

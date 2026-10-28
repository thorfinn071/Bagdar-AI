# Ускорение проверки объёма: 2026-10-11

Новый opt-in producer сохранил все поля прежних измерений и сократил время
проверки геометрии. На десяти ракурсах медиана всего pipeline улучшилась лишь
с 282,477 до 268,090 мс: копирование пикселей частично съело выигрыш.
**Срок не достигнут: 144/144 результатов просрочены.** Ложные STOP обычного
телефона остаются неисправленными; новая реализация остаётся synthetic shadow.

## Изменения

[CameraScalarHeightEnvelopePassageSource](../lib/safety/perception/camera_scalar_height_envelope_passage_source.dart)
создан отдельно от замороженного indexed producer. Он вычисляет pure camera-ray
geometry один раз на intrinsics tuple внутри одной конструкции, читает пиксели
через собственные typed copies, строит exact rejected-pixel prefix sums в общем
цикле и использует scalar projection/occupancy вместо временных списков.
Геометрия лучей не содержит измеренных глубин или timestamps. Наблюдённые
пиксели не переиспользуются между пакетами; новое время не обновляет старый capture.

Сохранены math.pow и порядок arithmetic, все predicates whole-pixel bounds,
floor support, occupancy/conflicts, subdivision, metric/alignment gates,
исходный oldest capture, 100000 мкс TTL, STOP/history и shadow-only delivery.
Обычный camera runtime новый producer не вызывает. Предыдущие источники,
данные, модели и receipts не изменялись.

## Совпадение и отрицательные случаи

До scoring заморожены 1370 файлов вместе с предыдущей цепочкой.
Новая матрица сравнила каждый observation field на 12 прежних статических
сценах в четырёх вариантах: все 12, выбранные 10, последний один и последние
шесть кадров. **48/48 пар совпали**, повтор receipt совпал byte-for-byte.
Независимый audit также сверил sections и статусы полных/минимальных обзоров
с предыдущим frozen experiment. При полной геометрии сохранились 6/6 clear
passable и 6/6 blocked hazards; single/partial не получили нового права clear.

Прошли 17 negative controls: single view, отсутствие upper/height/first-return,
depth holes, tile/image boundary holes, invalid first-return, relative units,
pose/origin, session, отсутствие upward views, reorder/empty, wrong model,
reflected pose, inverted heights и infinite first-return. Дополнительно
прошли 100 seeded трёхкадровых пакетов с разными intrinsics, NaN ranges,
invalid pixels и unknown bounds. Это проверки software arithmetic/отказов,
без доказательства точности физической камеры.

Финальный последовательный Flutter запуск: **56 tests pass** — 19 новых,
14 прежних indexed/frozen и 23 age-gate. Static analysis трёх новых Dart-файлов
без замечаний. Полный RC/Android runtime для этого opt-in этапа не запускались.

## Фактическое время на компьютере

Windows Dart AOT, preloaded known packets, один untimed warmup на каждую
implementation/input, три раунда с чередованием вариантов внутри сцены.
Геометрия лучей и typed copies строятся внутри каждого измеряемого source.
Отдельные counterfactual capture offsets задают 120 кадров/с и start lag 2 мс;
compute/evaluator/gate используют advancing Stopwatch. Это не реальные capture
timestamps, frame rate, temporal registration или скорость поворота телефона.
Физический захват, загрузка/распаковка fixture, transport, inference и delivery
не входят в pipeline. Параллельные тесты/NN нами не запускались; CPU/thermal
conditions не контролировались. Один запуск не устанавливает гарантию latency.

| Набор / producer | Samples | p50 pipeline, мс | p95 pipeline, мс |
|---|---:|---:|---:|
| 12 / indexed | 36 | 370,956 | 740,612 |
| 12 / scalar | 36 | 306,859 | 378,931 |
| 10 / indexed | 36 | 282,477 | 596,922 |
| 10 / scalar | 36 | 268,090 | 370,591 |

У десяти ракурсов p50 уменьшился примерно на 5,1%, p95 на 37,9% в этом workload.
Строгий age gate отклонил **все 144 samples** как expiredAfterCompute;
observation/decision не выданы. Запас после условного сбора десяти кадров —
23 мс, то есть новая медиана всё ещё превышает его примерно в 11,7 раза.

| Стадия десяти ракурсов | indexed p50, мс | scalar p50, мс |
|---|---:|---:|
| Pixel index/envelope validation | 171,820 | 197,972 |
| Occupancy/whole-volume coverage | 110,402 | 62,202 |

Scalar arithmetic ускорила coverage примерно на 43,7%, но pixel stage стала
примерно на 15,2% медленнее. Typed copies и текущая публикация пикселей через
generic immutable lists требуют отдельного измерения. Следующий обоснованный
шаг — проверить передачу immutable typed buffers с учётом времени упаковки,
allocation и GC, сохранив исходные значения/форму/ownership. Убирать время
упаковки из бюджета и объявлять это ускорением всего pipeline нельзя.

## Статус основной цели

Ordinary-camera false-stop reduction не установлено. Старые 14/14 и 34/34
ложных STOP не имеют нового успешного runtime-прогона. MiDaS остаётся
relative depth; реальных whole-pixel metric bounds и motion/current-scene
proof пока нет. Пользователь подтвердил, что Android-телефон сейчас недоступен.
Оптимизация вычислений не устраняет физическую неполноту одного ракурса.
Сохранены promotionAllowed=false, ordinaryCameraWired=false,
falseStopReductionEstablished=false и canAuthorizeMovement=false.

Все receipts: `scratch/scalar-scan-processing-2026-10-11/`.
[Протокол](scalar-scan-processing-protocol-2026-10-11.md).

# Одновременный синтетический обзор — протокол v1

Первый ограниченный шаг после scan-processing v1: новый корпус, новый контракт
каналов и сравнение полной геометрии с одним каналом. Это идеальный synthetic
optical rig, не зарегистрированный phone provider. Все результаты shadow-only;
`promotionAllowed=false`, `runtimeWired=false`. Прежние файлы/receipts неизменны.

## Вход и независимость

- Новые сцены с seed 202610041: три static пары (комната/коробка,
  высокий/низкий проход, ровный пол/ступень вниз) и два состояния одной
  анимированной сцены (объект сбоку/внутри прохода спустя 40 ms).
- Одно состояние Blender в момент T для всех каналов batch. Каждый канал —
  отдельная камера с собственной identity и проверяемыми extrinsics/intrinsics.
  Идеальные optical centres совпадают: физическая реализация не установлена.
  Последовательное выполнение renderer не моделирует последовательную съёмку;
  scene.frame и geometry digest не меняются между каналами одного batch.
- 160×120 pixels/channel, lens 26 mm/sensor 36 mm, optical centre height 1.47 m.
  Это новое разрешение с тем же углом обзора, не сравнение скорости со старым
  320×240 benchmark. Whole-pixel bounds остаются обязательными.
- Grid выбирается неизменённым label-free scan_view_selection.py по объёму
  0.9 m шириной, 1.85 m высотой, 0.2–3.5 m впереди. Single control — канал
  с минимальным yaw²+(pitch+12)², выбранный до обработки сцен.
- Consumer получает только optical range, first-Z, surface-Z, height bounds,
  validity и проверенную camera calibration. Mesh и hazard labels остаются у
  generator/scoring. MiDaS relative depth не становится metric evidence.
- Renderer использует frozen complete bounds плюс frozen exact floor-height
  supplement. Независимые Blender ray_cast witnesses проверяют first returns
  и height intervals в новых сценах. Все assets/source identities SHA256-bound.

## Admission

Новый отдельный source сохраняет frozen indexed coverage math. Он требует
нулевого skew, один batch/frame/session, ровно заявленные каналы без повторов,
совпадение каждого optical transform/pose/intrinsics и calibrated common frame.
Missing/foreign/duplicate channel, skew, неверные pose/session/frame/hash/units,
invalid pixels и несовместимые optical bounds не дают measuredClear.

Static completeness — геометрическое доказательство только в T при явно
заявленной stationary synthetic scene. Динамические batches консервативно
unavailable: нет motion/error bound для clearance в момент доставки.
Ненулевой skew также unavailable. Stationarity здесь — свойство synthetic
fixture, не оценка нейросети и не доказательство неподвижности реального мира.

## Измерение и выход

Preload/hash/decompression/rendering отдельно от AOT source+observation+strict
evaluator+single-use shadow age gate. Capture times не обновляются. Stopwatch
движется: независимый replay anchored на T+2 ms; completion отражает реальное
завершение вычислений. Возраст oldest=latest при zero skew. Deadline T+100 ms
не изменяется. Нет active planner/audio/haptics/phone transport.

Один untimed warmup, три раунда single/batch с чередованием порядка, без NN и
с непрерывной pinned one-thread CPU MiDaS NCNN из предыдущего стенда. NN —
конкурирующая нагрузка на прежних трёх RGB, не inference нового rig corpus.
Cross-mode timing не изолирует CPU thermal/clocks. Отдельные метрики:
static geometry/coverage, geometric hazard misses, fail-closed fallback,
false stops, unsafe continues, pipeline p50/p95 и strict admission.

Exit: все integrity/identity/freshness/motion negatives проходят; новые
static outcomes и timing честно записаны независимо от успеха 100 ms; frozen
scan-processing contract проверен. Phone sensing, Android runtime, real model
accuracy и controlled walking остаются отдельными непроверенными gates.

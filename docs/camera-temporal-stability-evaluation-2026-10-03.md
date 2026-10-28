# Стабильность RANSAC и временные камерные сцены — 2026-10-03

Подтверждённая ошибка исправлена в отдельной shadow-обёртке: один и тот же вход
больше не создаёт приближение из-за изменяющейся случайной выборки RANSAC.
Известная регрессия `test-association-wide-08`: false stop **1/1 → 0/1**.
На новом независимом test — **0/4** ложных остановок и **8/8** своевременных
опасных остановок, zero unsafe continue и необоснованных `measuredClear`.
У предыдущей камерной ветки на новом test также **0/4**, поэтому дополнительный
выигрыш относительно неё этим holdout **не установлен**. Относительно NCNN
контроля false stops меньше: 4/4 → 0/4. `promotionAllowed=false`.

## Причина и исправление

На неизменной relative-depth карте известной регрессии ground confidence
менялся 0,7031 → 0,7383, ground-disagreement 0 → 3692 пикселя. Broad-surface
компонент вырос с **13 561 до 17 268** пикселей, proximity **0,931734 → 1,0**.
Persistent tracker получил `approachTrend=0,068266`, хотя RGB и глубина не
менялись. Диагностическая трасса — `scratch/repeated-rgb-trace.json`.

Legacy detector сохраняет три random streams для wide/forward/opening ground.
Его `_groundResidualEma` только записывается, но не участвует в вычислениях.
Новый `FrameStableGenericObstacleDetector` создаёт исходный segmentation
engine для каждого текущего входа: тот же seed 7, те же budgets, sample bands,
нормализация и пороги. Никакие старые predictions или masks не кэшируются.
Первый результат совпадает с legacy. После другого кадра тот же вход вновь
даёт те же компоненты. Изменившаяся глубина вычисляется заново.

**Tracker, physical evidence ledger и planner сохраняют историю** на всю
последовательность. Обёртка не удаляет motion risk, не сбрасывает stop state,
не читает ground truth, hashes RGB, labels или объявленное движение объектов.
Семантический риск, приближение, unknown, истечение и ограничения стоя сохраняют
прежний приоритет. В контролируемом increasing-proximity тесте один track
сохранил три hits, confirmation, все timestamps и положительный trend 0,20.

Реализация применяется явно только новым replay. Обычная camera pipeline
использует прежний detector. Все commands — shadow, active arbiter пуст.
Прежние core-файлы, `camera_track_development_freeze.json`, корпусы и отчёты
не переписывались: их functional/freeze checks продолжают выполняться.

## Новый независимый корпус

[Протокол](camera-temporal-stability-protocol-2026-10-03.md) и generator
объявлены до реализации и первого test. `camera-temporal-passage-v1` содержит
**18 полных геометрических сцен, 192 RGB/depth кадра**: 6 validation, 12 test.
Development дал 3/3 безопасных продолжения после осмотра и 3/3 опасных остановки.
После development и чистого анализатора сохранён отдельный write-once
`camera_temporal_development_freeze.json`; первый holdout запущен после него.
После просмотра test зафиксированная реализация, geometry, fit и функциональная
разметка не менялись. Posthoc plots/timing/integrity tools не влияют на решения.

Статичные сцены: широкий проход, частично закрытая дверь с достаточным
остатком, наружная стойка; опасные перекладина, внутренняя и субпиксельная
стойки. По 13 настоящих renders: anchor, 9 направлений, возврат через 2 с и
две проверки с интервалом 200 мс. MiDaS выполнен на всех RGB; stateful решения
используют четыре anchor кадра, остальные направления — только метрический
producer. Pixel RGB и depth повторных anchors совпадают; PNG служебные
Date/RenderTime и gzip filenames могут отличаться. Это не NN-трекинг осмотра.
Дополнительная read-only проверка decoded RGB и nearest-256 входов исключила
влияние PNG metadata на доказательство новизны: 18/18 anchor отличаются от
прежних корпусов; dynamic frames различаются по настоящим pixels и model input.
Receipt — `camera_temporal_rgb_identity.json`, checker `verify_temporal_rgb_identity.py`.

Временные сцены: приближение и пересечение коробкой пути в validation/test;
удаление коробки, вращение и перенос камеры в test. По 7 разных RGB/depth
кадров через 200 мс. Каждый RGB имеет собственный NCNN output. Producer
получает **только текущую** visible-depth карту, с обычным возрастом 400 мс;
сканирование и накопление прежних взглядов здесь запрещены. Физические
опасности и sufficient-observation labels передаются только scorer после
producer → contract → runtime → planner. Потерянные/закрытые участки unknown.

Проекция вычислена `calc_matrix_camera`, metric bounds относятся к полному
pixel footprint первой видимой поверхности. Никаких meshes, object masks или
скрытых поверхностей consumer не получает. Запрос прежний: 0,9 × 1,8 м,
0,2–3,5 м, floor rise/drop ≤ 50 мм. Visible floor не доказывает headroom.

Веса `midas_small.ncnn.param/.bin`, CPU one thread и preprocessing
`rgb01-chw-256-nearest-stretch-no-crop-v1` сохранены. MiDaS outputs — relative
proximity, **не метры**. Исходная диагностическая калибровка перенесена без
fitting и остаётся rejected/unavailable. Новый корпус не участвовал в fit.

## Test-результат и оставшийся барьер

| 12 test-сцен, одинаковые RGB по режимам | False stops, достаточный обзор | Своевременные опасные остановки | Поздние | Пропущенные | Unsafe continue | Unjustified clear |
|---|---:|---:|---:|---:|---:|---:|
| NCNN контроль | 4/4 | 7/8 | 1 | 0 | 0 | 0 |
| Прежняя привязка, stateful RANSAC | 0/4 | 8/8 | 0 | 0 | 0 | 0 |
| Та же привязка, повторяемый RANSAC | **0/4** | **8/8** | **0** | **0** | **0** | **0** |

Producer даёт 4/4 `measuredClear` на достаточно наблюдаемых static test,
runtime применяет 4/4. На первом одиночном взгляде новая ветка останавливается
на 12/12 сценах. В конце на восьми недостаточно наблюдаемых/опасных сценах —
8/8 stopNow. Во временном crossing первые три взгляда — unavailable;
действия stopNow, holdAndScan, holdAndScan. При входе коробки в тело на 0,6 с
producer выдаёт blocked, planner stopNow. Измеренный timeline не подменяется
ожидаемыми labels. Hold во время уже исполненной остановки записан отдельно.

NCNN crossing даёт continueForward до физического onset, затем holdAndScan;
явный stopNow появляется только в 1,202 с, при deadline 0,9 с. Unsafe continue
после onset здесь ноль, но поздняя явная остановка указана отдельно; hold не
выдан за стоп с несуществующей подтверждённой историей.

Во всех static test исправленного detector approach trend равен нулю.
В реальном synthetic approaching test максимум **0,6364**: признак не снят.
Но на crossing test trend **0**, на receding максимум **+0,0559**, при повороте
камеры **+0,1966**, при переносе **+0,5666**. Относительная per-frame proximity
и изменяющиеся support/matches не являются оценкой физической скорости.
Остановки этих сцен обеспечены видимым blocked или unknown, а не доказанной
точностью динамического tracker. Латеральное движение и ego-motion ещё не
компенсируются; нельзя трактовать отсутствие trend как неподвижность.

Следующий препятствующий слой — **временное восстановление движения объектов
отдельно от движения камеры**. Для следующего bounded этапа нужны интервалы
движения по видимым метрическим границам и согласованному pose, отрицательные
случаи соответствия компонентов и истечение. Relative MiDaS не переводить в
м/с, не снимать неизвестность и moving priority ради снижения остановок.

## Время, воспроизводимость и проверка

Functional capture-to-decision offset — заданные 2000 мкс; deadline 300 мс
считается отдельно от desktop wall clock. Время static осмотра — **2 с**.
Фактические времена preprocessing, inference, normalization, detector/tracker,
producer и runtime сохранены отдельно. Сумма стадий — desktop estimate по
совпадающим frame IDs из отдельных serial measurements, не device latency.
Исключены loading depth/NN fixtures, render, capture/transport/scheduling,
posthoc diagnostics и получение осмотра. RGB preprocessing включает PNG decode,
проверку hash и RGB01 nearest stretch. Normalization — warmed Dart JIT, медиана
пяти измерений на каждый decision input в отдельном изолированном запуске.
Performance optimization в этом этапе не проводилась.

| Новая ветка, 63 test decision steps; desktop, мс | p50 | p95 |
|---|---:|---:|
| RGB preprocessing | 7,79 | 9,90 |
| NCNN inference | 133,38 | 149,74 |
| Relative normalization | 35,60 | 38,75 |
| Detector + tracker | 6,41 | 11,45 |
| Метрический producer | 56,26 | 389,13 |
| Привязка + fusion + planner | 2,02 | 60,31 |
| Оценка суммы записанных стадий | **276,29** | **617,04** |

Все **63/63** test шагов превышают 100 мс по этой оценке. Для первого опасного
решения сумма стадий укладывается в 300 мс на **7/8** событиях; subpixel-pole
даёт **335,82 мс**. Это отдельный desktop estimate, не восемь измеренных
capture-to-command реакций. Табличные 8/8 своевременных остановок выше относятся
к functional clock; фактический телефонный deadline не доказан.

Одно только desktop inference превышает окно привязки 100 мс на этих test
кадрах. Functional clocks не воспроизводят фактическую задержку CPU. При
подаче реального elapsed age такие старые привязки должны стать unavailable;
отчёт не устанавливает пригодность экспериментального пути в реальном времени.

Функциональные JSON: `camera_temporal_passage.json`,
`camera_temporal_development.json`, `camera_temporal_known_regression.json`,
`camera_temporal_development_freeze.json`. Изменчивое время:
`camera_temporal_ncnn_timing.json`, `camera_temporal_normalization_timing.json`,
`camera_temporal_passage_decision_timing.json`, `camera_temporal_latency.json`.
Hashes функциональных source и предыдущего immutable freeze проверяются
до holdout и при `--check`. Изображения читали только уже полученные RGB,
visible depth и решения, без annotations:
[пересечение](_baseline_logs/camera_temporal_diagnostics/test-temporal-crossing-14.png),
[приближение](_baseline_logs/camera_temporal_diagnostics/test-temporal-approach-13.png),
[manifest plots](_baseline_logs/camera_temporal_diagnostics/manifest.json).

```powershell
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_temporal_passage_assets.py
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/freeze_temporal_passage_development.py --check
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/generate_temporal_passage_ncnn.py --check
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_temporal_rgb_identity.py --check
dart run tool/model_benchmark/evaluate_temporal_passage.dart --check
powershell -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-temporal
```

Новые unit tests проверяют причину legacy-регрессии, стабильность после другого
кадра, first-frame equivalence, сохранение настоящего approach/history и
null/stale/unaligned/invalid/NaN. Runtime negative tests прежнего этапа покрывают
pose, projection, transform, frame, session, model/preprocessing, provider,
expiry/conflicts, subpixel, near obstacles и сохранение physical history.
Core RC дополнен четырьмя обязательными gates. Все Flutter checks выполнялись
последовательно. **1427 Flutter tests, 23 strict legacy scenarios, чистый
анализатор и все 34/34 обязательные gates Core RC — pass в одном полном запуске.**
Исходные camera-visible, recovery и track-association functional reports и
прежний development freeze совпали без обновления baselines.
Полный receipt: `scratch/verification-camera-temporal/core-verification.json`;
лог `scratch/core-camera-temporal.log`. Дополнительные posthoc проверки decoded
RGB и diagnostic PNG воспроизводятся отдельно. `desktopSoftwareRc=pass`,
`modelCorrectnessRc=not_established`; device/walking evidence не установлены.

Только synthetic desktop/shadow. Android build, phone calibration, named-device
runtime и controlled walking в этом этапе не запускались. Исправление известной
причины доказано; дополнительное снижение относительно предыдущей камерной
ветки на свежем test не установлено. Promotion запрещён.

# Независимая подача кадров и проверка ускоренного ядра — 2026-10-07

Исправлена методика elapsed replay: новые кадры поступают по исходным
timestamp без ожидания MiDaS или завершения fast-motion. NN lane использует
реальный `PerceptionScheduler`: одна активная depth-задача, без очереди;
занятые callback пропускаются. Это исправление **тестового контура**.

Остаточная задержка подтверждена и при независимой подаче. Packed-версия
сохранила 158/162 обновления риска вместо 142/162 у контроля, но один из трёх
прогонов потерял четыре обновления. Векторизация ядра прошла точную проверку,
однако в следующей серии дала лишь **157/162 против 156/162**, при одинаковых
86/90 test risk. Timing gate **не пройден**; SIMD не принимается как решение
проблемы задержек. Медиана трёх p50 снизилась с 64.964 до 63.440 мс, но p95
ускоренной версии в третьем прогоне вырос до 96.309 мс; отдельные кадры вышли
за 100 мс. Такие результаты были отклонены.

Все изменения остаются **Windows x64 desktop/shadow**. Обычная камера
не использует эту экспериментальную ветку; `promotionAllowed=false`.
TTL остаётся 100 мс, unknown сохраняется. Условие корректности software-check
не означает прохождение latency или scene/model correctness gate.

## Что исправлено и проверено

- `independent_replay_feed.dart` планирует callback заранее, сохраняет исходный
  capture timestamp при задержке и отменяет оставшиеся таймеры при сбое.
  Результаты объединяются после подачи кадров; ожидание NN отсутствует.
- `replay_depth_load_lane.dart` применяет app scheduler без retained queue.
  Проверены busy callbacks, отсутствие старого pending frame, session/stale
  rejection, inference failure, completion clock failure и освобождение слота.
- `pinned_depth_load_worker.dart` сохраняет прежний process/preprocess/raw-output
  протокол; изменено только публичное имя класса. Результаты модели проверяются
  против pinned output и служат нагрузкой, не источником метрического depth.
- `fast_motion_match_simd.c` вычисляет два соседних цветовых канала вместе.
  Порядок арифметики и накопления ошибки, ABI, пороги, радиус поиска, tie/ambiguity
  правила сохранены. Компиляция без fast-math и FP contraction. Этот кандидат
  не дал достаточного выигрыша в сравнительной серии.
- `tool/verify_core.ps1` получил четыре дополнительных software-check stages:
  stream integrity/evaluation и SIMD integrity/evaluation. Прежнее содержимое
  Core script и документации сохранено; старые source и receipts не изменены.

**Уточнение прежнего отчёта:** живая нагрузка в этих fast-motion CLI — только
**MiDaS Small NCNN**, один CPU thread, без Vulkan. YOLO параллельно не запускался.
Упоминание «YOLO/MiDaS» в предыдущем packed отчёте и frozen protocol было
неточным. Исторические документы сохранены; это явное исправление описания.

## Проверки

| Проверка | Результат |
| --- | --- |
| Independent feed + app scheduler | 15 Flutter tests, pass |
| Packed transport/worker + shadow с новым SIMD DLL | 21 Flutter tests, pass |
| Differential native ABI | 4 Python группы, 85 случаев, побитное совпадение |
| Полный native kernel diagnostic JSON | 109/109, точное совпадение |
| Полный functional worker JSON | 109/109, точное совпадение |
| Stream control и packed functional diagnostics | 109/109 каждый |
| Scene/planner/arbiter shadow replay | 67/67, прежние решения |
| Dart analyze новых исходников и теста | No issues found |
| Ранее frozen receipts + новые source receipts | pass |
| PowerShell syntax и git diff --check | pass |
| Запрет перезаписи elapsed evidence | pass, исходный SHA256 сохранён |

Differential-тесты сравнивают winner и все scratch scores/coordinates/axis/status,
проверяют неизменность входов, восемь seed для отдельных цветовых каналов,
unaligned loads, fractional sampling, границы, ties, пороги и invalid depth/pose.
Все Flutter-запуски последовательные с `--concurrency=1`. Полный Core RC,
APK и полный общий Flutter suite в этом продолжении не запускались.

## Независимый поток: прежний worker против packed

Windows x64, AMD Ryzen 5 7535HS, 6 cores / 12 logical processors, Dart 3.11.1.
По 109 кадров, 16 сцен, исходный интервал 200 мс. Порядок: control 1,
packed 1, packed 2, control 2, control 3, packed 3. Модель warmup выполнен
до подачи кадров, startup worker исключён. В timed trials не выполнялись
анализатор, сборки или тесты.

| Версия / прогон | Возраст p50 / p95, мс | Risk вовремя | Test risk | Отклонено кадров |
| --- | --- | --- | --- | --- |
| Контроль 1 | 77.769 / 99.369 | 44/54 | 24/30 | 5 |
| Контроль 2 | 76.779 / 98.506 | 48/54 | 26/30 | 4 |
| Контроль 3 | 76.437 / 95.309 | 50/54 | 28/30 | 5 |
| Packed 1 | 64.736 / 87.213 | 54/54 | 30/30 | 1 |
| Packed 2 | 67.176 / 88.212 | 54/54 | 30/30 | 2 |
| Packed 3 | 64.244 / 88.385 | 50/54 | 26/30 | 3 |

Суммарно: control **142/162 risk, 78/90 test**, packed **158/162 risk, 86/90 test**.
Эти числа — повторы одного известного корпуса; test-раздел не новый holdout.
Ни один callback или offer не пришёл старше 100 мс: проблема прежнего ожидания
NN устранена в методике. Оставшиеся истечения возникают после подачи кадра.
Пропуск результата также разрывает пару и может лишить следующего кадра risk
update, поэтому число потерянных risk update не равно числу expired frames.

## Следующая серия: обычное ядро против SIMD на одном packed caller

Порядок: original 1, SIMD 1, SIMD 2, original 2, original 3, SIMD 3.
Во всех шести вызовах используется один frozen stream executable и одинаковые
входы; меняется только DLL. Вторая серия оценивается отдельно от первой.

| Версия / прогон | Возраст p50 / p95, мс | Risk вовремя | Test risk | Отклонено кадров |
| --- | --- | --- | --- | --- |
| Обычное ядро + packed 1 | 64.321 / 84.646 | 52/54 | 28/30 | 1 |
| Обычное ядро + packed 2 | 64.964 / 90.490 | 54/54 | 30/30 | 0 |
| Обычное ядро + packed 3 | 66.209 / 91.027 | 50/54 | 28/30 | 3 |
| SIMD + packed 1 | 63.440 / 86.712 | 54/54 | 30/30 | 0 |
| SIMD + packed 2 | 64.572 / 91.166 | 52/54 | 28/30 | 1 |
| SIMD + packed 3 | 62.257 / 96.309 | 51/54 | 28/30 | 5 |

Обычное ядро: **156/162 risk, 86/90 test**, SIMD: **157/162 risk, 86/90 test**.
У SIMD только первый прогон прошёл и risk-update, и all-frame freshness gate;
два других теряют обновления. Повышать TTL для принятия этих результатов нельзя.

| Ядро / прогон | Worker p50 / p95, мс | Packing p50, мс | Native match p50, мс | Native copy p50, мс |
| --- | --- | --- | --- | --- |
| kernel-original 1 | 44.871 / 62.949 | 7.313 | 38.197 | 2.813 |
| kernel-original 2 | 43.183 / 64.082 | 7.061 | 36.735 | 2.568 |
| kernel-original 3 | 45.660 / 65.801 | 7.209 | 39.125 | 2.796 |
| kernel-simd 1 | 43.345 / 63.768 | 6.683 | 35.451 | 2.848 |
| kernel-simd 2 | 43.864 / 59.897 | 7.389 | 36.668 | 3.044 |
| kernel-simd 3 | 43.017 / 67.816 | 7.622 | 36.121 | 2.843 |

Compute/packing получены из per-computation diagnostics, включая истёкшие
вычисления. Для native match/copy используются вычисления с положительным
native временем; p50 — медиана, p95 — nearest rank. Возраст в основных таблицах
включает callback delay, packing, worker и выдачу и взят непосредственно из CLI.

## Что остаётся нерешённым

Во всех **12 прогонах, 1308 повторных кадрах**: ноль stale admissions,
неожиданных risk update и free-space certification; fast active ≤1, pending ≤1,
depth active =1, depth queue =0. Каждый завершённый MiDaS output совпал с pinned.
За прогон завершались 102–109 NN-задач; 0–7 callback пропускали занятую NN lane.
В 103–109 из 109 моментов выдачи fast-результата NN lane оставалась активной.
Задержанные результаты безопасно отклоняются, но пропуски risk update остаются.

55/55 false stops moving-passable paired-сцен из предыдущей проверки остаются
нерешённым отдельным вопросом. Этот цикл их не перезапускал и не менял
clearance/runtime: controller, detector, view-model и прежние producers
сохранены побайтно. Данных о полном объёме тела для безопасного снятия stop
по-прежнему недостаточно; unknown нельзя объявить свободным проходом.

RGB, metric first-return depth и pose motion-корпуса — синтетические входы.
Относительный MiDaS depth не является метрами. Проверка не доказывает качество
моделей, capture-to-command latency, работу на named mid-range Android,
thermal/battery поведение, accessibility или controlled walking.

## Воспроизведение и артефакты

```powershell
python tool/model_benchmark/verify_fast_camera_motion_simd.py --check
dart run tool/model_benchmark/evaluate_fast_camera_motion_stream.dart --check scratch/stream-recheck
dart run tool/model_benchmark/evaluate_fast_camera_motion_simd.dart --check scratch/simd-recheck
scratch/independent-feed-fix-2026-10-07/stream-replay.exe --elapsed-nn scratch/new-timing.json C:/Users/Nurik/Desktop/bagdar_app/scratch/independent-feed-fix-2026-10-07/simd-checks/fast_motion_match_simd.dll
```

[Все trial summaries, потери и SHA256](C:/Users/Nurik/Desktop/bagdar_app/scratch/independent-feed-fix-2026-10-07/comparison.json),
[validation](C:/Users/Nurik/Desktop/bagdar_app/scratch/independent-feed-fix-2026-10-07/validation.json),
[stream checks](C:/Users/Nurik/Desktop/bagdar_app/scratch/independent-feed-fix-2026-10-07/stream-checks.log),
[SIMD checks](C:/Users/Nurik/Desktop/bagdar_app/scratch/independent-feed-fix-2026-10-07/simd-checks.log).
Исходные 12 JSON и отдельные логи сохранены рядом. CLI отказывается
перезаписывать elapsed файл. Новые source contracts:
`camera_fast_motion_stream_contract_v1.json`, `camera_fast_motion_simd_contract_v1.json`.

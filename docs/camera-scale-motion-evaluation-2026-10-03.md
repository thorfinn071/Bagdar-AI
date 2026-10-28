# Сопоставление видимых участков при изменении масштаба — 2026-10-03

На независимом test новый источник добавляет approach risk во всех **18/18**
парах трёх сцен вместо **2/18** у frozen fixed-patch. Сохраняются **9/9**
функциональных остановок перед опасностями, zero unsafe continue и unjustified
clear. Улучшение наблюдения движения подтверждено; дополнительное снижение
ложных остановок не установлено. Desktop latency остаётся препятствием.
`promotionAllowed=false`; только synthetic shadow.

Добавлен отдельный `CameraScaleMetricMotionSource`, который распределяет до
48 признаков по изображению и учитывает отношение видимых оптических глубин
и поворот камер при сопоставлении. Предыдущие реализации, корпуса, отчёты и
write-once freezes сохранены. Источник подключён только экспериментальным
harness через прежний `CameraMetricMotionShadowScene`.

## Метод и ограничения

Три ветки на одинаковых RGB: frozen fixed-patch v1; spatial-only (прежний
matcher с распределёнными признаками); scale-motion (распределение и warp).
Раздельное сравнение необходимо: на известном approach v1 основной выигрыш
дал отбор, а не масштабирование. В development риск: 0/6 → 6/6 → 6/6 пар;
approaching patches: 4 → 58 → 59. Эта сцена уже изучена и не входит в holdout.

Новый matcher использует гипотезу локальной плоскости перед поверхностью,
оптические глубины и относительный поворот камер. Проверяет 25 RGB точек на
области 9×9 с bilinear sampling и масштабом 0,6–1,6. Он не оценивает полный
размер объекта и не доказывает идентичность материала на реальных изображениях.
Сильная деформация, смена освещения, малое разрешение и естественные однотонные
поверхности остаются ограничениями. Текстура синтетических объектов случайная,
воспроизводимая и диагностическая.

Пороги photometric error 0,065, uniqueness 0,015, reverse consistency 1 pixel,
motion 0,20 м/с и риска ≥3 угрожающих участка сохранены. Bounds центра учитывают
соседние depth pixels, регистрацию и объявленную ошибку pose. Неограниченная
или слишком неопределённая глубина не задаёт warp. Неоднозначность, holes,
несовместимая идентичность и выход за масштаб дают unknown.

Возраст текущего кадра ≤100 мс, pair interval 50–300 мс; expiry ограничен
current+100 мс и oldest+400 мс. Потеря pose/provider и смена frame/session/
transform/projection инвалидируют пару. Адаптер только добавляет риск; legacy
relative motion, physical/semantic risks, unknown и история planner сохраняются.
Локальные stationary-compatible участки не доказывают неподвижность всего
объекта, absence of motion или свободное пространство.

## Данные и проверка до holdout

`camera-scale-motion-v1`: 16 независимых геометрических сцен, 118 реальных
RGB/depth кадров, native 384×288, NN 256×256. Validation — 6 сцен; test — 10.
В каждом динамическом случае 7 кадров через 200 мс. Static wide использует
прежние 9 направлений и возврат за 2 с, camera height 1,55 м. Запрос сохранён:
0,9×1,8 м, forward 0,2–3,5 м; динамика не накапливает неподвижный осмотр.

Каждый RGB обработан прежней закреплённой MiDaS/NCNN с прежним preprocessing.
Она предоставляет relative proximity для контрольной detector/tracker/runtime
цепочки. Метрические интервалы нового источника используют независимую первую
видимую глубину; нейросеть не переобучалась. Диагностическая inverse-depth
калибровка осталась отклонённой; новый корпус не используется для подгонки.
Относительный характер глубины также указан в
[официальном README MiDaS](https://github.com/isl-org/MiDaS#applications).

В annotations отдельно сохранены физическая скорость и маски первой видимой
поверхности объекта. Scorer читает их после решений producer/runtime. Поэтому
совпадения фона не считаются наблюдением движущегося объекта. Производственный
packet не содержит масок, hidden geometry, expected decisions или labels.
Asset guard проверяет hash, проекцию Blender, pose, float32 units/bounds,
unknown, pinned model outputs и отличие начальных RGB от всех старых корпусов.

Достаточность static wide размечена до test. Независимые плотные FOV witnesses
по всему защищаемому объёму, включая прежнюю near-upper blind region, попадают
в девять обзоров. Проверка отдельных точек не является сертификатом полного
непрерывного свободного объёма; producer coverage и contract публикуются отдельно.
Labels после test не изменяются ради счётчика ложных остановок.

33 unit/contract/known-regression проверки прошли. На validation новая ветка
добавляет approach risk 6/6 в обоих approach случаях, receding risk 6/6,
crossing risk 6/6. Stationary/camera-yaw не создают уверенного object motion.
Surface mismatch, неверные интервалы скорости и false background motion — ноль
для новой ветки. В frozen fixed-patch при camera-yaw один интервал не содержит
истинный ноль, но классификация не устанавливает движение; это сохранённая
ошибка старой ветки. Analyzer чистый. До первого test создаётся отдельный
write-once freeze исходников, protocol, assets и development report.

## Результаты holdout и desktop timing

После write-once freeze test выполнен без изменений implementation или labels.

| Test, одинаковые RGB | Fixed-patch | Spatial-only | Scale-motion |
|---|---:|---:|---:|
| Slow approach: риск / корректные object patches | 0/6 / 8 | 6/6 / 67 | 6/6 / 69 |
| Fast approach: риск / корректные object patches | 2/6 / 11 | 6/6 / 66 | 6/6 / 73 |
| Small approach: риск / корректные object patches | 0/6 / 2 | 6/6 / 66 | 6/6 / 65 |
| Receding: риск / корректные object patches | 3/6 / 21 | 5/6 / 48 | 6/6 / 81 |
| Mixed camera/object: риск / корректные object patches | 6/6 / 38 | 6/6 / 68 | 6/6 / 75 |
| Stationary / camera-yaw: уверенное движение | 0 / 0 | 0 / 0 | 0 / 0 |
| Опасные сцены: on-time / late / missed | 9 / 0 / 0 | 9 / 0 / 0 | 9 / 0 / 0 |
| Unsafe continue / unjustified clear | 0 / 0 | 0 / 0 | 0 / 0 |
| Достаточно наблюдаемый wide: false stop / hold | 0/1 / 0/1 | 0/1 / 0/1 | 0/1 / 0/1 |

В новой ветке все 363 движущихся object patches (207 approach, 81 receding,
75 mixed) имеют истинную физическую скорость внутри интервалов. Surface
mismatch, incorrect velocity intervals и false background motion — ноль.
Все добавленные риски применены runtime; эти события видны отдельно в traces.
У spatial-only в mixed один интервал фона не содержит истинный ноль, но остаётся
uncertain и не добавляет ложного движения. Source после test не исправлялся.

Основной прирост approach дал распределённый отбор: spatial-only тоже 18/18.
Дополнительный warp дал 207 против 199 корректных approach patches; small case
имеет 65 против 66 — равномерного выигрыша по всем сценам нет. Для receding
warp восстановил шестую пару и дал 81 против 48 patches. Это позволяет
отделить отбор/сопоставление от нейросети и избежать приписывания всего эффекта
масштабированию. Ни один motion producer не отменяет старый relative risk.

Скрытый движущийся объект не дал ни одного object match; остались только
видимые stationary-compatible поверхности заслонки/фона. В textureless scene
есть лишь 6 совпадений на границе неподвижного объекта, прочая текстура относится
к фону; это не сертификат неподвижности всего однотонного объекта. Обе сцены
сохраняют stop при недостаточной наблюдаемости.

Новый wide scan имеет `measuredClear`, применение в runtime и финальное
`continueForward` во всех трёх ветках. Его camera height 1,55 м отличается от
прошлого корпуса, где высота 1,45 м оставляла ближний верхний запас неизвестным.
Этот результат подтверждает возможность полного producer/runtime прохождения
при достаточных данных, но его нельзя приписывать motion fix. Контроль уже
имеет zero false stops на единственной положительной test-сцене; статистика
не доказывает дальнейшего снижения и мала для общей оценки проходимых сцен.

67 test решений на режим. Измерения времени хранятся отдельно от functional
--check; functional capture+2 ms не является measured latency.

| Scale-motion, desktop мс | p50 | p95 |
|---|---:|---:|
| RGB preprocessing NN | 33,90 | 85,62 |
| NCNN inference | 154,83 | 163,34 |
| Relative normalization | 41,06 | 59,90 |
| Detector/tracker | 6,33 | 10,41 |
| Passage reconstruction | 47,66 | 140,21 |
| Motion, включая загрузку decoded RGB fixture | 216,77 | 272,12 |
| Runtime association/fusion/planner | 30,55 | 50,73 |
| Decision compute | 302,17 | 417,26 |
| Сумма последовательных стадий | **532,22** | **672,25** |

Сумма использует NCNN из отдельного прохода; его замеры выполнялись во время
development нагрузки. JIT, порядок веток и фоновые процессы влияют на числа.
Это не phone capture-to-command measurement или доказательство ускорения.
В rendering, scan, capture/transport/scheduling и depth fixture loading эти
суммы не входят. Pair accumulation 200 ms и static scan 2 s учитываются отдельно.
Все 67/67 шагов каждой ветки превышают сохранённую freshness 100 ms по этой
desktop estimate. Только 1/9 первых опасных решений новой ветки укладывается
в 300 ms estimate; это отличается от 9/9 функциональных своевременных stops.
В реальном elapsed clock такой packet должен стать unavailable. TTL не увеличен.

Следующий ограничивающий слой — стоимость обработки и реальное старение
packet. Нужен отдельный profiling/elapsed-clock этап с прежними требованиями
безопасности. Motion coverage улучшен; phone calibration, естественные RGB,
полезное снижение ложных остановок и controlled walking остаются непроверенными.

## Воспроизведение

```powershell
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_scale_motion_assets.py
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/freeze_scale_motion_development.py --check
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/generate_scale_motion_ncnn.py --check
dart run tool/model_benchmark/evaluate_scale_motion.dart --check
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-scale-motion
```

Функциональный артефакт: `docs/_baseline_logs/camera_scale_motion.json`.
Development/freeze и отдельные timings находятся рядом. Core RC получает
четыре новых обязательных gates. Flutter-проверки выполняются последовательно.
Android, named-device calibration/runtime и controlled walking не проверены.

В полном aggregate запуске прошли **1492 Flutter tests**, **23 strict legacy
scenarios**, чистый analyzer и **42/42 обязательных gates Core RC**. Все прежние
camera-visible/recovery/association/temporal/metric-motion freezes, model outputs
и функциональные отчёты совпали. Итоговый receipt:
`scratch/verification-camera-scale-motion/core-verification.json`; полный log:
`scratch/core-camera-scale-motion.log`. `desktopSoftwareRc=pass`,
`modelCorrectnessRc=not_established`; Android, named-device runtime и controlled
walking — `not_run`. Это software/shadow evidence, не разрешение активных подсказок.

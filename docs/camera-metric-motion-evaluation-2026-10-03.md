# Видимое метрическое движение — 2026-10-03

Добавлен отдельный camera-only источник локальных интервалов движения и opt-in
shadow-адаптер. На независимом test боковое пересечение добавляет риск во всех
6/6 межкадровых парах, camera-only движение не создаёт уверенного движения
сопоставленных участков. Все 9/9 физических опасностей сохраняют остановку в
функциональном replay; unsafe continue и необоснованные `measuredClear` — ноль.

**Этап дал диагностический прогресс, но полный критерий полезности не достигнут.**
В test-сцене приближения найдено лишь четыре движущихся участка за всю
последовательность; ни один кадр не достигает фиксированного порога трёх
угрожающих участков для добавления риска. Старые relative motion risks сохранены.
Дополнительное снижение ложных остановок и пригодность в реальном времени не
установлены. `promotionAllowed=false`; только synthetic desktop/shadow.

## Реализация и границы свидетельства

`lib/safety/perception/camera_metric_motion.dart` — чистый Dart producer.
Вход: RGB uint8, первая видимая метрическая глубина, whole-pixel lower/upper
bounds, проекция, pose с объявленными границами позиционной/угловой ошибки,
калибровка и идентичности. Producer не читает файлы, labels, mesh, object masks
или ожидаемые решения. Метры поступают из независимой видимой глубины, не из
MiDaS. Закреплённая MiDaS/NCNN и preprocessing не менялись; диагностическая
inverse-depth калибровка осталась ранее отклонённой.

Отбираются до 48 разнесённых текстурных участков. Patch 5×5 сопоставляется в обе
стороны в окне ±32 пикселя вокруг проекции при гипотезе неподвижности; применяются
фиксированные границы photometric error, уникальности и reverse consistency.
Несовместимые, повторяющиеся, пропавшие или неоднозначные соответствия — unknown.
Окклюзионный/неограниченный depth bound и пропуск в соседних пикселях не заменяются
центральным depth. Пиксельный footprint с регистрационным допуском и ошибка pose
расширяют интервалы обеих поверхностей. Их разность в одном walking frame,
делённая на фактический capture interval, даёт interval velocity, а не относительную
скорость NCNN. Уверенное направление требует нижней границы более 0,20 м/с.

`consistentWithStationary` относится только к видимому сопоставленному участку.
Он **не доказывает неподвижность объекта, отсутствие движения или свободный
проход**. `available` означает наличие хотя бы одного локального соответствия;
оно может относиться к неподвижному фону. Области без признаков и закрытые части
остаются неизвестными. Photometric correspondence — экспериментальная гипотеза,
не гарантия идентичности материала на произвольных реальных изображениях.

Текущий кадр должен быть не старше 100 мс; интервал пары — 50–300 мс.
Evidence содержит oldest capture timestamp; срок действия ограничен current+100 мс
и oldest+400 мс. Смена session/camera/provider/model/projection/transform,
reorder, loss/invalid pose и испорченный packet уничтожают старую пару.
Следующий совместимый кадр начинает новую пару. TTL не увеличен ради быстродействия.

`lib/safety/runtime/camera_metric_motion_shadow_scene.dart` внедряется только
экспериментальным harness как dependency существующего runtime. Три угрожающих
локальных участка могут добавить forward moving risk. Future envelope видимых
участков на ≤1 с используется только для положительного риска пересечения тела,
не для исключения неизвестного размера объекта. Адаптер не добавляет positive
coverage, не удаляет относительное движение/семантику, physical history или
unknown и не сбрасывает planner. Совпадение frame/session/capture/transform и
expiry проверяются; packet одноразовый. Обычный телефонный runtime не подключён.

## Независимые сцены и исправленная достаточность обзора

`camera-metric-motion-v1`: **17 полных геометрических сцен, 131 настоящий RGB/depth
рендер**, native 384×288 и прежний NN input 256×256. Семь validation и десять test.
Есть stationary, approach, receding, crossing, yaw, translation, mixed motion,
occluded, textureless и статичный осмотр. Динамика — семь кадров с шагом 200 мс;
producer и passage source используют текущую видимую глубину. Только статичный
осмотр объединяет девять ракурсов и возврат. Диапазон 0,2–3,5 м и тело 0,9×1,8 м
не сокращались. История tracker/runtime/planner остаётся на всю последовательность.

Видимые поверхности имеют случайную воспроизводимую цветную текстуру, чтобы
проверить correspondences; textureless/окклюзия показывают ограничения.
Такая диагностическая текстура не устанавливает качество на обычных телефонных
изображениях. Пиксели начальных RGB отличаются от всех прежних корпусов и друг
от друга; model/asset/RGB identities и фактическая матрица проекции проверяются.

Номинальная разметка считала static scan достаточно наблюдаемым, но не учитывала
полный объём принятого консервативного контракта с запасом подъёма пола.
На validation найдена узкая верхняя непроверенная область перед камерой.
Независимый `annotate_metric_motion_observability.py` по проекции, **без
producer/NN/planner output**, подтвердил пять точек защищаемого объёма вне всех
девяти направлений: y=0,2 м, z=1,85 м, x от −0,10 до +0,10 м. Верхняя граница
учитывает разрешённый подъём пола 50 мм. Камера находится на высоте 1,45 м;
pitch +35° не покрывает весь этот ближний объём.

Исходные labels сохранены в `annotations.nominal.json`; исправленные labels и
свидетельства — `annotations.json`/`observability.json`. Исправление выполнено
до первого test replay, одинаковым правилом для всех сцен. Данные test и
реализация после freeze не менялись. Этот корпус поэтому **не содержит
достаточно наблюдаемых проходимых test-сцен**. False-stop denominator = 0;
нулевой счётчик не является доказательством снижения ложных остановок.
**По сохранённой номинальной разметке обе ветки имеют 1/1 ложную остановку.**
Остановка на wide scan связана с неизвестностью верхнего запаса, не с движением.
Независимый post-hoc `camera_metric_motion_observation_audit.json` публикует обе
оценки. На высоте 1,80 м эти же контрольные точки попадают в обзор; это ещё не
сертификат всего объёма. Невозможность подтвердить номинальный проход при более
точном восстановлении upper floor bound **не доказана**. Уточнение floor-rise
bound могло бы уменьшить необходимый верхний запас; оно в этом этапе не внедрено.

После 28 unit/integration cases, validation и чистого analyzer записан
write-once `camera_metric_motion_development_freeze.json`. Он фиксирует source,
protocol, model, данные и обе версии annotations. Затем выполнен первый test.
Labels физических опасностей/скорости читаются scorer только после решения.

## Результаты отложенного test

| Одинаковые RGB, 10 test-сцен | Своевременные функциональные остановки | Поздние / пропущенные | Unsafe continue | Unjustified clear |
|---|---:|---:|---:|---:|
| Прежний frame-stable NCNN + visible passage | 9/9 | 0 / 0 | 0 | 0 |
| Та же цепочка + metric motion | 9/9 | 0 / 0 | 0 | 0 |

Все десять финальных решений сохраняют stopNow при опасности/неполном обзоре.
Дополнительного выигрыша решений относительно прежней ветки здесь нет.
Истечение старых стопов и восстановление стоя проходят прежние gates; новый
producer не имеет полномочий отменять старый риск.

| Test-сцена | Локальные пары с движущимися участками | Кадры добавления / применения нового риска | Вывод |
|---|---:|---:|---|
| Stationary | 0/6 | 0 / 0 | Нет ложного уверенного движения на сопоставленных участках |
| Approach | 3/6, всего 4 участка | **0 / 0** | Направление измерено локально, coverage недостаточен для runtime-порога |
| Receding | Есть 15 удаляющихся участков | 2 / 2 | Нет ложного приближения; движущийся объект ещё в защищённом объёме |
| Crossing | 6/6, 47 боковых участков | **6 / 6** | Боковое движение и положительный риск достигают runtime |
| Camera yaw / translation | 0/6 в каждой | 0 / 0 | Компенсация pose не создаёт object motion на измеренных участках |
| Mixed | Есть 16 движущихся участков | 3 / 3 | Часть соответствий потеряна; полный motion coverage не доказан |
| Occluded | Только видимые статичные участки | 0 / 0 | Движение за заслоняющей поверхностью неизвестно |
| Textureless | Только текстурные участки фона | 0 / 0 | Скорость однотонного объекта не подтверждена |

Примеры metric intervals: в approach при frame 4 forward velocity
**[−1,1804; −1,1196] м/с**, физическое движение −1,15 м/с.
В crossing при frame 2 lateral velocity **[−0,8963; −0,6709] м/с**,
физическое движение −0,80 м/с. Это отдельные правильно сопоставленные видимые
участки, не средняя ошибка скорости всех объектов.

В receding старый относительный tracker всё ещё имеет max positive approach
trend 0,07114; новый источник имеет 15 receding patches и 0 approaching patches.
Этот результат отделяет ошибку relative trend от направления metric displacement,
но старый риск намеренно сохраняется. Ни один unknown участок не становится free.

Ограничивающий слой следующего улучшения — **отбор и сопоставление видимых
участков при изменении масштаба**, особенно у приближающегося объекта.
Неподвижный текстурный фон забирает часть бюджета признаков; patch без учёта
изменения масштаба теряет соответствия. Удаление неизвестности или снижение
порога ради test не выполнялось. Нужен отдельный development этап устойчивого
сопоставления, а текущий approach следует считать известной регрессией.

## Отдельные desktop timings

`camera_metric_motion_latency.json` содержит только test: 67 решений на режим.
Preprocessing/inference измерены отдельным pinned NCNN проходом, остальные
стадии — wall clock Flutter replay. Нагрузка, JIT и состав сцен отличаются от
прошлого отчёта; числовое изменение времени между корпусами не доказывает
оптимизацию. Ниже сумма согласованных стадий, не capture-to-command измерение.

| Новый режим, мс | p50 | p95 |
|---|---:|---:|
| RGB preprocessing NN | 22,15 | 47,16 |
| NCNN inference | 104,53 | 117,30 |
| Relative normalization | 30,43 | 36,67 |
| Detector + tracker | 5,41 | 7,72 |
| Passage reconstruction | 36,77 | 63,42 |
| Metric motion, включая загрузку decoded RGB fixture | **169,37** | **210,56** |
| Runtime association + fusion + planner | 28,16 | 47,42 |
| Оценка суммы стадий | **399,02** | **465,74** |

Все **67/67** test шагов превышают 100 мс freshness window по оценке суммы.
В реальном времени старое свидетельство должно стать unavailable; функциональные
clocks фиксированы capture+2 мс и не воспроизводят это CPU-старение.
Функциональные 9/9 своевременных остановок не означают девять доказанных реальных
реакций. Desktop estimate первого опасного решения укладывается в 300 мс на
7/9 событиях: crossing **406,72 мс**, mixed **362,03 мс** превышают бюджет.
У первой пары дополнительно есть интервал накопления 200 мс. Время осмотра 2 с,
capture/transport/scheduling, рендер и загрузка depth fixtures в эти суммы не входят.

Путь пока слишком медленный для сохранённых требований возраста данных.
Оптимизация/реальный elapsed-clock replay остаются отдельным этапом; TTL не
расширен. Пакет с хорошим направлением, но старым timestamp, не должен применяться.

## Проверки и воспроизведение

28 unit/integration cases проверяют forward/lateral, pose translation,
неоднозначные/однотонные RGB, метрические bounds и units, noise bounds 5/20 мм,
holes/conflicts, несовместимые проекции и калибровку, model/transform/camera/
provider/session, reorder/future/stale/expiry/recovery. Реальный planner получает
добавленный боковой риск с `SPATIAL-P0-IMMINENT`; прежние physical/unknown risks
сохраняются. Старые subpixel/межлучевые/hidden-geometry safety cases сохранены
в Core RC. Source guard проверяет отсутствие IO и чтения annotations; API новых
producers не содержит скрытую геометрию.

```powershell
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_metric_motion_assets.py
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/annotate_metric_motion_observability.py --check
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/freeze_metric_motion_development.py --check
tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/generate_metric_motion_ncnn.py --check
dart run tool/model_benchmark/evaluate_metric_motion.dart --check
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-metric-motion
```

Core RC получил четыре обязательных gates; все Flutter-проверки выполнены
последовательно. **1457 Flutter tests, 23 strict legacy scenarios, чистый analyzer
и все 38/38 обязательных gates — pass в одном полном aggregate запуске.**
Прежние camera-visible/recovery/association/temporal reports, development freezes
и pinned model outputs совпали. Receipt:
`scratch/verification-camera-metric-motion/core-verification.json`; полный log:
`scratch/core-camera-metric-motion.log`. Дополнительный post-hoc nominal observation
audit воспроизводится с `audit_metric_motion_observation.py --check` и проверен
отдельно; он не меняет frozen pipeline или её test-решения.

Основной функциональный артефакт: `docs/_baseline_logs/camera_metric_motion.json`.
Development/freeze и timings находятся рядом. Диагностика текущих видимых RGB и
локальных correspondences — `camera_metric_motion_diagnostics/manifest.json`.
Просмотрен crossing plot: настоящий объект смещается к центру, новый источник
выделяет боковые участки, отрицательные/потерянные соответствия остаются unknown.

Android build, phone calibration, named-device runtime и controlled walking
не запускались. Семантика, calibrated real pose, natural texture и phone latency
остаются отдельными проверками. Продвижение в активные подсказки запрещено.

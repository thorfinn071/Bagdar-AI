# Передача оптических измерений: 2026-10-11

Основная цель — уменьшить ложные STOP обычной камеры при сохранении
консервативной проверки опасностей — **не достигнута**. Новый экспериментальный
transport сохраняет измерения и отклоняет чужие метаданные, но увеличивает
время обработки. Все 108 фактически измеренных результатов просрочены.
Обычный camera runtime эту реализацию не использует; shadow сохранён.

## Что исправлено в экспериментальном коде

`CameraTypedHeightEnvelopeFrame` хранит шесть исходных Float64 planes и
validity mask в собственном contiguous buffer с read-only interfaces.
Copy и pack/materialize сохраняют значения, pose, error bounds, units,
идентификаторы и исходное время захвата. Они не создают отсутствующих
измерений и не превращают relative depth в метрическую глубину.

В первой версии нового transport обнаружен дефект: получатель мог случайно
сопоставить payload с метаданными другого кадра. Девять regression cases
сначала воспроизвели ошибку. В версии 2 добавлен 32-byte SHA256 fingerprint
исходных метаданных, включая exact floating-point bits. Получатель отклоняет
несовпадение frame, capture time, session, model, transform, reference,
origin, rotation или intrinsics. Fingerprint защищает от ошибочного
сопоставления; он не является аутентификацией или доказательством точности
датчика. Исправление относится к новому opt-in transport, а не к прежнему
обычному runtime.

Первая версия сохранена вместе с protocol/source snapshots, заморозкой,
receipts, executable и журналом девяти первоначально проваленных тестов.
Версия 2 заморожена до повторного scoring: 1398 файлов. Проверены все 1382
архивных source hashes версии 1, три явных перенаправления на snapshots и
совпадение canonical preregistration с версией 2. Данные, модели, scoring
cases, геометрические predicates, 100000 мкс TTL и STOP/history не менялись.

## Проверки

Два последовательных Flutter запуска прошли **59/59 tests** каждый:

- 19 corpus/negative/seeded tests: 48 пары на 12 известных сценах в вариантах
  full 12, minimal 10, single и suffix 6; 17 отрицательных случаев; 100
  seeded small packets с разными intrinsics и invalid/NaN pixels;
- 8 ownership/shape/value-preservation tests;
- 9 metadata-binding regressions;
- 23 ранее существовавших age-gate tests.

Все 48 observation pairs совпали с замороженным indexed producer.
Повторный receipt совпал byte-for-byte; receipt версии 2 также совпал с
архивом версии 1. Hazard labels применялись после вычисления измерений.
Static analysis пяти новых Dart-файлов прошёл без замечаний.
Это проверки software consistency, а не физической точности камеры.
Полный Core RC и Android runtime для этого opt-in этапа не запускались.

## Фактическое время обработки

Windows Dart AOT, preloaded known static synthetic packets, minimal ten views,
один warmup на mode/scene, три раунда с чередованием порядка. Все варианты
использовали один frozen scalar producer. Publication всех десяти packets,
fingerprint, source, evaluator и age gate входили в advancing Stopwatch.
Тесты и другие модельные workload одновременно не запускались.

| Input mode | Samples | p50 pipeline, мс | p95 pipeline, мс |
|---|---:|---:|---:|
| Generic input | 36 | 271,718 | 372,762 |
| Typed copy publication | 36 | 311,066 | 452,162 |
| Typed pack/materialize publication | 36 | 340,923 | 474,696 |

Copy и pack/materialize ухудшили медиану примерно на 14,5% и 25,5% в этом
workload. Эксперимент не подтверждает ускорение. Архивные timings версии 1
сохранены отдельно; разницу между отдельными запусками нельзя целиком
приписывать fingerprint.

Capture offsets COUNTERFACTUAL: 120 fps плюс 2 мс start lag, возраст самого
старого вклада на старте 77 мс. Это оставляло 23 мс до TTL, но не означает
реальную скорость захвата или поворота телефона. **108/108 samples получили
expiredAfterCompute**; observations и decisions не выпущены. Загрузка fixture,
физический capture, inference, actual isolate dispatch/queue, Android transport,
feedback delivery и thermal/device условия не измерялись.

## Почему основная проблема остаётся

Goal audit повторно проверил hashes прежних runtime receipts: ordinary single
view остаётся на 14/14 false STOP; независимый набор — 34/34 false STOP и
50/50 hazard STOP. Эти runtime прогоны в текущем этапе не повторялись;
нового успешного результата для них нет.

Все четыре ранее проверенных ordinary camera views не охватывают весь
требуемый body volume. У исходной камеры полное сечение попадало в кадр
лишь с 1,738 м при запросе 0,2–3,5 м: ближний участок длиной около 1,54 м
остаётся вне полного обзора. Это вывод для проверенной геометрии, а не для
всех телефонов. Минимальные десять ракурсов относятся только к данному
синтетическому набору двенадцати poses; их реальный сбор за 77 мс не доказан.

MiDaS по-прежнему даёт относительную глубину. Реального текущего paired
RGB/depth/pose/intrinsics capture с независимыми metric, alignment/error и
body-volume evidence нет. Пользователь подтвердил недоступность телефона;
свежий `adb devices -l` также не показал устройств.

Один и тот же внешний блок сохранялся на трёх последовательных этапах:
minimal scan, scalar processing и typed transport. Оптимизация вычислений
может уменьшить latency, но не создаст отсутствующие near/body-volume
observations и не установит реальную метрическую калибровку. Дальнейший
прогресс по основной цели требует нового проверяемого источника измерений:
реального синхронизированного захвата с intrinsics/pose и независимой проверкой
масштаба, выравнивания, ошибок и необходимого обзора. Подключение телефона
само по себе не доказывает эти свойства. Подготовка research capture сохранена
в [инструкции](research-capture-guide-2026-10-11.md).

Сохранены `promotionAllowed=false`, `ordinaryCameraWired=false`,
`falseStopReductionEstablished=false`, `canAuthorizeMovement=false`.
Основная цель остаётся незавершённой.

Receipts: `scratch/typed-scan-transport-2026-10-11/`, включая `goal-audit.json`.
[Протокол](typed-scan-transport-protocol-2026-10-11.md).

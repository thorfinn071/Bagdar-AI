# Первые исправления после проверки сцен — 2026-10-07

Исправлены лишние копии при передаче fast-motion кадра и избыточное обнуление
нативных числовых буферов. Медиана p50 трёх прогонов снизилась с **75.066 до
66.078 мс**. В test-разделе вовремя сохранены **84/90** эталонных обновлений
риска вместо **76/90** у контроля. Это повторения одного известного корпуса.
Полный timing gate **не пройден**: два из трёх новых прогонов теряют обновления,
а третий имеет p95 109.392 мс. 55/55 ложных остановок paired-сцен сохраняются.

Исправленная версия доступна в отдельном **desktop/shadow** контуре. Обычная
камера её не использует; `promotionAllowed=false`. TTL остаётся 100 мс.
Метрические first-return depth/pose в motion-корпусе — синтетические входы,
а не результат MiDaS. Живые pinned YOLO/MiDaS используются только как нагрузка.

## Что изменено

- [Transport](C:/Users/Nurik/Desktop/bagdar_app/lib/safety/runtime/camera_fast_motion_packed_transport.dart)
  создаёт один выровненный пакет. RGB, три Float64-карты и маска переносятся
  собственным снимком `TransferableTypedData`; получатель видит read-only данные.
- [Нативный адаптер](C:/Users/Nurik/Desktop/bagdar_app/lib/safety/perception/camera_fast_motion_bulk_native_match.dart)
  выделяет числовой блок через `malloc`, заполняет все входные плоскости и
  освобождает его тем же allocator. Ленивая axis-плоскость читается только
  после записи значения; status-маска по-прежнему обнулена через `calloc`.
- [Worker](C:/Users/Nurik/Desktop/bagdar_app/lib/safety/runtime/camera_fast_motion_packed_worker.dart) и
  [shadow adapter](C:/Users/Nurik/Desktop/bagdar_app/lib/safety/runtime/camera_fast_motion_packed_shadow_adapter.dart)
  используют новую версию копирования. Численные расчёты, native C, пороги,
  identity/session, bounded queue, clocks, stale rejection и release-token
  правила сохранены.
- В `tool/verify_core.ps1` добавлены две проверки новой версии. Старые source,
  receipts и эталонные отчёты сохранены. Новый elapsed CLI отказывается
  перезаписывать существующий файл измерения.

Версии source выделены отдельно, поскольку прежние load/kernel receipts
заморожены. Проверка подтверждает, что численный source отличается только
именем и импортом нативного адаптера; native adapter — только выделением,
освобождением и способом копирования числового блока.

## Проверки

| Проверка | Результат |
| --- | --- |
| `flutter analyze --no-pub` | No issues found |
| Packed native contract/transport и shadow tests | 21/21 |
| Paired correction replay и confidence authority tests | 13/13 |
| Полный kernel diagnostic JSON, AOT/native | 109/109, точное совпадение |
| Полный functional worker JSON, AOT/native | 109/109, точное совпадение |
| Реальный shadow scene/planner/arbiter | 67/67, прежние решения |
| Source receipt и ранее замороженные contracts | pass |
| Запрет перезаписи elapsed evidence | pass, исходный JSON не изменён |

В transport проверены все восемь вариантов выравнивания, NaN, signed zero,
mixed validity и read-only/однократное materialization. Worker-тесты проверяют
просроченные кадры на входе, завершении и выдаче, точную границу 100 мс,
поддельный/reused token, session/provider/clock failures, newest queue,
неоднозначное сопоставление и сохранение физических рисков/unknown.
Все Flutter-запуски выполнялись последовательно с `--concurrency=1`.
**Полный Core RC, APK и named-device испытания в этом исправлении не запускались.**

## Повторные измерения с живой NCNN-нагрузкой

Windows x64, AMD Ryzen 5 7535HS, 6 cores/12 logical processors, Dart 3.11.1.
По 109 кадров в каждом прогоне; эталон — 54 motion-risk обновления, из них
30 в test-разделе. Это известный synthetic corpus, не новый holdout.
Счётчики risk update не являются счётчиками остановок пользователя.

| Версия / прогон | Возраст p50, мс | Возраст p95, мс | Вовремя risk | Test risk | Просрочены / отклонены |
| --- | --- | --- | --- | --- | --- |
| Контроль 1 | 75.066 | 103.514 | 47/54 | 24/30 | 7 |
| Контроль 2 | 73.772 | 97.759 | 50/54 | 26/30 | 4 |
| Контроль 3 | 76.519 | 99.728 | 48/54 | 26/30 | 4 |
| Исправление 1 | 65.125 | 89.316 | 50/54 | 26/30 | 2 |
| Исправление 2 | 66.078 | 87.132 | 54/54 | 30/30 | 0 |
| Исправление 3 | 66.741 | 109.392 | 50/54 | 28/30 | 7 |

Итого все эталонные risk updates: контроль **145/162**, исправление **154/162**.
Для test-раздела: **76/90 → 84/90**. Потери не исключены из отчёта.
В каждой версии фактических admitted release старше 100 мс — **0**;
сертификаций свободного пространства — **0**.

p50 упаковки по диагностике реально обработанных запросов снизился с
11.408–12.311 до 7.111–7.647 мс. p50 native-frame copy — с 9.111–9.980
до 2.771–2.824 мс. p50 compute уменьшился, но outliers остаются.
Данные packing берутся из per-request diagnostics, поскольку глобальное
`lastPackingUs` старого harness повторяет прошлое значение у кадров,
отклонённых до упаковки. Такие кадры сохраняются в age/rejection счётчиках.

Контроль и новая версия запускались в одной сессии по три раза, без
параллельного Flutter/analyzer. Это не строго рандомизированный эксперимент.
Промежуточные `packed-nn-1.json` (только упаковка) и `bulk-nn-1.json`
(копирование до malloc) также сохранены; они не включены в итоговую новую
версию. Фактическая последовательность: packed, control-1, bulk, control-2,
fixed-1, fixed-2, control-3, fixed-3. Частота CPU, температура и фоновые процессы
во время этих измерений не записывались; причина отдельных outliers неизвестна.

Harness передаёт fast-результат до завершения NN, затем ожидает NN перед
следующим предложением кадра. При затянувшемся NN некоторые последующие
синтетические кадры могут уже быть просрочены на входе. Это ограничение данного
сравнения; оно не доказывает поведение независимого capture/scheduler телефона.
Timestamp не переписывался. Capture-to-command здесь не измеряется.

## Оставшиеся проблемы

- **55/55** проходных moving-кадров paired corpus всё ещё получают stop.
  Повторный replay с pinned предсказаниями совпал с прежним эталоном:
  66/66 опасных кадров останавливаются, unsafe continues и false IMMINENT — 0.
  Эти остановки завязаны на неподтверждённый объём для тела. Хороший fit пола
  или отсутствие YOLO-объекта не создаёт такого подтверждения.
- Timing остаётся **частично исправленным**. Один новый прогон сохраняет все
  54/54 риска, два других теряют по четыре. Готовность к активной помощи
  и named mid-range phone performance не установлена.
- Качество YOLO на синтетическом `person-approach` в этой работе не исправлялось.
  Веса и preprocessing не изменены; fresh neural accuracy повторно не измерялась.

Следующий отдельный шаг — разбирать paired `path-clear` и подтверждение
проходимости по наблюдаемым данным, сохраняя неизвестные области как unknown.
Перед переносом ускоренной ветки в обычную камеру требуется отдельная
проверка capture/scheduler и целевого Android-устройства.

## Артефакты и воспроизведение

- [Машинная проверка](C:/Users/Nurik/Desktop/bagdar_app/scratch/safety-fix-2026-10-07/validation.json)
- [Все шесть итоговых замеров](C:/Users/Nurik/Desktop/bagdar_app/scratch/safety-fix-2026-10-07/comparison.json)
- [Лог native/kernel/worker/shadow checks](C:/Users/Nurik/Desktop/bagdar_app/scratch/safety-fix-2026-10-07/checks.log)
- [Paired regression log](C:/Users/Nurik/Desktop/bagdar_app/scratch/safety-fix-2026-10-07/paired-regression.log)
- [Новый write-once source receipt](C:/Users/Nurik/Desktop/bagdar_app/docs/_baseline_logs/camera_fast_motion_packed_contract_v1.json)
- [Протокол](C:/Users/Nurik/Desktop/bagdar_app/docs/camera-fast-motion-packed-protocol-2026-10-07.md)

```powershell
dart run tool/model_benchmark/evaluate_fast_camera_motion_packed.dart --check
python tool/model_benchmark/verify_fast_camera_motion_packed.py --check
```

# Исправление транспорта fast-motion — 2026-10-07

Область: отдельная версия экспериментального Windows x64 shadow-контура.
Обычная камера и выдача команд пользователю эту версию не используют.
`promotionAllowed=false`. Корпус известный: 109 кадров, включая 67 test-кадров.
Повторы замеров не являются независимыми испытаниями распознавания.

## Изменения

1. `packFastMotionFrame` заполняет один выровненный буфер RGB, трёх Float64
   карт и маски. `TransferableTypedData` получает собственный снимок этого
   буфера. Промежуточные массивы и список boxed-значений маски не создаются.
   Данные после переноса остаются read-only; исходные timestamps сохраняются.
2. Нативный адаптер выделяет семь числовых плоскостей через `malloc`.
   Все входные числовые плоскости полностью заполняются перед вызовом C.
   Ленивая плоскость axis читается только после записи значения и установки
   status=2 в прежнем `axis_at`. Маски status по-прежнему выделяются через
   `calloc`. Этот инвариант запрещает чтение неинициализированной памяти.
   Освобождение числового блока выполняется через `malloc.free`.

Новый source отличается от `CameraFastMetricMotionLoadSource` только именем
и импортом адаптера копирования. Прежние C-модуль, расчёты, 48 features,
радиус поиска 32, порядок сравнения, пороги и scoring не изменены.
Копии модулей сохраняют предыдущие исходники и write-once receipts для
сравнения. Проверка новой версии подтверждает точное совпадение численного
source и ограниченный набор изменений нативного адаптера.

## Условия проверки

- Полное совпадение 109-frame kernel parity и functional worker JSON с
  замороженными эталонами; не только совпадение итоговых счётчиков.
- 67-frame replay через настоящий shadow scene/planner/arbiter. Unknown и
  история физических препятствий сохраняются; clearance не создаётся.
- Native contract tests: некорректные identity/depth/pose, неоднозначность,
  поддельный и повторный release token, устаревание при входе/вычислении/выдаче,
  смена session, потеря provider, rollback clock, ограниченная newest-queue.
- Transport tests: все восемь вариантов byte-alignment, mixed validity,
  NaN, signed zero, read-only views и однократная materialization.
- TTL текущего кадра 100000 мкс, pair interval и oldest-evidence TTL прежние.
  Проверяется точная граница и отбрасывание после неё.
- Три измерения каждой версии с одновременно работающими pinned YOLO/MiDaS,
  без запуска анализатора/Flutter во время измерений. Сохраняются все
  результаты, включая потери risk update и сбросы пары; elapsed-файлы
  запрещено перезаписывать.

Прохождение функциональных проверок не означает прохождение timing gate.
Если хотя бы один эталонный риск потерян из-за задержки, в отчёте остаётся
открытое ограничение производительности. Capture-to-command, Android,
температура, named-device и controlled-walking здесь не измеряются.

## Воспроизведение

```powershell
dart run tool/model_benchmark/evaluate_fast_camera_motion_packed.dart --check
python tool/model_benchmark/verify_fast_camera_motion_packed.py --check
```

Измерение после сборки, каждый раз с новым путём вывода:

```powershell
& scratch/fast-camera-packed-verification/replay.exe --elapsed-nn scratch/packed-measurement-new.json C:/Users/Nurik/Desktop/bagdar_app/scratch/fast-camera-packed-verification/fast_motion_match.dll
```

Исправление относится к задержкам. 55/55 ложных остановок в paired corpus
этой работой не устранены: обычный относительный MiDaS не подтверждает полный
свободный объём для тела. Unknown нельзя объявить свободным пространством
на основании отсутствия объекта или хорошего fit пола. См. исходный отчёт
`scratch/scene-validation-2026-10-06/report.md` и paired correction evaluation.

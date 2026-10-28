# Bagdar: исследовательский путь iPhone — 17 октября 2026

Добавлены отдельный UIKit-рекордер, строгий импорт ARKit, эмпирический
калибровочный отчёт, диагностическая карта и preregistered-план на 72 записи.
Повторены прежние синтетические контроли. Реальных записей iPhone пока нет;
снижение ложных STOP на телефоне не установлено.

## Реализация

- Один ARSession получает `capturedImage`, `sceneDepth`, confidence, intrinsics,
  camera transform и исходное время кадра. Native размеры и invalid значения
  сохраняются. Лимиты: 10 секунд, 300 сохранённых кадров, 512 MiB; один active и
  один newest pending. Start/Stop/Export требуют действий пользователя.
- Рекордер находится в отдельном Xcode-проекте; Flutter и обычный Core в нём не
  запускаются. Каталог записи и экспортный ZIP исключены из системного backup.
  Mac-скрипт сохраняет хеши исходников и встраивает provenance ID сборки.
- Формат `bagdar-arkit-capture-v1` имеет отдельный валидатор. Он сверяет SHA-256,
  recording ID, кадры, native strides/форматы, clocks, маску валидности, tracking
  и счётчики пропусков. Повреждённые/частичные записи и импорт raw media в Git
  отклоняются. Прежний ARCore-формат сохранён.
- `RecordedRgbdFrame` владеет неизменяемыми копиями. `PhysicalEvidenceProfile`
  описывает только эмпирические ошибки и условную геометрию.
  `RecordedPassageEvidenceSource` возвращает unknown/unavailable при отсутствии
  независимых свидетельств. Он не подключён к обычной камере.
- Анализ выдаёт `feasibility.json`, строки кадров и `coverage.svg`. Доступность
  SDK samples показана отдельно от покрытия тела/пола. При заданной измеренной
  позе отдельно отображается условный ближний пробел поля зрения.

Сборка, перенос ZIP и команды Windows описаны в
[инструкции Mac → Windows](../tool/research_capture/README_ARKIT.md).

## Почему gate пока закрыт

ARKit выдаёт оценку глубины в центре пикселя и категориальную confidence.
Текущий passage-контракт требует консервативных first-return границ для всей
площади пикселя, полного текущего тела и пола. Ни confidence, ни небольшой
эмпирический error fit такие свидетельства не создают.

Поэтому этот адаптер не выпускает `measuredClear`. Его физические флаги остаются
false даже после чтения эмпирического calibration report. Декларация в JSON не
может самостоятельно включить физическую готовность. Это предусмотренное
условие остановки, а не подтверждённое исправление ложных STOP.

Проверяемый объём остаётся 0,2–3,5 м, ширина 0,9 м, headroom 1,85 м, допуски
пола ±0,05 м. TTL остаётся 100000 мкс. Переход к уменьшенному объёму, заполнению
дыр или накопленной модели не используется для получения clear.

Native ARKit time и Dispatch uptime сохраняются раздельно. Replay использует
явно искусственную эпоху, сохраняет интервалы исходного времени и прибавляет
фактическую работу host-анализа к возрасту кадра. Native capture/transport age
при этом неизвестен. `captureToDecisionMs=null`; измерения Windows не являются
задержкой iPhone или Android.

## Повторённые известные контроли

| Проверка | Фактический результат |
| --- | --- |
| Closed-volume producer, до runtime | 14/14 свободных кадров дали measuredClear; 21/21 provider healthy |
| Closed-volume runtime, оба прежних detector mode | 7/7 hazard STOP; fixed rig 0/14 ложных STOP против 14/14 same-rig control |
| Отказы после clear и отрицательные предпосылки | 48/48 fault STOP, 48/48 moving-recovery STOP, 24/24 clear preconditions |
| Прежний независимый набор, read-only producer audit | 84/84 provider healthy, 0/84 measuredClear |
| Сохранённый исходный результат независимого набора | 34/34 свободных STOP, 50/50 hazard STOP; новый runtime-прогон этого набора здесь не заявлен |

Повтор положительного runtime сравнен побайтно с сохранённым receipt.
Это повтор известных синтетических данных, без нового независимого holdout,
физической точности камеры, Android или испытаний ходьбы.

## Программная проверка

Полный серийный Flutter-прогон завершён: **2548 passed, 0 failed, 16 skipped**
за 23 минуты 48 секунд. Пропуски сохраняют существующие условия запуска.
Новые контрактные проверки: **62/62 Python** (включая Python → Dart CLI),
**14/14 Dart**. Анализатор сообщил **0 замечаний**. Swift parser проверил синтаксис
шести файлов и структуру Xcode-проекта; Xcode compilation и XCTest на Mac этим
не подтверждаются.

До работы сохранены SHA-256 1722 существующих файлов, моделей и старых receipts
в `scratch/iphone-spatial-20261017/baseline.json`. После выполнения все **1722/1722**
хеша совпали; старые файлы и receipts сохранены.
Серийный воспроизводимый verifier:

```powershell
python tool/research_capture/verify_arkit.py --output scratch/arkit-verification-NEW
```

Итоговые журналы этого выполнения находятся в
`scratch/iphone-spatial-20261017/`. [Основной программный receipt](../scratch/iphone-spatial-20261017/final-verification/verification.json)
содержит семь выполненных стадий; [журнал окончательных Python-проверок](../scratch/iphone-spatial-20261017/python-final-advancing-clock.log)
содержит 62 проверки после финальных дополнений формата/анализа.
Сводка передачи — [delivery-verification.json](../scratch/iphone-spatial-20261017/delivery-verification.json),
заморозка реализации — `implementation-freeze.json`, отдельный diff только
21 нового файла — `task-only.patch` в том же каталоге.
Полный агрегатор `tool/verify_core.ps1 -Rc`
здесь не заявлен пройденным: полный Flutter-набор и Core aggregate RC имеют
разные границы доказательств.

## Физический этап

| Свойство | Статус |
| --- | --- |
| Xcode compilation / native XCTest | not_run |
| Реальная камера и lifecycle iPhone | not_run |
| RGB/depth alignment и метрические error bounds | not_established |
| Измеренное поле зрения и ближний пробел iPhone | not_run |
| Полный body/floor measuredClear | not_established |
| Реальные записи / сравнение ложных STOP | not_run |
| Android / controlled walking | not_run |
| Доставка / promotion / ordinary camera wiring | shadow / false / false |

Следующий физический шаг — собрать и проверить рекордер на Mac, выполнить
одну согласованную неподвижную калибровочную запись и проверить её импорт.
План из 72 записей остаётся подготовленным протоколом. Поведенческий сбор
и сравнение с RGB/MiDaS начинаются только после отдельного физического producer
gate; при невозможности полного подтверждения этап заканчивается описанием
недостающих измерений, как предусмотрено согласованным планом.

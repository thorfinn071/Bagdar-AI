# Первая запись: подготовка без iPhone и Mac

На 18 октября 2026 года iPhone и Mac недоступны — по сообщению пользователя.
Съёмка, сборка Xcode, проверка камеры на устройстве и физическая калибровка имеют
статус `not_run`. Подготовлена и проверена программная обработка будущей первой
неподвижной записи. Это ещё не устранение ложных STOP.

## Что готово сейчас

`tool/research_capture/first_capture_trial.py` объединяет существующую проверку
целостности ARKit-записи, ввод независимо измеренного положения камеры,
геометрический анализ Dart и итоговый отчёт. Оригинальная запись остаётся
неизменной. Каждый запуск требует новый каталог вывода.

Готовый пакет оператора находится в
`scratch/first-capture-trial-20261018/final-kit/`: `START_HERE.md`,
`placement.template.json`, `operator-checks.json` и `trial.json`.
Все фактические измерения в шаблоне пустые; проверки устройства — `not_run`.
Другой пакет можно создать из корня проекта:

```powershell
python tool/research_capture/first_capture_trial.py prepare --output C:\BagdarCaptures\first-trial-kit
```

`prepare` возвращает 0 за подготовку файлов, при этом
`physicalGatePassed=false`. Команда не проверяет наличие оборудования.

## Когда оборудование появится

1. На Mac собрать рекордер и выполнить native-тесты по
   `tool/research_capture/README_ARKIT.md`; сохранить исходники, build log,
   source ID и результат тестов. Этот шаг здесь не выполнен.
2. В согласованной частной комнате разметить систему координат и исходный
   объём: ширина 0,9 м, headroom 1,85 м, расстояние вперёд 0,2–3,5 м,
   допустимый подъём/спуск пола 0,05 м. В геометрическом контракте верх тела
   включает подъём пола: 1,90 м. TTL остаётся 100 мс.
3. Независимо измерить положение и ориентацию камеры относительно пола и
   разметки. Зафиксировать способ измерения и его допуски. Данные глубины
   проверяемого телефона не служат эталоном этих же измерений.
4. Оставаясь на месте, записать до 10 секунд, нажать Stop, проверить остановку
   камеры и экспортировать именно выбранный `capture-ID`. Проверки отказа
   разрешений, background/interruption и повторного Start описаны в README.
5. Хранить оригинальный ZIP и извлечённые данные вне любого Git-репозитория.
   Импортировать с ID, показанным рекордером. Все пути вывода должны быть новыми.

```powershell
python tool/research_capture/arkit_capture.py C:\BagdarCaptures\capture.zip --expected-recording-id capture-ID --extract-to C:\BagdarCaptures\capture-ID --output C:\BagdarCaptures\capture-ID-audit.json

python tool/research_capture/first_capture_trial.py evaluate C:\BagdarCaptures\capture-ID --recording-id capture-ID --output C:\BagdarCaptures\trial-without-placement
```

Без положения камеры команда проверяет запись, но оставляет охват непроверенным:
`awaiting_independent_placement`. Успешная проверка хешей подтверждает файловую
целостность и соответствие выбранному ID; она не удостоверяет происхождение
записи, установленный бинарник или точность датчика.

## Как заполнить положение камеры

Скопировать `placement.template.json` в отдельный файл. Нельзя заменять
неизмеренные значения нулями. Используются следующие поля:

| Поле | Значение |
| --- | --- |
| `recordingId` | Точный ID выбранной записи |
| `captureManifestSha256` | `manifestSha256` из её audit JSON |
| `frameId` | ID кадра в `frames.jsonl`, к которому относится измеренное положение |
| `cameraOriginWalkingM` | `[вправо, вперёд, вверх]`, метры от размеченного walking origin на полу до оптического центра |
| `originToleranceM` | Три положительных допуска измерения координат, в метрах |
| `yawRightDeg` | Поворот оптической оси вправо от направления движения |
| `pitchDownDeg` | Наклон оптической оси вниз от горизонта |
| `rollClockwiseDeg` | Поворот native image axes по часовой стрелке при взгляде вдоль оптической оси вперёд |
| `angleToleranceDeg` | Положительный допуск измерения углов, в градусах |
| `referenceMethod` | Конкретный независимый способ измерения, инструменты и привязка к кадру |
| `independentReferenceAssertion` | `true` только после фактического независимого измерения |

Углы относятся к исходному растру камеры **right/down/forward**, а не к повороту
экрана или портретному UI. При нулевых углах native image right направлен вправо,
down — вниз, forward — вдоль пути. Положительный roll поворачивает right к down.
Порядок преобразований зафиксирован в коде:
`Rz(-yaw) × Rx(-pitch) × imageToWalkingLevel × Rz(roll)`.
ARKit camera right/up/back преобразуется отдельно. Измерение выбранного кадра
привязывает ARKit world к walking origin; корректность tracking физически
не подтверждается этой операцией.

Неоднозначное или недоступное измерение оставляется незаполненным: анализ без
placement допустим. Введённые допуски сохраняются, но пока не распространяются
в гарантированные границы охвата: `placementUncertaintyPropagated=false`.

После заполнения:

```powershell
python tool/research_capture/first_capture_trial.py evaluate C:\BagdarCaptures\capture-ID --recording-id capture-ID --placement C:\BagdarCaptures\placement.json --output C:\BagdarCaptures\trial-with-placement
```

Нужен доступный Dart из Flutter SDK. При необходимости указать абсолютный путь
через `--dart-executable`. Код выхода **2** означает, что отчёт создан, а
физический допуск не пройден; **1** — ошибка входных данных или анализа.

## Как читать результат

Итоговый каталог содержит `audit.json`, необязательный `placement-profile.json`,
`analysis/feasibility.json`, `analysis/frames.jsonl`, `analysis/coverage.svg`,
логи анализатора, `trial.json` и `report.md`.

| Статус | Вывод |
| --- | --- |
| `awaiting_independent_placement` | Не введено независимо измеренное положение; охват не оценён |
| `nominal_geometry_inconclusive` | Допустимых геометрических кадров недостаточно для положительного вывода |
| `nominal_geometry_gap_observed` | В одном или нескольких допустимых кадрах номинальная геометрия не охватывает весь запрос |
| `nominal_geometry_possible_physical_evidence_missing` | Во всех кадрах запрос номинально попадает в поле зрения; физические свидетельства всё ещё отсутствуют |

Просроченная, недопущенная или отсутствующая геометрия не даёт положительного
результата. Пробел в номинальной геометрии — основание проверить измерения и
схему наблюдения до поведенческого сбора. Он не доказывает универсальную
невозможность решения. Попадание в поле зрения не подтверждает отсутствие
препятствий, полный наблюдаемый объём или границы погрешности.

Во всех исходах `physicalGatePassed=false`, `runtimeComparisonAllowed=false`,
`behaviouralCollectionAllowed=false`, `promotionAllowed=false`,
`ordinaryCameraWired=false`; доставка остаётся `shadow`.
`captureToDecisionMs=null`, проверка на именованном устройстве и controlled
walking — `not_run`. Текущий адаптер выдаёт только центральные depth samples
и не может сформировать `measuredClear`.

До отдельного подтверждения метрических границ ошибок, RGB/depth alignment,
пола, связи native clocks, whole-pixel first-return bounds и полного актуального
покрытия тела/пола сбор 72 поведенческих записей остаётся закрыт.
Пороговые значения, TTL и runtime в этой работе не менялись.

## Проверка программы на Windows

- 76 Python-тестов исследовательского capture tooling прошли с включёнными
  `BAGDAR_TEST_ARKIT_DART=1` и `BAGDAR_TEST_FIRST_CAPTURE_DART=1`; среди них
  14 новых тестов первого испытания. Проверены реальные запуски Python → Dart
  без placement, с синтетическим placement и через CLI, включая exit 2.
- 14 тестов `test/recorded_rgbd_test.dart` прошли последовательно.
- Анализатор Flutter для источника записей, Dart-команды и этих тестов:
  `No issues found`.
- Синтетические тесты проверяют оси и знаки углов, независимость от ARKit world
  origin, привязку ID/manifest/frame, отказ при пустых измерениях и неизвестной
  давности, запрет самовольного допуска, сохранность исходных файлов и запрет
  перезаписи результатов. Они не являются физическими измерениями.

Логи, пакет и проверка сохранности исходного среза находятся в
`scratch/first-capture-trial-20261018/`. Итоговая квитанция —
`delivery-verification.json`.

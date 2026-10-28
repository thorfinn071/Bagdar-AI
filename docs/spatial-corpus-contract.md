# Bagdar Spatial Safety — replay corpus contract

Дата: 2026-09-19

Версия schema: 1

Scope: phone-independent relative spatial safety software path

Этот контракт задаёт воспроизводимый вход для `GuidanceStateMachine` и
`AlertArbiter`. Он проверяет planner/alert-инварианты на именованном корпусе,
но не заменяет RGB/depth model parity, Android device tests или controlled
walking.

## Структура

```text
test/fixtures/spatial_safety/
  manifest.json
  scenes/<scene-id>/
    frames.jsonl
    annotations.json
```

`manifest.json` фиксирует:

- `schemaVersion`, `corpusId`, deterministic `seed` и `generatorId`;
- source, license, consent class и public/private handling;
- camera mount/parameters и `coordinateMode`;
- `modelId`, SHA-256 model identity и `preprocessId`;
- scene tags, annotation revision, coverage и `requiredForRc`;
- SHA-256 каждого `frames.jsonl` и `annotations.json`;
- отсутствующие external/private corpora отдельно от встроенного corpus.

Пути в manifest только относительные и не могут выходить из corpus root.
Неизвестная schema, небезопасный путь, дублирующийся scene ID, неверный hash,
model/preprocess mismatch или неверная annotation revision являются ошибкой.

## Frame schema

Каждая строка `frames.jsonl` — один объект:

```text
schemaVersion
sceneId
frameIndex
capturedOffsetMs
evaluateOffsetMs
validUntilOffsetMs
sessionGeneration
frameId
modelId / modelHash / preprocessId
orientationValid / sensingHealthy / userMoving
sectors.left / sectors.forward / sectors.right
```

Каждый sector содержит только нормализованные значения `0..1`:

```text
observedFraction
occupancyProbability
traversabilityProbability
dropProbability
movingThreatRisk
unknownProbability
confidence
sourceMask
hazardIds
lastObservedOffsetMs
```

Relative corpus не содержит и не выводит метры. Время вычисляется от
`timelineOriginUtc` из manifest, поэтому результат не зависит от wall clock.
Frame indexes идут непрерывно от нуля; runner сортирует scenes и frames перед
выполнением.

## Annotation schema

`annotations.json` содержит `sceneId`, `annotationRevision`, опциональное
начальное информационное сообщение и непересекающиеся timeline-интервалы.
Каждый интервал задаёт:

- `expectedActions`;
- `forbiddenActions`;
- `expectedHealth`;
- `expectedAlertEvents`;
- `expectedShadowDirections`;
- ожидаемый `interruptCurrent`.

Каждый replay frame обязан попасть ровно в один интервал. Несовпадение action,
health, alert или shadow direction делает scenario `fail`. Попадание в
`forbiddenActions` дополнительно увеличивает `unsafeGuidanceCount`.

## Статусы и RC semantics

- `pass`: все файлы, identity, timeline и инварианты совпали;
- `fail`: schema/hash/identity либо фактическое поведение не совпало;
- `partial`: доступная часть прошла, но coverage не полон;
- `missing`: scene-файлы отсутствуют.

В developer mode `partial` и `missing` видны в отчёте, но блокируют запуск
только фактические `fail` и safety-метрики. В `releaseCandidate` любой
`partial`/`missing` для `requiredForRc: true` является failure. External/private
corpus блокирует RC только при собственном `requiredForRc: true`.

Главные software gates:

```text
unsafeGuidanceCount == 0
guidanceIntoUnknownCount == 0
staleActionEmissionCount == 0
```

RC этого корпуса означает только прохождение перечисленных software fixtures.
Он не переводит `GenericObstacleMode` из `shadow` и не подтверждает телефонную
производительность или безопасность реальной ходьбы.

## Воспроизводимость

Сгенерировать встроенный procedural corpus:

```powershell
dart run tool/build_spatial_corpus.dart
```

Проверить, что committed fixtures точно соответствуют generator:

```powershell
dart run tool/build_spatial_corpus.dart --check
```

Получить developer report:

```powershell
dart run tool/report_spatial_metrics.dart
```

Запустить строгий software RC gate:

```powershell
dart run tool/report_spatial_metrics.dart --rc
```

Сохранить машинный отчёт:

```powershell
dart run tool/report_spatial_metrics.dart --rc `
  --output docs/_baseline_logs/spatial_replay_rc.json
```

Unit gate:

```powershell
flutter test --no-pub test/spatial_replay_harness_test.dart
```

## Текущий corpus v1

Встроены девять procedural scenarios:

- центральное препятствие;
- неизвестный центр в покое и движении;
- центр заблокирован, слева наблюдаемый shadow-коридор;
- центр заблокирован, обе стороны неизвестны;
- stale depth во время движения;
- критическая угроза во время информационной речи;
- появление препятствия после безопасного внутреннего состояния.
- три стабильных ревизии перед shadow-предложением направления.

`blender-egocentric-v1`, `blender-temporal-v2` и `blender-context-v3` существуют
как обязательные публичные синтетические external corpora. Их manifest hashes
проверяются встроенным RC; каждый timeline запускается отдельно через
`test/spatial_replay_harness_test.dart` и `tool/verify_core.ps1`.
RGB/depth/mask assets и class-compatible COCO-аннотации `v3` описаны в
`docs/blender-context-evaluation-2026-09-23.md`. External planner replay
использует заданные сектора; отдельный shadow replay строит геометрию из
raycast depth. Consent-controlled private camera corpus пока `missing` и
`requiredForRc: false`.

## Privacy boundary

Публичные Blender RGB/depth/mask кадры синтетические и не содержат людей из
реального мира, речи, координат пользователя или персональных данных.
Будущие raw camera/depth записи по умолчанию остаются вне Git; manifest хранит
только разрешенные metadata/hashes. Private corpus требует отдельного явного
consent и политики хранения.

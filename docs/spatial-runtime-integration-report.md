# Bagdar Spatial Safety — Runtime Integration Report

Дата: 2026-09-20

Статус: software/shadow integration Этапа 7 выполнена. Android device и
assistive promotion gates не пройдены.

## Runtime boundary

Добавлен отдельный `SpatialSafetyRuntime`, который является единственным
владельцем цепочки:

```text
accepted depth observation
  -> generic geometry adapter
  -> LocalSceneModel
  -> RelativePolarGrid
  -> GuidanceStateMachine
  -> AlertArbiter
  -> shadow-only suppression + bounded trace
```

Runtime повторно проверяет `sessionGeneration`, монотонный `frameId` и TTL
observation. Cross-session, повторный, out-of-order и stale результат не может
изменить scene или попасть в arbiter.

Каждая primary planner action перед admission копируется с
`SafetyActionDelivery.shadow`. Поэтому текущая интеграция исполняет настоящий
planner/arbiter path, но не отправляет его в UI, TTS, earcon или haptics.
Перевод в assistive нельзя включить setting-ом; он относится к Этапу 10.

## Camera ownership

В Core остаётся один RGB camera owner: `CameraController` в
`camera_screen.dart`. Lifecycle controller только перезапускает тот же
controller и не создаёт вторую камеру.

Существующий `HardwareDepthSession` открывает независимую ARCore session и не
может доказать alignment с Flutter RGB frame. Поэтому production factory не
запускает его. Даже на hardware-capable tier выбирается aligned
`midas-small-ncnn` из того же Flutter frame. Независимая ARCore session скрыта
из Core UI и допускается только в Research build при явном opt-in.

Это безопасный defer, а не доказательство ARCore integration. Shared-camera
owner, RGB/depth timestamp parity и named-device evidence остаются blocked.

## Runtime wiring

- `CameraViewModel` создаёт один runtime и общий с `AlertManager`
  `AlertArbiter`.
- Новый camera session очищает scene, planner hysteresis, arbiter queue,
  cooldown identities и trace.
- `DepthPipelineController` очищает accepted observation в начале каждого
  анализа, поэтому failure не может повторно подать предыдущий frame.
- Controller публикует только текущие `ObservationHeader`, detection и
  generic tracks.
- Отсутствующий provider/result превращается в explicit unknown scene.
  Движущийся пользователь получает shadow `stopNow`, остановившийся —
  conservative hold; пустой scene не считается свободным.
- Старый direct generic-obstacle alert loop удалён из camera runtime.
- Старый YOLO-gap corridor engine остаётся недоступен Core через
  `BuildProfile`; он не влияет на Core UI/TTS.
- Каждый результат пишет privacy-safe `spatial_runtime_trace`: identity,
  scene revision, planner state/action/rule, shadow delivery и arbiter reason.
  Trace ограничен 128 записями.

## Exit gate Этапа 7

| Gate | Evidence | Статус |
| --- | --- | --- |
| один user-action authority | один runtime planner/arbiter path; старый Core corridor path выключен | pass shadow-only |
| старый corridor engine не влияет на Core UI/TTS | compile-time `BuildProfile` gate | pass |
| provider failure не блокирует UI thread | failure становится bounded synchronous unknown-scene update; model inference остаётся async | pass software-only |
| latest-frame-wins | controller ownership guards + runtime session/frame/TTL guards | pass software-only |
| no silent empty scene | provider-loss regression выдаёт unknown + conservative action | pass |
| полный action trace | bounded privacy-safe runtime diagnostic map | pass |
| один production camera owner | independent ARCore blocked in Core; aligned NCNN consumes Flutter frame | pass by safe defer |
| новый planner остаётся shadow | forced delivery conversion + arbiter suppression test | pass |
| shared ARCore RGB/depth owner | реализации и device parity нет | blocked |
| Android UI-thread/runtime evidence | physical device run не выполнялся | blocked |

## Выполненные проверки

```text
dart analyze
No issues found!

flutter test
984 passed, 1 skipped, 0 failed

dart run tool/build_spatial_corpus.dart --check
Spatial corpus matches generator (19 files).

dart run tool/report_spatial_metrics.dart --rc \
  --output docs/_baseline_logs/spatial_replay_rc.json
passed: true; all six replay counters: 0

flutter build apk --debug
Built build/app/outputs/flutter-apk/app-debug.apk
```

APK build подтверждает Android compilation/package assembly, но не camera
ownership, UI-thread responsiveness, hardware depth, latency или lifecycle на
физическом устройстве.

## Непройденные границы

- runtime integration не закрывает Stage 6 correctness/license gates;
- NCNN native/reference fixture отсутствует;
- нет recorded detector/candidate downstream replay;
- нет physical Android lifecycle, ANR, latency, memory, thermal и audio-route
  evidence;
- `genericObstacleMode` не повышается из `shadow`;
- controlled walking и accessibility walkthrough не выполнялись.

Следующий допустимый этап без телефона — только подготовка research contracts
и статических Android/build проверок. Этапы 9–10 требуют named device и
контролируемой пользовательской валидации.

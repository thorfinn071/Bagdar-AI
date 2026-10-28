# Bagdar Spatial Safety — Sonar Research Report

Дата: 2026-09-20

Статус: software contracts Этапа 8 реализованы; shadow corpus и
named-device repeatability не пройдены. Sonar не подключён к risk и не создаёт
пользовательские предупреждения.

## Безопасная граница

Sonar runtime лениво создаётся только при разрешённом Research profile; Core
не обращается к singleton при init/dispose. Удалён прежний путь
`single correlation peak -> ExternalHazardEvent -> AlertManager`.
`SonarService` теперь может публиковать только `SonarShadowObservation` для
privacy-safe telemetry. Observation не попадает в `LocalSceneModel`, planner,
arbiter, UI, TTS, earcon или haptics.

Нативный прототип пока не реализует direct-path cancellation,
multipath-aware peak selection и проверку допустимого акустического уровня.
Поэтому `SonarPlugin` имеет закрытый DSP safety gate и не включает физический
chirp output. Это намеренный fail-closed блок, а не готовая sonar-функция.

## Capability contract

Перед захватом microphone/speaker lease Dart запрашивает нативный отчёт и
требует одновременно:

- Android `SUPPORT_MIC_NEAR_ULTRASOUND == true`;
- Android `SUPPORT_SPEAKER_NEAR_ULTRASOUND == true`;
- Android `SUPPORT_AUDIO_SOURCE_UNPROCESSED == true`;
- 48 kHz capture feasibility;
- известные input и output route fingerprints.

Отсутствующее, пустое, частично `unknown` или malformed значение отклоняется.
После admission native prototype использует только
`MediaRecorder.AudioSource.UNPROCESSED`; fallback на обработанный `MIC` не
разрешён.

## Calibration contract

Версия schema — 1. Admission требует не менее восьми chirps, фактический
sample rate не ниже 48 kHz, известный route fingerprint, подтверждённые
direct-path cancellation, multipath selection и acoustic-level validation, а
также конечный неотрицательный repeatability MAD не более 0.12 m.

Текущий native prototype при снятии build-time safety block смог бы сообщить
все три незавершённых evidence-флага как `false` и MAD `-1`; Dart обязательно
отклонит такой отчёт, остановит native session и освободит leases.

## Multi-chirp consensus

Один range estimate никогда не создаёт observation. Bounded window требует
пять последовательных chirps, минимум четыре usable confidence samples,
spread не более 0.25 m и возраст не более двух секунд. Результат использует
median range/confidence и всегда помечен `delivery: shadow`.

Out-of-order timestamp очищает накопленный consensus. Неконечные, выходящие
за 0–3 m или malformed confidence samples отклоняются до окна.

## Interruption и ownership

- microphone и speaker выдаются через `SensorSessionCoordinator`;
- headphones и active call останавливают native session;
- TTS audio-route interruption переводит активный/calibrating sonar в
  `paused` и освобождает оба lease;
- неуспешный voice start возвращает Research setting в `false`, поэтому UI не
  заявляет, что sonar работает;
- native loop всегда сбрасывает `running` при выходе.

## Exit gate Этапа 8

| Gate | Evidence | Статус |
| --- | --- | --- |
| capability checks | строгий Dart admission + Android property/route report | pass software/build |
| calibration contract | versioned fail-closed report и unit tests | pass contract-only |
| multi-chirp confidence | bounded median/spread/age/order tests | pass synthetic |
| shadow corpus | synchronized sonar + vision recordings отсутствуют | blocked: device/data |
| named-device repeatability | phone model/orientation/restart/route matrix отсутствует | blocked: physical phone |
| ноль direct user alerts | hazard callback и AlertManager wiring удалены; shadow-only API | pass static/test |
| acceptable acoustic level | native output заблокирован до измерений | safe defer |
| direct-path/multipath DSP | реализация отсутствует, admission невозможен | blocked |

## Проверки

```text
dart analyze
No issues found!

flutter test test/sonar_service_test.dart
20 passed, 0 failed

flutter test
995 passed, 1 skipped, 0 failed

flutter build apk --debug
Built build/app/outputs/flutter-apk/app-debug.apk
```

APK build проверяет Kotlin/Dart compilation и package assembly. Он не является
доказательством near-ultrasound capability, акустической безопасности,
repeatability, latency или пригодности sonar на телефоне.

## Что требуется для продолжения

1. Реализовать и отдельно верифицировать direct-path cancellation,
   loopback-latency calibration и multipath-aware peak selection.
2. Определить безопасный SPL/duty cycle и проверить слышимость chirp с
   пользователями; только после этого снимать native output block.
3. Записать consent-controlled shadow corpus рядом с vision ground truth для
   стены, стекла, ткани, человека, открытого прохода, угла, улицы,
   транспортного шума и разных чехлов.
4. Измерить false-near, missed-near и repeatability по named phone model,
   orientation, restart и route change.

До этих evidence sonar нельзя подключать к risk, использовать для доказательства
свободного corridor или повышать из Research/shadow.

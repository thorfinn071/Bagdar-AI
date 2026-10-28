# Core health contract

Date: 2026-09-12  
Implementation: `lib/core/core_health.dart`, `lib/core/core_health_coordinator.dart`

UI, TTS, and tests consume one [CoreHealthSnapshot]. Widgets must not
recompute “ready” from YOLO or TTS alone.

## Required for operational

- camera permission, session, and image stream **available**
- at least one of TTS or haptics usable
- fall detection not **unavailable** (gyro-missing is **degraded**)

YOLO, NCNN, GPS, and compass are **not** sufficient for a global ready
event. Missing YOLO degrades moving-threat awareness only.

## Run states

| State | Meaning |
| --- | --- |
| starting | required vision or output still initializing |
| operational | required vision + an output channel |
| degraded | vision up but geometry, audio, haptics, or fall is impaired |
| unavailable | camera/stream dead or no output channel |
| recovering | announced once when returning from degraded/unavailable |
| stopped | session ended |

Invalid depth is never a healthy empty scene: map it to
`genericGeometry` degraded/unavailable.

## Announcements

Edge-triggered, 30 s cooldown per key. Operational (`system_ready`) waits
until required camera components have left `initializing`. Recovery
(`core_health_recovered`) is announced once after a degraded/unavailable
episode.

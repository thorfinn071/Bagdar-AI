# Bagdar Core — scope and permission matrix

Date: 2026-09-12  
Authority: `docs/bagdar-core-hardening-master-plan.md`  
Compile-time switch: `--dart-define=BAGDAR_RESEARCH=true` plus Android flavor
`research`. Default flavor is **`core`**.

A persisted preference cannot enable a feature that `CoreFeaturePolicy`
excludes.

---

## Profiles

| Profile | Artifact | Deferred experiments |
| --- | --- | --- |
| `BuildProfile.core` | default debug/release candidate | not initialized, not shown, no extra permissions |
| `BuildProfile.research` | `--flavor research` internal builds | source remains; runtime may start behind flags |

Generic obstacle alerts stay in **`shadow`**. `assistive` is rejected until
`docs/generic-obstacle-validation-report.md` names a build.

---

## Core Safety runtime (always compiled)

Startup/capability health, camera session, orientation, generic geometry
(shadow), surface/drop heuristics, YOLO enrichment, tracking, alert
arbitration, TTS/haptic/earcon, thermal/memory/battery, manual SOS, fall
countdown, minimal settings/onboarding, privacy-preserving diagnostics.

Pedestrian navigation **code** may exist; it is not a Core Safety release
gate and must not suppress hazard alerts.

---

## Deferred (source preserved, Core runtime inactive)

| Feature | `CoreFeature` | Core permission impact |
| --- | --- | --- |
| Bazaar / livestock | `bazaarLivestock` | none |
| Acoustic world model | `acousticWorldModel` | would use mic; not started |
| VLM scene Q&A | `vlmSceneQa` | none |
| Sonar | `sonar` | `MODIFY_AUDIO_SETTINGS` research-only |
| BLE mesh | `bleMesh` | BLE permissions research-only |
| Smart-cane OSCP | `smartCane` | BLE research-only |
| Indoor trail | `indoorTrail` | none |
| Charging jobs | `chargingJobs` | none |
| Payment SMS | `paymentSms` | `RECEIVE_SMS` research-only |
| Phone-abandoned | `phoneAbandoned` | none |
| Object memory/finder | `objectMemoryFinder` | none |
| Public transit / GTFS | `publicTransit` | none |
| Experimental winter | `experimentalWinter` | none |
| Scene narration | `sceneNarration` | developer-only in research |
| Paddle OCR init | `paddleOcr` | no production models packaged |
| Kazakh stack v2 | `kazakhStackV2` | placeholder ZIPs only |
| Local ASR adaptation | `localAsrAdaptation` | none |

---

## Core permission set

Approved:

- `CAMERA`, `RECORD_AUDIO` (voice commands)
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CAMERA`,
  `FOREGROUND_SERVICE_LOCATION` (user-started keep-alive / future nav)
- `POST_NOTIFICATIONS`, `WAKE_LOCK`, `VIBRATE`
- `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` (SOS; not background)
- `SEND_SMS` (emergency path; Play declaration still required at release)
- `HIGH_SAMPLING_RATE_SENSORS`, `ACCESS_WIFI_STATE`

Excluded from Core (stripped if plugins merge them):

- `RECEIVE_SMS`
- BLE `BLUETOOTH*`
- `ACCESS_BACKGROUND_LOCATION`
- `MODIFY_AUDIO_SETTINGS`

`SEND_SMS` remains because Core SOS uses it. Opening `sms:` / `tel:` is not
delivery success (Phase 8).

---

## Background location decision

Core Safety does **not** need `ACCESS_BACKGROUND_LOCATION`. Location for SOS
is taken while the user (or fall countdown) is already in the app. Pedestrian
navigation, when later enabled, must use a **user-started** foreground
service rather than background location.

---

## Product claims

See README “Verified current state” vs “Planned / research”. Do not claim
Android 5, estimated FPS, shipped Kazakh ASR/OCR models, or a pilot-city
map until those artifacts exist.

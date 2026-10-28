# 🔴 Bagdar AI — Critical Safety & Architecture Audit

**Auditor Role**: Senior QA Engineer / System Architect / CV Safety Specialist  
**Date**: 2026-06-03  
**Codebase**: 132 Dart source files · ~1,382 KB · 71 services · 58 test files  
**Verdict**: The project demonstrates exceptional engineering maturity for a solo-developed assistive app. It has already addressed many failure modes that industry-grade products miss. The vulnerabilities below are what separates *good* from *life-safe*.

---

## Executive Summary

| Vector | Critical | High | Medium | Low |
|--------|:--------:|:----:|:------:|:---:|
| 1. Dynamic Obstacle Handling | 2 | 2 | 1 | 0 |
| 2. Out-of-Distribution Objects | 1 | 2 | 1 | 0 |
| 3. Alert Fatigue & UX Overload | 0 | 2 | 2 | 1 |
| 4. Feedback Synchronization | 1 | 1 | 2 | 0 |
| 5. Systemic & Environmental | 1 | 2 | 2 | 1 |
| **Total** | **5** | **9** | **8** | **2** |

> [!CAUTION]
> 5 CRITICAL vulnerabilities identified. In a mobility-assist context, each of these can directly cause user injury under specific, non-exotic real-world conditions.

---

## Vector 1: Dynamic Obstacle Handling Logic

### V1.1 — End-to-End Latency Floor is 280–440ms on Target Hardware

**Criticality**: 🔴 CRITICAL

**Analysis**: The pipeline is serial: `frame capture → quality guard → blur check → motion prealert → YOLO inference (~45ms mid-range) → tracker update → alert_manager.processFrame → TTS enqueue → TTS engine speak`. On a Snapdragon 680 target device:

- YOLO inference: ~45ms
- Detection interval floor: 140ms ([constants.dart:338](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart#L338) `kTargetFrameBudgetMs`)  
- TTS enqueue → first audio: 50–150ms (platform TTS engine latency)
- Total: **235–340ms best case**

Under thermal throttling (`kThermalPenaltyHotMs = 80ms`, `kThermalPenaltyCriticalMs = 120ms`), detection interval jumps to 220–260ms. With TTS queue, worst-case alert delivery is **400–500ms**.

**Failure Scenario**: User walks at 1.4 m/s (normal pace). A cyclist enters the frame from the side at 5 m/s (18 km/h). In 400ms the cyclist covers 2.0m. If initial detection distance is 3m, the user has only **0.2 seconds** (1 frame) of warning after the alert sounds. At a fast walk of 1.8 m/s, collision occurs before the second frame even processes.

**Technical Solution**:  
1. The synthetic event camera (`motion_prealert.dart`) partially mitigates this — it runs on *every* frame regardless of YOLO cadence and fires within ~20ms. This is well-designed. **But** it only covers peripheral intrusion, not center-frame sudden appearances (e.g., door opening directly ahead).
2. Add a **center-corridor motion delta trigger** to `MotionPreAlert` that fires for significant luma changes in the central 40% of the frame, independent of YOLO cadence. This catches opening doors, sudden pedestrian step-outs, and vehicles turning toward the user.
3. Consider a dedicated **ultra-fast tiny model** (e.g., person/vehicle-only detector at 160×160, ~8ms) that runs on alternating frames when YOLO is skipped.

---

### V1.2 — No Explicit User Velocity Gating in the Detection Cadence

**Criticality**: 🔴 CRITICAL  

**Analysis**: The `PerformanceThrottler` tracks `MotionState` (stationary/walking/unstable) and adjusts cadence — stationary users get longer intervals (battery saving), unstable users get shorter intervals. However, there is **no distinction between slow walking and running**. The `MotionState` enum has only three values: `stationary`, `walking`, `unstable` ([fall_detector.dart:7](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/fall_detector.dart#L7)).

The `unstable` state triggers at a combined accel/gyro score of ≥0.45 ([fall_detector.dart:410](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/fall_detector.dart#L410)), which can mean either "running" or "being jostled on a bus." There is no `running` state.

**Failure Scenario**: A visually impaired user is running (perhaps crossing a street after hearing the walk signal). At 3 m/s, the reaction distance window halves compared to walking. The system processes at the same cadence, and the 140ms detection interval means obstacles detected at 3m give only ~0.5s of warning after TTS delivery — below human auditory reaction time (~0.3s) + physical stopping distance (~0.5m at 3m/s).

**Technical Solution**:
1. Split `MotionState.unstable` into `running` (sustained high accel score >0.6, low gyro jitter) and `jostled` (high gyro + high accel).
2. When `running` is detected: **halve** the detection interval, clamp `_detectInterval` to `max(60ms, infTime)`, and preemptively flush the TTS queue of info-priority messages to keep the audio channel clear for critical alerts.
3. Announce "You are running, please slow down for safety" once per running episode as a verbal cue.

---

### V1.3 — Multi-Obstacle Prioritization is Implicit, Not Formalized

**Criticality**: 🟡 HIGH

**Analysis**: The alert prioritization across simultaneous obstacles is distributed across multiple files with no single decision matrix:

- [alert_manager.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera/alert_manager.dart) handles per-track cooldowns and distance-based priority
- [alert_filter.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/utils/alert_filter.dart) deduplicates by category with minimum gaps (1.5s between any two alerts)
- [constants.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart) defines `kClassWeight` where truck=2.0 > bus=1.8 > car=1.6 > person=1.0

The system correctly uses `SpeechPriority.critical` with barge semantics (interrupt current speech). **However**, when a car approaches from the left AND a pothole is detected ahead simultaneously, the ordering depends on which code path executes first in `_onFrame`. The `processFrame` call for YOLO tracks happens before `_processDepthAnalysis` for depth hazards — meaning the depth-detected pothole alert may arrive 100–200ms after the vehicle alert, potentially causing the user to step *into* the pothole while avoiding the car.

**Failure Scenario**: Busy intersection. Car approaching from the left (YOLO detects, AlertManager fires "car approaching left" as critical). User reflexively steps right. 200ms later, depth analysis fires "stairs down ahead" as critical — but user is already mid-step.

**Technical Solution**:
1. Implement a **synchronous hazard fusion point** that collects both YOLO-track alerts AND depth hazards in the same frame cycle before any TTS emission.
2. When multiple critical hazards exist, synthesize a single compound alert: "Stop! Car left, drop-off ahead" — using the most dangerous combined escape direction.
3. Add a `kMultiHazardHoldMs = 50` delay on first critical alert to check if a second critical arrives from the depth pipeline before committing to TTS.

---

### V1.4 — Vehicle Approach Detection Has a Calibration Dependency

**Criticality**: 🟡 HIGH

**Analysis**: The approaching-vehicle detection uses bounding-box area rate of change ([constants.dart:151](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart#L151) `kVehApproachAreaRateT = 0.22`) and height rate (`kVehApproachHeightRateT = 0.14`). These thresholds assume a specific focal length / resolution relationship. The focal length is loaded from calibration (`_isCalibrated = Settings.instance.isCalibrated`), but:

1. If the user skips calibration (or uses a phone with an unusual lens), the focal-length heuristic distance estimation ([distance_utils.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/utils/distance_utils.dart)) will be wrong.
2. The approach rate is measured in normalized bbox area per second. Different camera resolutions produce different absolute pixel areas, but normalization should handle this. **However**, the depth cross-check (MiDaS metric validation) is only available when NCNN is loaded — on devices where NCNN permanently disables itself after 3 failures, approach rate is the **only** distance signal.

**Failure Scenario**: User has a budget phone where NCNN failed and self-disabled. Focal length is uncalibrated. A truck approaches from behind a parked car — the bbox starts small and grows slowly (occluded approach). Area rate stays below 0.22 threshold until the truck is 3m away, at which point it explodes past the threshold. Alert fires, but the truck is already too close.

**Technical Solution**:
1. Lower `kVehApproachAreaRateT` to 0.15 when `_isCalibrated == false` and depth provider is unavailable. Accept higher false-positive rate in exchange for earlier warnings.
2. Implement a secondary **absolute bbox-size danger threshold**: any vehicle bbox occupying >40% of frame area triggers immediate critical alert regardless of approach rate.
3. The existing `sizeSanity` escalation at 55–75% frame area ([README](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L43)) is too late — by that point, the vehicle is essentially on top of the user. Lower to **35%** for vehicles specifically.

---

### V1.5 — Tracker `kTrackMaxAge = 6` Frames Can Cause Ghost Tracks at Low FPS

**Criticality**: 🟠 MEDIUM

**Analysis**: At 8 FPS (mid-range target), `kTrackMaxAge = 6` means a track survives 750ms without a matched detection. This is adequate. But under thermal throttling where effective FPS drops to 3-4 ([heartbeat tick warning at effFps < 3.0](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera_screen.dart#L825)), 6 frames = 1.5–2 seconds. A track that lost its match (object left frame, or was occluded) continues to exist and potentially generate alerts for a non-existent obstacle.

**Failure Scenario**: A car drives past the user and exits the frame. At 3 FPS, the ghost track persists for 2 seconds, during which the Kalman predictor continues moving the bbox. If the predicted position drifts toward center-frame, `AlertManager` may fire a spurious "car approaching" critical alert, causing the user to panic-stop in the middle of a crosswalk.

**Technical Solution**:
1. Make `kTrackMaxAge` time-based rather than frame-based: `max(6, (1000 / effectiveFps).ceil())` capped at 8 frames, so at 3 FPS the track dies after 6 frames = 2 seconds, but at 15 FPS it dies after 6 frames = 400ms.
2. Add a prediction-confidence decay: after 3 frames of no match, reduce the track's effective confidence by 50% per frame, preventing high-confidence ghost alerts.

---

## Vector 2: Out-of-Distribution (Non-COCO) Objects

### V2.1 — Curb/Step-Down Detection Depends Entirely on MiDaS Depth Quality

**Criticality**: 🔴 CRITICAL

**Analysis**: The YOLO model detects 80 COCO classes. Curbs, potholes, steps, and drop-offs are **not** in COCO. The system correctly addresses this via `GroundPlaneAnalyzer` ([ground_plane_analyzer.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/utils/ground_plane_analyzer.dart) — 47KB, the largest utility file), which uses RANSAC-based plane fitting on the MiDaS depth map to detect deviations from the estimated ground surface.

This is architecturally sound. **However**, the entire ground hazard detection chain is disabled when:
- MiDaS NCNN fails 3 times and permanently self-disables
- Thermal severity reaches `critical` — MiDaS is fully disabled
- Memory pressure is `critical` — MiDaS is disabled
- Weather gate marks visibility as `degraded` — some depth features disabled (though stairs-down is preserved with higher threshold ≥0.715)

When MiDaS is disabled, the user has **zero** curb/pothole/step detection. The focal-length heuristic fallback only provides distance estimation for YOLO-detected objects — it cannot detect ground-plane anomalies at all.

**Failure Scenario**: User walks on a hot summer day (38°C). After 20 minutes, battery temperature hits 43°C → thermal severity goes critical → MiDaS disabled. User approaches a 15cm curb at a crosswalk. No YOLO detection (curbs aren't in COCO). No depth analysis (MiDaS is off). No haptic warning. User trips, falls face-first into traffic.

**Technical Solution**:
1. **Never fully disable stairs-down/curb detection even at critical thermal**. Instead, run MiDaS at drastically reduced cadence (every 3–5 seconds) with the 320×320 thermal-fallback model specifically for ground-plane-only analysis. Skip all other depth features.
2. Implement a **thermal burst specifically for depth safety**: at critical thermal, process 1 MiDaS frame every 5 seconds, focused on the bottom 40% of the frame (ground zone only). This costs ~30ms of additional thermal load per 5s cycle — negligible compared to the safety gain.
3. Add a TTS warning: "Ground hazard detection reduced due to device temperature" at critical thermal entry. The existing "reduced mode" announcement is generic.
4. The winter mode already preserves stairs-down detection under weather degradation ([README:280](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L280)) — extend this same principle to thermal throttling.

---

### V2.2 — Glass Door/Transparent Surface Detection is Heuristic-Only

**Criticality**: 🟡 HIGH

**Analysis**: The README mentions "Glass door detection — Luma variance analysis identifies transparent surfaces that depth models misinterpret as open space." This is in [frame_quality_guard.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera/frame_quality_guard.dart) (12KB). The approach analyzes luma variance to find regions where the depth map shows "far" but the visual texture suggests a surface.

The fundamental problem: glass is specifically designed to be visually transparent. Luma variance analysis works for *dirty* glass, glass with stickers, or glass reflecting strong ambient light. Clean, anti-reflective glass in modern buildings produces almost no luma variance signal.

**Failure Scenario**: User approaches a floor-to-ceiling glass wall in a modern shopping mall. Glass is clean, anti-reflective coated. Luma variance is near-zero (you see the outdoor scene through the glass clearly). MiDaS depth map shows "far" (interpreting the scene behind the glass as open space). No detection fires. User walks into glass wall face-first.

**Technical Solution**:
1. **Cross-check depth discontinuities with IMU**: if the depth map shows the path ahead is "open" for 10+ meters but the user's step count (from `StepService`) shows they've walked 5m since the last similar reading with no depth change, flag an "impossible depth" anomaly.
2. **Train a small binary glass-detector** on a custom dataset (glass/not-glass patches) — even a 50KB MobileNet-v3 patch classifier can catch ~80% of glass panels. Run it only in indoor mode at low cadence.
3. In the interim, when indoor mode is active and the forward path shows uniformly "far" depth with no YOLO detections, emit a cautionary "Path appears clear but indoor accuracy may be limited" alert at info priority, once per 30s.

---

### V2.3 — Overhead/Neck-Height Hazards Have No Dedicated Detection

**Criticality**: 🟡 HIGH

**Analysis**: Low-hanging branches, wires, awnings, and clotheslines are not in COCO. The `GroundPlaneAnalyzer` specifically handles *ground* deviations (potholes, steps, slopes). The depth map can theoretically show a close-range object at head height, but the current depth hazard classification focuses on the lower portion of the frame.

The `BazaarLivestockService` applies a priority boost for "hanging obstacles" ([bazaar_livestock_service.dart:19](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/bazaar_livestock_service.dart#L19)), but this only applies to COCO labels (`umbrella`, `handbag`, `suitcase`) which are not actual overhead hazards.

The `OrientationService` tracks device pitch and adjusts the depth-map crop-top fraction to match viewing angle ([README:96](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L96)), which helps see *higher* in the scene. But there's no dedicated "overhead obstacle in walking corridor" classifier.

**Failure Scenario**: User walks under scaffolding. A horizontal pole extends at 170cm height. User is 175cm tall. YOLO doesn't detect it (not a COCO class). MiDaS shows a depth discontinuity in the upper frame but the `GroundPlaneAnalyzer` ignores upper-frame anomalies (it focuses on ground plane). User hits the pole with their face.

**Technical Solution**:
1. Add an **overhead corridor scan** in `GroundPlaneAnalyzer`: analyze the top 20–40% of the depth map for objects at close range (MiDaS score > 0.5) that span horizontally across the walking corridor. These are overhead obstructions.
2. The RANSAC ground plane establishes the expected vertical geometry. Any close-range depth response *above* the expected head height (estimated from the ground plane + 1.8m) is either an overhead obstacle or a ceiling. If it's closer than 2m in metric depth, flag it.
3. Output a dedicated `DepthHazardType.overheadObstacle` with high urgency and a specific TTS string: "Low overhead ahead."

---

### V2.4 — Silent Failure Mode When All Detection Fails

**Criticality**: 🟠 MEDIUM

**Analysis**: The system has multiple overlapping detection modalities: YOLO, MiDaS depth, motion prealert, acoustic world model, traffic light analyzer. If YOLO is loaded but produces no detections, and MiDaS is disabled or degraded, the user gets silence — which they interpret as "path is clear."

The `MisalignmentWatchdog` partially addresses this — it detects "no detections while walking with the camera pointed correctly" and warns the user. The depth-pipeline confidence monitoring gates on `depth-blind` status before escalating warnings. This is well-designed.

**However**, the watchdog has enter/exit hysteresis and a sustained-interval before firing. In the gap between "no detections" and "watchdog fires," there's a window of silence that the user trusts.

**Failure Scenario**: User walks through a construction zone with novel obstacles (concrete barriers, rebar stacks, equipment). YOLO detects nothing (not COCO classes). MiDaS is on but the RANSAC plane fit fails because the ground is cluttered (the plane-fit failure status triggers a `depth_degraded` TTS, which helps). But if the ground plane *succeeds* (flat surface with obstacles ON it), those above-ground novel objects produce no hazard score — they're at the correct depth for the ground plane.

**Technical Solution**:
1. Implement a **depth variance corridor check**: in the forward walking corridor (center 40%, bottom 60%), if the standard deviation of MiDaS depth values exceeds a threshold but no YOLO labels match, flag an "unclassified obstruction" at warning priority.
2. Fuse the sonar prototype (when available) as a validation signal: if sonar reports range < 2m but YOLO has no detections and MiDaS reports "clear," something is definitely wrong. Emit a critical alert.
3. The existing `NearMissBuffer` ([near_miss_buffer.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/near_miss_buffer.dart)) could log these "depth anomaly without YOLO match" events for offline analysis to iteratively improve detection.

---

## Vector 3: Alert Fatigue & UX Overload

### V3.1 — Person-Alert Spam in Dense Urban Environments

**Criticality**: 🟡 HIGH

**Analysis**: The crowd grouping system was significantly improved (per [constants.dart:187-195](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart#L187) noting "Safety audit 2.4" fix). The `kCrowdAlertCooldown` is 10 seconds, and individual person alerts are suppressed in favor of grouped "crowd ahead, N persons" alerts.

However, `kPersonCooldown = 15 seconds` applies per-track, not per-person. In a dense urban area with high pedestrian turnover (e.g., near a bus stop), the tracker continuously creates new person tracks as people enter/exit the frame. Each NEW person track is a separate cooldown counter.

The `AlertFilter` has a minimum gap of 1.5s between any two alerts. But with 10 new people entering the frame in 30 seconds (busy sidewalk), the system can still produce:
- Crowd alert at t=0
- Crowd alert at t=10 (cooldown expired)
- Individual "person close" critical at t=11.5 (someone steps very close)
- Crowd alert at t=21.5

That's ~4 person-related alerts in 30 seconds on a busy sidewalk, which is acceptable — **but** it competes with vehicle and hazard alerts for the TTS channel. The three-tier priority queue correctly handles this (critical preempts), but the user is hearing person-related chatter *between* safety-critical alerts.

**Failure Scenario**: User walks along a busy commercial street. Every 10s: "group ahead, 5 persons." Every 3-8s: vehicle/hazard alerts interleaved. The constant audio stream becomes white noise. User stops paying attention. A quiet electric scooter approaches from behind — the acoustic world model detects it, but the user has habituated to constant alerts and doesn't react.

**Technical Solution**:
1. Implement **adaptive verbosity** that monitors TTS queue depth and alert frequency. If >3 alerts fire in any 10s window, automatically escalate to "minimal" verbosity (critical-only + vehicles) for the next 20s, then decay back.
2. Add a "high-traffic mode" that triggers automatically when `personTracksInFrame > 5` for >10 consecutive detections: suppress all person-distance alerts, keep only crowd-count updates at 20s intervals, and reserve the TTS channel exclusively for vehicles and depth hazards.
3. The verbosity control ([README:66](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L66)) exists as a user setting — make it **adaptive** in addition to manual.

---

### V3.2 — Static Object Filtering Lacks Trajectory Analysis

**Criticality**: 🟡 HIGH

**Analysis**: The `kStaticObjectCooldown = 10 seconds` ([constants.dart:211](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart#L211)) provides a cooldown for static objects. The tracker marks tracks with `approaching = false` for stationary objects. **But** the definition of "static" is relative to the camera frame, not relative to the user's trajectory.

A wall parallel to the user's walking direction stays at constant distance and position in the frame — it looks "approaching" at constant rate as the user moves. A parked car on the left side of a sidewalk produces a track with slowly growing bbox area (due to approaching by walking past), which may trigger the approach threshold.

The `DecisionEngine` ([decision_engine.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/utils/decision_engine.dart) — 2.5KB) performs corridor width analysis, but it's focused on finding the best navigation direction, not on suppressing alerts for parallel obstacles.

**Failure Scenario**: User walks along a narrow alley with walls on both sides. The parked cars, walls, and fences continuously produce "obstacle left," "obstacle right" warnings as the user walks past them. Even with cooldowns, the constant low-priority chatter prevents the user from hearing the bicycle approaching from behind.

**Technical Solution**:
1. Add **lateral-offset stability tracking** to each track: if a track's X-center displacement per second is < 5px/s for >3 frames while the user is walking, classify it as "lateral static" and suppress info/warning alerts entirely.
2. For tracks that maintain a consistent offset from frame center across >5 frames, reduce their effective `kClassWeight` by 50% for alert priority calculations.
3. Track the user's heading via compass data and cross-reference with object track velocity vectors: objects moving perpendicular to heading at consistent speed are being walked past, not approaching.

---

### V3.3 — Alert Decay for Persistent Objects Partially Implemented

**Criticality**: 🟠 MEDIUM

**Analysis**: The cooldown system uses fixed intervals (`kCriticalCooldown = 800ms`, `kWarningCooldown = 3s`, `kInfoCooldown = 10s`). Once the cooldown expires, the same alert fires again if the object is still present. There is a `kSustainedHazardEscalationDistanceFraction = 0.70` that *escalates* alerts when objects get closer, and the `kCriticalRepeatCooldownDefault = 4000ms` and `kCriticalRepeatCooldownSafety = 2000ms` provide repeat-fire spacing.

The escalation logic is correct — objects getting closer get more urgent alerts. **But** objects that are close and *remaining at constant distance* (e.g., user stops near a pole) continue to fire alerts at the cooldown cadence indefinitely. There is no exponential backoff or intensity decay for objects that haven't changed their threat level.

**Failure Scenario**: User stops at a bus stop next to a bench (COCO class, detected by YOLO). Bench is at "close" distance and stays there. Every 3 seconds: "bench on the right." For 10 minutes. User turns off the app.

**Technical Solution**:
1. Implement **alert fatigue decay**: for any track that has been announced ≥3 times at the same distance category with no escalation, double the cooldown for each subsequent repeat. After 5 repeats, suppress to info-priority earcon only.
2. Reset the decay when: (a) distance category changes, (b) user starts walking after being stationary, or (c) the object's track ID changes (new object).
3. The existing `ObjectMemory` could flag "already known" objects and suppress re-alerting entirely for remembered items.

---

### V3.4 — Earcon Volume Independence Not Guaranteed Across Devices

**Criticality**: 🟠 MEDIUM

**Analysis**: The `EarconService` ([earcon_service.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/earcon_service.dart) — 10KB) plays non-speech audio signals. The README states earcon volume is "independently adjustable." However, earcons are played via `audioplayers` while TTS goes through the platform TTS engine. These use different audio channels/streams.

On Android, `audioplayers` typically uses the MUSIC stream while TTS uses the NOTIFICATION or ALARM stream. Volume levels for these streams are independently controlled by the user's Android volume buttons. If the user lowers music volume but keeps notification volume high (or vice versa), earcons and TTS will be mismatched.

**Failure Scenario**: User adjusts phone volume — lowers media volume to minimum (earcons become inaudible) but TTS stays at normal volume. The heartbeat earcon (the "I'm alive" signal in pitch-black mode) never reaches the user. User assumes the app has crashed and walks without assistance.

**Technical Solution**:
1. Route earcons through the same audio stream as TTS (NOTIFICATION or ALARM) using `AudioSession` configuration.
2. The existing `audio_session` dependency ([pubspec.yaml:27](file:///c:/Users/Nurik/Desktop/bagdar_app/pubspec.yaml#L27)) can be configured to request a consistent audio session category.
3. On startup, check if the active audio stream volume is below 30% and warn the user via haptic pattern + TTS (on the still-audible channel): "App volume is low, please increase volume for safety."

---

### V3.5 — Guide Dog Mode Suppression May Be Over-Broad

**Criticality**: 🟢 LOW

**Analysis**: Guide dog mode "suppresses alerts that conflict with trained guide dog behavior" ([README:65](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L65)). Without seeing the exact suppression list, the risk is that guide dog mode suppresses *too many* alerts — including ones that the dog might miss (overhead obstacles, potholes covered by water, traffic lights if the dog is trained to cross on handler command).

**Failure Scenario**: User in guide dog mode approaches a construction zone with overhead scaffolding. Guide dog navigates around ground obstacles but doesn't detect the 170cm horizontal bar. App suppresses the alert because "the dog handles obstacle avoidance." User hits the bar.

**Technical Solution**:
1. In guide dog mode, only suppress: pedestrian-distance alerts, static-object-position alerts, "path clear" announcements, and crowd grouping alerts.
2. **Never** suppress: depth hazards (potholes, steps, curbs), overhead obstacles, approaching vehicles, traffic light state, glass door warnings, acoustic events (horns, sirens).
3. Create a documented "guide dog mode alert matrix" listing exactly which alert categories are suppressed.

---

## Vector 4: Feedback Synchronization & Execution

### V4.1 — TTS Engine Hang is a Single Point of Complete Silence

**Criticality**: 🔴 CRITICAL

**Analysis**: The TTS stall watchdog ([constants.dart:287-300](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/models/constants.dart#L287-L300)) fires after 4 seconds if a single utterance hangs. When it fires, it:
1. Plays an earcon (`Earcon.cameraBlocked`)
2. Fires a distinctive haptic pattern (`kHapticTtsStallPattern`)
3. Pings the native watchdog channel

The `onTtsUnavailable` callback re-initializes the TTS engine ([camera_screen.dart:698-705](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera_screen.dart#L698-L705)). This is well-designed.

**However**, during the TTS re-initialization period (which can take 1–5 seconds on Android), the system continues detecting hazards, enqueuing alerts, but **cannot speak any of them**. If a critical hazard appears during TTS recovery, the user gets only haptics and earcons — which may not be sufficient to convey the specific hazard type and direction.

**Failure Scenario**: TTS engine hangs (known Android bug with Samsung TTS engine on One UI 5+). Watchdog fires at +4s. Re-init starts at +4s. Car approaches from the left at +5s. Haptic fires (generic vibration), earcon fires (generic "approaching" sound). But the user doesn't know the direction or type — it could be a person, a bicycle, or a car. They hesitate. Car arrives at +6.5s. Re-init completes at +7s.

**Technical Solution**:
1. During TTS unavailability, use **directional haptic patterns** to convey position: left-biased pattern (long-short) for left hazards, right-biased (short-long) for right hazards, as already partially defined in `kHapticCloseLeft/Center/Right`. These are currently only used with TTS, not as TTS *replacements*.
2. Add an **earcon vocabulary** for critical TTS-down mode: different earcon tones for "vehicle", "obstacle", "step", "stop." Even 4 distinct tones vastly improve information density over a single generic earcon.
3. Pre-cache the most critical TTS utterances ("Stop!", "Car left!", "Car right!", "Step down!") as audio files. When TTS is unavailable, play these cached audio files directly via `audioplayers` — bypassing the TTS engine entirely.

---

### V4.2 — Bluetooth Audio Disconnect Handling

**Criticality**: 🟡 HIGH

**Analysis**: The `onAudioRouteInterrupted` and `onAudioRouteResumed` callbacks in [camera_screen.dart:673-682](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera_screen.dart#L673-L682) handle audio route changes. When interrupted, it plays an earcon; when resumed, it speaks "Audio resumed" at info priority.

The `audio_session` package provides route-change notifications. When Bluetooth disconnects, Android routes audio to the device speaker. **But** the route-change notification is asynchronous, and the first few hundred milliseconds of speech after Bluetooth disconnect may be lost to the transition.

The `preClaimAudioFocus` call in camera init ([camera_screen.dart:1249](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera_screen.dart#L1249)) helps with initial setup. However, there's no explicit handling for the scenario where Bluetooth reconnects *during* a critical utterance.

**Failure Scenario**: User is wearing Bluetooth earbuds. Right earbud falls out (disconnects). Android switches to speaker. During the 200ms transition, a critical "Stop! Car!" alert fires but its first 200ms (the "Stop!" part) is lost. User hears "...Car!" from the speaker but misses the urgency cue.

**Technical Solution**:
1. On audio route change, insert a **50ms silence** before the next TTS utterance to let the audio path stabilize.
2. If a critical alert was in-progress or enqueued during the route change, **replay it** after the route stabilizes — even if it means interrupting the "Audio resumed" message.
3. Track the exact time of route change. For any critical utterance that was mid-play during the change, re-enqueue it at critical priority with `barge: true`.

---

### V4.3 — Haptic Pattern Discriminability Under Cognitive Load

**Criticality**: 🟠 MEDIUM

**Analysis**: The haptic vocabulary is well-differentiated in the constants:

| Pattern | Use |
|---------|-----|
| `[0, 40, 30, 80]` | Far left |
| `[0, 60, 30, 60]` | Far center |
| `[0, 80, 30, 40]` | Far right |
| `[0, 60, 30, 140]` | Close left |
| `[0, 100, 30, 100]` | Close center |
| `[0, 140, 30, 60]` | Close right |
| `[0, 80, 30, 80, 30, 80]` | Critical cooldown |
| `[0, 300, 120, 300, 120, 300]` | Depth hazard critical |
| `[0, 220, 100, 220, 100, 220]` | TTS stall |

The close/far left/right patterns differ only in the relative duration of the first and last pulse (e.g., 60ms vs 140ms for close-left, 140ms vs 60ms for close-right). Under stress and with phone in pocket (damped vibrations), these differences are extremely difficult to perceive. Research shows humans can reliably distinguish vibration patterns that differ by >100ms in total duration or >3x in intensity.

**Failure Scenario**: User in a noisy environment with phone in coat pocket. Receives `[0, 60, 30, 140]` (close left) — perceives it as "short-pause-long." Next, receives `[0, 140, 30, 60]` (close right) — perceives it as "long-pause-short." The amplitude difference between 60ms and 140ms pulses is subtle through fabric. User misidentifies direction 30–40% of the time.

**Technical Solution**:
1. **Increase the asymmetry**: close-left = `[0, 40, 60, 200]`, close-right = `[0, 200, 60, 40]`. The 5:1 ratio is much more distinguishable than the current ~2.3:1.
2. Add **repetition encoding**: left = single pulse, center = double pulse, right = triple pulse. This is universally distinguishable regardless of amplitude perception.
3. Use the `intensities` parameter (already used for TTS stall pattern) to add intensity variation: left = ramp up, right = ramp down, center = constant high.

---

### V4.4 — Concurrent Inference and Audio/Haptic Jitter on Single-Core Budget Devices

**Criticality**: 🟠 MEDIUM

**Analysis**: YOLO inference runs in the Dart isolate's main thread (via `flutter_vision` plugin, which calls native code but blocks the calling Dart async method until completion). MiDaS runs via NCNN through FFI (also blocking). TTS runs via the platform engine (separate process). Haptics run via method channel (async, quick).

On a Snapdragon 680 (Cortex-A73 × 2 + Cortex-A53 × 6), YOLO + MiDaS can saturate both big cores. The TTS engine runs in a system process (separate scheduling), so it shouldn't stutter from inference load. **However**, the Dart event loop (which handles TTS completion callbacks, haptic dispatch, and UI updates) runs on a single thread and can be delayed by long synchronous operations.

The `_onFrame` method is `async` but the YOLO call `_models.vision.yoloOnFrame(...)` blocks the Dart execution until the native inference returns. During this ~45ms window, no other Dart callbacks (including TTS completion events, haptic timing callbacks, or audio route change notifications) can execute.

**Failure Scenario**: YOLO inference takes 45ms. During this window, TTS finishes an utterance and posts a completion callback. The callback waits 45ms in the event loop queue. The next critical alert, which was supposed to barge-interrupt the finished utterance, is delayed by 45ms. On a fast-approaching bicycle (10 m/s), 45ms = 0.45m of additional travel.

**Technical Solution**:
1. This is inherent to the Flutter/Dart execution model and cannot be fully eliminated without moving inference to a background isolate. The current architecture handles it well given the constraints.
2. **Mitigation**: Use a `Completer`-based yield mechanism: after YOLO inference returns, yield the event loop (`await Future.delayed(Duration.zero)`) before proceeding to tracker update and alert processing. This allows queued TTS callbacks to execute between inference and alert generation.
3. For mission-critical alerts, use the haptic channel (which is hardware-timed by the Android Vibrator service, independent of Dart event loop) as the *primary* instant-response channel, not TTS.

---

## Vector 5: Systemic & Environmental Risks

### V5.1 — Thermal Throttling Can Create a 30-Second Detection Gap

**Criticality**: 🔴 CRITICAL

**Analysis**: The thermal severity system has 4 tiers with committed dwell:

| Tier | Battery Temp | Detection Penalty | MiDaS Status |
|------|-------------|-------------------|--------------|
| Normal | <37°C | +0ms | Full |
| Warm | 37–40°C | +30ms | Full |
| Hot | 40–43°C | +80ms | 320×320 model | 
| Critical | >43°C | +120ms | **Disabled** |

The `kThermalCommitDwell = 60 seconds` prevents oscillation between tiers. **This means once the system enters critical thermal, it stays there for at least 60 seconds before it can recover**, even if the temperature drops.

During critical thermal: detection interval is ~260ms, MiDaS is fully off (no ground hazards), and the thermal burst scheduling processes 3 frames then idles for a full cycle. The "full cycle" idle period means there can be a window of ~1–2 seconds with zero processing.

The `kDetectIntervalSafetyCeilingMs = 500ms` caps the detection interval, ensuring at least 2 FPS even under maximum throttling.

**Failure Scenario**: Hot summer afternoon, 35°C ambient. User has been walking for 25 minutes. Phone battery temp reaches 43°C → critical thermal. MiDaS off. Detection drops to ~2-4 FPS with burst/idle cycling. During a 1.5-second idle burst gap, a child runs out from behind a parked car. The synthetic event camera catches it (it runs on every frame from the camera stream), but YOLO can't classify it. The depth-based ground hazard detection (pothole ahead of the child) is invisible because MiDaS is off.

**Technical Solution**:
1. Reduce `kThermalCommitDwell` to 30 seconds for *recovery* from critical → hot (keep 60s for *entering* critical to prevent oscillation).
2. At critical thermal, maintain the synthetic event camera at full frame rate (it's computationally cheap — grid differencing on the Y-plane only) and route its outputs at higher priority: any motion intrusion during critical thermal is auto-promoted to warning priority, not just earcon.
3. Never disable the **safety ceiling** detection: even at critical thermal, run YOLO at 500ms intervals (2 FPS) using the 320×320 model. The 320×320 model inference is ~30% faster, so thermal impact is reduced.
4. Add a proactive TTS warning at warm tier entry: "Device warming up. Please move to shade if possible. Detection will reduce at higher temperatures."

---

### V5.2 — Night/Low-Light Performance Degrades Silently

**Criticality**: 🟡 HIGH

**Analysis**: The `WeatherGate` ([weather_gate.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/services/weather_gate.dart) — 2KB) uses luminosity variance + average brightness to classify visibility degradation. This triggers a TTS warning and raises detection thresholds.

YOLOv8n INT8 was trained on COCO, which contains primarily daytime images. The published mAP drops 30–50% under low-light conditions. The quantization to INT8 further amplifies this degradation because the reduced dynamic range is less able to resolve low-contrast features.

At night or in headlight glare, the model produces:
- **False negatives**: pedestrians wearing dark clothing become invisible
- **False positives**: headlights and streetlights may be detected as "traffic lights"
- **Reduced confidence**: detections that exist come in at lower confidence, causing them to be filtered by `kClassMinConf` thresholds

The traffic light analyzer is particularly vulnerable: at night, the three-zone brightness analysis may be confused by headlights illuminating the traffic light housing, or by LED billboards in the background.

**Failure Scenario**: User walks along a poorly-lit street at dusk. Person wearing dark clothing is 4m ahead. YOLO confidence for "person" is 0.35 — below the `kClassMinConf['person'] = 0.40` threshold. Detection is silently dropped. MiDaS depth shows a slight anomaly but not enough to trigger ground-plane deviation (person is standing, not a hole). No alert. User collides with the person.

**Technical Solution**:
1. When `WeatherGate` detects low light, **lower** `kClassMinConf` for safety-critical classes by 0.05–0.10: `person → 0.32`, `car → 0.35`, etc. Accept higher false-positive rate in exchange for fewer missed detections.
2. Increase the motion prealert sensitivity in low light: lower `kEventDiffThreshold` from 18 to 12, since even small brightness differences in a dark scene are more significant.
3. Announce to the user: "Low light detected. Detection accuracy is reduced. Please use additional caution." — the existing `weather_low_vis` alert partially covers this.
4. In the traffic light analyzer, when `lastLowVisibility == true`, require **+2 additional stable frames** before confirming a green light, to prevent headlight false positives.

---

### V5.3 — NCNN Permanent Self-Disable is Irreversible Across Sessions

**Criticality**: 🟡 HIGH

**Analysis**: Per [README:224](file:///c:/Users/Nurik/Desktop/bagdar_app/README.md#L224): "After 3 inference failures within 5 minutes, the provider permanently disables itself and persists the decision (no further init attempts in future sessions)."

This is a reasonable safety measure to prevent crash loops on incompatible hardware. **However**, the failures might be transient (e.g., caused by memory pressure from another app, a one-time GPU driver crash, or a firmware update that later fixes the issue). Once NCNN is permanently disabled, the user loses ground-hazard detection forever (falling back to focal-length heuristic, which cannot detect curbs/potholes).

**Failure Scenario**: User installs Bagdar on a compatible phone. During first use, a heavy game is running in the background, consuming GPU memory. NCNN fails 3 times (GPU resource contention). NCNN permanently self-disables. User uninstalls the game and reboots the phone — GPU is now fully available, but NCNN is disabled forever. User now has zero ground-hazard detection on capable hardware.

**Technical Solution**:
1. Replace "permanent disable" with **exponential backoff retry**: after 3 failures, wait 1 hour before retrying. After next failure, wait 24 hours. After 5 consecutive retry-set failures, wait 7 days. Never fully disable.
2. Add a voice command: "reset depth engine" that clears the persisted disable flag and retries NCNN initialization. Announce the command in the "depth unavailable" TTS warning.
3. On major OS version change (detected via stored `Build.VERSION.SDK_INT`), clear the disable flag automatically — firmware updates may fix GPU issues.

---

### V5.4 — Battery Drain Creates a Progressive Safety Degradation

**Criticality**: 🟠 MEDIUM

**Analysis**: The `BatteryMonitor` has four throttle levels: normal, moderate (reduces cadence), aggressive (degrades MiDaS), critical (maximizes intervals). At ~15% battery drain/hour on mid-range hardware, a full charge gives ~6-7 hours of use.

**However**, the user doesn't receive proactive time-remaining estimates. They may not realize that at 20% battery, the system has already entered aggressive mode with degraded depth detection. The `batteryAnnounce` setting provides messages at tier transitions, but these are reactive, not predictive.

**Failure Scenario**: User starts a 2-hour walk at 100% battery. At 90 minutes in, battery is at 20%. Depth detection is degraded. At 110 minutes, battery is at 10%. Critical mode — minimal detection. User is now in an unfamiliar area with barely functional obstacle detection and may not realize the progressive degradation until they trip.

**Technical Solution**:
1. At 50% battery, announce estimated remaining active time: "Battery at 50%. Approximately X hours of active detection remaining."
2. At 30% battery, suggest reducing walk duration and recommend enabling pitch-black mode for power savings.
3. At 15% battery, proactively announce: "Low battery. Ground hazard detection is reduced. Please use a cane or seek assistance."

---

### V5.5 — Heavy Rain / Fog Performance Has Limited Empirical Validation

**Criticality**: 🟠 MEDIUM

**Analysis**: The weather gate detects degraded visibility and adjusts thresholds. The stairs-down detection is preserved even under weather degradation (higher MiDaS score threshold ≥0.715 required). Winter mode promotes slippery surfaces to critical. This is well-engineered.

**However**, heavy rain introduces two specific camera challenges:
1. **Water droplets on the lens**: The `FrameQualityGuard` has droplet detection and lens smear detection, which is excellent.
2. **Rain streaks in the frame**: The motion prealert system uses luma-grid differencing. Rain streaks produce consistent luma changes across the entire frame, potentially triggering `kEventGlobalPanFrac = 0.60` global-pan suppression. But if rain is less than 60% of the grid, individual rain-streak blobs may trigger false motion intrusion alerts.

**Failure Scenario**: Light rain (not heavy enough to trigger weather gate degradation). Rain drops produce scattered luma changes in the motion prealert grid. System fires multiple "movement detected" alerts from rain. User habituates. A real cyclist passes through the rain at high speed — alert is dismissed by the user as "more rain noise."

**Technical Solution**:
1. Add rain-specific blob filtering in `MotionPreAlert`: rain streaks are characteristically vertical, thin (aspect ratio >3:1), and short-lived (1-2 frames). Filter blobs matching this signature.
2. When `WeatherGate` detects rain (via its luminosity variance classifier), raise `kEventMinPersistFrames` from 3 to 5 — requiring moving objects to persist longer before alerting, which filters transient rain artifacts while still catching real objects.
3. Correlate motion prealert events with acoustic world model: if motion is detected but no acoustic vehicle/bicycle signature accompanies it, demote from warning to earcon-only.

---

### V5.6 — Camera Auto-Exposure Transitions Create Detection Blackouts

**Criticality**: 🟢 LOW

**Analysis**: The `FrameQualityGuard` has AE (auto-exposure) transition detection with suppression logic ([frame_quality_guard.dart](file:///c:/Users/Nurik/Desktop/bagdar_app/lib/camera/frame_quality_guard.dart)). During AE transitions (e.g., walking from indoor to outdoor), the guard freezes the pipeline to prevent false detections from improperly exposed frames.

This is correctly handled — during AE freeze, the motion prealert still runs to catch fast-moving objects. The guard fires an earcon to notify the user. This is good design.

The risk is minor: AE transitions on budget cameras can take 500ms–1.5s, during which only motion (not YOLO) detection is active. The motion prealert covers the most dangerous fast-moving cases.

**Failure Scenario**: User walks from a dark indoor corridor to bright outdoor sunshine. AE transition takes 1.2s. A stationary bollard is 1.5m ahead in the bright area. No YOLO detection (pipeline frozen). No motion detection (bollard is static). User walks into the bollard. 

This is partially mitigated by the fact that the user has been moving at walking speed, so 1.2s = 1.7m traveled, and the bollard was likely visible in the last pre-transition frame if the indoor exposure was adequate.

**Technical Solution**:
1. During AE transitions, run the **last successfully exposed frame** through YOLO one more time with augmented brightness — even a poorly-exposed frame can catch large obstacles.
2. Preserve the last pre-transition depth map and continue using it for ground-hazard detection during the transition, with a "stale data" flag that reduces confidence scores by 30%.
3. Current implementation is already reasonable — this is a minor risk.

---

## Summary & Priority Action Items

> [!IMPORTANT]
> **Top 5 actions ranked by safety impact per engineering effort:**

| Priority | Item | Vector | Fix Effort |
|:--------:|------|--------|:----------:|
| 1 | V2.1: Never fully disable ground-hazard depth at critical thermal | V2 | 2 days |
| 2 | V1.2: Add `running` motion state with halved detection interval | V1 | 1 day |
| 3 | V4.1: Pre-cache critical audio files as TTS-engine-independent fallback | V4 | 2 days |
| 4 | V5.3: Replace NCNN permanent self-disable with exponential backoff | V5 | 3 hours |
| 5 | V1.1: Add center-corridor motion delta to MotionPreAlert | V1 | 1 day |

---

> [!NOTE]
> **Recognition**: This codebase shows evidence of multiple prior safety audit cycles (the code comments reference "Safety audit 2.4", "Safety audit 3.6", "Safety audit 6.1", "Safety audit 7.2"). The `GroundPlaneAnalyzer`, thermal burst scheduling, weather gate with stairs-down preservation, fall detector with phone-drop suppression, crowd grouping, TTS stall watchdog, misalignment watchdog, phone abandoned detector, and winter mode all demonstrate serious safety-first engineering. The vulnerabilities identified here are edge cases that require deliberate adversarial thinking to find — they are not evidence of negligence but of the inherent difficulty of building a life-safety system on consumer hardware.

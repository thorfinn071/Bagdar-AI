# Bagdar Core — Phase 0 baseline (evidence freeze)

Recorded: **2026-09-12**  
Workspace: `C:\Users\Nurik\Desktop\bagdar_app`  
HEAD: `5775f5e56aecb1bca1ffe8fffcb5fd42a701620a` (`main`, ahead of `origin/main` by 3)  
Safety behavior added in this phase: **none** (inspection and evidence only)

Command transcripts (untracked working files, not product claims):

- `docs/_baseline_logs/dart_analyze.txt`
- `docs/_baseline_logs/flutter_test.txt`
- `docs/_baseline_logs/focused_groups.txt`
- `docs/_baseline_logs/flutter_build_apk_debug.txt`

---

## 1. Toolchain and host

| Item | Value |
| --- | --- |
| Flutter | 3.41.4 stable (`ff37bef603`, 2026-03-03) |
| Dart | 3.11.1 |
| Engine | `e4b8dca3f1` / hash `99578ad0355da00edb26301c874a3c250a5716f5` |
| Android compileSdk / targetSdk | 36 (Flutter Gradle extension defaults) |
| minSdk | **30** (`android/app/build.gradle.kts`) |
| applicationId / namespace | `com.example.bagdar` |
| NDK | Flutter `ndkVersion` 28.2.13676358 |
| Host | Windows 11 25H2 (`10.0.26200.0`) |
| `adb` | `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe` |
| Attached devices | **none** (`adb devices -l` listed no devices) |

Release `signingConfig` is still `signingConfigs.getByName("debug")`.

---

## 2. Git status (short) at freeze

Dirty worktree was recorded and not modified by Phase 0. Unrelated user
material (presentations, Blender, City/FBX, grant docs) was not reverted.

Modified (tracked):

```text
 M android/app/src/main/cpp/bagdar_depth_ncnn.cpp
 D bagdar_samsung_sft.pptx
 M lib/camera/alert_manager.dart
 M lib/camera/depth_pipeline_controller.dart
 M lib/camera/fall_countdown_controller.dart
 M lib/camera_screen.dart
 M lib/models/strings.dart
 M lib/services/depth_provider.dart
 M lib/services/fall_detector.dart
 M lib/services/misalignment_watchdog.dart
 M lib/services/model_service.dart
 M lib/services/ncnn_depth_bridge.dart
 M lib/services/ncnn_depth_provider.dart
 M lib/services/settings_service.dart
 M lib/services/tts_service.dart
 M lib/utils/alert_filter.dart
 M lib/utils/performance_throttler.dart
 M lib/viewmodels/camera_view_model.dart
 M lib/widgets/status_panel.dart
 M presentation/bagdar_presentation.pptx
 M pubspec.lock
 M pubspec.yaml
 M test/core_logic_test.dart
 M test/fall_countdown_dazed_test.dart
 M test/features_test.dart
 M test/hardware_depth_aggressive_close_test.dart
 M test/performance_throttler_test.dart
 M test/safety_audit_fixes_test.dart
 M test/scene_narrator_test.dart
 M test/strings_completeness_test.dart
```

Untracked of product relevance includes the generic-obstacle stack, Core
hardening docs, integration tests, and new unit tests. Unrelated untracked
user files (City/, VisionGuide/, bagdar_blend/, pptx, docx) remain present.

`git diff --check`: **passed** (exit 0).

---

## 3. Packaged assets (factual sizes)

| Asset | Bytes | Status |
| --- | ---: | --- |
| `assets/yolov8n_int8.tflite` | 3,382,280 | real YOLOv8n INT8 |
| `assets/labels.txt` | 699 | present |
| `assets/midas_small.ncnn.bin` | 33,209,056 | real MiDaS NCNN |
| `assets/midas_small.ncnn.param` | 16,926 | present |
| `assets/espeak-ng-data/` | README 1,449 | documentation only |
| `assets/paddle_ocr/` | README 3,088 | documentation only |
| `assets/lang_packs/rhvoice-kk-aigul.zip` | 135 | placeholder-sized |
| `assets/lang_packs/vosk-kk.zip` | 138 | placeholder-sized |
| Flutter asset maps / GTFS / pilot-city package | — | **not listed in `pubspec.yaml`** |

Do not advertise Kazakh ASR/OCR/espeak or a city map package as shipped.

---

## 4. Commands

### `dart analyze`

Analyzer process exit **2**. No compile errors. **9 issues** (4 warnings, 5 infos):

| Severity | Code | File |
| --- | --- | --- |
| WARNING | unused_import | `test/alert_filter_same_category_critical_test.dart` |
| WARNING | unused_import | `test/fall_countdown_cancel_test.dart` |
| WARNING | unused_import | `test/harness/scenario_harness_test.dart` (×2) |
| INFO | avoid_print | `scratch/create_dummy_zips.dart` (×2) |
| INFO | unnecessary_import | `test/harness/scenario_harness_test.dart` |
| INFO | prefer_const_declarations | `test/motion_prealert_ae_test.dart` (×2) |

Owner: **Phase 2**. No `lib/` compile errors.

### `flutter test --no-pub`

**832 passed, 1 skipped, 4 failed.** Exit 1.

Skipped:

- `test/ncnn_reference_correlation_test.dart` — `missing fixture: test/fixtures/ncnn_contract/reference_outputs.json`
- Owner: **Phase 5** (corpus) / release-candidate gate. Ordinary developer suite may skip; RC must fail.

Failed — all in `test/misalignment_watchdog_test.dart` (Safety follow-up H6):

1. `sustained-but-short (<10s) misalignment fires neither haptic nor speech`  
   Expected `shouldAnnounce == false`; actual `true` (`no announce before 10 s threshold`).
2. `empty-scene path: 25 s sustained misalignment with depth OK fires haptic but NOT verbal`  
   Expected 0 verbal; actual 1 (`depth OK = empty scene, no verbal alert`).
3. `misaligned + walking + depth low ≥15 s + sustained ≥10 s fires warning verbal alert exactly once`  
   Expected announce key `pitch_misaligned_blind`; actual `misalign_no_detections`.
4. `returning to optimal pitch resets the watchdog and warning can re-announce on a fresh episode`  
   Expected 1 warning; actual 2.

**Causal hypothesis (Phase 2 / Phase 7 owner):**  
`MisalignmentWatchdog` gained a D-5 no-detection verbal fallback
(`kNoDetectionThreshold = 20s`, key `misalign_no_detections`). `_lastDetectionAt`
defaults to Unix epoch, so `t.difference(_lastDetectionAt) >= 20s` is already
true on the first tick of a fresh watchdog. That path speaks before the 10 s
sustained warning, on empty-scene (depth OK) runs, and a second time on a
fresh episode. Tests still encode the older H6 contract (depth-gated speech,
silence before 10 s, empty-scene haptic-only). Do **not** retarget tests to
the current output; write the product contract first.

### Focused Core groups (independent runs)

| Group | Result | Exit |
| --- | --- | ---: |
| obstacle / depth | 61 passed, 1 skipped (NCNN fixture) | 0 |
| alerts / TTS | 80 passed | 0 |
| camera lifecycle (stall/quality/AE/blur) | 22 passed | 0 |
| misalignment | 4 passed, 4 failed (same names as full suite) | 1 |
| fall / SOS | 46 passed | 0 |
| accessibility / widget / strings | 48 passed | 0 |
| navigation (GPS gate, turns, core_logic) | 111 passed | 0 |

No additional failing test files were found outside misalignment.

### `flutter build apk --debug`

Exit **0**. `✓ Built build\app\outputs\flutter-apk\app-debug.apk`

| Field | Value |
| --- | --- |
| Size | 595,773,835 bytes (~567.8 MiB) |
| SHA-256 | `606cef18a766205e0ceb9c715275f75bf55513f8ab9927df69f9cd9d5b4c05ee` |
| Built at | 2026-09-12 23:34 local |

This is a **universal debug APK**, not a release-size or per-ABI result.
Previous generic-obstacle report hash `a7a3cada…` was an earlier debug
artifact of the same byte size; this rebuild produced a new hash.

### `adb devices -l`

No devices attached. Named-device, TalkBack, SMS, ARCore spike, thermal,
and walking evidence: **blocked**.

---

## 5. Feature flags and Core vs deferred startup

There is **no** compile-time `BuildProfile` / `CoreFeaturePolicy` yet.
Deferred experiments are preference-gated (defaults off) but several are
still constructed or initialized on Core camera boot.

Defaults in `Settings`:

| Flag | Default |
| --- | --- |
| `genericObstacleMode` | **shadow** |
| `clearPathAnnounce` | false |
| `enableKazakhStackV2` | false |
| bazaar / livestock / mesh / sonar / VLM / OSCP / indoor trail / payment SMS / local ASR | false |
| `sceneNarrationEnabled` | **true** |

### Always-on or always-initialized today (mismatch vs Core boundary)

| Initializer | Location | Classification |
| --- | --- | --- |
| `PaddleOcrBridge.init()` | `main.dart:38` | OCR probe at process start |
| `NativeTtsBridge.init()` | `main.dart:35` | Core TTS probe (Kazakh engines may be absent) |
| `CameraViewModel.init()` PaymentSMS / ObjectMemory / AWM | `camera_view_model.dart:319-324` | Deferred services on Core boot list; AWM starts mic capture by default |
| Phone-abandoned detector tick | `camera_screen.dart` | Deferred, no prefs flag |
| BLE / sonar / OSCP / VLM native plugins | `MainActivity.configureFlutterEngine` | Registered even if Dart never starts them |
| Winter mode load | `CameraViewModel` ctor | Experimental environment profile |

Voice commands can still toggle bazaar, livestock, mesh, and sonar
(`voice_command_dispatcher.dart`).

---

## 6. Manifest, channels, signing

`android/app/src/main/AndroidManifest.xml` currently declares (among others):

- Core-plausible: `CAMERA`, `RECORD_AUDIO`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_CAMERA`, `FOREGROUND_SERVICE_LOCATION`,
  `POST_NOTIFICATIONS`, `WAKE_LOCK`, `ACCESS_FINE_LOCATION`,
  `ACCESS_COARSE_LOCATION`, `SEND_SMS`, `VIBRATE`,
  `HIGH_SAMPLING_RATE_SENSORS`, `ACCESS_WIFI_STATE`
- Deferred / over-scoped for Core: `RECEIVE_SMS`, BLE scan/connect/advertise
  (+ legacy BLUETOOTH*), `ACCESS_BACKGROUND_LOCATION`,
  `MODIFY_AUDIO_SETTINGS`, optional `bluetooth_le` feature

Native / plugin channels observed:

| Channel | Role |
| --- | --- |
| `bagdar/sms` | SOS SMS; SENT `PendingIntent` exists; still boolean; `SmsManager.getDefault()` |
| `bagdar/incoming_sms` | Payment SMS (deferred) |
| `bagdar/watchdog` | Foreground Dart-isolate heartbeat |
| `bagdar/device_info` | thermal / memory / capabilities |
| `bagdar/hardware_depth` | ARCore session (second camera owner) |
| `bagdar/native_tts` | RHVoice / espeak |
| `bagdar/paddle_ocr` | OCR |
| `bagdar/audio_capture` | mic broker (AWM/sonar/ASR) |
| `bagdar/ble_buddy` | BLE mesh |
| `bagdar/oscp_pod` | smart-cane |
| `bagdar/sonar` | FMCW sonar |
| `bagdar/vlm_engine` | VLM stub |

ARCore generic depth remains `alignedToImage: false` /
`genericObstacleUnavailable` until a device spike
(`docs/generic-obstacle-camera-decision.md`).

---

## 7. Product-claim mismatches (Phase 1 documentation)

`README.md` currently states Android 5.0+, estimated 8–25 FPS, $100 / $150–200
hardware, public transit, bazaar/livestock, acoustic world model, object
memory, payment SMS, VLM, indoor trail, and similar items as present
capabilities. Gradle `minSdk` is 30. Kazakh language-pack ZIPs are
placeholder-sized. No pilot-city map is packaged.

User-facing “path clear” speech keys (`path_clear`, `status_no_obstacle`, …)
were rewritten to **“Анализ активен” / “Analysis active.”** `AlertManager`
does not speak those keys on empty detection. Residual: developer earcon
button label `Путь свободен` in `camera_controls_sheet.dart:922`.

`GenericObstacleMode.assistive` is **not** authorized
(`docs/generic-obstacle-validation-report.md`).

---

## 8. Safety-audit 2026-06 re-triage (current tree)

Line numbers in the June audit are stale. Status is from the dirty tree on
this date.

### Critical / high

| ID | June severity | Status now | Evidence | Owner phase |
| --- | --- | --- | --- | --- |
| A-1 | CRITICAL | **partially fixed** | Thermal YOLO reload rolls back and calls `onYoloUnavailable`; `if (!_yoloLoaded) return` still blocks later retries. No reload-failure test. | 3 |
| A-2 | CRITICAL | **fixed** | `dp.onSessionDisabled` wired; not-ready frames degrade status. `test/depth_pipeline_session_disable_test.dart` | — |
| E-1 | CRITICAL | **partially fixed** | Native SENT broadcast + 10 s timeout; Dart still maps native bool and sms-URI fallback to `pendingEnqueued`, not a full delivery state machine. No native instrumentation tests. | 8 |
| E-2 | CRITICAL | **partially fixed** | `dialerOpened` exists; sms URI still `pendingEnqueued`; `composerOpened` is unused from `_tryDeliver`. | 8 |
| A-3 | HIGH | **fixed** (residual luma index) | analyze catch increments failures → `lowConfidence`. `test/depth_pipeline_analyze_exception_test.dart`. `_extractLuma` still unguarded. | 4 residual |
| A-4 | HIGH | **fixed** | degenerate / invalid NCNN records failure; not a healthy empty scene. | — |
| A-5 | HIGH | **fixed** | `_kCriticalDedupWindow = 2s`. No Δt=2.5s regression test yet. | 6 test |
| A-6 | HIGH | **fixed** | camera-init catch speaks critical; `system_ready` only if `_isCameraReady`. No widget test. | 4 test |
| B-1 | HIGH | **fixed** | cross-category link only for non-critical. `safety_audit_fixes_test.dart` | — |
| B-2 | HIGH | **fixed** | running halves `midasInterval` with 200 ms floor. `performance_throttler_test.dart` | — |
| C-1 | HIGH | **fixed** | accel-only Class A + gyro staleness + `fall_detector_degraded`. `fall_detector_gyro_unavailable_test.dart` | — |
| D-1 | HIGH | **partially fixed** | dead `aeTransitioning: true` feed removed; AE start announced; YOLO/depth still skipped during AE freeze; motion prealert still returns null if `aeTransitioning`. | 4 / 6 |

### Medium items inspected while refreshing (not a complete medium re-audit)

| ID | Status now | Note |
| --- | --- | --- |
| A-7 | **fixed** (software) | `startImageStream` is awaited; cold restart on failure. Device lifecycle matrix still blocked. |
| A-9 | **still valid** | haptic floor uses `identical` and omits `kHapticCriticalAlertPattern`. |
| C-2 | **fixed** | `alertMgr.reset()` from `CameraViewModel.setMode`. |
| C-5a | **fixed** | paused repeats include running (not walking-only). |
| D-5 | **partially fixed / tests failing** | running included; no-detection speech added; epoch default last-detection makes tests fail. |
| E-3 | **still valid** | `Permission.sms.request()` still inside `_sendSmsDirect`. |
| E-4 | **still valid** | `SmsManager.getDefault()`; no subscription selection. |

---

## 9. Known missing fixtures and blocked hardware gates

| Gate | State |
| --- | --- |
| NCNN vs reference rank correlation ≥ 0.90 | **blocked** — `reference_outputs.json` absent |
| Native/Dart NCNN pixel parity on a phone | **blocked** — no device |
| ARCore single-owner camera spike | **blocked** — see `generic-obstacle-camera-decision.md` |
| Device-matrix FPS / thermal / 30 min | **blocked** — no named devices |
| Controlled walking / TalkBack walkthrough | **blocked** |
| Replay corpus / integration_test scenarios | **skipped by design** (`missing_fixture`) |
| Pilot-city map package | **absent** |
| Release signing identity / final applicationId | **not chosen** |
| Generic `assistive` alerts | **disabled / shadow** |

---

## 10. Failing-test ownership

| Failure | Owner phase | Hypothesis |
| --- | --- | --- |
| Four `misalignment_watchdog_test` cases | Phase 2 (green baseline from written contract) and Phase 7 (full orientation contract) | D-5 no-detection speech vs epoch `_lastDetectionAt` vs older H6 expectations |
| Nine analyzer lints | Phase 2 | unused imports / scratch prints / const |
| NCNN skip | Phase 5 | external corpus not present; do not fabricate |

---

## 11. Phase 0 exit checklist

- Baseline is reproducible from the commands above.
- No invented device, FPS, thermal, SMS, or TalkBack result.
- Every known failing test has an owner phase and a causal hypothesis.
- No runtime behavior was changed in Phase 0.

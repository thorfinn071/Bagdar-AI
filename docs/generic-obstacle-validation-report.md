# Generic obstacle validation report

Status: **not authorized for assistive alerts**  
Date: 2026-09-12

The feature flag defaults to **shadow**. Supervised `assistive` alerts are
not authorized until the gates below have factual device/corpus evidence.

Post-change `flutter build apk --debug`: **succeeded**
(`build\app\outputs\flutter-apk\app-debug.apk`, 595,773,835 bytes,
SHA-256 `a7a3cada2b3450ef660eeef222fa109bddeb3a8290dc8d01430d35f8573d114a`).

## Independently verified in this change (unit)

- NCNN preprocess contract (RGB, ImageNet mean/std in-graph, YUV420, crop,
  rotation, mirror, and an identically transformed luma plane)
- Spatial output resize (no zero-pad flatten)
- Invalid depth is NaN
- Per-frame NCNN health rejects weak dynamic range / low finite coverage instead
  of reporting every structurally valid tensor as healthy
- Focal fallback is `genericObstacleUnavailable`, not a healthy empty scene
- Detector: wall / pole / box / overhead fixtures without YOLO; open corridor
  does not warn; stale, low-quality, strongly rolled, and unaligned frames reject;
  crop coordinates are remapped to the full upright frame
- Thin hazards require real aligned image-edge support; missing luma can no
  longer count as positive evidence
- Tracker: stable IDs, actual rolling N-of-M confirmation, expiry, approach
  trend, and no ID reuse for spatially unrelated same-zone observations
- YOLO enrichment uses a fresh spatial IoU match and keeps the matched track's
  own ID, label, and confidence; geometry detection remains independent of YOLO
- Risk: YOLO absence does not reduce geometry; receding suppress; low-quality
  never critical; shadow does not speak; relative critical gate
- Alerts: new track ID not hidden by global cooldown; RU/KK/EN copy; no
  "path clear" strings on the empty-detection keys
- Every generic-stack frame records its rejection/health reason in shadow
  telemetry, and early-return paths clear prior decisions instead of replaying
  stale hazards

## Verification snapshot

- Focused obstacle/depth/alert/pipeline tests: **58 passed, 1 skipped**
- Full `flutter test`: **832 passed, 1 skipped, 4 failed**
- The four failures are the pre-existing expectations in
  `test/misalignment_watchdog_test.dart`; the baseline already had the same four
  failures before this hardening pass
- Reference-correlation test is skipped only when the external fixture is
  absent. Once present, it computes rank correlation and fails below 0.90; it
  no longer fabricates a passing map and no longer makes every default test run
  fail solely because the corpus is external
- `git diff --check`: **passed**
- `dart analyze`: no compilation errors; **9 existing repository lint issues**
  remain (4 warnings, 5 infos)

## Blocked gates (not simulated)

| Gate | Why blocked |
| --- | --- |
| NCNN vs reference rank correlation | `test/fixtures/ncnn_contract/reference_outputs.json` missing; no on-device NCNN run |
| Native/Dart transform parity | Dart rotation/mirror/crop mapping is unit-tested and native code compiles, but native pixels have not been compared on a phone |
| Camera-ownership spike | No Android device attached; see `generic-obstacle-camera-decision.md` |
| Device-matrix FPS / thermal / 30 min | No named device results |
| Controlled walking protocol | Not started |
| Replay corpus | Manifest absent; tests must report missing fixture, not pass |
| True metric 3D generic-obstacle path | ARCore generic depth remains deliberately unaligned/disabled; current generic path uses relative monocular geometry and must not claim metric clearance |

Do not promote `GenericObstacleMode.assistive` until this report is updated
with named devices, hashes, and measured numbers.

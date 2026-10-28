# Generic obstacle stack — Phase 0 baseline

Recorded: 2026-09-12  
Workspace: `C:\Users\Nurik\Desktop\bagdar_app`  
HEAD: `5775f5e56aecb1bca1ffe8fffcb5fd42a701620a` (`main`, ahead of `origin/main` by 3)  
Safety behavior added in this phase: **none** (evidence only)

## Git status (short) at start

Dirty worktree was preserved. Unrelated user changes were not reverted.

Modified (among others): `lib/camera/depth_pipeline_controller.dart`,
`lib/camera/fall_countdown_controller.dart`, `lib/camera_screen.dart`,
`lib/models/strings.dart`, `lib/services/fall_detector.dart`,
`lib/services/misalignment_watchdog.dart`, `lib/services/model_service.dart`,
`lib/services/tts_service.dart`, `lib/utils/alert_filter.dart`,
`lib/utils/performance_throttler.dart`, `lib/viewmodels/camera_view_model.dart`,
plus presentation/pptx and pubspec files.

Untracked: this plan, integration tests, extra test files, docs, media assets.

## Toolchain

| Item | Value |
| --- | --- |
| Flutter | 3.41.4 stable (`ff37bef603`, 2026-03-03) |
| Dart | 3.11.1 |
| Android SDK | 36.1.0 at `%LOCALAPPDATA%\Android\Sdk` |
| Flutter NDK | 28.2.13676358 (`FlutterExtension.ndkVersion`) |
| Installed NDKs | 28.2.13676358, 30.0.14904198 |
| JDK for Gradle | Android Studio JBR 21.0.8 |
| minSdk | 30 |
| Host | Windows 11 25H2, locale ru-KZ |

## Feature flags (code defaults)

- `enableKazakhStackV2`: false
- bazaar / livestock / mesh-buddy / sonar / VLM / indoor trail: false
- `ncnnDisabled`: false (transient; cleared on NCNN init)
- `useHardwareDepthMode`: false
- `useNativeDepthBridge`: false
- `clearPathAnnounce`: was default **true** at baseline; this stack later
  defaults it to **false** and stops speaking path-clear copy
- `genericObstacleMode`: **not present at baseline**; added later, default
  `shadow`

## Commands

### `dart analyze`

Exit code **2** (warnings/infos, no errors). 9 issues, all pre-existing in
tests/scratch:

- unused imports in `test/alert_filter_same_category_critical_test.dart`,
  `test/fall_countdown_cancel_test.dart`, `test/harness/scenario_harness_test.dart`
- `avoid_print` in `scratch/create_dummy_zips.dart`
- `unnecessary_import` / `prefer_const_declarations` in tests

### `flutter test --no-pub` (pre-change)

**789 passed, 4 failed.** Failures are pre-existing and confined to
`test/misalignment_watchdog_test.dart` (Safety follow-up H6), matching the
dirty `lib/services/misalignment_watchdog.dart` change. They are **not**
generic-obstacle regressions.

### `flutter build apk --debug`

Started on the baseline tree. The Gradle/CMake compile ran after native
Phase 1 edits began, so this is **not** a clean pre-change APK. The first
pass failed compiling `bagdar_depth_ncnn.cpp` (`reinterpret_cast` from
`ncnn::Mat` to `float*`). That native error was then fixed. A clean
post-change APK is a remaining build gate.

## Devices

`adb devices -l`: **no devices attached**.

Named device matrix, YOLO/NCNN/ARCore startup traces, FPS, thermal, and
battery numbers: **not recorded**. Do not invent them.

Current-device provider startup/fallback trace: **blocked** (no Android
device).

## Known blockers (from the plan, confirmed in code)

1. ARCore session + Flutter camera are two owners
   (`HardwareDepthSession.kt` vs `camera` plugin).
2. Metric ARCore depth and relative MiDaS share `GroundPlaneAnalyzer`
   without an explicit semantic contract.
3. ARCore raw-depth confidence image is not acquired.
4. Independent 256×256 resize of ARCore depth and camera pixels; no proven
   alignment.
5. NCNN preprocess **was** grayscale Y-replication. The `.bin` starts with
   ImageNet RGB mean/std `(0.485, 0.456, 0.406)` / `(0.229, 0.224, 0.225)`,
   so RGB `[0,1]` is required. Mean/std are inside the graph.
6. Native output was memcpy + **zero-pad** if smaller than 256×256.
7. Coverage gates can reject thin poles (legacy analyzer).
8. `FocalLengthDepthProvider.analyze` returns `[]` with `lastPlaneFitOk == true`
   — a healthy empty scene. Must be `genericObstacleUnavailable`.

## After this implementation (not Phase 0)

See `docs/generic-obstacle-validation-report.md` and
`docs/generic-obstacle-camera-decision.md`. Assistive alerts are **not**
authorized. Default mode is shadow.

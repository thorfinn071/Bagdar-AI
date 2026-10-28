# Camera observations and walking clearance — 19 October 2026

The inspection screen now explains what the latest usable camera analysis
reported separately from whether the app can check a walking route. This is
the first implementation following the STOP logic audit.

It improves the meaning of status messages. It does not reduce false STOPs,
provide new distance measurements, or authorise walking assistance.

## What a user gets

The inspection controls show the latest observation and the instruction to
remain stationary. System status provides three separate pieces of information:

| Information | Example in English | Meaning |
| --- | --- | --- |
| Camera observation | No obstacles were reported in the latest camera analysis. This does not confirm a clear path | No geometric components were reported in that usable frame; missing detections and unobserved space are not ruled out |
| Possible obstacle | Possible obstacles in the camera view. Distance and passage clearance are unconfirmed | Current detector components exist; this is not independently measured collision geometry |
| Coverage capability | This camera mode does not check the full space needed for walking | The normal camera path does not provide a walking-clearance source |
| Movement limit | Inspect while standing still. Walking guidance is unavailable | This status cannot grant movement permission |

Missing, rejected, unhealthy or previous-session results do not become a
"no obstacles reported" message. Expired results say that camera data is out of
date. Invalid current orientation asks the user to adjust the phone.

Russian, Kazakh and English have corresponding messages. The Status button's
screen-reader label includes the observation and stationary-use limit. The
status dialog and existing spoken Status command use the same presentation.
Reading aloud remains an explicit action; this change adds no automatic TTS,
earcon, vibration or external action.

## Implementation

- `lib/camera/inspection_scene_status.dart` is a read-only view of accepted
  camera observations. Observation state, clearance capability and the fixed
  restriction on movement are independent fields.
- `lib/camera/inspection_system_status.dart` formats observations and limits
  alongside the existing service-health information. Healthy services do not
  establish a clear path.
- `lib/camera_screen.dart` supplies current pipeline evidence and the runtime's
  active session/admitted frame. Existing frame and cadence callbacks refresh
  presentation when its state changes. The status getter reads current time,
  so opening or speaking status rechecks expiry immediately.
- `lib/widgets/inspection_surface.dart` displays the observation and stationary
  limit, and includes the three messages in the status dialog.
- `lib/models/strings.dart` contains RU/KK/EN wording.

An observation is usable only when its header belongs to the active runtime
session and admitted frame, timestamps are consistent and live, the specific
provider is healthy, the phone orientation is valid, and detection did not
reject the frame. A configured experiment is labelled experimental rather
than treated as a validated source.

The observation view uses the existing relative-observation lifetime. It does
not extend the separate **100 ms metric-clearance limit**, re-date captures,
or reinterpret a shadow CONTINUE as permission to walk. Status queries do not
call the planner, mutate the scene, submit actions, or reset history.

## Verification

The focused run passed **180 tests**, including:

- 22 new status tests covering session/frame binding, rejection, provider loss,
  invalid orientation, future timestamps, expiry and independent movement
  permission;
- 25 new widget cases: RU/KK/EN, four themes, portrait/landscape, 200% text,
  plus an open-dialog update under the screen curtain;
- existing inspection, transition, accessibility and voice-control checks.

One new control generates an actual shadow CONTINUE using constructed relative
inputs and verifies that the status still cannot authorise movement. Another
uses a healthy service snapshot and confirms that the spoken status retains
both the coverage limitation and stationary-use instruction.

The visual checks use Flutter's widget renderer with a substitute camera
background. Twenty-four captures cover light/dark, RU/KK/EN and both
orientations. Portrait and landscape samples were inspected visually; longer
status details scroll, with the dialog's actions remaining available at large
text sizes. These are layout and semantics checks, not a phone camera or
TalkBack trial.

Evidence is saved under `output/inspection-evidence-status-2026-10-19/`:

- `targeted-tests.log` and `captures/`;
- `analyze.log`, `final-analyze.log`, `targeted-final.log`;
- `broad-standard-interrupted.log` and `research-rc-interrupted.log`: optional
  broad runs stopped while scoping acceptance to this presentation change;
- `safety-replay/` for the current known-scene comparison;
- `delivery-verification.json` for final checks, preservation and artifact hashes.

The existing application restriction to stationary inspection, shadow spatial
delivery, unknown/stale handling, and movement-authorisation gates remains.
Named-device camera/audio behavior, real TalkBack focus and announcements,
physical perception accuracy and controlled walking have not been tested here.

## Reproduce the focused checks

```powershell
flutter test --no-pub --concurrency=1 --reporter=expanded test/inspection_scene_status_test.dart test/inspection_scene_status_widget_test.dart test/inspection_accessibility_test.dart test/inspection_transition_accessibility_test.dart test/inspection_voice_test.dart test/inspection_voice_widget_test.dart
```

Set `BAGDAR_INSPECTION_SCENE_CAPTURE_DIR` to a new output directory to save
widget captures. The new presentation is visible in the existing inspection
screen; it does not create a new route or request additional permissions.

## Final software verification

The final focused run passed **180 tests**; full and final targeted analysis were clean. The dedicated safety run passed 54 tests. All 224 exported fixed-replay rows, including 132 known paired frames, matched the previous audit exactly.

All 57 existing safety-module files are unchanged. 665 recorded existing files were preserved in total; four existing presentation files changed. Optional broad standard and research RC runs were interrupted while scoping verification to this presentation change. Their partial logs are retained; neither is claimed as a complete passing suite. Full Core aggregate RC, Android build and named-device/user acceptance were not run.

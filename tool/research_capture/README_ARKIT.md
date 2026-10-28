# iPhone spatial research workflow

This is a separate UIKit recorder and an offline feasibility gate. It does not
port Bagdar to iOS or enable guidance. There are no real recordings in this
implementation. Xcode compilation and iPhone lifecycle tests remain `not_run`
until the Mac/device procedure below is actually performed.

The provider accepts **centre samples only** from ARKit. Its current adapter
cannot produce `measuredClear`: the existing safety contract requires bounded
first returns over complete pixel footprints and complete current body/floor
coverage. ARKit confidence, an empirical depth fit, and camera pose do not
establish those facts. This explicit gate is the planned stopping condition,
not a successful reduction of false STOPs.

Apple's [sceneDepth documentation](https://developer.apple.com/documentation/arkit/arframe/scenedepth)
describes distance estimates; its [confidence documentation](https://developer.apple.com/documentation/arkit/ardepthdata/confidencemap)
describes categorical accuracy estimates. Neither API supplies the complete
whole-pixel first-return intervals required by this project's passage contract.

## 1. Build and test on the Mac

Copy this `ios/` directory to the Mac. Open
`ios/BagdarCapture.xcodeproj` in Xcode. No Flutter, CocoaPods, XcodeGen or package
downloads are required. The checked-in project is generated deterministically
by `ios/generate_project.py`. Minimum target: iOS 15; runtime support for
`ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)` is required.
Run the following Mac commands from the parent directory containing the copied
`ios/` folder (in a full checkout, `cd tool/research_capture`).

In Signing & Capabilities choose your Apple development team for **both**
BagdarCapture and BagdarCaptureTests. Change the research bundle identifier
under your account if Xcode requires a unique ID. Connect and trust the iPhone,
enable Developer Mode when requested, and select that device. Build/test the
BagdarCapture scheme, then Run it. A simulator cannot establish depth support.

To preserve the compilation and XCTest results, obtain the connected UDID from
Xcode's Devices window and run (replace the two identifiers):

```bash
bash ios/verify_on_mac.sh YOUR_TEAM_ID YOUR_IPHONE_UDID "$PWD/verification-iphone-001"
```

The native tests exercise buffer padding, invalid samples, bounded admission,
stop/drain state and ZIP CRC. Successful native tests do not establish sensor
accuracy or camera lifecycle. Windows validation checks Swift syntax and the
project structure only; it is not a substitute for Xcode compilation.

The script preserves native source hashes and embeds their combined identifier
as `recorderSourceId` in the installed test build. A direct Xcode Run uses
`unfrozen-development` unless you set `BAGDAR_CAPTURE_SOURCE_ID` to that same
identifier in the app target's build settings. Preserve `source-sha256.txt`,
the build log and the source ID with the recordings. The build tag is an
operator-supplied provenance link, not authentication of the installed binary.
After the script succeeds, launch the installed app from the iPhone Home Screen
to retain the embedded ID; another direct Xcode Run may replace that build.

## 2. First stationary capture and lifecycle checks

Use a prepared private room, remain stationary and obtain agreement from anyone
who could be recorded. Confirm the local-recording switch, press Start, approve
camera access and keep a known textured surface in view. Stop and export the
selected `capture-UUID` to Files. Transfer the ZIP to Windows. The original
recording stays in the iPhone's Documents folder, also accessible through File
Sharing. Every start gets a new recording/session ID. No microphone or network
capture is used by the app.

Limits: 10 s, 300 saved frames or 512 MiB payload, whichever is reached first.
The writer holds one active frame plus one newest pending frame. Superseded and
cancelled frames are counted, not fabricated. A stop drains only the already
active write and pauses the ARSession. The 10 s timer is a request deadline, not
a guarantee that an SDK call or disk write finishes within that deadline.

Manually record outcomes for: permission denied, user Stop, duration limit,
backgrounding, interruption, orientation change, repeated Start after Stop,
unavailable depth and export. Background/interruption/error captures are marked
failed; a crash without a final manifest is partial. They are retained and
rejected by the complete-recording importer. Check that the camera stops and
that a new start does not overlap the previous owner. These checks are currently
`not_run`.

## 3. Import on Windows

From the repository root, use the recording ID actually shown by the app.
All directories below must be new. Keep original recordings outside Git.

```powershell
python tool/research_capture/arkit_capture.py C:\BagdarCaptures\capture.zip `
  --expected-recording-id capture-UUID_FROM_PHONE `
  --extract-to C:\BagdarCaptures\capture-UUID_FROM_PHONE `
  --output C:\BagdarCaptures\capture-UUID_FROM_PHONE-audit.json
```

Exit 0 means file integrity passed. It does not confirm physical alignment,
accuracy, a free path or real-time freshness. Exit 2 means the import was
rejected. Extraction never overwrites an existing directory or deletes the
source. Rejected extracted files are retained for inspection.
Raw recording archives cannot be extracted into a Git repository.

## 4. Calibration and feasibility

First collect separate calibration-only recordings at measured 0.25, 0.5, 1,
2 and 3.5 m, with centre/left/right edge samples and independent measurement
tolerances. Distances must be camera-axis depth, not an off-axis Euclidean range.
Measure alignment using identifiable RGB/depth features and the floor reference
using a measured transform to walking axes. Do not infer the reference from the
depth that is being evaluated. The pixel centre convention is `(x+.5,y+.5)`.

Supply a JSON file with `recordingId`, the audit's `captureManifestSha256`,
`scope: "calibration-only"`, `independentReferenceAssertion: true`, and `samples`.
Each sample has `frameId`, `x`, `y`, `referenceCameraAxisM`,
`referenceToleranceM`, `targetDistanceM` and `region` (`centre`, `left-edge` or
`right-edge`). Optional `independentRgbFeaturePixel: [u,v]` yields an empirical
alignment residual. Use separate files for separate recording IDs.

Optional `diagnosticWorldToWalkingRowMajor` is a 4×4 rigid transform from ARKit
world right/up/back into walking lateral/forward/height with an independently
measured floor origin. Optional `floorReferenceSamples` entries contain
`frameId`, `x`, `y`, `referenceHeightM`, `referenceToleranceM`. They yield sample
height residuals. The program records assertions and empirical errors; it does
not authenticate measurements or extrapolate them into guaranteed error bounds.

```powershell
python tool/research_capture/arkit_experiment.py calibrate C:\BagdarCaptures\capture-UUID `
  --recording-id capture-UUID --measurements C:\BagdarCaptures\measurements.json `
  --output C:\BagdarCaptures\empirical-profile.json

dart run tool/research_capture/analyze_arkit.dart `
  C:\BagdarCaptures\capture-UUID C:\BagdarCaptures\capture-UUID-audit.json `
  C:\BagdarCaptures\analysis-001 C:\BagdarCaptures\empirical-profile.json
```

The calibration command returns 2 after writing a valid empirical report
because physical clearance remains unestablished. Analysis returns 2 after
writing `feasibility.json`, `frames.jsonl` and `coverage.svg` when the provider
gate is unmet; 1 means invalid input. An optional profile may supply diagnostic
placement and empirical sample error only. Attempts to set validated physical
flags to true are rejected.

Without measured placement, body visibility is `not_run`. With placement it is
explicitly conditional geometry, not physical free-space evidence. The native
availability grid is separate from body/floor coverage. Whole-pixel bounds stay
unknown; the diagram cannot turn a finite sample into free space.

The artificial replay clock preserves source intervals. Native capture and
receive clocks remain distinct. `captureToDecisionMs` stays null. Reported
analysis times include Windows reading/hash/decode/provider/evaluator work and
exclude initial audit/metadata parsing, capture, inference, feedback and phone
thermals. The artificial replay age advances by that per-frame host work; old
source timestamps are not renewed when processing finishes. This is still only
a partial age budget, with unknown native capture/transport age.

## 5. Behavioural collection is gated

`arkit_protocol.json` preregisters 72 planned recordings: 12 scenarios × 3 repeats
× 2 sessions. It is a schedule, not collected data. Session 1 is development;
session 2 is holdout. The six free and six hazardous scenarios, unchanged volume,
100 ms TTL and 50% false-STOP-reduction target are in that file. Do not begin the
behavioural collection or advertise improvement while provider feasibility is
unmet. No extra sensor or changed navigation promise is introduced here.

Capture the implementation identity in a new file:

```powershell
python tool/research_capture/arkit_experiment.py freeze --output C:\BagdarCaptures\implementation-freeze.json
```

This is **not** a holdout release: the current provider cannot certify physical
whole-volume evidence. A later physically justified source requires a new
candidate/calibration freeze before session 2, no tuning on the inspected
holdout, and a separate implementation of that evidence source.

The `score` subcommand compares independently supplied labels and decisions.
Both JSON inputs require `schemaVersion: 1`, `split: "holdout"`, matching
`candidateFreezeSha256`, and one row per `(recordingId,frameId)` in `frames`.
Labels contain `scenario` and `class` (`passable`, `hazard`, `unlabelled`).
Decision rows contain `baseline` and `candidate`, each with `action`
(`stopNow`, `continueForward`, `wait`), optional `providerStatus` and `stale`.
It reports rates per recording and scenario and includes unavailable free
frames in the false-STOP denominator. This scorer does not execute NCNN or
Bagdar, authenticate decisions or accept a declared clear status as proof.
It cannot establish reduction or promotion in this version.

## 6. Software checks

```powershell
$env:BAGDAR_TEST_ARKIT_DART='1'
python -m unittest discover -s tool/research_capture -p 'test_*.py'
flutter test --no-pub --concurrency=1 --reporter expanded test/recorded_rgbd_test.dart
flutter analyze --no-pub
flutter test --no-pub --concurrency=1 --reporter expanded --dart-define=BAGDAR_RC=true
```

Historical strict scripts and receipts retain their original meaning. New
research files are not wired into `camera_screen.dart`, Android or iOS Runner.
`promotionAllowed=false`, `ordinaryCameraWired=false`, and `shadow` remain.

## Format: bagdar-arkit-capture-v1

The ZIP contains exactly `manifest.json`, `frames.jsonl` and referenced
`payloads/`. Files use SHA-256 descriptors. Manifest identity, device/OS/version,
ownership, limits, final status, clock domains, counts, drop reasons and false
authority flags are mandatory. Frames are ordered by original capture ID/time;
saved `frameIndex` is contiguous even when original frame IDs have gaps.

ARFrame timestamps are retained as JSON seconds, IEEE-754 bits and derived
microseconds. Receive/payload-ready clocks use Dispatch uptime nanoseconds and
are not subtracted from ARFrame time. Camera transforms and intrinsics are
column-major. ARKit camera axes are right/up/back; native image camera axes are
right/down/forward. Raster geometry uses the native orientation; screen rotation
is recorded separately. Intrinsics must be scaled separately in x/y to depth
resolution; they are not the intrinsics of a square resized map.

RGB uses its native two-plane YCbCr bytes, original CV pixel format, colour
range/matrix, and source row strides. Depth is native little-endian Float32
**camera-axis metres**, with NaN/zero/negative samples preserved. Confidence is
UInt8 with 0=low, 1=medium, 2=high (not a probability). The separate validity mask
is 1 exactly for finite positive depth; confidence 0 does not overwrite depth.
Packed files remove row padding only and retain native dimensions. Each image
descriptor is bound to its enclosing frame ID/time. Missing depth/confidence
and limited tracking remain explicit unavailability.

The format is separate from ARCore's `bagdar-native-capture-v1`. No existing
ARCore timestamp, confidence or raw-depth assumptions have been relaxed.

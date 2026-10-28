# Whole visible track evidence — 10 October 2026

The optical-support confound is largely removed, but continuous false stops
remain **10/11 in both detector modes**. Existing metric correspondences cover
at most **0.07577%** of a visible track footprint in this known corpus. They
cannot justify clearing relative motion priority. The usefulness/promotion gate
does not pass. All delivery remains shadow; `promotionAllowed=false` and
`ordinaryCameraWired=false`.

## What changed

Added a diagnostic `CameraTrackMotionCoverage` contract, separate from runtime
admission. It binds two original observations, complete component support,
RGB/depth geometry, calibrated metric units, a bounded pose and live motion
result. Missing/lost/foreign/malformed/stale evidence is unavailable. The pair
interval remains 50–300 ms, current age <=100 ms, oldest evidence <=400 ms.

The coverage numerator counts unique correspondence **centres** that belong to
the track in both captures. A photometric template, search window or 3x3 depth
registration envelope is not an independent material match at every enclosed
pixel. The denominator is the complete native-image segmentation footprint,
including the same one-source-pixel registration margin as track association.
These are segmented components, not validated physical object masks.

Even a crafted control with complete visible coverage cannot certify hidden
object extent or whole-object stationarity. The diagnostic always reports
`mayResolveMotionPriority=false`, `wholeObjectStationarityCertified=false` and
`freeSpaceCertified=false`. It is not imported by the ordinary camera pipeline.
No planner, tracker, motion producer, history, recovery, STOP/unknown behavior
or runtime freshness policy changed.

## First-return support control

Before evaluating the new replay, selected the union of both modes' complete
native footprints from the frozen preceding receipt, without scene labels.
The existing exact rational first-visible-surface exporter certified **1442 of
1577 additional candidate pixels**, with **7210 independent first-hit ray
witnesses**. The remaining 135 failed proofs retain unknown upper bounds.

Old finite upper bounds, lower/range/validity, RGB, neural outputs, camera
projection/pose, capture/frame/session and simultaneous rig geometry are
preserved. A new manifest hash binds the supplemental primary and unchanged
rig payloads into a new calibration identity. No hidden surface becomes a
first return. Offline export duration is not runtime latency evidence.

The geometry-only diagnostic queries use `motionOrSemanticRisk=false` only in
the diagnostic call; real runtime associations retain their risk priority.

| Continuous path-clear replay | Stateful detector | Frame-stable detector |
| --- | ---: | ---: |
| Captures, one persistent session per mode | 11 | 11 |
| Sum of geometric unknown pixel queries, before | 1 | 935 |
| Sum of geometric unknown pixel queries, after | 1 | 1 |
| Frames with relative/semantic motion priority | 7 | 7 |
| Frames containing missed tracks | 4 | 1 |
| STOP before / after | 10 / 10 | 10 / 10 |
| Continue before / after | 1 / 1 | 1 / 1 |

The remaining geometric unknown occurs at frame index 4 in both modes.
Unknown-pixel query totals are not counts of all uncertified optical pixels:
the existing associator can exclude an unbounded return using a sufficient
lower bound outside the passage, and missed tracks are unavailable separately.
All simultaneous synthetic rig body-volume queries still report zero unknown
boxes. Complete body coverage does not cancel track risk or retained history.
Actual track IDs, hits/misses/age, relative histories and complete support
hashes exactly reproduce the preceding receipt. Scene revisions remain
continuous; there are no resets, retimed captures or warmed recovery clocks.

## Correspondence coverage audit

Replayed both detectors, persistent trackers and shadow runtime on all nine
known non-scan scale-motion test sequences: 63 captures, 54 pairs per mode.
The metric producer's full output exactly reproduces its frozen predecessor;
runtime actions and rules also match. Scoring annotations are copied only
after decisions and never enter the coverage contract.

There are **256 combined track samples**: 145 admit the structural measurement
contract, 106 of those contain at least one owned matched centre, and **0/256**
have complete visible support measurements. The other 111 are unavailable,
including new/missed tracks or absent metric correspondences. Availability
means the measurement packet is usable for counting; it does not mean the
component was stationary, adequately covered, or safe.

| Known sequence | Best visible coverage, stateful | Best visible coverage, stable | Owned moving centres, stateful / stable |
| --- | ---: | ---: | ---: |
| Approach slow | 0.06426% | 0.06373% | 63 / 68 |
| Approach fast | 0.07577% | 0.07470% | 44 / 43 |
| Approach small | 0.04759% | 0.04419% | 65 / 65 |
| Receding | 0.03872% | 0.02917% | 17 / 15 |
| Stationary | 0.03619% | 0.04239% | 0 / 0 |
| Camera yaw | 0.06742% | 0.06710% | 0 / 0 |
| Mixed motion | 0.03226% | 0.04348% | 12 / 12 |
| Occluded | 0.01712% | 0.02365% | 0 / 0 |
| Textureless | 0.00423% | 0.00319% | 0 / 0 |

These percentages are the best current footprint coverage of any admitted
track sample in each sequence, not object detection recall or motion accuracy.
Moving-centre totals count track-owned measurements across samples; overlapping
component footprints can count the same local correspondence in different
tracks. Stationary/yaw/occluded/textureless controls supply no proof of global
motion absence. In particular, background matches cannot establish the
stationarity of an occluded or textureless object.

## Validation and reproduction

New unit controls include sparse/background/one-sided matches, a crafted dense
visible control, approach/crossing, duplicates, partial/retimed support,
malformed intervals, image bounds, invalid RGB bytes, projection/pose/session/
model/unit mismatch, missing/unbounded/contradictory depth and stale/future
timestamps. All **28 unit tests plus the continuous experiment** pass.

Both new optical replay modes retain **22/22 initial-clear fault/explicit-risk
stops**. Known physical hazards retain **60/60 stops in each mode**, with zero
unsafe continues. The upstream safety suite is run unchanged: 137 Flutter tests
and 7 exact surface geometry Python tests. Targeted Dart analysis has no issues.
The verifier checks the prior immutable evidence chain, source and payload
hashes, exact selected union, repair masks/failed proofs, original identities,
track traces, continuous history, motion equality and diagnostic authority.

Run the complete serial check from the project root:

```powershell
& tool/model_benchmark/check_whole_track_evidence.ps1
```

The initial new replay is created with `BAGDAR_WHOLE_TRACK=true` and
`BAGDAR_WRITE_WHOLE_TRACK=true`; later checks use
`BAGDAR_CHECK_WHOLE_TRACK=true` and compare exact replay bytes. Completed
receipts, optical manifests, diagnosis and figures refuse overwrite.
Local artifacts are in `scratch/whole-track-evidence-2026-10-10/`:
`optical/manifest.json`, `replay.json`, `diagnosis.json`, `validation.json`,
`whole-track-evidence.png` and `.svg`. The plotted figure was visually inspected.

## Decision and remaining boundary

Keep the frame-stable detector and whole-track coverage diagnostic opt-in and
shadow-only. The known false-stop gate has not improved, and no whole-object
negative-motion evidence exists. Simply using stationary local patches to
clear relative priority would exceed the evidence. Missing tracks and retained
history must stay visible in the next experiment.

This is known synthetic geometry and replay, not a new independent holdout or
new neural inference. The functional clock is capture+2 ms; capture-to-command
latency was not measured. The earlier live-age result remains open (4/21 expired
in its measured desktop lane); the 100 ms TTL is unchanged. Named-device Android,
memory/thermal behavior, accessibility/feedback delivery and controlled walking
remain unestablished.

# Ego motion and separated risk — 10 October 2026

The experiment separates world motion from closing on the user, but does not
reduce false stops. The frozen continuous path-clear sequence remains **10/11
STOP in each detector mode**; no new branch can retire relative risk or unknown.
The usefulness/promotion gate **does not pass**. Delivery remains `shadow`,
`promotionAllowed=false`; the ordinary camera runtime is unchanged.

## Implementation

Added `CameraEgoMotionSource`, an opt-in wrapper around the unchanged fast
metric producer. A versioned pose contract binds the walking origin's original
capture, session/frame/timestamp, provider/revision, local/world references,
health, confidence, bounded error and fixed body heading. Camera yaw/pitch stay
in the calibrated optical rotation. This version supports translation of the
walking origin; a change of body heading is unavailable.

RGB/depth projection and alignment are validated before transforming their
origins into one fixed frame. Original arrays and capture clocks are retained.
World intervals propagate pose error. Subtracting the walking origin velocity
interval gives body-relative velocities; subtracting the current origin gives
body-relative positions. Pose uncertainty is conservatively counted in both
steps; no independence or cancellation of correlated errors is assumed.

Current freshness remains <=100 ms; the existing source retains its original
pair and oldest-evidence constraints. Missing/stale/future/invalid or unbound
poses reset pairing. Neither an unavailable result nor stationary visible
patches certify zero whole-object velocity, motion absence or free space.

`SeparatedMotionRisk` reports raw relative NN trends, explicit approach/TTC,
semantic attachment and metric track velocity separately. The raw relative
trend remains a hypothesis; it is not relabelled as m/s and is not dropped.
`applyEgoMotionShadow` binds the current packet again before sending positive
body-relative motion to the existing additive shadow scene. It cannot increase
coverage, clear unknown/physical risk, or reset scene/planner history.

## New data and comparisons

The protocol and six cases were fixed before evaluation. The new generator
renders **42 original captures: six independent seven-frame sequences**, with
different room dimensions/material seeds from the known motion corpus. It
exports only RGB, conservative whole-pixel visible first returns, calibrated
camera geometry and original-capture walking poses to consumers. Hazard and
object-motion labels are read only after all decisions have been computed.

Pinned MiDaS Small NCNN runs on every new RGB using the frozen model and
preprocessing, without a new metric fit. Relative detector/tracker inputs come
from those neural outputs. Metric motion consumes the synthetic calibrated
first returns; this is **not a neural metric-depth accuracy result**. All replay
decisions use a fixed clock 2 ms after capture. This proves neither actual
processing latency nor Android/device readiness.

Three motion views use the same originals: naive comparison of recentered
walking frames, pose-aligned world motion, and body-relative motion. Each case
keeps one source, detector, tracker and runtime session throughout seven frames.
Both stateful and frame-stable relative detectors are replayed.

| New sequence | Naive / world / body approaching patches | World stationary-consistent patches | Naive / world / body positive-risk frames |
| --- | ---: | ---: | ---: |
| Camera forward, static room | 215 / 0 / 215 | 198 | 0 / 0 / 1 |
| Camera yaw, static room | 0 / 0 / 0 | 161 | 0 / 0 / 0 |
| Object approach, fixed camera | 16 / 16 / 16 | 212 | 3 / 3 / 3 |
| Object approach plus camera advance | 11 / 11 / 11 | 195 | 2 / 2 / 2 |
| Crossing object plus camera translation | 0 / 0 / 0 | 175 | 4 / 4 / 4 |
| Occluded crossing plus camera translation | 0 / 0 / 0 | 134 | 0 / 0 / 0 |

These are local matched-patch totals over six pairs, not object recall or
independent examples. Crossing retains **21 lateral patches** in each view.
World-stationary wall patches still close on the advancing user. The one
camera-forward body-relative risk frame uses the declared conservative
one-second sweep; the room is clear at the current capture, but the wall can
enter the protected volume if the advance continues. World motion alone must
not cancel that warning. No-risk frames, especially occlusion, prove no absence.

![Local, world and body-relative motion](../scratch/ego-motion-2026-10-10/ego-motion.png)

## Runtime outcomes and failed gates

The unchanged confidence-authority runtime is replayed as the canonical lane.
A separate **pair of plain-scene runtimes** validates the existing additive
scene with and without the new motion. Its policy is different from the
canonical confidence policy; comparison between those policies is not an
ego-motion improvement. No confidence-policy implementation was replaced.

| Runtime lane, each detector mode | New hazardous frames stopped | Hazardous frames continued | Passable frames stopped |
| --- | ---: | ---: | ---: |
| Canonical confidence runtime | 25/25 | 0 | 17/17 |
| Plain-scene additive control | 24/25 | 1 | 17/17 |
| Plain-scene plus ego-motion | 24/25 | 1 | 17/17 |

The single missed hazard is the **first frame of the occluded-crossing case**,
before a motion pair exists. Both plain-scene control and candidate return
`continueForward`, rule `SPATIAL-P3-NO-CHANGE`; the canonical confidence runtime
stops. This is an exposed limitation of that experimental integration lane,
not a regression introduced by compensation. The zero-miss integration gate
fails and that lane must not replace the confidence-authority runtime.

The new data provide only a primary camera view, so they do not prove the full
body volume clear. All 17 physically passable captures still stop. Compensation
improves local motion attribution, not the coverage needed to retire unknown or
relative risk. The frozen rig sequence is rerun unchanged: **10/11 false stops**,
**60/60 known hazard stops per mode**, and **22/22 initial fault/explicit-risk
stops**. We do not claim the new producer was wired into that frozen runtime.

The next required result is track-owned temporal evidence sufficient to resolve
the relative hypothesis under the confidence policy. Sparse background matches
and an estimated zero world velocity cannot supply it. Unknown, missed tracks,
occluded extent and retained STOP history remain binding constraints.

## Validation and reproduction

The full check contains **38 new Flutter tests/replays**, **166 unchanged
upstream Flutter tests**, and **7 unchanged exact-surface Python tests**. It
also recomputes all 42 pinned NCNN outputs byte for byte and checks targeted
Dart analysis. New controls cover static world/user closing, real approach,
combined/lateral motion, pose errors, all capture/provider/reference/session
bindings, heading changes, missing/stale/future evidence, invalid RGB/depth/
units, shadow admission, physical/unknown history and deterministic replay.

The first development assertions exposed the plain-scene hazard miss and the
fact that adding zero-coverage motion evidence can lower aggregated observed
fraction. The replay checks now enforce the actual additive contract: no new
hazard miss relative to the matched control, no STOP release, no increase in
coverage and no decrease in unknown. The independent diagnosis separately
records the failed zero-hazard-miss and false-stop gates. Passing reproducibility
and monotonicity checks does not turn those product gates into passes.

The verifier checks immutable upstream receipts, all new source/payload hashes,
label separation, original clocks and continuous revisions, bounded intervals,
independent ego/body subtraction and sweep arithmetic, summaries and failed
gates. Run from the repository root:

```powershell
tool/model_benchmark/check_ego_motion.ps1
```

Data are in `scratch/ego-motion-2026-10-10/`: the new corpus and inference
manifest, deterministic `replay.json`, `diagnosis.json`, PNG/SVG plot and
`validation.json`. No Android model correctness, named-device timing, feedback
delivery, accessibility or controlled walking claim is established here.

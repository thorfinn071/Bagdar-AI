# Single-camera fresh scan window — 2026-10-11

Continue the one-camera observability diagnosis with an opt-in bounded temporal
cache and a known-scene counterfactual. Preserve all previous files and receipts,
unknown space, the 100000 us TTL, STOP history, models and shadow-only delivery.
The cache stores immutable original frames, never renews capture times, never
certifies stationarity, clearance or movement. It retains at most 12 fresh frames
from one camera/session/intrinsics/calibration identity. Bad inputs invalidate
the accumulated window. Clock rollback or lifecycle end terminates the window.
Ordering watermarks survive expiry and rejected frames; rejected frames cannot
reset the watermark. Valid calibration/intrinsics changes start a new window.

Use all 12 known static snapshots from ScanCompleteFixture, with the frozen
indexed whole-pixel body/floor producer and exact optical/height arrays. Keep
their original order of views, which was selected without scoring labels. Keep
the original 2.2-second schedule as a negative control. In separate clones only,
assign capture offsets round(i * 1000000 / fps), i=0..11, at fps 30, 60 and 120.
These timestamps are COUNTERFACTUAL, not measured camera timestamps. Add
processing-start lag 2000 us; also test 120 fps with 25000 us start lag and
120 fps with 2000 us lag plus 15000 us simulated computation. This is a six-case
matrix per snapshot. Source pixel arrays/poses and old original clocks stay
unchanged. No inference is run and no physical frame rate is claimed.

For each case, stream frames through the new window at their assigned capture
plus start lag. At the final time select only retained frames, then run the
existing indexed producer and strict evaluator via CameraScanAgeGate. The
original oldest contributing capture must reach the age gate; simulated compute
completion must update production time and the gate's advancing clock. Never
return the computed observation or decision after expiry. Record surviving
indices/clocks, geometric body/floor coverage, strict measurement status/reasons,
age status, and post-compute window. Labels are read after consumers have run.

Report the geodesic rotation between consecutive poses, sweep duration and peak
required angular rate for each counterfactual schedule. These are schedule
requirements, not phone capabilities. Multiple individually fresh views do not
establish that their scene states are mutually current: all positive measurement
results here depend on the frozen synthetic static scene assumption. The cache
and every report retain canAuthorizeMovement=false, promotionAllowed=false,
ordinaryCameraWired=false and falseStopReductionEstablished=false.

Before running the scene matrix, freeze new sources/tests/protocol/audit script,
the preceding single-camera preregistration chain, relevant fixture manifests,
and old scan receipts. Independently check timestamps, fresh suffix selection,
expiry, measurement/gate consistency, angular-rate arithmetic and frozen hashes.
Repeat the deterministic matrix byte-for-byte. Test lifecycle, identity changes,
bad pose/relative/stale/future data, replay/order, capacity, immutable snapshots,
expiry at 100000 vs 100001 us and clock rollback. No Android or latency readiness
claim follows from passing software tests or fixed-clock counterfactuals.

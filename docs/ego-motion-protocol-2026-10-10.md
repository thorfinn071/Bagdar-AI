# Ego motion and separated risk protocol — 10 October 2026

Implement a versioned, opt-in shadow producer. Never change frozen detector,
tracker, planner, original receipts or their history. Retain 100000 us current
freshness and 400000 us oldest evidence; missing/invalid poses are unavailable.
Relative NN proximity growth is an unconfirmed hypothesis, not metric velocity.
It must remain distinct from explicit semantic/TTC/metric and measured motion.

Local walking frames cannot be compared as a fixed world frame merely because
their reference strings match. Bind a healthy, original-capture translation
from the local walking origin into one fixed, gravity/heading-aligned frame.
This version supports translation only for that origin. Camera pan/pitch remain
in calibrated camera rotation. A changing body heading needs another validated
transform provider; it is not silently treated as translation.

Use the unchanged metric motion producer after transforming both depth and RGB
geometry into the fixed frame. Propagate translation errors into world bounds.
Then subtract the interval of walking-origin velocity and current origin from
world patch velocities and positions. Report world motion and body-relative
closing independently. A stationary world surface may still close on the user.
Missing/nonstatic patches never certify zero object velocity or free space.

An additive shadow scene may consume body-relative positive motion only. It
cannot retire relative hypotheses, physical risk, unknown or stop history.
Separate raw relative risk attribution from metric additions. Do not bypass
relative priority based on sparse stationary correspondences. A floor-only
diagnostic must not be represented as a fix for the actual distant-wall tracks.

Before evaluating the new corpus freeze six seven-capture cases: camera-only
forward translation in a clear room, camera-only yaw, stationary camera with
approaching object, translating camera with approaching object, crossing object
with camera motion, and an occluded crossing object. Room/material/dimensions
and texture seed differ from frozen motion corpora. Render original RGB and
whole-pixel conservative visible first returns; pinned MiDaS inference uses no
new fit. Geometry, motion-kind, object masks and hazard labels are scoring-only.

Compare naive local-frame motion, pose-aligned world motion and body-relative
motion. Recompute original detector/tracker and shadow runtime actions; report
false stops, hazard stops and motion classifications separately. New scene
parameters are fixed in the generator before evaluation. Seven frames at
200000 us intervals and one persistent source/tracker/runtime per case/arm.
The single primary view does not establish whole body coverage. Missing body
coverage must stay unknown even if visible local motion is stationary.

Unit controls: camera-only translation, stationary camera/true approach,
combined user/object approach, lateral motion, pose error, wrong/expired/future/
missing pose, reference/provider/session/capture/frame mismatch, nontranslation
body heading, invalid projection/RGB/units and stale completion. Verify that
world stationarity never cancels body-relative approach, relative risk or
history. Replay the frozen whole-track safety suite unchanged. Publish whether
the known 10/11 false-stop gate improved; no Android or live timing claim.

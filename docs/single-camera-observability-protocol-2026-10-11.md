# Single-camera observability preflight — 2026-10-11

Implement an opt-in architectural preflight separate from frozen producers/runtime.
Its output describes camera-frustum containment, never measured clearance,
obstacle absence, movement permission or calibrated phone readiness. Keep unknown,
100000 us freshness, STOP history, original models and all prior receipts.

Solve the interval of walking-forward distances where the entire requested
lateral/height cross-section AND floor lie inside a single calibrated pinhole
frustum. Use the existing right/down/forward camera → lateral/forward/height
walking transform. Each frustum plane is an affine inequality in distance;
intersect the constraints from every extremal lateral/height corner. Retain a
near gap and a far gap explicitly; never replace the original request with the
visible subinterval for movement recovery. Require fresh matching calibration,
reference, frame/session/transform/clock/model identity and metric pose.

Geometry containment is necessary but insufficient: valid first-return bounds,
occlusion, whole-pixel support, floor error and dynamic risks still need the
existing producer/evaluator. Even an all-invalid depth map may have an in-view
geometric interval; that must not become measuredClear. Relative MiDaS cannot
provide the metric pose/calibration input to this preflight.

Evaluate every one of the 35 previously exported view/case packets without
changing RGB, optics or neural outputs. This is a known-scene diagnostic, NOT
an independent holdout. Verify all input hashes. Compare full original requests
with deliberately shorter far-only requests through the frozen optical producer
and evaluator. Count blocked, unavailable and measuredClear separately. Every
partial measuredClear must fail coversCameraRecoveryVolume and appliesTo the
full request. Do not rename/reclassify prior 14/14 or 34/34 false STOP outcomes.

Independently verify reported analytic interval endpoints and their inside/outside
witnesses by direct perspective projection in Python. Check every old body/floor
cell's frustum status against the existing coverage maps. A geometric false reject
is allowed at the documented tiny image-border inset; a claimed contained box
with an outside corner fails the experiment. Before execution, freeze new sources,
old input receipts and the existing source files used by the comparison.

Report earliest fully in-view distance for each fixed view, counts of positive
partial measurements, unchanged full-request failures, relative/invalid/stale/
misaligned/calibration fault outcomes, and the remaining architectural decision.
Do not infer that a different model, phone, sequential scan or relaxed corridor
will fix the near gap. Measured latency, Android, frame-to-frame static assumptions,
physical metric alignment and assistive delivery remain unestablished.

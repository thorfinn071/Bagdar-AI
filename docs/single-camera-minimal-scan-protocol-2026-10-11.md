# Minimal finite camera scan — 2026-10-11

Continue the existing single-camera experiment without changing any frozen
producer, pixel predicate, TTL, request, capture, model, history or runtime.
This is a known-static-scene diagnostic, not phone validation or a STOP fix.

Before reading depth or labels, plan_camera_scan_geometry.py considers only the
12 existing camera poses/intrinsics and the producer's body/floor cell grid.
It recursively subdivides the same cells through depth four. Every terminal
cell must lie wholly in at least one selected frustum. Enumerate all subsets;
choose minimum cardinality, then the smallest numeric mask, retaining original
index order. This is a finite-pose geometry condition only. It cannot certify
depth, floor support, occlusion or temporal consistency. Freeze the resulting
geometry-plan.json before the measurement matrix.

Compare all twelve views with that fixed selected subset on all twelve existing
ScanCompleteFixture snapshots. First retain original capture offsets as a
negative control. In separate clones assign sequential counterfactual offsets
round(i * 1000000 / fps) for fps 30, 60, 90 and 120, with 2000 us start lag.
Also test 120 fps with simulated compute of 15000 and 25000 us. These assigned
timestamps describe hypothetical acquisition, not recorded camera speed.
Stream through SingleCameraScanWindow, select its surviving immutable frames,
then run the frozen indexed whole-pixel source and strict CameraScanAgeGate.
The original contributing oldest timestamp reaches the gate unchanged.

Read scoring labels only after measurement. Record selected original indices,
surviving indices/times, full observation, pre-completion measurement, released
status, oldest age, rotation requirements and all evidence limitations. Hazards
must never become measuredClear. Report any loss of complete measurement after
subset selection; never choose another subset using those measurement results.

For each scene, separately corrupt the complete selected 120 fps packet with
relative units, invalid pixels, absent height bounds, absent first-return bounds,
bad pose, wrong model and mixed sessions. None may produce measuredClear.
These fault cases are deliberately whole-packet faults, not claims about sparse
fault detection. Preserve existing fine-grained source and window tests.

Freeze source/test/protocol/audit/plan and the preceding preregistration chain
before scoring. Independently audit hashes, subset enumeration, projection
metadata, assigned clocks, suffix selection, strict ages and every released
clear section's complete body/floor fractions. Repeat deterministic output
byte-for-byte. Finally measure preloaded warmed source/evaluator/gate elapsed
time on this desktop for both subsets over three alternating rounds. Include
actual compute time in a separate advancing replay clock; no fixed-clock result
may be reported as measured latency. No neural load, physical capture, named
phone, scene-motion or Android performance claim follows from this experiment.

All artifacts retain promotionAllowed=false, ordinaryCameraWired=false,
falseStopReductionEstablished=false and canAuthorizeMovement=false. Existing
14/14 and 34/34 false STOP receipts remain unmet until a proper runtime replay
with independently justified ordinary-camera measurements improves them.

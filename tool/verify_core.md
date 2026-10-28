# Core software verification

Research payloads must be present at their pinned paths. Use the
[dataset guide](datasets/README.md) to verify or restore them. Bundles are
currently local and no public source is configured. The verifier's required
fixture checks remain unchanged.

The 2026-10-04 concurrent-load experiment adds two desktop steps: its separate
write-once receipt preserving v2, and Windows x64 LLVM native-module compilation,
full AOT diagnostic/functional parity, negative cases and actual shadow runtime.
Run `dart run tool/model_benchmark/evaluate_fast_camera_motion_load.dart --check`.
The required native build currently uses a Windows-host LLVM compiler from the
installed Android NDK; it does not build or validate Android code. `--measure`
runs three alternating advancing-clock trials against current Dart v2, with
and without live pinned NCNN. Timing results are separate from software RC and
the immutable receipt. See `docs/camera-fast-motion-load-protocol-2026-10-04.md`.

The 2026-10-03 independent fast motion stage adds two required gates: write-once
source/report integrity and compiled desktop Dart AOT parity, persistent-worker
functional replay, worker negative cases, and actual shadow scene/planner replay.
Run `dart run tool/model_benchmark/evaluate_fast_camera_motion.dart --check`.
Use `--measure` separately for alternating warmed JIT/AOT profiles and advancing
clock AOT worker replay, including a competing live pinned CPU NCNN branch.
Measurements exclude fixture preload and real phone capture/feedback. Numeric
caches retain at most the current and previous immutable frames, without
retimestamping authority. Worker buffers transfer read-only RGB/depth views;
idle feature preparation is measured separately and grants no risk authority.
The receipt is `camera_fast_motion_contract_v2.json`; the initial candidate's
receipt and matching source snapshot are preserved. This risk-only branch never certifies free space;
with NN unavailable, the sufficiently passable control stays stop/hold.
All phone/device/promotion gates remain separate.

Ordinary developer suite (NCNN reference corpus may skip):

```text
powershell -File tool/verify_core.ps1
```

Release-candidate mode: missing required Core fixtures **fail**, they do not skip.

```text
powershell -File tool/verify_core.ps1 -Rc
```

`-Rc` passes `--dart-define=BAGDAR_RC=true` so
`test/ncnn_reference_correlation_test.dart` executes and fails if
`test/fixtures/ncnn_contract/reference_outputs.json` is absent.

A green ordinary run is not a Core Safety RC. Hardware, TalkBack, walking,
and corpus gates remain separate.

The verifier runs the v1, temporal v2, and contextual v3 Blender frame timelines explicitly.
The canonical procedural manifest alone checks external manifest hashes; it
does not execute their frames. The detector diagnostics have separate Python
environment requirements and are reported in
`docs/blender-temporal-evaluation-2026-09-22.md`. A passing Core software RC
does not promote a detector: v2 has zero central hazard-mask overlaps on its 12
obstacle frames, while contextual v3 has zero class-compatible overlaps on its
six COCO-scorable frames.

The verifier also reproduces the v2 and v3 offline Blender oracle-depth shadow
runtime reports from `test/blender_temporal_shadow_replay_test.dart`. This test uses
precomputed desktop RGB predictions and Blender raycast depth, then exercises
the actual generic geometry detector, tracker, scene adapter, planner, and
shadow arbiter. Its green gate checks conservative safety behavior and report
integrity; the report separately exposes false stops on traversable scenes.
Accordingly, the aggregate JSON reports `modelCorrectnessRc=not_established`;
model correctness requires the separate scene, downstream, and device gates.
The contextual v3 doorway classification fix and its remaining conservative
stops are recorded in `docs/blender-context-evaluation-2026-09-23.md`.

The verifier also pins desktop NCNN MiDaS depth maps derived from the same
contextual RGB frames, runs a separate relative-depth shadow replay, and checks
the oracle-versus-NCNN comparison report. This isolates a model-depth/geometry
regression; it does not emulate Android YUV capture, provider health or audio.

The 2026-10-01 forward-ground and component-uncertainty regressions reduce
contextual desktop NCNN traversable stops from 6/6 through 4/6 to 3/6,
while retaining 12/12 hazard stops and zero
hazard continues. `test/generic_obstacle_free_space_regression_test.dart`
also gates fully observed procedural passages, per-band depth dropouts and
blocked/degraded cases through the shadow runtime.
`test/generic_geometry_uncertainty_regression_test.dart` separates low component
confidence from sector observability while preserving close/approaching threats,
coverage loss and degraded sensing stops. See
`docs/false-stop-reduction-2026-10-01.md` for the before/after evidence and
the remaining doorway and oracle-depth limitations. This is a desktop software result.

The 2026-10-02 opening diagnostics are opt-in and do not change decision inputs
or the ordinary detector's fit budget. The shadow reports expose separate
aperture/ground-disagreement reasons and opening-local depth/surface support.
`test/generic_obstacle_opening_diagnostics_test.dart` checks missing support,
blocked openings, crop coordinates and diagnostic isolation across frames.
See `docs/doorway-evidence-diagnostics-2026-10-02.md`; NCNN false stops remain 3/6.

The metric passage contract has a required standalone reproducibility gate:

```text
dart run tool/model_benchmark/evaluate_passage_clearance_contract.dart --check docs/_baseline_logs/passage_clearance_contract.json
```

Its 44 synthetic cases check declared conservative width, headroom, floor,
coverage, identity, calibration and timestamps; nine additional Flutter tests
check boundary conditions and result reuse. Relative depth never supplies metres.
No calibrated producer or runtime integration is included, and a green contract
gate establishes neither model accuracy nor physical device calibration.
See `docs/passage-clearance-contract-2026-10-02.md`.

The opt-in synthetic passage experiment has a separate required replay gate:

```text
flutter test --no-pub --concurrency=1 --dart-define=BAGDAR_CHECK_PASSAGE_REPORT=true test/synthetic_passage_shadow_replay_test.dart
```

On the same 18 contextual frames, NCNN control retains 3/6 traversable stops;
adding the complete Blender geometry oracle gives 0/6 while both runs retain
12/12 hazard stops and zero hazard continues. This is additional omniscient
geometry, including camera-hidden surfaces, not camera-only model improvement.
The runtime option is absent by default and always uses shadow delivery.
42 safety regressions cover mesh contrasts, input faults, threats and expiry.
See `docs/synthetic-passage-shadow-2026-10-02.md`.

The camera-visible passage stage adds three required gates: first-return corpus
and whole-layout split integrity; pinned NCNN inference/frozen scale `--check`;
and the deterministic camera-only shadow replay report. Flutter tests run serially.
The functional CLI is `dart run tool/model_benchmark/evaluate_visible_passage.dart --check`
(`--write` refreshes the report and separate measured timings).
Wall-clock desktop timings are stored separately and are not compared as
deterministic receipts. A passing reproducibility gate does not imply false-stop
reduction or metric MiDaS acceptance. See
`docs/camera-visible-passage-evaluation-2026-10-02.md` and
`docs/_baseline_logs/camera_visible_passage_replay.json` (`promotionAllowed=false`).

The camera recovery follow-up adds three required gates: integrity of the separate
`camera-visible-passage-recovery-v1` corpus, RGB-only NCNN inference with the original
frozen calibration, and the recovery replay `--check`. Run
`dart run tool/model_benchmark/evaluate_visible_passage.dart --check --recovery`.
Its four validation and twelve test layouts were declared before testing the fix.
Independent evidence clocks and full-volume coverage recovery are opt-in through
`requireCameraEvidence`; the ordinary application path is unchanged. Obstacles,
conflicts, unclassified unknown and the planner's standing recovery checks retain
priority. See `docs/passage-recovery-evaluation-2026-10-02.md`.

The 2026-10-03 camera-track association stage adds four required gates: the
separate `camera-track-passage-v1` corpus, the implementation freeze recorded
after development and before the first test replay, pinned RGB-only NCNN with
the original rejected metric calibration, and the functional shadow replay.
Run `dart run tool/model_benchmark/evaluate_visible_passage.dart --check --association`.
The 22 whole-layout scenes contain six validation and sixteen test layouts.
On the held-out test, camera false stops decrease from 3/6 to 1/6, with 10/10
hazards stopped and zero unsafe continues or unjustified clearances. The
remaining false stop preserves a relative approaching-track risk. Association
requires its own opt-in flag and matching camera data; historical physical risk,
motion/semantic priority, unknown coverage and standing recovery remain intact.
No active application/device promotion is provided. Diagnostic RGB/component/depth
plots and separate timings are linked from
`docs/camera-track-association-evaluation-2026-10-03.md`.

# Camera temporal stability gate (2026-10-03)

Core RC additionally checks the separate `camera-temporal-passage-v1` assets,
write-once development freeze, pinned NCNN outputs and deterministic shadow
replay via `dart run tool/model_benchmark/evaluate_temporal_passage.dart --check`.
Desktop timings are separate and are not compared byte-for-byte. This is a
software/shadow gate; phone motion calibration and walking remain unverified.
Previous camera-track implementation/freeze and reports remain unchanged.

# Camera metric motion gate (2026-10-03)

Core RC checks `camera-metric-motion-v1`, independent projection witnesses for
observation sufficiency, a write-once development freeze, pinned NCNN outputs,
and `dart run tool/model_benchmark/evaluate_metric_motion.dart --check`.
RGB/depth/pose correspondences produce local velocity intervals only. The
opt-in scene model adds motion risk and cannot clear space, cancel relative or
semantic risk, reset physical history or release the planner's stop state.
Functional processing clocks and separate desktop timing estimates are reported
independently; this stage does not establish phone latency or walking readiness.

# Camera scale motion gate (2026-10-03)

The additive scale-motion stage has four further required gates: independent
`camera-scale-motion-v1` visible assets and scoring-mask isolation, write-once
development freeze, pinned NCNN reproduction, and
`dart run tool/model_benchmark/evaluate_scale_motion.dart --check`.
Its spatial-only ablation and scale matcher run on identical RGB; scoring masks
are read after runtime decisions. Variable desktop timings remain separate.
All producers and adapters remain opt-in shadow, `promotionAllowed=false`.

# Camera processing age gate (2026-10-03)

Two additive required gates check the write-once processing-age source/report
contract and `evaluate_camera_processing_age.dart --check`. The latter verifies
exact frozen/cached matcher equality on known regressions, completion/dispatch
deadlines, a one-frame pending queue, deterministic overload and late runtime
decisions. Previous source freezes remain intact. Use `--measure` for separate
warmed matcher timings and live pinned NCNN elapsed replay. Measurements remain
outside deterministic receipts; no timing threshold relaxes the 100 ms current
capture age or oldest+400 ms expiry. Unavailable stops are reported separately
from stops supported by fresh evidence. All paths remain experimental shadow;
phone capture-to-command latency and active guidance are not established.

# Paired Blender scenes (2026-10-04)

Five additional required gates check the separate 12-scene/132-frame corpus,
admission negatives and write-once source/report closure, actual pinned YOLO
and NCNN reproduction, two fixed-clock shadow runtime replays, and a separate
quality assertion. Hash parity is insufficient: the quality gate requires
zero `continueForward` on labelled hazard frames, no missed/late stops within
the declared 300 ms onset window, and no imminent-hazard rule on physically
passable moving frames. Ordinary conservative unknown-space stops are reported
separately and are never relaxed to meet a test.

The first baseline failed that quality gate; its source snapshots and all
first reports remain immutable. The correction gate now evaluates a separate
versioned report, with the same zero limits, and both legacy and corrected
replays run. The original live source hashes remain unchanged and their
verifier still runs. `verify_paired_scene_correction.py --baseline-only`
also checks archived bytes, while the correction receipt pins the separate
module and camera wiring. A corrected camera shadow policy keeps unresolved
components blocking and does not turn percentile proximity into confidence.
See `docs/blender-paired-scenes-evaluation-2026-10-04.md`. New scenes were used
for evaluation initially; the separately declared correction uses this known
regression corpus. Model weights and quality thresholds were not tuned.
See `docs/blender-paired-correction-evaluation-2026-10-04.md` for both
the corrected critical outcomes and the remaining 55/55 moving false stops.
After this first evaluation the corpus is a known regression, so future
generalisation claims require another unseen set. Timings are serial desktop
stages; no Android/camera/audio/thermal evidence is added.

# Visible body observability (2026-10-04)

Two further gates check the separate first-return whole-pixel optical packets
against the same 132 original poses, preserve both older source/output freezes,
and reproduce the single-frame MiDaS comparison plus static-scan diagnostics.
The body volume remains 0.9m wide, 1.85m high, and 0.2–3.5m forward. Unknown
body space never becomes free because a floor component is localized outside.
The 12 frozen-state scans are geometry diagnostics with a separate 3s policy;
the strict 100ms policy must reject every 2s scan. They cannot establish
dynamic safety or hide capture-to-decision latency. Positive full-volume and
floor-bounds/depth-hole/nonmetric contrasts also run in the Flutter suite.
The original camera shadow wiring is unchanged; this metric provider is only
an explicit synthetic benchmark input. See
`docs/blender-visible-body-evaluation-2026-10-04.md` and its protocol.

# Complete static scan coverage (2026-10-04)

Two further required stages preserve the preceding body/source receipts and
check independent full-pixel surface envelopes plus both scan replays.
Pure polygon tests reject overlaps with holes, subpixel gaps, and exhausted
fragment budgets. Separate Blender witnesses pin identical previous arrays,
hidden-geometry invariance, and a thin foreground missed by centre rays.
The geometry suite now contains 35 tests. Canonical shared near-plane
vertices and exact rational polygon topology retain representable real gaps
without accepting numerical cracks as visible slab bottoms. Separate height
supplements preserve all depth/free-Z assets and prior positive floor proofs.
The new provider supplies correlated first-return height and free-Z bounds;
the separate synthetic wrapper retains the previous body/occupancy/conflict
producer. Camera wiring and neural models are unchanged.

The 12 optical views are selected from intrinsics and the request. Geometric
coverage on frozen snapshots and strict 100ms freshness are separate gates;
the latter must reject every 2.2s scan, even when geometry is complete.
This does not remeasure the 55 moving false stops, establish Android timing,
or authorize assistive promotion. Functional outputs are write-once.
The final replay also reproduces the original height ablation: all six
passable snapshots retain complete body coverage but lack floor support.
# Static scan processing evidence (2026-10-04)

The aggregate Core suite includes the indexed complete-envelope observation
parity and scan age tests. The additional Python stage checks two versioned AOT
elapsed receipts, live pinned NCNN load identities, exact timing arithmetic,
strict stale rejection, fallback/false-stop counts and all previous source
freezes. Timing values are measured observations; they are not a deterministic
performance gate. Fresh full coverage remains unmet at the original 100 ms TTL.

Reproduce measurements into new write-once paths, after compiling the current
standalone runner; do not overwrite the saved baseline receipts:

```powershell
dart compile exe tool/model_benchmark/profile_scan_processing.dart -o scratch/scan-processing.exe
& scratch/scan-processing.exe --output scratch/scan-processing-elapsed.json --rounds=3
& scratch/scan-processing.exe --output scratch/scan-processing-nn.json --nn --rounds=3
& tools/ncnn/.venv/Scripts/python.exe tool/model_benchmark/verify_scan_processing.py
```

See `docs/blender-scan-processing-protocol-2026-10-04.md` for measurement scope,
and `docs/blender-scan-processing-evaluation-2026-10-04.md` for results. This
experiment has no normal-camera, active planner, speech or haptic wiring.

# Synchronized synthetic rig (2026-10-04)

The new required integrity stage validates the new eight-state corpus, its
independent optical witnesses, zero-skew channels/calibration, frozen coverage
math and two v3 AOT receipts. It preserves the initially rejected v1/v2
receipts and their exact source snapshots. The aggregate Flutter suite includes
22 additional synchronized-rig tests. This is an ideal co-located optical rig;
phone realization, capture/transport cost and dynamic clearance are unverified.

The corpus and receipts are write-once. Reproduce elapsed samples into new paths:

```powershell
dart compile exe tool/model_benchmark/profile_synchronized_rig.dart -o scratch/rig-processing.exe
& scratch/rig-processing.exe --output scratch/rig-elapsed.json
& scratch/rig-processing.exe --output scratch/rig-elapsed-nn.json --nn
python tool/model_benchmark/verify_synchronized_rig.py
flutter test test/camera_synchronized_rig_test.dart test/camera_scan_age_gate_test.dart
```

Blender source corpus and the coherent v2 bundle can be generated into their
versioned directories only when those completed manifests do not exist:

```powershell
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --python-exit-code 1 --python tool/blender/generate_synchronized_rig.py -- --output test/fixtures/spatial_safety/blender-synchronized-rig-v1
& 'C:/Program Files (x86)/Steam/steamapps/common/Blender/blender.exe' --background --python-exit-code 1 --python tool/blender/export_synchronized_rig_bundle_v2.py
```

See `docs/blender-synchronized-rig-protocol-2026-10-04.md`, its bundle supplement,
and `docs/blender-synchronized-rig-evaluation-2026-10-04.md`. Performance is
measured evidence, not a deterministic release pass. The 100 ms TTL is retained.


# Fast-motion transport/allocation correction (2026-10-07)

Two required stages check the versioned packed source receipt and rebuild its
native AOT parity/worker/shadow checks. Earlier load and kernel receipts remain
unchanged. The Flutter suite includes the new transport alignment and packed
worker contract tests. Elapsed timing is reported separately; software checks
do not certify the 100 ms performance gate or remove paired-scene false stops.
See `docs/camera-fast-motion-packed-protocol-2026-10-07.md`.


# Independent callback stream (2026-10-07)

Two additional stages preserve the earlier receipts, check stream sources,
and reproduce control/packed 109-frame diagnostic parity plus independent-feed
and app scheduler contracts. The new elapsed CLI schedules callbacks without
waiting for NN or fast completion. Depth load is MiDaS Small NCNN only, with
one active job and no queue. Elapsed timing remains separate from software RC.
See `docs/camera-fast-motion-stream-protocol-2026-10-07.md`.

# Strict SIMD motion (2026-10-07)

Two additional stages check the separate SIMD source receipt, preserving all
older receipts, and rebuild both DLLs with strict arithmetic flags. They compare
bitwise scratch results on 85 differential cases, full 109-frame kernel/worker
reports, native ownership/freshness tests and the 67-frame shadow replay. The
ordinary camera does not use this Windows x64 experiment. Timed trials remain
separate from software RC and model correctness.
See `docs/camera-fast-motion-simd-protocol-2026-10-07.md`.

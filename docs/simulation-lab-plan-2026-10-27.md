# Bagdar simulation lab: implementation plan

Date: 2026-10-27. This is a synthetic software evaluation, not physical-device or walking validation.

## Architecture chosen before implementation

1. Add a separate, opt-in simulation entry point. Feed immutable, hash-checked YUV420 camera frames to the existing `AiCameraScreen` callback. Keep the current YOLO, NCNN worker, depth controller, trackers, scene/planner and inspection interface. Normal launches continue to use the physical camera. The simulation build cannot send SMS or initiate calls.
2. Keep sequence capture times, delivery delays, missing frames and continuous application state. Do not reset the detector between frames or retimestamp a delayed image as fresh. Simulated orientation/motion must be explicitly labelled and kept separate from physical-device evidence.
3. Generate a new corpus in a new directory. Use structurally different environments with paired unobstructed/obstructed routes, metric dimensions, animated cameras and moving objects. Include walking shake, low light/noise, defocus, rain/lens droplets and a combined stress condition. Use fixed seeds and record all conditions, source hashes and frame hashes.
4. Export runtime inputs separately from evaluator annotations. Ordinary-camera inference receives camera pixels and synthetic sensor samples only; exact depth, collision geometry, labels and expected actions never enter this path. Preserve relative MiDaS semantics and shadow delivery.
5. Provide one-command generation, validation, desktop replay and emulator launch. Pre-rendering is independent of replay speed. Report missing dependencies and unavailable models explicitly.

## Verification and honest completion criteria

- Validate frame identity, dimensions, plane lengths/strides, hashes, safe paths, increasing timestamps and bounded input sizes. Reject malformed bundles before starting playback.
- Test pause/resume, end-of-sequence, delayed/dropped frames and session retirement; reject simulation in ordinary builds.
- Run real pinned model inference and the production perception path on newly generated frames. Distinguish cached desktop replay from live Android inference.
- Inspect rendered scene/effect previews. Report both dangerous decisions/missed or late hazard responses and stops on physically passable controls. A stop due to unknown evidence is not confirmed hazard detection.
- Record the exact tested subset, actual model availability and emulator result. Synthetic image realism, sensor profiles and laptop timings cannot establish camera calibration, phone performance, TalkBack usability or controlled walking.
- Preserve all pre-existing working-tree changes and older frozen corpora/reports. Do not modify safety thresholds, enable assistive mode or promote results to physical evidence.

## First delivery

A working end-to-end slice with a configurable scene generator, effect pipeline, checked replay format, actual app input adapter, tests, visual previews and a reproducible evaluation. Larger suites use the same format and commands; unexecuted combinations remain unexecuted.

## Continuation: finish the automated run

1. Isolate automatic episode navigation from animated screen transitions. Await actual disposal with a bounded deadline, and record the current episode/phase so a failure cannot look like a completed batch. Keep interactive navigation unchanged.
2. Add a widget regression for two consecutive episodes, disposal before singleton reuse, and timeout cleanup. Add explicit selection of a small subset for an emulator smoke run.
3. Build one immutable simulation APK, verify the installed APK identity, and run two contrasting clips with live CPU YOLO/NCNN. Only proceed to all 72 clips after both terminate and produce matching receipts.
4. Run all 72 clips, collect receipts for the exact run ID, and evaluate actual model calls, data acceptance/rejection, missing decisions, latency and passable/hazard outcomes. Report stalled or failed episodes explicitly.
5. Run appropriate affected software checks. Save a concise evaluation with the exact APK/input/source identity and the remaining synthetic/physical evidence boundary. Investigating the blur/noise gate is a separate measured follow-up; do not tune it to make this corpus green.

Native smoke evidence revised step 1: zero-duration routes passed widget tests,
but an Android ANR still prevented disposal on the emulator. Therefore the
default host batch uses an independently cold-started process of the same APK
for every episode and waits for an input/run-matched application receipt.
The within-episode camera clock, models, scheduler and temporal state remain
unchanged. Keep the navigation-based runner opt-in and preserve its failed smoke
receipt. Record timeout/ANR evidence rather than changing perception deadlines.

## Completed continuation and next steps

All 72 two-second episodes produced matching receipts: 2,232 delivered frames,
115 YOLO results, 64 depth-provider calls and 55 accepted depth results. Only 55
source frames had associated spatial results. This establishes batch execution,
not perception quality or sustained application stability. See
`simulation-lab-continuation-2026-10-27.md` for the measured breakdown.

## Completed independent quality diagnosis

The first quality-diagnosis slice is now complete. An independent corpus
of 968 diagnostic images reproduced blur-to-noisy-blur acceptance flips in 64/64
paired controls. Phase-shifted sharp grids were admitted in 28/64 phases with
stride 8 versus 64/64 with dense sampling. Six unchanged-APK episodes also
reproduced the blur/noise difference. See `image-quality-evaluation-2026-10-27.md`
and `image-quality-android-probe-2026-10-27.md`; neither changes production gates.

The research-only quality observer is now implemented. The intended slice separates
noise-dominated, insufficient-structure and blur-suspected evidence, retaining
an unknown state. It must estimate from pixels, never consume the generator's
true noise/blur parameters. Test any candidate on a new predeclared holdout,
including correlated/shot noise and non-periodic sparse edges. Do not tune on
the current holdout or turn an optically sharp image into movement authority.

## Implemented continuation and remaining work

The frozen observer was evaluated on 1,032 new images. Correlated noise defeated
it, so it remains research-only. Two continuous 30-second streams now exercise
actual Android background/resume and screen reuse. Framework diagnostics found
an uninitialized acoustic-subsystem cleanup crash; its fix passed the final
native run with 902 delivered frames and both disposal acknowledgements. A new
versioned camera/geometry/material smoke corpus contains eight clips/56 frames.

See `quality-and-continuity-evaluation-2026-10-27.md` for executed checks and
`quality-and-continuity-implementation-plan-2026-10-27.md` for all remaining
milestones: new observer holdout, minute-scale stress, stationary hardware,
physical perception and independently gated controlled walking. Hardware camera,
audio and TalkBack validation remain separate; no synthetic result completes them.

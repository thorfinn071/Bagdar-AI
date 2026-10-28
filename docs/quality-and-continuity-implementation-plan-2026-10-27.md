# Quality observer and simulation continuity plan

Date: 2026-10-27. Implements the next work in `simulation-lab-plan-2026-10-27.md`.

## Scope and sequence

1. **Research quality observer.** Add a pure Dart, pixel-only observer and a
   standalone comparison runner. Record high-frequency residual, coarse edge
   support and edge concentration separately. Return noise-dominated,
   insufficient-structure, blur-suspected, structured, or unknown evidence.
   Structured is an optical description, never permission to process or move.
2. **Fresh experiment.** Freeze `quality_observer_protocol_v1.json` before input
   generation or scoring. Use new disjoint development/holdout chart families and
   seeds, white/correlated/shot noise, sparse nonperiodic edges and sampling-phase
   controls. Freeze the candidate source hash in the corpus manifest. Do not
   revise it after seeing holdout. Compare the existing filter and candidate,
   including paired masking, sparse sharp controls, uncertainty, and cost.
3. **Continuity and lifecycle.** Package longer versioned streams from existing
   rendered inputs, preserving one continuous app state. Add elapsed-time,
   memory and callback concurrency diagnostics. Exercise actual Android
   background/resume and navigation disposal, with bounded controller deadlines,
   run/input/source identities, explicit ANR/timeouts and partial failures.
   A repeated short render is a continuity stress test, not a new natural scene.
4. **Corpus breadth and physical gates.** Provide versioned camera/condition
   controls and provenance for new experiments. Procedural variation does not
   establish calibrated materials, sensor realism or camera accuracy. Prepare a
   concrete stationary hardware checklist. Record physical camera, audio,
   TalkBack and controlled walking as not_run unless actually observed.

## Candidate hypotheses, frozen before evaluation

- Dense pixel scans avoid selecting only one phase of an 8-pixel grid.
- Median absolute 2x2 mixed differences report a residual proxy, not calibrated
  camera noise sigma; image texture and correlated noise can confound it.
- Smoothed gradients locate support. Fine gradient / wider edge span describes
  edge concentration. Sparse support, clipping, low contrast and contradictory
  signals must retain uncertainty rather than claim a clear image.
- Fixed constants are engineering hypotheses, not fitted or validated camera
  thresholds. No automatic production admission or runtime promotion is added.
- Background: Colom and Buades explain why image structure confounds direct
  noise estimates: https://www.ipol.im/pub/art/2013/90/ . This candidate is an
  original lightweight diagnostic, not an implementation of that paper.

## Validation and completion evidence

- Unit regressions: invalid layout/buffers, row padding, immutable inputs, noise
  masking, low structure, broad edges, phase changes and unknown results.
- Corpus/runner regressions: split leakage, changed pixels/protocol/source,
  escaped paths, duplicate IDs, no overwrite, finite metrics and empty groups.
- Lifecycle regressions: pause ages, outstanding callback accounting, disposal,
  deadlines, foreign receipts and no fabricated success on timeout.
- Run affected Flutter tests serially and targeted analysis; run Python lab
  tests; execute the fresh benchmark and Android emulator continuity probe.
- Seal an evaluation with source/input/output hashes and measured limitations.
  Candidate rejection is a completed experiment, not a reason to tune holdout.

## Invariants

Preserve the dirty working copy and earlier receipts. Production `BlurDetector`,
its threshold/stride, safety authority, stale-data limits and SOS behavior are
unchanged. `promotionAllowed=false`; generic geometry remains shadow-only.
Physical-device evidence cannot be inferred from desktop or emulator results.

## Execution status

The observer, frozen experiment, continuity diagnostics/controller, versioned
procedural controls and stationary hardware checklist are implemented. The
1,032-image v1 experiment is complete: correlated noise defeats this candidate,
so it remains research-only. The native probe identified cleanup of an
uninitialized acoustic subsystem as the screen-disposal failure. Cleanup is now
safe before initialization and during initialization, with regression coverage.
See `quality-and-continuity-evaluation-2026-10-27.md` for final executed checks,
native results, source/input identities and remaining gates.

## Remaining milestones and their exit evidence

1. **Observer v2, before integration.** Predeclare new disjoint families/seeds.
   Measure correlated noise at several spatial scales, signal-dependent noise,
   directional motion blur, sparse curved edges, and periodic cells including
   the original 8-pixel aliasing diagnostic. State contradictions explicitly;
   do not declare suspected blur absent merely because a residual is small.
   Compare all evidence states and cost by condition, without a pooled accuracy
   that hides weak groups. A changed candidate must never reuse v1 holdout as an
   unseen test. Integration remains gated on new evidence and named-device cost.
2. **Longer software stress.** Extend continuity to minutes using streamed
   verified assets instead of raising memory limits. Record event retention,
   native queue ownership where instrumentable, memory/thermal trends, repeated
   background/resume and five screen reopen cycles. Thirty seconds and RSS
   snapshots alone do not establish memory-leak freedom or thermal stability.
3. **Stationary physical Android session.** Execute the named-device checklist
   with the exact APK, real camera, audio and TalkBack. Preserve failures and
   logs. Fix observed lifecycle/accessibility issues before further promotion.
4. **Perception evidence.** Capture independently labelled physical scenes and
   measured camera/depth alignment. Separate optical condition, object evidence,
   temporal safety behavior and positive free-space coverage. Relative depth or
   absent detections cannot establish a clear walking corridor.
5. **Controlled walking and release.** Establish a separately reviewed human
   protocol only after the physical/perception gates. Keep walking disabled
   until those gates are independently evidenced. Desktop and emulator results
   never complete this milestone.

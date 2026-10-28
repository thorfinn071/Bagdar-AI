# Image quality and simulation continuity evaluation

Date: 2026-10-27. Software experiment; no physical-device or walking promotion.

The planned software stages are implemented. The quality observer is a measured
research candidate, **not suitable for replacing production admission**. The
Android continuity experiment reproduced and fixed an actual cleanup crash; the
final run completed both streams in the same app process.

## Implemented changes

- Pixel-only research observer with separate residual, structure and edge
  concentration signals, explicit unknown evidence and no admission API.
- Fresh frozen protocol/corpus, unchanged-filter comparison, candidate-source
  binding, input-integrity validation and reports preserving every evidence state.
- Longer streams, deduplicated checked preloads, callback/RSS/scheduler samples,
  actual Android Home/resume, framework-error capture and separate route/host
  disposal acknowledgements. Disposal releases replay buffers and callbacks.
- Safe, idempotent acoustic-subsystem cleanup before initialization. Core skips
  initialization of that deferred subsystem but still disposes its owner. The
  former late-field access threw during camera-view-model cleanup and prevented
  route disposal. Failed hypotheses about frame delivery/navigation were removed;
  the final app uses its original normal pop path.
- Versioned camera, geometry and material controls with original/effective spec
  hashes, and a separate stationary-device acceptance checklist.

## Frozen observer v1

Artifacts: `output/simulation-lab/quality-observer-v1/`.
Candidate SHA-256: `5d8bf9760896cc8287c28115800224cbc4b2103d7d015711f0e67c81f12f0e56`.
All **1,032** images were generated after protocol/source freeze. Development and
holdout families/seeds are disjoint and differ from the earlier chart corpus.
The candidate takes only pixels/layout, never known blur/noise parameters.

| Holdout condition | Images | Candidate evidence |
|---|---:|---|
| Sharp | 32 | 24 structured; 8 insufficient structure |
| Defocus 6 | 32 | 22 blur suspected; 10 insufficient structure |
| Defocus 6 + white noise | 32 | 32 noise dominated |
| Defocus 6 + shot noise | 32 | 32 noise dominated |
| Defocus 6 + correlated noise | 32 | **32 structured: unresolved masking failure** |
| Directional motion blur | 32 | 12 structured; 9 blur suspected; 7 unknown; 4 insufficient structure |

The unchanged filter admitted all 32 noisy blurred holdout images for each of
white, correlated and shot noise. The new residual signal handles the white/shot
controls but does not solve correlated noise or all directional blur. All eight
sharp sparse-arc controls remained insufficient structure. That state cannot be
counted as successful recognition of a sharp image or a navigation-quality pass.
All 256 new phase controls were structured; the existing filter also admitted all
of them. These cell-7/cell-11 controls do not prove the original cell-8 problem
solved. No threshold/candidate was changed after this holdout evaluation.

At 320x480, desktop Dart/JIT observer cost was p50 **4.054 ms**, p95 **5.027 ms**,
maximum **7.829 ms**, 516 observations. Includes allocation/JIT effects and excludes
IO; it is not Android inference latency. The executed scorer is preserved as
`scorer-executed.dart.txt`; later scorer cleanup/freeze tests did not rerun or
retune the candidate. Full per-condition/pair/phase/sparse results are in
`observer-summary.json` and `report.md`.

The original diagnostic is informed by the general warning that image structure
confounds noise estimates; see [Colom and Buades](https://www.ipol.im/pub/art/2013/90/).
It does not implement that paper's estimator.

## Final Android continuity run

Artifacts: `output/simulation-lab/continuity-v1-run6/`.
Run ID: `4997ea51-f055-49f6-a020-b37fa87288b7`.
APK SHA-256: `2e6c89e0fe30670cf56c432d83ab2c86db228dafa66e2221fde3eba471f65447`.
The build and installed APK were bound to **268** current Dart source hashes.

| Continuous stream | Delivered frames | YOLO results | Depth results / accepted | Route + host disposed |
|---|---:|---:|---:|---|
| Courtyard, low light | 451 | 104 | 34 / 33 | yes |
| Hallway, clean | 451 | 7 | 7 / 7 | yes |

Both inputs lasted 30 seconds and repeat existing two-second rendered clips,
including their ideal IMU samples. State continues inside each stream; loops are
stress inputs, not a naturally continuous scene. The second screen initialized
and completed in the same application process after the first screen closed.

- All **902** expected frame identities delivered; no callback errors or omitted
  telemetry events. Final callback counts and active model lanes were zero.
- Actual inactive/hidden/paused/resumed events and post-resume delivery were
  observed in the first stream. Target background interval was 2 seconds;
  controller Home-to-resume time was 3 seconds including ADB overhead.
- First-stream delivery age: p50 4.727 ms, p95 1604.642 ms, maximum 3042.946 ms.
  Catch-up after backgrounding retains original capture times. One depth result
  was rejected for `stale_observation_latency`; freshness limits were unchanged.
- Second-stream delivery age: p50 1.767 ms, p95 5.642 ms, maximum 28.647 ms.
- Sampled active model lanes peaked at 2; sampled queued camera frames at 0.
  These scheduler snapshots and callback concurrency are not native inference
  queue instrumentation. Native internal queue depth remains unmeasured.
- RSS maximum: 760,233,984 bytes in the first stream and 677,597,184 bytes in the
  second. These short debug-emulator samples do not establish leak freedom,
  thermal stability or phone memory requirements.
- Batch completed; both route and end-of-camera-disposal acknowledgements true.
  No framework errors, recorded ADB read timeouts or observed ANRs in this run.
- The clean hallway still had **437 quality skips / 451 frames**. Continuity
  success does not establish perception usefulness or fix the original filter.

Earlier failed native runs remain in `continuity-v1-run1` through `run4`.
Run4's `framework-errors.json` and cleanup-stage evidence identify the
uninitialized acoustic classifier, followed by a secondary framework error.
Run5 completed both native streams but its collector aborted on an ADB read
timeout. Its exact native receipts were recovered without changing the original
failed status (`recovered-evaluation.json`). The controller now records read
timeouts and retries on later bounded polls, and re-collects final receipts after
the terminal marker to avoid a collection race. Run6 is the fresh successful run.

Earcon playback logs contain handled errors in the emulator. This work does not
establish audible output or audio-focus correctness.

## Procedural breadth

`output/simulation-lab/breadth-v1/` contains eight new courtyard/shop clips,
clear/blocked pairs under clean/rain conditions, **56 frames**. The versioned
spec changes lens/height/pitch/speed, cross-track geometry scale and material
texture/bump/roughness controls. Render and runtime manifests bind the actual
spec, effective CLI overrides, validator, generator, image effects and pixels.
All **8/8** app receipts completed, delivering 56 frames. There were 5 YOLO
results and 4 depth calls, with spatial results linked to only 4 source frames.
Of 28 frames with hazard geometry witnesses, only 2 had linked spatial results;
26 had none. Zero hazardous continues therefore does not establish perception
quality. No ANRs were observed at collection snapshots. See `evaluation.json`.

These are short procedural smoke inputs. Measured camera calibration, physical
material accuracy, sensor noise realism and representative hazard recognition
are not established. Sparse geometry witnesses remain evaluator-only.

## Verification

- **119** focused Flutter checks in the normal build.
- **39** focused Flutter checks with `BAGDAR_SIMULATION=true`, including lifetime,
  callback, frame identity, unknown/blur/noise, frozen-source and acoustic cleanup
  regressions. Counts are executions in two configurations, not disjoint cases.
- **23** Python checks covering corpora, effects, split leakage, identity,
  evaluation, controller transport timeout/recovery and no-overwrite contracts.
- Targeted Dart/Flutter analysis: no issues. Simulation x86_64 debug APK built;
  current source/build/installed identity verified. No whole-tree formatting.
- The production blur source still hashes to
  `d7cbef341199a793a9226b9dd42966d1094dd47f1f2e92ae0c1f0da07956cf0b`.

Logs and a final hash ledger are under `output/simulation-lab/`. The seal at
`quality-continuity-evidence-v1/receipt.json` verifies the final source/artifact
identities without promoting the research candidate.

## Remaining gates

Observer v2 needs a new protocol and unseen holdout that address correlated
noise, oriented blur and sparse curved structure. Minute-scale operation,
thermal behavior and native queue measurement remain future work. The full
sequence and exit evidence are in the implementation plan.

Physical Android camera, audio, TalkBack and controlled walking are **not_run**;
model correctness is **not_established**. Use the stationary-device checklist
for the next hardware session. `promotionAllowed=false`, generic geometry remains
shadow-only and walking guidance remains disabled.

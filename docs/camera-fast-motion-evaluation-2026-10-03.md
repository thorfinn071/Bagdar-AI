# Independent fast motion branch — 2026-10-03

Implemented an additive, opt-in shadow branch for RGB + independently calibrated
visible metric depth + pose. RGB identity/health belongs to its capture provider;
no neural result, NN confidence or NN-produced timestamp is awaited. The normal
phone camera path and user feedback are not connected to this experiment.

The pure-Dart kernel is compiled and executed as a Windows desktop AOT binary.
This establishes AOT compute evidence for the kernel, not a complete release APK
or named-device performance. Blender first-visible-depth bounds remain synthetic
metric input; real phone depth/alignment/pose calibration is not established.

## Implementation

- Separate capture provider/version/preprocessing/health/frame/session/transform
  contract. Preserved metric scale, projection and pose admission checks.
- Exact-preserving normalized RGB, optical-coordinate and axis caches, typed hot
  loop reads, unchanged-order RGB interpolation, conservative winner/uniqueness
  pruning. Candidates are visited from the projected centre outward; equal-score
  winners retain the original row/column order. The full search window remains.
  Numeric caches retain at most two immutable input frames and clear on
  invalidation. They grant no authority to reuse an old result.
- Persistent isolate with one active and one newest pending frame. Advancing
  owner clock checks entry, completion and single-use release, including IPC
  and queue time. Deadline, provider loss, clock rollback, identity/session/order
  failure and worker loss invalidate authority. Original capture timestamps,
  100 ms current-age budget, 50–300 ms pairs and oldest+400 ms expiry are preserved.
  RGB/depth/validity transfer in a uniquely owned read-only buffer. After replying,
  the worker prepares the current frame's feature cache for the next pair; this
  preparation creates no motion result and its CPU time is reported separately.
- Adapter uses the existing additive shadow scene. Physical/unknown history
  remains; absence of motion cannot certify free space. The real scene, planner
  and arbiter are exercised while the relative NN provider is unavailable.

## Software and evidence boundaries

Full diagnostics match the frozen source on 109/109 known inputs in desktop AOT,
including 18/18 known test approach pairs. The functional persistent-worker
replay also matches all 109 inputs. The existing corpus is known regression,
not a new holdout or evidence of general real-world accuracy.

In the functional fixed-clock replay with NN unavailable, the actual shadow runtime matches the motion diagnostics
on 67/67 test inputs and applies fresh motion risk in 30 frames. There are zero
stale applications, unsafe continues or clearances; unknown remains in all 67
frames. The single sufficiently passable control still has a false stop. This
branch provides additive danger evidence and does not establish useful passage
guidance. Shadow commands never activate UI/TTS/haptics.

Ten targeted tests include 21 invalid/ambiguous variants, real scene/planner
integration, owner event-loop responsiveness, age boundaries/recovery, forged
and reused tokens, future/clock/session/order/identity failures, provider loss,
bounded latest queue, excessive pair gaps, exact/read-only/single-materialization
transfer buffers, and idle-preparation equivalence/invalidation. A separate replay test checks
the 67-frame real shadow runtime report. These targeted checks passed.

Earlier stage sources/models/reports remain frozen. Android runtime and walking are
unverified; `adb devices -l` currently reports no attached device.

## Measured performance and remaining failure

Windows x64 Dart 3.11.1 desktop AOT: one warm-up traversal, three alternating
rounds, 327 observations per mode, fixture preload excluded. All measured
diagnostics still match the frozen reference. The optimized kernel does not
include the worker's separate idle preparation, transport, or camera capture.

| Pure AOT kernel | p50 | p95 |
| --- | ---: | ---: |
| Same-contract control, optimizations off | 278.969 ms | 339.242 ms |
| Optimized | 67.692 ms | 95.689 ms |

The p50 reduction is about 76% in this desktop comparison. A kernel p95 below
100 ms does not establish timely end-to-end motion: packing, dispatch, isolate
heap work, competing NN load, and final release still consume the same budget.
The separately run Dart JIT profile also preserves all diagnostics: control
p50/p95 244.831 / 427.817 ms; optimized 65.747 / 89.559 ms, 327 observations per
mode. These profiles do not run concurrently and do not measure phone speed.

The advancing-clock replay preloads known RGB/depth/pose and excludes real camera
capture and user feedback. Capture spacing is 200 ms; original capture metadata
is preserved. The live competing branch is the pinned CPU NCNN model, one thread,
with output equality checked. Fast input does not use or await its output.

| Advancing-clock AOT worker | Without NN | With concurrent live NN |
| --- | ---: | ---: |
| Total known frames | 109 | 109 |
| Admitted outcomes, including unknown/new-pair | 82 | 70 |
| Timely motion-risk frames / functional reference risk frames | 18 / 54 | 4 / 54 |
| Reference risk frames lost to timing or pair reset | 36 | 50 |
| Known test subset: timely risk / reference risk | 8 / 30 | 0 / 30 |
| Known test approach pairs: timely risk / reference pairs | 6 / 18 | 0 / 18 |
| Stale risk releases / clearance authority | 0 / 0 | 0 / 0 |
| Outcome age p50 / p95, including rejected outcomes | 80.084 / 110.117 ms | 39.126 / 112.281 ms |

The lower median with NN comes from cheap unknown/new-pair outcomes after expiry,
not better danger detection. Only 4 of the 109 outcomes released before the NN
are useful motion risk. All 109 finish before NN completion, but that aggregate
alone would hide the failure. Observed NN wait p50 is 124.508 ms, p95 147.122 ms,
max 162.885 ms, below the 200 ms capture spacing in this run.

Known-frame functional risk preservation and real-time risk availability are
separate results: **the timing/usability gate remains unmet**. Lost reference
risk frames are processing/pair-reset losses, not measured field hazard recall.
The passable shadow control still stops; this branch supplies no passage proof.
Owner event-loop timers fire during processing (460 events without NN, 394 with
NN), which establishes off-owner computation rather than phone UI smoothness.
Deadline outcomes with missing compute replies are explicitly counted (17 / 30);
returned-computation percentiles omit those replies and must not summarize the
entire workload. Completed idle-preparation CPU is 2297.910 / 2946.076 ms over
93 / 109 frames; it is not free work.

The initial full-object-transfer candidate had zero timely risk. Its original
receipt and matching source snapshot remain preserved. The revised branch uses
`camera_fast_motion_contract_v2.json`; variable timing reports are excluded from
the integrity receipt.

Next bounded step: profile worker-side matching/allocation under concurrent NN,
including cold-pair cost and scheduling. Optimize that bottleneck or evaluate a
native worker, then repeat full-diagnostic parity and this advancing-clock gate.
Do not wire the experiment to normal camera guidance until useful timely risk
and an actual registered metric provider/calibration are validated. Named-device
capture/depth/pose/thermal/audio evidence remains
necessary and currently unavailable.

## Aggregate verification

Serial `tool/verify_core.ps1 -Rc` passed **46/46 required gates**. The analyzer
reports no issues; the full Flutter suite passes **1523 tests**. The strict
legacy harness also passes 23 checks, and the new stage's separate reproducibility
gate reruns the compiled 109-frame parity, persistent-worker functional replay
and 11 targeted/shadow tests successfully. Earlier source/model/corpus/report
integrity and inference-output checks pass without rewriting their receipts.

Machine-readable result: `scratch/verification-camera-fast-motion/core-verification.json`.
Full log: `scratch/fast-camera-core-final.log`.
Evidence classes remain `desktopSoftwareRc=pass`,
`modelCorrectnessRc=not_established`, `androidBuild=not_run`,
`namedDeviceRuntime=not_run`, and `controlledWalking=not_run`.
This software result does not close the unmet timing/usability gate above.

## Reproduction

```powershell
dart run tool/model_benchmark/evaluate_fast_camera_motion.dart --check
python tool/model_benchmark/verify_fast_camera_motion.py --check
dart run tool/model_benchmark/evaluate_fast_camera_motion.dart --measure
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-fast-motion
```

Deterministic parity/functional/shadow reports and write-once contract are in
`docs/_baseline_logs/camera_fast_motion_*`. Variable JIT/AOT/elapsed measurements
are excluded from the reproducibility receipt. No thresholds or freshness
limits are loosened to obtain a faster or apparently safer result.

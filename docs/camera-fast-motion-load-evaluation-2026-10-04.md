# Motion under concurrent neural load — 2026-10-04

The versioned desktop experiment now releases all **30/30 known test risk
frames** and **18/18 known test approach pairs** before the original 100 ms
deadline in each of three alternating trials with live pinned CPU NCNN. All
54/54 reference risk frames are timely in every trial. The unchanged optimized
Dart v2 control releases 0/30 test risk frames in these same three comparisons.
This closes the declared timing gate for this preloaded, known Windows workload.
It does not establish phone latency, field accuracy or assistive readiness.

## Change and measured bottleneck

The new source writes RGB normalization directly into Float64 storage, avoiding
the temporary object list and a boxed double for each channel. It also offers
an explicit Windows x64 native warped-patch matcher. The matcher preserves
the complete radius-32 search, pixel interpolation and score accumulation order,
spatial uniqueness, row/column ties and reverse checking. LLVM builds it without
fast-math or floating-point contraction. The committed C source has no CRT
dependency, native allocation, model output, annotations or timestamps.

Dart retains feature selection, metric bounds, pose/identity admission,
classification and additive shadow integration. The owner retains capture-clock
entry, completion and single-use release checks. No age limit, threshold,
feature count, capture timestamp or pair interval was loosened. The frozen v2
implementation and receipts are unchanged. The new files are separate because
that reference is immutable.

The worker prepares numeric feature/native-frame caches after replying. These
copies retain at most two admitted immutable frames, grant no temporal authority
and clear on invalidation. Normal shutdown waits for resource-disposal
acknowledgment. Native startup errors fail startup; timeout/worker failure never
creates risk or passage authority. This is an opt-in experiment, disconnected
from the ordinary phone camera, TTS and haptics.

## Current controlled comparison

Windows x64 Dart 3.11.1 AOT; Windows-host Android NDK LLVM 21; pinned one-thread
CPU NCNN with every output checked against its existing receipt. RGB, synthetic
first-visible metric depth and pose are preloaded. The 200 ms capture spacing,
50–300 ms pair interval, 100 ms current age and oldest+400 ms expiry are unchanged.
Each elapsed mode runs three trials with alternating implementation order.

| Pure kernel, 327 observations per implementation | p50 | p95 |
| --- | ---: | ---: |
| Existing optimized Dart v2 control | 70.968 ms | 130.337 ms |
| Direct typed normalization + native matcher | 38.608 ms | 71.083 ms |

One warm-up traversal precedes three alternating rounds. Every measured
diagnostic matches the frozen reference. The median reduction is about 46% in
this current comparison. Kernel timings exclude transport and separate idle
preparation. They do not use yesterday's 279 ms unoptimized control.

| Advancing-clock results in rounds 0 / 1 / 2 | v2 without NN | New without NN | v2 with live NN | New with live NN |
| --- | --- | --- | --- | --- |
| Known inputs per trial | 109 | 109 | 109 | 109 |
| Admitted outcomes, including unknown/new-pair | 85 / 80 / 77 | 109 / 109 / 109 | 63 / 65 / 65 | 109 / 109 / 109 |
| Timely reference risk frames, out of 54 | 26 / 16 / 11 | 54 / 54 / 54 | 0 / 0 / 0 | 54 / 54 / 54 |
| Timely test risk frames, out of 30 | 12 / 10 / 4 | 30 / 30 / 30 | 0 / 0 / 0 | 30 / 30 / 30 |
| Timely test approach pairs, out of 18 | 12 / 7 / 4 | 18 / 18 / 18 | 0 / 0 / 0 | 18 / 18 / 18 |
| Reference risk lost to timing/pair reset | 28 / 38 / 43 | 0 / 0 / 0 | 54 / 54 / 54 | 0 / 0 / 0 |
| Missing compute replies at deadline outcome | 16 / 20 / 24 | 0 / 0 / 0 | 38 / 41 / 42 | 0 / 0 / 0 |
| Stale risk releases / clearance authority | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

Fresh-risk ages include owner packing, IPC, scheduling, computation and release,
measured against original capture timestamps; they exclude real capture and
user-command delivery. With NN, new fresh-risk p50 is **63.238 / 63.359 / 63.557
ms**, p95 **82.379 / 78.317 / 79.798 ms**, maximum **93.215 ms** across all trials.
All-outcome p50 is 60.220 / 60.021 / 59.966 ms. The old with-NN all-outcome p50
is only 30.727 / 27.806 / 31.064 ms because it returns cheap unknown/new-pair
outcomes; zero timely risk makes that lower median misleading.

The new worker returns all 109 computations in every trial. With NN,
compute p50 is 38.580 / 38.357 / 38.642 ms, p95 55.934 / 51.796 / 53.833 ms.
Owner packing p50 remains 9.492 / 9.592 / 9.598 ms; its maximum is 18.613 ms.
Completed idle preparation is 1292.122 / 1262.076 / 1334.828 ms per 109-frame
trial, and is separately counted, not free. Detailed stage/transport diagnostics
include replies after deadlines and have a bounded 128-sample per-worker limit;
no samples overflowed. The unchanged v2 runner does not expose detailed stage or
late-reply samples: empty detailed diagnostic sets in the comparison are
unavailable data, not proof of zero late computation.
All 109 preparation replies are observed in each NN trial. Without NN, 93
preparation replies per trial are observed before owner shutdown; the final
preparation for each of 16 layout workers completes during shutdown and its
reply is ignored. Those no-NN preparation totals are lower bounds on paid CPU,
not complete lifetime accounting.

All 109 new outcomes in every NN trial release before NN completion. The live
NN wait p50 is 119.825 / 120.930 / 121.659 ms and p95
142.206 / 141.637 / 139.238 ms, below the 200 ms capture spacing. Owner timers
fire during computation. Fast motion never consumes or waits for the model's
output.

Before the controlled series, an exploratory rerun of v2 produced 48/54 timely
risk frames with NN. Other pilots and yesterday's report differ. Those results
show why measurements from separate sessions must not be compared as a fixed
speed guarantee. The final conclusion uses the three alternating comparisons
above, and remains limited to their workload and desktop environment.

## Functional safety and evidence limits

Compiled full diagnostics and fixed-clock worker reports match frozen v2 on
109/109 known inputs. Thirteen native-path tests include the existing 21
invalid/ambiguous variants, transfer immutability, deadlines/recovery, forged or
reused tokens, provider/session/order/clock failures, bounded queue, and actual
scene/planner integration. An additional translation/texture matrix checks 63
inputs against v2, including plain and repeated ambiguous textures. A final
boundary test rejects projected windows outside the image before converting
Dart integers to the native Int32 ABI, including coordinates beyond 2^31 and
2^32, and rejects malformed native frame buffers. These cannot wrap into a
valid image window. This guard does not change any measured known input.

The actual shadow runtime report matches v2 on 67/67 test frames: fresh motion
risk is applied in 30 frames, unknown is retained in every frame, and stale
applications, unsafe continues and clearances are all zero. The single
sufficiently passable control still stops. Timely risk does not solve passage
usability or validate general hazard recognition.

All data remain known synthetic regression. Metric bounds and pose are supplied
by the Blender visible-depth fixture; no registered, calibrated phone metric
provider is established. No Android integration/build, named-device runtime,
thermal/audio/capture timing, TalkBack or controlled walking was performed in
this stage. The native library is Windows x64 only. Three successful trials
with a maximum risk age near the deadline are not a worst-case scheduling
guarantee.

The next bounded gate is a phone implementation/provider and calibration spike:
prove synchronized real RGB/metric depth/pose admission, measure original
capture-to-release latency under actual concurrent models, and retain shadow
delivery until device and useful hazard-versus-passable discrimination gates
pass.

## Verification and artifacts

Full serial `tool/verify_core.ps1 -Rc` passes **48/48 required checks** after
the final coordinate guard. The analyzer reports no issues. The complete Flutter
suite passes **1535 tests**, with one native-specific test skipped because its
explicit library flag is absent in the generic suite; that test passes in the
separate **13/13 native targeted/shadow tests**. The strict legacy harness passes
23 checks. Compiled native parity, fixed-clock worker replay, actual shadow
runtime, original source/model/report integrity and inference-output gates all
pass. The earlier partial aggregate run is retained separately.

Machine-readable Core RC result is recorded in
`scratch/verification-camera-fast-motion-load/core-verification.json`; its log
is `scratch/fast-motion-load-core-final.log`.
Evidence classes remain `desktopSoftwareRc=pass`,
`modelCorrectnessRc=not_established`, `androidBuild=not_run`,
`namedDeviceRuntime=not_run`, and `controlledWalking=not_run`.

Deterministic receipt: `docs/_baseline_logs/camera_fast_motion_load_contract_v2.json`.
The initial load receipt is preserved, with its matching sources in
`scratch/fast-motion-load-first-freeze`. The v2 checker verifies those source
snapshots as well as the earlier 2026-10-03 fast-motion receipt.
Functional references remain the frozen v2 parity and worker reports. New
runtime report: `docs/_baseline_logs/camera_fast_motion_load_shadow.json`.
Variable measurements: `camera_fast_motion_load_aot_profile.json`, twelve
`camera_fast_motion_load_elapsed*.json` trials and
`camera_fast_motion_load_comparison.json` in `docs/_baseline_logs`.
Variable timings are excluded from the immutable receipt.

Reproduction is specified in
`docs/camera-fast-motion-load-protocol-2026-10-04.md`.

# Concurrent-load motion experiment — 2026-10-04

Bounded desktop experiment, separate from the frozen 2026-10-03 v2 kernel,
worker, reports and receipt. No ordinary camera path, user feedback or assistive
promotion. Reuse of the known 109-frame synthetic corpus is regression evidence,
not an independent holdout or a phone accuracy result.

The versioned source removes the temporary boxed RGB normalization list and
writes the same divisions directly into Float64 storage. Its optional native
matcher evaluates the identical warped RGB search. Keep 48 features, radius 32,
photometric threshold .065, uniqueness .015, reverse consistency one pixel,
speed .20 m/s, the 50–300 ms pair interval, the 100 ms current-age limit and
oldest+400 ms expiry. Search the entire original window; retain row/column ties
and floating-point accumulation order. Do not use fast-math or contraction.

The native matcher is a Windows x64 DLL built from the committed C source by a
Windows-host LLVM compiler. It has no CRT dependency, native allocation,
timestamps, model output, annotations, masks or hidden scene data. Dart owns
workspace and copies of at most two admitted frames. Cache invalidation releases
the frame copies. Normal shutdown acknowledges disposal before closing the
worker; a two-second shutdown timeout terminates a failed worker. Abnormal
process termination is not a device memory/recovery validation.

The isolate retains entry/completion/release checks, bounded latest pending
queue, provider/session/order/clock failures and single-use release tokens. The
native module is explicitly supplied to the desktop replay/tests; default phone
code does not instantiate it. Library load/ABI errors fail worker startup.
Idle feature/native-buffer preparation is reported separately and grants no
freshness authority. Owner packing, transport, scheduling, compute and release
still consume the original capture-age budget.

Acceptance checks:

1. Compile the native module and desktop Dart AOT binaries. Full 109-frame
   diagnostics and functional-worker reports must match the frozen v2 reports.
2. Run invalid/ambiguous, translated, plain/repeated texture, token reuse,
   expiry, recovery, queue, provider/session and clock tests against the native
   path. Exercise the real shadow scene/planner on 67 test frames. Unknown and
   physical history remain; zero stale applications, unsafe continues or
   clearance authority. The sufficiently passable control's false stop remains.
3. Measure one warm-up and three alternating pure-kernel rounds, 327 inputs per
   mode, with current optimized Dart v2 as control. Fixture preload is excluded.
4. Run three alternating advancing-clock AOT trials per mode with and without
   the same live pinned one-thread CPU NCNN competitor, preserving 200 ms
   capture metadata. For NN trials require fresh risk on all known 54 reference
   risk frames, including all 30 test risk frames and 18 test approach pairs,
   in each trial. Cheap unknown/new-pair outcomes must not substitute for risk.
5. Report risk-only ages, all outcome ages, packing, materialization, matching,
   native-copy/native-search, late returned computation, missing deadline
   replies, and preparation CPU. Bounded diagnostic samples include completed
   late work; timings are variable and excluded from deterministic receipts.
6. Preserve earlier receipts; add a new write-once source/report receipt and
   two Core software verification steps. Run full serial Core RC after checks.

The measured timing gate is limited to this known, preloaded desktop workload.
Passing it does not authorize phone guidance, certify space, demonstrate actual
camera capture/depth/pose/audio/thermal latency, or establish field accuracy.

Reproduction:

```powershell
dart run tool/model_benchmark/evaluate_fast_camera_motion_load.dart --check
dart run tool/model_benchmark/evaluate_fast_camera_motion_load.dart --measure
python tool/model_benchmark/verify_fast_camera_motion_load.py --check
powershell -NoProfile -File tool/verify_core.ps1 -Rc -OutputDirectory scratch/verification-camera-fast-motion-load
```

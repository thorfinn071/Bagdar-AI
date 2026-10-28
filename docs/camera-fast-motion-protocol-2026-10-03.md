# Independent fast motion shadow branch — 2026-10-03

Scope: additive experimental RGB + independently calibrated visible metric depth
+ pose branch. No camera-screen, assistive, TTS/haptic or model promotion.
Previously frozen sources, model assets, labels, timestamps and reports remain
unchanged. The scale-motion corpus is known regression, not a fresh holdout.

1. Provide a pure-Dart kernel with its own RGB capture provider identity,
   version, preprocessing, health, frame/session/capture/transform contract.
   It must not wait for NN output or claim relative MiDaS depth is metric.
   Metric calibration and registered first-visible-surface bounds are required.
2. Preserve the 48-feature selection, search radius 32, photometric 0.065,
   uniqueness 0.015, reverse consistency 1 pixel, risk >=3 patches, speed
   0.20 m/s, pair 50–300 ms, current age 100 ms and oldest expiry 400 ms.
   Pure baseline and exact-preserving pixel cache/pruning must reproduce the
   full frozen diagnostics on all 109 known decision inputs and negative cases.
   Candidate coordinates may be visited from the projected centre outward
   to tighten the proven conservative SAD bound sooner. The complete original
   search window remains; equal-score winners retain original row/column order.
3. Measure baseline/optimized pure kernels both with Dart JIT and compiled
   desktop AOT: preload excluded, warm-up, alternating order, three rounds.
   No claimed phone speed, capture-to-command latency or new scene accuracy.
4. Persistent isolate worker: at most one in-flight and one newest pending
   frame. Main-owner advancing capture-domain clock checks entry, completion,
   and single-use release. Expiry, provider loss, identity mismatch, clock
   rollback, session change and worker failure invalidate temporal authority.
   Queue replacement and expiry are explicit; no retimestamping or bridging
   pair gaps. Work remains off the owner event loop.
   RGB, Float64 depth bounds and validity use a uniquely owned transferable
   buffer with read-only receiver views; scalar identity/geometry is separate.
   Owner packing, transfer and receive costs are included in the age budget.
   After replying, the worker may prepare feature/normalized-pixel numeric
   caches of the immutable current frame for the next pair. These bounded
   caches carry no freshness or risk authority and clear on reset. Report
   preparation CPU time separately; queue/transport/compute still count toward
   the next frame's original 100 ms release deadline.
5. Risk is additive only, using the existing shadow scene/planner. Missing NN
   output cannot authorize passage, erase unknown, or clear a historical stop.
   Verify expiry/recovery/session/reorder/overload and owner responsiveness.
   Compare actual advancing-clock worker results with functional fixed-clock
   results. Published fresh risk and unknown outcomes remain separate.
6. After targeted verification, run analyzer and serial full Core RC, including
   reproducibility/integrity gates for this stage. Preserve all old receipts.

Success requires full regression parity, preserved known 18/18 approach pairs,
zero stale motion application or clearance authority, and measured latency
with explicit unavailable outcomes. Reaching 100 ms is measured, not assumed.
Metric inputs currently come from Blender; a real phone provider/calibration,
Android runtime and controlled walking remain separate unverified gates.

The first full-object transport candidate returned no fresh risk in elapsed
replay. Its initial write-once receipt remains intact and matching source files
are archived in `scratch/fast-camera-first-freeze`. The revised transferable
transport uses the separately named `camera_fast_motion_contract_v2.json`.

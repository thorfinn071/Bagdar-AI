# Closed upper-volume control — 11 October 2026

This is a new diagnostic positive control after the failed 10 October holdout,
not a replacement holdout or evidence of real-world model correctness. Preserve
all 84 old decisions, their failed usefulness gate, and every old source/receipt.
Freeze runtime, producer, generators and new consumers before export. No tuning
after observing this version's measurements or decisions.

Export three layouts, seven consecutive captures each (21 total): the earlier
clear-forward, clear-yaw and low-lintel layouts, now in rooms whose side walls
extend to 3.38 m and overlap the ceiling at 3.23–3.33 m. Retain their portal,
camera trajectory, exposure, 200 ms frame interval, textures/seed algorithm and
12 simultaneous optical directions. The low lintel is an explicit hazard
control. These are deliberately related diagnostic scenes, not independent
holdout scenes. New capture clocks and corpus/calibration identities distinguish
them from the untouched originals. Only scene geometry changes; never fill
missing returns, lower required coverage, or change runtime thresholds.

First run the unchanged optical producer and clearance evaluator on all new
captures, before any neural inference or runtime decisions. Both clear layouts
must have complete fresh body/floor measuredClear on all 14 captures. If that
precondition fails, retain the outcome and do not claim a useful runtime test.
Independently probe the previously escaping body direction using analytic
ray/AABB intersection; the probe must now have a finite opaque first return.
The old open-band controls must still be unavailable with unchanged unknowns.

After the producer precondition, run pinned NCNN inference twice, byte-exact,
using the existing weights and preprocessing without fitting. Compare the same
four runtime arms as before, in both detector modes, with one persistent session,
tracker and scene/planner history per layout. Count every capture. Fixed replay
clocks remain capture+2 ms, production capture+1 ms, freshness 100000 us;
this is contract timing, not measured latency. Scoring geometry is loaded only
after all runtime decisions. Report positive motion and retained STOP separately.

Predeclared behavioral gates: 14/14 clear producer preconditions; zero non-STOP
hazard decisions in repaired arms; fewer false STOPs in repaired rig than old
same-rig control; every repaired CONTINUE has complete fresh current proof and
no positive body motion. Also report every single-view action without assuming
that producer coverage certifies single-view completeness.

Exercise all 12 existing faults initially and after a real first-frame CONTINUE,
in both detector modes (48 derived trials, 24 after-clear preconditions). Each
fault and the immediate fresh-data recovery while moving must STOP. Preserve
continuous revision/history and original timestamps within each trial. These
trials are separate from the 21 capture denominator. A failed clear precondition
does not count as causal fault-after-clear evidence.

Reproduce new receipts, rerun the old 84-capture producer audit and the unchanged
volume-authority regression chain. Verify source/payload hashes, independent
geometry scoring, channel identities/zero skew and original negative receipts.
All delivery stays shadow with promotionAllowed=false, ordinaryCameraWired=false.
Android, aligned real camera depth, actual latency, memory/thermal behavior,
feedback delivery and controlled walking remain unestablished.

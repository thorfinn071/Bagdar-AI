# Frozen-runtime independent scene check — 10 October 2026

Freeze the previously validated runtime, perception, detector, tracker, fusion,
guidance and optical producer source hashes BEFORE exporting or inferring any
new scene. Do not tune them after looking at this holdout. Preserve all earlier
sources/receipts and unrelated worktree changes. A failed gate is a reported
failure, not permission to edit the frozen candidate or discard a difficult scene.

Twelve predeclared new layouts, seven captures each (84 captures), use new room
dimensions, portal positions, textures, exposures and camera trajectories.
Four clear controls cover forward camera travel, camera yaw, dim/low-contrast
appearance and an off-path moving object. Six hazards cover a narrow portal,
low lintel, thin pole, raised floor, missing floor and an occluded moving object.
Two mixed sequences contain an approaching and a crossing object. Parameters
and seeds are in tool/blender/volume_holdout_spec_v1.json. No rendered frame or
relative NN output from an earlier corpus is reused. This is independent of
the repair's development captures, but shares the synthetic renderer family;
it is not a real-world or general model-correctness benchmark.

Export original RGB, conservative primary first returns and twelve co-located
simultaneous whole-pixel/floor/first-Z channels at each capture. Each batch
contains ONE instantaneous scene state, including dynamic cases. View selection
uses only projection, optical height and the requested body, never scoring
labels. No inter-frame stationarity, hidden extent or future clearance authority.
Pinned NCNN/MiDaS weights, preprocessing and relative semantics are unchanged.

Four paired arms per detector mode: old confidence single-view, repaired
single-view with body-relative motion, old confidence with full rig, repaired
with the SAME full rig plus body-relative motion. The same untouched detector
and tracker outputs feed all arms. Run one continuous session per sequence;
never reset history or manually advance time to remove a stop. Fixed replay
clock: now=capture+2000 us, production=capture+1000 us, freshness=100000 us.
This timing is a contract check, NOT measured inference/capture-to-command time.

Only AFTER all runtime decisions, load separate scoring annotations. Physical
occupancy is computed independently from mesh bounds in the requested body
volume; missing floor has a separate discontinuity label. Report all 84
instantaneous decisions without exclusions. Separately describe advance warnings
using a continuous one-second translating-box intersection under the known
constant-velocity synthetic continuation, and retained-stop history. Never
silently remove these stops from the instantaneous false-stop denominator.

Fault controls on the new clear layout: missing primary, invalid returns,
nonmetric units, foreign model/pose, absent upper stream, missing/partial rig,
one-us channel skew, stale capture, future production and foreign motion.
For BOTH detector modes exercise each fault initially and after a clear frame,
then restore fresh data while still moving. Fault and recovery must STOP.
These derived controls are separate from the independent 84-frame denominator.

Predeclared gates: zero hazardous non-STOP decisions in repaired arms; every
fault/moving-recovery STOP; no single-view optimism without complete current
body/floor proof; lower aggregate instantaneous false STOP count for repaired
rig than old SAME-rig control. Every CONTINUE must have fresh complete current
volume proof and no positive body-relative motion. Retain 100 ms, shadow
delivery, history and promotionAllowed=false regardless of gate outcome.

Re-run the previous 226 Flutter/7 Python verification chain and byte-exact
inference checks. Check source/payload identities, original-capture timestamps,
zero channel skew, ray witnesses, duplicate captures and scoring arithmetic.
Named-device Android, real depth alignment/coverage, measured latency, thermal,
memory and controlled walking remain separate gates.

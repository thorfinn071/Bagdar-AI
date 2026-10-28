# Path-clear stop diagnosis contract — 2026-10-07

Scope: one known paired regression, `path-clear` and `path-box`, 11 frames each.
Use the frozen RGB, pinned MiDaS outputs, unchanged preprocessing, actual
detector/tracker, camera-visible synthetic first-return depth and pose, and the
real confidence-authority runtime/scene/planner/arbiter. NN inference is not
rerun. This is software diagnosis, not independent model, device or latency proof.

Preserve every prior source/output receipt. The new planner subclasses the
frozen confidence planner and delegates state, hysteresis, action and safety
decisions to it. It changes only cause and rule when `AWAIT-STATIONARY` hides a
currently unconfirmed corridor. Positive moving evidence still awaits stationary
confirmation. Physical risk, missing sensing, freshness, queue ownership,
release counters and session reset remain under the existing policy.

Compare baseline and corrected authority fields for all 22 frames. Unit tests
also compare priority, kind, delivery, IDs, hazards, evidence summary, direction,
confidence, creation/expiry, planner state and proposed correction. Keep body
passage freshness at 100000 us and delivery shadow-only. The ordinary camera
does not select the new planner; promotion remains false.

Require exact reproduction of the frozen selected baseline's action, rule,
forward unknown/occupancy and passage-application fields. Require the entire
new JSON to reproduce during subsequent checks. The first JSON and source
receipt are write-once. Hashes include the new planner, tests, harness, verifier
and this protocol. The verifier executes the existing visible-body integrity
check, preserving the earlier correction/source/model/optical contracts.

Separately inspect these causal ablations on `path-clear` only:

- New runtime/planner for every frame: removes stop/scene history.
- No tracks plus a new runtime: removes every tracked component, including any
  legitimate one. This is a deliberately unrealistic diagnostic intervention,
  not an algorithm change, false-stop improvement or candidate for runtime.
- The same no-track intervention while stationary: checks stop versus scan.

None of these changes RGB, neural output, optical timestamp or camera coverage.
Never infer free space from a deleted track, good ground fit or filled depth.
Run separate hole, relative-unit and stale-metric controls. Keep stale capture
timestamps intact; evaluate the stale case at original capture +100001 us.
Require unavailable passage, no clearance and no continue in each fault.

Success for this diagnosis means locating the blocking data and correcting
misleading decision causes while retaining the obstacle contrast. Success for
false-stop reduction is a separate gate: sufficient current camera evidence
must let the selected passable scene recover, while obstacle, hidden region,
invalid sensing and stale data retain protective behavior. Do not mark that
gate passed when the passable scene still stops.

Use serial Flutter tests. Report full Core RC, Android, named-device, feedback
delivery, performance and walking as not_run unless separately executed.

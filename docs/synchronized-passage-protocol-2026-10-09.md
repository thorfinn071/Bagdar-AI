# Synchronized passage transfer experiment — 9 October 2026

Apply the existing frozen CameraSynchronizedEnvelopeSource to the current
paired path-clear regression. Do not modify its coverage, static-scene,
calibration, identity or freshness predicates, or any prior receipt.

The unchanged target is 0.9 m width, 1.85 m headroom, 0.2–3.5 m forward,
0.05 m floor rise/drop margins and 100000 us age. A label-free grid chosen
only from target volume and intrinsics supplies 12 simultaneous, ideal,
co-located depth channels. All channels observe one evaluated scene state
with identical frame/session/capture IDs; no old observation is retimestamped.
This is a synthetic optical rig, not an ordinary single-camera phone scan.

Generate clear-first/clear-final, box, low-headroom, floor-drop, 4 mm pole and
opaque-occluder/pole contrasts using the preserved meshes and same contrasts
as the camera-view experiment. The original camera supplies an independent
primary RGB/metric packet for detector/track localization, in addition to the
12 depth channels. Render it anew; require RGB pixel and optical parity with the
preceding trial before using its matching relative MiDaS output. Run MiDaS
on the new primary RGB and verify output parity where canonical RGB pixels match.
PNG metadata may differ; every actual file remains bound by its own SHA256.
The rig's metric envelope is renderer output, never inferred from MiDaS.

Whole-pixel surface height and first-Z bounds must remain coherent. Exact
visible first-return partition can repair a missing bound only when all
fragments are covered; any incomplete pixel stays unknown. Mesh/labels are
visible only to generation and scoring. Independent sampled ray witnesses
check the exported optical bounds. They are not model-accuracy evidence.

First compare original single and synchronized source at a fixed +2 ms test
clock. Then feed the same primary relative neural output and actual detector,
tracker, scene, planner and arbiter with/without synchronized evidence.
Bind the primary-camera optical packet to the rig aggregate transform only
after checking matching scene state, camera pose, capture/frame/session and
RGB hash. This binding changes provider/calibration namespace only; it must
not change optics, raw depths, timestamps or actual observations.

Report complete passage certification separately from planner stop/continue.
Keep historical stops, moving threats and the existing stationary release
policy. Never create positive inputs by removing tracks or scene history.
Every runtime trial is declared as a fresh snapshot; it does not establish
temporal recovery or replace the earlier 11-frame false-stop measurement.

Reject missing/duplicate/reordered channels, even 1 us skew, foreign pose or
identity, relative units, incomplete depth/envelopes, unestablished dynamic
scene, stale completion, dispatch expiry, duplicate release and session loss.
Use original captures for +100001 us faults. Delivery is always shadow.

Measure source+evaluator+age-gate processing in AOT, after preload, in three
alternating single/rig rounds. Include no-NN and concurrent pinned CPU NCNN
series and report p50/p95, maximum and late count. Startup, file decode/hash,
physical capture, neural-primary inference, tracking and command delivery are
excluded and explicitly reported. Actual completion/dispatch clocks advance;
fixed-clock functional success never proves the 100 ms processing gate.

Exit: complete current observations on known passable snapshots while
hazards/faults stay protective, plus a separate honest timing result; or a
measured remaining coverage/runtime limitation. Preserve all prior contracts.
No normal-camera wiring, assistive promotion, Android or walking claims.

# Camera view coverage experiment — 9 October 2026

Scope: locate the source of unknown body/floor cells and compare predeclared
single-camera viewpoints. No production file, previous corpus, threshold,
history, freshness policy or frozen receipt is changed. Delivery stays shadow.

The request remains 0.9 m wide, 1.85 m headroom, 0.2–3.5 m forward, with the
existing 0.05 m floor margins and 100000 us maximum age. Each packet is one
current observation; no static multi-second scan or past view is accumulated.
Evaluation at capture +2000 us is a fixed test clock, not measured latency.

Views are declared before generating or evaluating their depth:

| View | Height m | Pitch down degrees | Lens mm |
| --- | ---: | ---: | ---: |
| original | 1.42 | 12 | 26 |
| chest-level | 1.42 | 0 | 26 |
| waist-level | 0.975 | 0 | 26 |
| waist-down | 0.975 | 25 | 26 |
| ideal-wide-control | 0.975 | 0 | 2.5 |

The last view changes optics dramatically and is an idealized projection
control, not a proposed phone configuration or evidence of hardware support.
All other views retain the original intrinsics. Walking coordinates follow
the original camera's horizontal location; changing height does not move the
tested volume. Original view packets must reproduce the prior optical packets
within float rounding and the exact body/floor diagnostic fractions.

Generate final-state snapshots for path-clear, path-box, headroom-low and
floor-drop from their hash-checked frozen .blend files. Two additional
contrasts add a 4 mm pole and an opaque occluder with a pole behind it to the
clear mesh. A separate path-clear first-frame snapshot checks both ends of the
known approach. These are known synthetic scenes, not independent holdout.
Scene geometry and labels stay inside generation/scoring; producers receive
only first-return optical packets, intrinsics, pose and identity.

Render new RGB and whole-pixel first-return metric bounds for every changed
view. Run the pinned desktop MiDaS NCNN model with canonical RGB01/CHW/256
nearest stretch. Raw neural output remains relative; only the independent
synthetic renderer supplies metres. Keep neural and metric evidence separate
in reports. Never reuse original RGB or neural outputs for changed views.

The coverage observer independently repeats the source's whole-cell tests
and must match its per-section body/floor fractions and total box counts.
Its masks have no risk authority. Unknown cells are classified by geometric
frustum exclusion versus return/pixel-bound proof failure. A centre ray or a
visible centre never certifies an entire cell. Blocked sections remain blocked.

Feed regenerated relative depth, real detector/tracker, matching camera track
input and synthetic passage evidence through the existing shadow runtime.
Report snapshot stop/continue decisions separately from passage certification.
Do not compare these selected snapshots as if they were the earlier 11-frame
temporal false-stop trial. Keep hazards, invalid pixels, hidden depth, relative
units and capture +100001 us stale inputs protective. A hidden region is never
filled. Stale packets keep their original capture timestamps.

Exit: reproducible cell maps and viewpoint comparison; either sufficient
positive observation with retained negative controls or a measured optical /
depth-proof limitation. Report full Core RC, APK, named Android, measured
capture-to-command latency, thermals, accessibility and walking as not_run
unless actually performed. Promotion and ordinary-camera wiring remain false.

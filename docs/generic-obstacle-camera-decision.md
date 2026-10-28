# Camera-ownership decision (Phase 6 gate)

Status: **blocked — not executed**  
Date: 2026-09-12

Update 2026-10-11: the first native ARCore-only Research recorder is prepared;
see [capture guide](research-capture-guide-2026-10-11.md). Its build and contract
tests are software evidence. No phone is attached, the SHARED_CAMERA comparison
and physical alignment are not executed, and the production decision remains open.

The implementation plan requires an isolated native spike on:

- one ARCore-depth device with a hardware ToF sensor
- one ARCore-depth device without hardware ToF

comparing:

1. ARCore as the only camera owner (YUV + raw depth + confidence +
   timestamp + rotation + intrinsics + pose)
2. ARCore `SHARED_CAMERA` Camera2 pipeline

## What this repo currently does

`HardwareDepthSession` opens a **separate** ARCore session while Flutter's
`camera` plugin also owns the rear camera. That combination is **not** the
production architecture.

Until the spike produces a written evidence record, ARCore metric depth is:

- kept as a legacy hazard source
- marked `alignedToImage: false`
- `genericObstacleAvailable: false` with reason `arcore_not_single_owner`

The generic detector therefore uses the synchronized NCNN path (same Flutter
camera frame) and does not treat ARCore as healthy geometry.

## Not recorded (do not invent)

- timestamp match between camera and depth
- whether hardware depth remains active under shared camera
- image/depth transform correctness
- 30-minute heat / FPS / memory
- pause/resume and screen-lock behavior
- selected single owner

No Android device was attached to this workstation during implementation
(`adb devices` was empty). Re-run the spike on the device matrix and replace
this document with factual numbers before making ARCore the default.

# Bagdar Core: implementation plan for generic obstacle detection

Status: implementation specification  
Date: 2026-09-12  
Primary target: Android 11+ (`minSdk = 30`)  
Safety classification: assistive feature, not a mobility aid replacement

## 1. Objective

Implement an on-device obstacle stack that warns a blind pedestrian about a
physical obstruction in the walking corridor even when the obstruction has no
YOLO class.

The stack must answer two independent questions:

1. Geometry: is physical space in the user's walking corridor occupied or is
   the ground plane interrupted?
2. Semantics: if possible, what known object caused the geometric risk?

Geometry is the safety authority. YOLO may name an object or raise the priority
of a known dynamic threat, but the absence of a YOLO detection must never
suppress a geometric obstacle.

Expected speech examples:

- `Препятствие впереди.`
- `Препятствие слева.`
- `Стоп. Препятствие очень близко.`
- `Машина справа.` when a sufficiently reliable YOLO track matches the
  geometric observation.
- `Анализ пространства ограничен. Используйте трость.` when the geometric
  stack is unavailable or unreliable.

The app must never say `Путь свободен`, `Препятствий нет`, or an equivalent
claim based only on a lack of detections.

## 2. Explicit non-goals

Do not include these in this implementation:

- Bazaar/livestock mode, mesh/buddy mode, sonar, smart-cane integration,
  payment SMS, VLM scene narration, iOS, or model training on charge.
- Open-vocabulary or generative models in the critical alert path.
- A generic YOLO class named `obstacle`.
- Automatic instructions to walk around an obstacle. V1 warns about occupied
  space; it does not certify a safe alternative path.
- A guarantee of detecting transparent glass, mirrors, very thin wires, holes,
  or all negative obstacles.
- Exact distance speech when only relative monocular depth is available.
- Public-road or unsupervised blind-user testing before the controlled safety
  gates in this document pass.

Existing stair, curb, pothole, glass, slippery-surface, and fall-detection code
must not be expanded as part of this task. Preserve it behind the existing
behavior until the generic obstacle stack is independently proven.

## 3. Current repository reality

Relevant existing components:

- `assets/yolov8n_int8.tflite` and `assets/labels.txt`: YOLOv8n COCO detector.
  COCO has no `wall` or `pole` class.
- `lib/services/depth_provider.dart`: hardware, NCNN, and focal fallback
  selection.
- `lib/services/ncnn_depth_provider.dart` and
  `android/app/src/main/cpp/bagdar_depth_ncnn.cpp`: bundled MiDaS/NCNN path.
- `android/app/src/main/kotlin/com/example/bagdar/HardwareDepthSession.kt`:
  separate ARCore raw-depth session.
- `lib/utils/ground_plane_analyzer.dart`: image-space RANSAC and legacy depth
  hazard heuristics.
- `lib/camera/depth_pipeline_controller.dart`: provider health, YOLO/depth
  fusion, and conversion to alert events.
- `lib/camera/alert_manager.dart`, `lib/utils/alert_filter.dart`, and
  `lib/services/tts_service.dart`: mature alert-priority path.
- `lib/services/orientation_service.dart`: phone pitch/roll state.
- `lib/services/fall_detector.dart`: motion state.
- `lib/services/field_logger.dart`: device/session and inference logging.
- `integration_test/pipeline_scenarios_test.dart`: desired scenarios, currently
  skipped because real fixtures and hardware evidence are missing.

Known risks that must be resolved before threshold tuning:

1. `HardwareDepthSession` opens an ARCore session while Flutter's `camera`
   plugin also opens the rear camera. Two independent owners are not a valid
   cross-device architecture. Simultaneous success must not be assumed from a
   single device.
2. ARCore produces metric depth where smaller positive values are nearer.
   MiDaS normally produces relative depth/disparity with a model-specific
   direction and scale. They currently feed the same analyzer without an
   explicit semantic contract.
3. ARCore raw depth is sparse, but the current native path does not acquire or
   propagate the corresponding confidence image.
4. ARCore depth and Flutter camera pixels are independently resized to 256x256
   without a proven rotation/crop/intrinsics alignment.
5. NCNN preprocessing currently replicates the Y plane into three channels.
   Verify whether this exact exported model expects grayscale replication,
   RGB/BGR, mean/std normalization, and a specific resize policy.
6. NCNN output is copied and zero-padded if smaller than 256x256. A smaller
   output must be spatially resized, not flattened into the top of a larger
   map.
7. Current coverage gates can reject thin poles even when they intersect the
   center line.
8. The current focal fallback returns no generic hazards. This must be exposed
   as degraded spatial coverage, not a healthy empty scene.

Do not tune around any of these defects. Fix or explicitly gate them.

## 4. Target architecture

```text
Camera owner
  |
  +-- synchronized image frame --------------------+
  |                                                 |
  +-- depth provider                                +-- YOLO / known tracks
        |                                           |
        +-- ARCore metric depth + confidence        |
        |   OR                                      |
        +-- NCNN relative monocular depth            |
        |                                            |
        +--> CanonicalDepthFrame                     |
               |                                     |
               +--> frame quality and alignment gate |
               +--> ground/free-space estimator      |
               +--> walking-corridor projector       |
               +--> obstacle-mask/components         |
               +--> generic obstacle tracker         |
               +--> collision-risk engine <-----------+
                              |
                              +--> AlertManager
                              +--> FieldLogger
```

### 4.1 Provider policy

Use the following production policy:

1. NCNN on the same Flutter camera frame is the first implementation path. It
   avoids a second camera owner and gives all Android target devices a common
   baseline.
2. ARCore becomes the preferred metric provider only after a single-owner,
   synchronized camera path passes the camera-ownership gate below.
3. Focal-length estimates may enrich known YOLO objects, but they are not a
   generic obstacle provider.
4. Provider selection and health must be visible to the risk engine and the
   user-facing degradation state.

Do not ship the current combination of a separate ARCore session plus a
separate Flutter camera controller as the final architecture.

### 4.2 Camera-ownership decision gate

Run an isolated native spike before making ARCore the default. Capture evidence
on at least one ARCore-depth device and one ARCore device without a hardware
ToF sensor.

Evaluate two options:

- Preferred quality option: ARCore is the only camera owner and exposes a
  synchronized YUV image, depth image, confidence image, timestamp, rotation,
  intrinsics, and pose to Flutter/native inference.
- Alternative: an ARCore `SHARED_CAMERA` Camera2 pipeline. Verify all depth
  limitations before selecting it; shared-camera mode may prevent ARCore from
  using a hardware depth sensor.

The decision record must include:

- whether camera and depth timestamps match;
- whether hardware depth remains active;
- image/depth coordinate transform correctness;
- sustained frame rate, heat, and memory for 30 minutes;
- behavior across pause/resume and screen lock;
- the selected single owner and why.

If neither option is reliable within scope, keep ARCore experimental and ship
the synchronized NCNN path. Do not block the generic detector on ARCore.

## 5. New data contracts

Add `lib/models/depth_frame.dart`.

Suggested contract:

```dart
enum DepthProviderKind { arcoreMetric, ncnnRelative, unavailable }

enum DepthValueSemantics {
  metricMeters,       // finite positive metres; smaller means nearer
  relativeProximity,  // normalized 0..1; larger means nearer
}

class CameraIntrinsics {
  final double fx;
  final double fy;
  final double cx;
  final double cy;
}

class DepthFrame {
  final Float32List values;
  final Float32List confidence01;
  final int width;
  final int height;
  final int timestampUs;
  final DepthProviderKind provider;
  final DepthValueSemantics semantics;
  final CameraIntrinsics? intrinsics;
  final int rotationDegrees;
  final bool mirrored;
  final double cropTopFraction;
  final double frameQuality;
  final bool alignedToImage;
}
```

Rules:

- Invalid depth is `NaN` internally, never an ambiguous zero after
  normalization.
- `confidence01` has exactly `width * height` elements.
- ARCore confidence is derived from `acquireRawDepthConfidenceImage()` and
  invalid/low-confidence raw pixels remain invalid.
- If dense ARCore depth is used, record that it has no per-pixel raw confidence
  rather than fabricating it.
- Relative depth must be converted once so `larger == nearer` throughout Dart.
- Never convert relative depth into metres using an arbitrary constant.
- Reject stale or unaligned frames. Start with a configurable maximum image ↔
  depth timestamp delta and establish the final value from device evidence.
- Rotation, crop, and coordinate transforms must be unit-tested.

Add `lib/models/generic_obstacle.dart`.

Suggested model:

```dart
enum ObstacleGeometry {
  broadSurface,
  thinVertical,
  lowObstacle,
  overhead,
  unknown,
}

enum ObstacleRiskLevel { monitor, warning, critical }

class GenericObstacleObservation {
  final int? trackId;
  final ObstacleGeometry geometry;
  final HazardZone zone;
  final Rect normalizedBounds;
  final double corridorOverlap;
  final double confidence;
  final double relativeProximity;
  final double? nearestDistanceM;
  final double? approachRateMps;
  final double? timeToCollisionS;
  final DepthProviderKind source;
}
```

Keep semantic labels separate:

```dart
class SemanticMatch {
  final int yoloTrackId;
  final String label;
  final double confidence;
}
```

An observation does not become invalid when `SemanticMatch` is absent.

## 6. Implementation phases

Each phase must be a reviewable change with tests. Do not implement the entire
plan in one diff.

### Phase 0 — Baseline and evidence

1. Preserve the dirty worktree. Do not revert, delete, or rewrite unrelated
   user changes.
2. Record `git status --short`, Flutter/Dart/NDK versions, target devices, and
   current feature flags.
3. Run and record:
   - `dart analyze`
   - `flutter test --no-pub`
   - `flutter build apk --debug`
4. Existing failures must be listed separately from failures introduced by
   this work. Do not claim a green baseline if the command stalls or fails.
5. Capture a short current-device trace showing YOLO, NCNN, and ARCore provider
   startup/fallback behavior.
6. Add no safety behavior in this phase.

Deliverable: `docs/generic-obstacle-baseline.md` with commands, outputs,
devices, and known blockers.

### Phase 1 — Prove the NCNN model contract

Before implementing obstacle logic, verify inference correctness.

1. Create a small deterministic fixture set containing RGB/YUV frames for:
   flat corridor, wall, chair, narrow pole, and outdoor walkway.
2. Run the original/reference model and the Android NCNN model on the same
   images.
3. Verify:
   - input color order;
   - normalization and mean/std;
   - crop and aspect-ratio policy;
   - output width/height/channel layout;
   - whether larger or smaller output means nearer;
   - rank correlation and spatial correspondence with reference output.
4. Fix native preprocessing. If RGB is required, implement explicit YUV420 →
   RGB/BGR conversion in native code; do not silently use grayscale.
5. Resize model output spatially to the canonical map size. Never zero-pad a
   smaller flattened output.
6. Add a debug-only dump tool for normalized depth and confidence metadata.
   It must be off in production and must not persist camera data without
   explicit developer consent.

Tests:

- deterministic preprocess unit tests;
- output-shape tests;
- near/far direction test;
- invalid NaN/Inf/constant-output test;
- native/reference correlation test with a documented tolerance.

Exit gate: the same fixture produces spatially consistent reference and NCNN
depth. No obstacle thresholds may be tuned before this gate passes.

### Phase 2 — Canonical provider output and health

Refactor provider output without running inference twice.

1. Replace the hazard-only return value with a result object:

   ```dart
   class DepthAnalysisResult {
     final DepthFrame? frame;
     final List<DepthHazard> legacyHazards;
     final DepthHealth health;
   }
   ```

2. Keep a temporary compatibility adapter for existing tests/callers while
   migrating. Remove the adapter only after all call sites move.
3. NCNN returns relative proximity plus a computed frame-quality score.
4. ARCore returns metric metres, confidence, timestamp, and alignment
   metadata.
5. Focal fallback returns `frame: null` and an explicit
   `genericObstacleUnavailable` health capability.
6. Replace the current scalar confidence heuristic with named components:
   valid coverage, dynamic range, temporal stability, blur/light gate, and
   provider state. Log each component.
7. Extend `DepthPipelineStatus` so the host can distinguish:
   - healthy metric geometry;
   - healthy relative geometry;
   - temporarily low confidence;
   - unaligned/stale frames;
   - provider unavailable;
   - legacy-only degraded operation.
8. Announce only state transitions and bounded reminders. Recovery must also
   be announced once.

Exit gate: all providers obey one documented contract, and unavailable generic
geometry can never be represented as a healthy empty scene.

### Phase 3 — Generic obstacle detector

Add `lib/services/generic_obstacle_detector.dart` as a pure-Dart component with
no TTS, Flutter widget, singleton, or platform-channel dependency.

Inputs:

- `DepthFrame`;
- current pitch/roll and motion state;
- optional camera intrinsics and pose/gravity;
- configured walking-corridor parameters;
- timestamp.

Outputs:

- zero or more `GenericObstacleObservation` values;
- diagnostic rejection reason;
- detector quality.

Algorithm, metric path:

1. Filter invalid and low-confidence depth values.
2. Unproject valid pixels to camera-space 3D using intrinsics.
3. Use gravity/orientation to constrain a real 3D ground-plane fit. RANSAC is
   acceptable, but fit in 3D coordinates, not only `z = f(pixelX, pixelY)`.
4. Define a configurable body corridor in camera/world coordinates. Keep all
   dimensions in one configuration object, not scattered constants.
5. Build an occupancy mask for points that:
   - are above the ground plane;
   - intersect the user's forward corridor;
   - are within the usable metric range;
   - satisfy confidence requirements.
6. Use connected components and morphological operations that preserve thin
   vertical structures.
7. Extract broad surfaces, thin vertical components, low obstacles, overhead
   components, and unknown geometry.
8. Report nearest reliable depth, bounds, corridor overlap, component shape,
   and confidence.

Algorithm, relative-depth path:

1. Normalize each frame robustly using valid percentiles; do not use raw MiDaS
   magnitude across sessions.
2. Estimate image-space ground/free-space shape using orientation and temporal
   history.
3. Detect coherent proximity discontinuities and components inside the
   projected corridor.
4. Use component expansion and relative-proximity change across frames.
5. Never output metres or metric velocity from this path.
6. Require stronger temporal evidence before a critical alert than the metric
   path.

Thin-pole branch:

- Do not use the broad obstacle coverage threshold.
- Require vertical continuity, center/corridor intersection, depth-edge
  support, and temporal persistence.
- Fuse high-resolution RGB luma edges with the lower-resolution depth mask.
- Treat an edge-only candidate as `monitor`, never immediately critical.
- Promote only after depth/proximity and multi-frame evidence agree.

Broad-wall branch:

- Detect a coherent near surface whose projected width blocks most of the
  walking corridor.
- A slowly approaching wall must be detected even without a sudden depth jump.
- Do not classify the surface as a step or pothole merely because the provider
  uses the opposite near/far convention.

Do not merge legacy negative-obstacle heuristics into this detector yet.
Deduplicate overlapping generic/legacy observations later in the controller.

Exit gate: synthetic and recorded fixtures detect a wall, a center pole, a
chair/box, and an overhead obstacle without any YOLO labels, while a flat open
corridor produces no warning.

### Phase 4 — Temporal tracking and collision risk

Add:

- `lib/tracker/generic_obstacle_tracker.dart`
- `lib/utils/collision_risk_engine.dart`

Tracking requirements:

1. Associate components using position, shape, overlap, and depth/proximity.
2. Compensate for phone motion with ARCore pose when available and IMU/optical
   evidence otherwise.
3. Use N-of-M confirmation rather than a single fixed consecutive-frame gate.
4. Preserve a track through short occlusion but expire it promptly.
5. Assign stable IDs so alert cooldown applies to a hazard, not only to the
   global `obstacleClose` category.
6. Track approach/recede behavior. Metric paths may calculate velocity and
   TTC; relative paths use expansion/proximity trend only.

Risk must be rule-based and inspectable. It should consider:

- provider and frame quality;
- persistence;
- corridor overlap;
- center versus side zone;
- nearest distance when metric;
- TTC or relative approach trend;
- geometry size and vertical level;
- user motion state;
- optional matched YOLO class/confidence.

Fusion invariants:

- YOLO absence never reduces geometric risk.
- A conflicting or stale YOLO track never suppresses geometry.
- A matched vehicle/bicycle/motorcycle may raise urgency.
- A semantic label is spoken only above a documented confidence and spatial
  match threshold; otherwise speak `Препятствие`.
- Relative monocular depth alone may reach critical only with strong centered
  near-field and temporal evidence.
- Low-quality or stale depth never creates a critical alert.
- No simple `depthScore + yoloScore` clipped to 1.0; keep evidence and gates
  observable in logs.

Use provisional thresholds from one configuration file. Mark them as
engineering defaults and tune only against recorded evidence. Do not scatter
magic numbers across detector, controller, and alert code.

Exit gate: deterministic tests prove approach escalation, receding
suppression, new-hazard cooldown independence, and generic alerts with empty
YOLO results.

### Phase 5 — Alert integration and accessible copy

1. Feed risk results through `AlertManager`; do not call TTS directly from the
   detector or tracker.
2. Add a stable generic-obstacle category/track key without breaking existing
   vehicle and fall-countdown preemption rules.
3. Deduplicate a generic observation against legacy depth hazards and YOLO
   tracks that occupy the same zone/time window.
4. Use short copy:
   - warning: `Препятствие впереди.`
   - critical: `Стоп. Препятствие впереди.`
   - side: `Препятствие слева/справа.`
   - overhead: `Стоп. Препятствие на уровне головы.`
   - degraded: `Анализ пространства ограничен. Используйте трость.`
5. Provide Russian, Kazakh, and English strings in the same change. Add
   completeness tests.
6. Never speak an exact distance when `nearestDistanceM == null`.
7. Replace `status_no_obstacle` with a neutral health state such as
   `Анализ активен`; an empty detector output should normally be silent.
8. Critical alert audio/haptic behavior must reuse existing preemption,
   cooldown, and earcon infrastructure.

Exit gate: alerts are short, localized, non-duplicated, correctly prioritized,
and never claim that the route is safe.

### Phase 6 — ARCore metric provider

Proceed only after the camera-ownership decision gate.

1. Implement the selected single-owner camera architecture.
2. Acquire synchronized camera image, metric depth, raw-depth confidence,
   timestamp, intrinsics, pose, rotation, and coordinate transforms.
3. Use ARCore's confidence data; do not infer confidence only from mean depth.
4. Preserve native depth resolution until alignment, then resample with a
   documented valid-pixel policy.
5. Handle sparse raw depth. Do not fill large holes in a way that invents thin
   obstacles or erases them.
6. Verify image/depth alignment with a calibration target at center, sides,
   near, and far distances.
7. On camera contention, tracking loss, stale depth, lifecycle pause, or
   thermal failure, transition to NCNN or explicit degraded mode and announce
   it once.
8. Do not run ARCore and Flutter camera independently.

Exit gate: the native session sustains synchronized camera + depth on the
device matrix, passes alignment fixtures, and falls back without a silent
period.

### Phase 7 — Shadow mode and controlled rollout

Add a developer feature flag and three modes:

1. `off`: no generic detector work.
2. `shadow`: detector runs and logs decisions but produces no user alerts.
3. `assistive`: alerts enabled for supervised tests.

Start in `shadow`. Compare logged decisions to annotated ground truth. Promote
to `assistive` only when the controlled gates pass.

Do not add a user-facing mode carousel. This flag is for development and
controlled rollout, not daily product complexity.

## 7. Tests and fixtures

### 7.1 Pure unit tests

Add focused tests for:

- metric and relative near/far normalization;
- NaN, Inf, zero, constant, sparse, and low-confidence maps;
- rotation, crop, mirroring, and timestamp rejection;
- flat ground with no obstacle;
- wide wall blocking center/left/right;
- slowly approaching wall;
- thin pole inside and outside the corridor;
- two poles leaving a narrow gap;
- low box/chair;
- overhead branch/sign;
- stationary versus walking user;
- obstacle approach, steady state, receding, and occlusion;
- phone pitch/roll changes;
- YOLO absent, matched, stale, and contradictory;
- provider loss and recovery;
- alert deduplication and stable-track cooldown;
- no `path clear` output under any empty-detection condition.

Use seeded randomness in RANSAC tests. Avoid nondeterministic time by injecting
a clock/timestamps.

### 7.2 Recorded replay fixtures

A plain MP4 is insufficient for depth behavior. Define a versioned replay
format with:

- synchronized YUV/RGB frame or a privacy-safe cropped fixture;
- depth values and confidence;
- provider semantics;
- width/height, timestamp, intrinsics, rotation, and crop;
- IMU/pose sample;
- ground-truth obstacle masks, corridor intersection, and measured distance
  when available.

Keep a few tiny deterministic fixtures in the repository. Store the larger
field corpus outside Git with a manifest, SHA-256 hashes, provenance, consent,
and download/setup instructions. Tests must report `missing fixture`, not pass,
when the corpus is absent.

Required positive scenes:

- plain and textured walls;
- narrow poles/bollards of multiple widths;
- fence, barrier, chair, table edge, box, open door, and hanging branch;
- obstacle entering from left/right;
- stationary and moving people/vehicles for YOLO fusion;
- indoor, outdoor, daylight, dusk, backlight, and low-light conditions.

Required negative/hard scenes:

- empty corridor and open sidewalk;
- shadows, floor markings, patterned tile, cobblestones, grass edge;
- camera tilt, hand shake, brief occlusion, lens partially covered;
- reflective wall, mirror, glass door, rain/snow artifacts;
- a pole outside the projected walking corridor.

### 7.3 Device matrix

At minimum test:

- ARCore Depth device with hardware depth/ToF where available;
- ARCore Depth device without hardware depth;
- Android 11+ device using NCNN CPU fallback;
- a low/mid-range device representative of the supported performance floor.

Record model, Android version, provider, acceleration path, sustained FPS,
inference latency, thermal transitions, and battery use. Device names and
results must be factual, not inferred from capability flags.

### 7.4 Controlled safety protocol

- Use padded/static obstacles first.
- The tester keeps a white cane and has a sighted spotter.
- Do not begin with traffic or unsupervised public walking.
- Start stationary, then 0.8 m/s, then approximately 1.3 m/s.
- Test center, left, and right approaches and deliberate phone misalignment.
- Obtain explicit consent before retaining camera/depth recordings.
- Never recruit blind participants to discover basic crashes, camera
  contention, or known detector failures.

## 8. Proposed initial acceptance gates

These are engineering gates for the controlled corpus, not a claim of general
real-world safety. Change them only with a written evidence-based reason.

Functional:

- A geometric wall/pole/box alert is generated with an empty YOLO result.
- YOLO absence or misclassification cannot suppress the alert.
- Center broad obstacles are detected before the existing controlled target of
  approximately 1.5 m at normal walking speed.
- Thin-pole capability is reported with an explicit tested minimum apparent
  width/range; unsupported thinner cases are documented, not hidden.
- Low-confidence, stale, or unaligned depth produces a degradation state rather
  than a healthy empty result.
- No user-facing code says the path is clear.

Quality:

- Zero center-corridor misses across the fixed canonical controlled set on each
  release device. This does not imply zero misses outside that set.
- Median detector-decision latency <= 500 ms and p95 <= 900 ms after the risk
  threshold is satisfied on the supported performance floor.
- No duplicate speech for one stable obstacle inside the configured cooldown.
- No more than one false critical alert during a 30-minute annotated open-path
  controlled run per device/provider. Report warnings separately.
- 30-minute sustained run without crash, silent provider loss, unbounded
  memory growth, or unannounced thermal degradation.
- All previously passing tests remain passing; all new unit/replay tests pass;
  core on-device scenarios are no longer skipped for a release candidate.

If a gate cannot be met, keep the feature in shadow/experimental state and
report the measured limitation. Do not lower a gate merely to mark the task
complete.

## 9. Performance design

- Never run YOLO and monocular depth redundantly on multiple copies of one
  frame.
- Keep one bounded latest-frame queue; drop stale frames rather than build
  latency.
- Measure preprocess, inference, analysis, tracking, decision, and
  speech-enqueue latency separately.
- Hardware depth may run more frequently than NCNN. Tracking must bridge depth
  intervals without pretending predictions are measurements.
- Preserve existing thermal/battery controls, but generic geometry loss must
  be announced.
- Use pooled typed buffers and avoid per-frame large allocations.
- Keep debug depth visualization and frame dumps disabled in production.
- Establish budgets from the real device matrix before finalizing cadence.

## 10. Logging and observability

Extend `FieldLogger` with privacy-preserving structured events:

- provider selected/fallback and reason;
- image/depth timestamp delta and alignment rejection;
- valid/confident depth coverage;
- ground-plane confidence;
- component count and geometry types;
- per-track persistence, distance/proximity trend, TTC, and corridor overlap;
- risk inputs, rule selected, and final level;
- semantic match or absence;
- alert emitted/suppressed/deduplicated and reason;
- end-to-end decision and speech-enqueue latency;
- thermal, memory, and battery state.

Do not log raw images, OCR text, precise location, contacts, or audio by
default. Any development recording must be explicit, visible, locally stored,
and removable.

## 11. File-level change map

New files expected:

- `lib/models/depth_frame.dart`
- `lib/models/generic_obstacle.dart`
- `lib/services/generic_obstacle_detector.dart`
- `lib/tracker/generic_obstacle_tracker.dart`
- `lib/utils/collision_risk_engine.dart`
- focused unit tests matching each new file
- a replay fixture schema/reader under `test/harness/`
- `docs/generic-obstacle-baseline.md`
- `docs/generic-obstacle-camera-decision.md`
- `docs/generic-obstacle-validation-report.md`

Existing files likely changed:

- `lib/services/depth_provider.dart`
- `lib/services/ncnn_depth_provider.dart`
- `lib/services/hardware_depth_bridge.dart`
- `lib/services/model_service.dart`
- `lib/camera/depth_pipeline_controller.dart`
- `lib/camera/alert_manager.dart`
- `lib/utils/fusion_engine.dart` or its replacement
- `lib/utils/ground_plane_analyzer.dart` only for shared contracts or bug fixes;
  do not rewrite all legacy hazards in the first change
- `lib/models/depth_hazard.dart`
- `lib/models/constants.dart`
- `lib/models/strings.dart`
- `lib/services/field_logger.dart`
- `lib/camera_screen.dart`
- `android/app/src/main/kotlin/com/example/bagdar/HardwareDepthSession.kt`
- `android/app/src/main/cpp/bagdar_depth_ncnn.cpp`
- `integration_test/pipeline_scenarios_test.dart`

Avoid adding another global singleton. Pure algorithm classes must accept their
dependencies and time/input explicitly.

## 12. Review checklist for every phase

- Does this change preserve unrelated dirty-worktree changes?
- Is the provider's depth direction and unit explicit?
- Are the image and depth from the same coordinate system and time window?
- Can a missing YOLO result suppress a physical obstacle? It must not.
- Can invalid depth look like an empty safe scene? It must not.
- Can one noisy frame trigger critical speech? It should not.
- Can a genuinely new obstacle be hidden by a global cooldown? It must not.
- Is exact distance spoken from relative depth? It must not be.
- Is there any `path clear` or equivalent assurance? Remove it.
- Are all thresholds centralized, named, logged, and covered by tests?
- Are performance results from a real named device?
- Are skipped tests and missing fixtures reported honestly?
- Are RU/KK/EN strings complete and concise?
- Are raw sensory data and personal data private by default?

## 13. Definition of done

Implementation is complete only when:

1. The NCNN model contract is verified against a reference implementation.
2. A canonical depth contract distinguishes metric, relative, stale,
   unaligned, and unavailable data.
3. Wall, pole, box/chair, and overhead fixtures produce generic observations
   without YOLO.
4. Temporal tracking and collision risk pass deterministic tests.
5. Alert fusion follows the invariants in this document.
6. User-facing copy never certifies a clear path.
7. Provider degradation and recovery are announced without spam.
8. The selected camera architecture has a written on-device decision record.
9. Controlled replay and device-matrix acceptance gates pass, with factual
   results in `docs/generic-obstacle-validation-report.md`.
10. `dart analyze`, the full Flutter test suite, debug APK build, and required
    on-device integration scenarios pass. Any pre-existing exception is
    documented and must not overlap this stack.
11. The feature remains in shadow mode until the validation report explicitly
    authorizes supervised assistive alerts.

Passing unit tests alone is not completion. A generated APK alone is not
completion. A successful demo on one phone is not completion.

## 14. Execution prompt for another coding agent

Use the following prompt together with this document:

> Work in `C:\Users\Nurik\Desktop\bagdar_app`. Read
> `docs/generic-obstacle-stack-implementation-plan.md` completely before
> changing code. Implement the plan phase by phase, beginning with Phase 0 and
> the Phase 1 NCNN model-contract proof. Preserve every unrelated dirty
> worktree change and do not delete or revert user files. Do not tune detector
> thresholds until preprocessing, output semantics, and image/depth alignment
> are proven. Keep existing legacy depth hazards working while adding the new
> generic detector behind an off/shadow/assistive developer flag. After each
> phase, run the focused tests plus `dart analyze` and `flutter test --no-pub`,
> report exact results, and update the required evidence document. Never
> fabricate device, fixture, performance, or safety results. Do not call the
> work complete until the Definition of Done is met; if hardware or fixtures
> are unavailable, finish all independently verifiable work and report the
> remaining gate as blocked rather than simulating it.

## References

- ARCore Depth overview:
  https://developers.google.com/ar/develop/depth
- ARCore Raw Depth and confidence:
  https://developers.google.com/ar/develop/java/depth/raw-depth
- ARCore shared camera:
  https://developers.google.com/ar/develop/java/camera-sharing
- ARCore `Frame` API and timestamps:
  https://developers.google.com/ar/reference/java/com/google/ar/core/Frame
- Depth Anything V2 paper:
  https://arxiv.org/abs/2406.09414
- MiDaS robust monocular depth paper:
  https://arxiv.org/abs/1907.01341

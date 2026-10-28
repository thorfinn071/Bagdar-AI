# Bagdar Core — master implementation and validation plan

Target executor: **Grok 4.6 Extra High**  
Plan date: **2026-09-12**  
Repository: Flutter/Android, `bagdar_app`  
Status at plan creation: engineering prototype; generic obstacles remain in
`shadow`; not authorized for unsupervised assistive use.

This document is the execution authority for the Bagdar Core hardening pass.
It complements, but does not replace:

- `docs/safety-audit-2026-06.md`;
- `docs/generic-obstacle-stack-implementation-plan.md`;
- `docs/generic-obstacle-validation-report.md`;
- `docs/generic-obstacle-camera-decision.md`.

If an older document conflicts with the current source tree, inspect the code
and tests, record the discrepancy, and follow the safety invariants below. Do
not reintroduce a defect just to match an old audit line number.

---

## 1. Product definition

Bagdar Core is not an object-recognition demo. It is an offline-first mobility
safety system around imperfect phone sensors. Its primary job is to:

1. determine whether its own sensing and alert channels are usable;
2. detect relevant physical hazards in the user's direction of travel;
3. issue short, prioritized, spatially useful speech and haptic warnings;
4. report degradation instead of silently presenting an empty scene;
5. provide a dependable, honestly reported emergency path;
6. later provide basic pedestrian guidance without claiming that a route is
   safe.

Bagdar remains a supplementary aid. It does not replace a white cane, guide
dog, orientation and mobility training, or the user's judgment.

### 1.1 Release milestones

**Milestone A — Core Safety RC**

- safe startup and truthful capability status;
- camera, orientation, lifecycle, and pipeline watchdogs;
- generic positive obstacles, surface/drop hazards, and moving threats;
- one deterministic alert arbitration path;
- manual SOS and fall countdown;
- complete TalkBack-operable Core UI;
- device and controlled-walking evidence;
- no experimental feature active in the Core build.

**Milestone B — Core Mobility RC**

- all Core Safety gates remain passing;
- one real pilot-city offline map package;
- destination selection and pedestrian turn-by-turn guidance;
- GPS/heading quality, stale-location, and off-route handling;
- concurrent navigation and hazard detection under the device budgets;
- supervised outdoor route validation.

OCR, scene narration, object finding, transit, and additional languages can be
promoted after Milestone B only through their own evidence gates. They must not
block or destabilize Core Safety.

---

## 2. Non-negotiable safety invariants

1. **Fail loud, not silent.** A dead camera, frozen stream, unavailable model,
   stale depth frame, failed audio route, or missing permission must become a
   visible and accessible degraded/unavailable state.
2. **No clear-path assurance.** Never say or imply “path clear”, “no
   obstacles”, “safe to cross”, or an equivalent in RU/KK/EN.
3. **Unknown geometry is independent of YOLO.** A physical obstacle must not
   disappear because it is not in the YOLO label set or is misclassified.
4. **Semantics cannot reduce geometric risk.** YOLO may name an already
   detected obstacle or independently detect a moving threat; it may not veto
   generic geometry.
5. **Relative depth is not metres.** Exact metric distance may be spoken only
   when the active provider has a validated, aligned metric contract.
6. **Invalid is not empty.** NaN, low finite coverage, weak dynamic range,
   stale timestamps, failed ground fit, or image/depth misalignment must not be
   converted into a healthy zero-obstacle result.
7. **No one-frame speech noise.** Ordinary warnings require temporal support.
   Any exception for an imminent critical event must be explicit, supported by
   redundant evidence, logged, and tested.
8. **New threats survive cooldowns.** Cooldowns and deduplication are scoped by
   stable threat identity/category/direction and cannot hide a distinct
   critical hazard.
9. **Emergency truthfulness.** “Sent”, “accepted by modem”, “delivered”,
   “composer opened”, “dialer opened”, and “failed” are different states.
10. **No permission prompt during an emergency when it can be completed during
    onboarding.** Missing authority must be announced before the user relies on
    SOS.
11. **No gesture-only Core action.** Every gesture has a reachable semantic
    control or accessibility action.
12. **Privacy by default.** Do not log raw images, audio, OCR text, contacts, or
    precise location. Development recording is explicit, visible, local,
    removable, and consented.
13. **Hardware claims require hardware evidence.** Unit tests, a built APK, or
    a simulated provider do not prove on-device behavior.
14. **Do not lower a gate to obtain a green report.** A blocked gate remains
    blocked and the feature stays `shadow` or disabled.

---

## 3. Scope boundary

### 3.1 Required Core Safety runtime

- startup/capability health;
- camera and image-stream lifecycle;
- orientation and misalignment monitoring;
- frame-quality and visibility degradation;
- generic obstacle geometry;
- ground/drop/stairs/curb hazards;
- YOLO only for semantic enrichment and validated moving threats;
- temporal tracking and collision risk;
- alert arbitration, TTS, haptic, and essential earcons;
- thermal, memory, battery, and stall protection;
- manual SOS;
- fall detection and cancellation countdown;
- minimal settings, permissions, language, and emergency contact;
- privacy-preserving diagnostic events.

### 3.2 Required Core Mobility runtime after Safety RC

- GPS and compass quality;
- offline pedestrian route package for one named pilot city;
- offline POI lookup for that same package;
- route progress, turns, off-route state, and explicit rerouting;
- foreground continuation only after a user starts navigation;
- concurrent operation with the Core Safety vision loop.

### 3.3 Deferred from Core builds

Preserve source code unless it conflicts with Core, but do not initialize,
display, request permissions for, advertise, or package incomplete assets for:

- Bazaar and livestock modes;
- acoustic world model and environment classification;
- VLM scene Q&A;
- sonar;
- OSCP/smart-cane and BLE mesh;
- indoor trail recording/replay;
- charging/background adaptation jobs;
- payment SMS reading;
- phone-abandoned detector;
- object memory/finder;
- public transit/GTFS until pedestrian navigation is validated;
- experimental winter behavior unless it becomes a separately validated
  Core environment profile.

Scene narration and OCR may remain developer-only on-demand tools. They are not
allowed to compete with hazard speech or be represented as complete while
their production assets are absent.

---

## 4. Confirmed repository reality at plan creation

Grok must refresh this snapshot before editing; these facts can drift.

- The worktree is dirty and contains unrelated user material. Never reset,
  checkout, delete, stage, or rewrite unrelated changes.
- The Android `minSdk` is 30 even though README currently claims Android 5.0+.
- `applicationId`/namespace still use `com.example.bagdar`.
- the release build currently uses the debug signing configuration;
- the debug APK was built successfully but is about 595.8 MB; this is not a
  release-size result;
- real packaged ML assets include YOLOv8n INT8 and MiDaS NCNN;
- Paddle OCR and espeak data directories contain documentation rather than a
  complete production payload;
- the bundled Kazakh language pack ZIP files are placeholder-sized and must not
  be claimed as working production models;
- no real pilot-city route/map package is included in the Flutter asset list;
- generic obstacle logic defaults to `GenericObstacleMode.shadow`;
- focused obstacle/depth/alert/pipeline tests: 58 passed, 1 skipped because the
  external reference corpus is absent;
- full test snapshot: 832 passed, 1 skipped, 4 failed; all four failures were in
  `test/misalignment_watchdog_test.dart`;
- analyzer snapshot: no compile errors and 9 lint issues;
- no attached Android device was available for the prior validation;
- ARCore generic depth is intentionally not treated as aligned until the
  camera-ownership spike is completed.

The old safety audit contains findings already partially or fully fixed in the
dirty tree. Revalidate each finding against current code and current regression
tests before acting.

---

## 5. Target architecture

### 5.1 Compile-time Core boundary

Introduce one compile-time product policy rather than scattered booleans:

```text
BuildProfile.core
BuildProfile.research
```

The Core profile is the only release candidate. The research profile may
expose experiments in debug/internal builds. A persisted user preference must
never bypass a compile-time exclusion.

Suggested responsibilities:

```text
CoreFeaturePolicy
  isCompiled(feature)
  mayInitialize(feature)
  mayRequestPermission(feature)
  mayShowInUi(feature)
```

Use Android manifest overlays or equivalent build variants so the Core artifact
does not declare BLE, received-SMS, background-location, or other permissions
solely required by excluded experiments. Keep `SEND_SMS` only if the emergency
use case and Play policy path are explicitly accepted.

### 5.2 Capability-based health, not one boolean

Create a central, dependency-injected `CoreHealthCoordinator`. Do not add a new
global singleton for pure logic.

Suggested contracts:

```text
CoreComponent
  cameraPermission, cameraSession, imageStream,
  alertAudio, haptics,
  genericGeometry, semanticObjects, movingThreats,
  orientation, accelerometer, gyroscope,
  location, compass, emergencySms

ComponentState
  initializing, available, degraded, unavailable, recovering, stopped

CoreCapability
  mobilityVision, genericObstacleAwareness, surfaceHazards,
  movingThreatAwareness, fallDetection, emergencyMessaging,
  pedestrianNavigation

CoreRunState
  starting, operational, degraded, unavailable, recovering, stopped
```

Each component state includes:

- stable reason code, not only localized text;
- monotonic/source timestamp;
- last success timestamp;
- confidence/quality when relevant;
- whether the failure is temporary or session-terminal;
- recovery attempt count and next allowed attempt;
- the capabilities affected by the state.

The coordinator produces a snapshot. UI, speech, telemetry, and tests consume
the same snapshot. Do not infer health independently in several widgets.

### 5.3 Data path

```text
Camera owner
  -> timestamped upright FramePacket
  -> quality/orientation gate
  -> YOLO --------------------------+
  -> depth provider -> DepthFrame --+-> observations
  -> motion evidence ---------------+-> temporal tracks
                                        -> collision risk
                                        -> AlertManager
                                        -> TTS + haptic + essential earcon
```

One physical camera frame has one timestamp and one documented transform. Raw
YOLO rectangles, luma, and depth must be mapped into the same upright normalized
coordinate space before fusion.

Every stage has a bounded latest-frame queue. Drop stale work; never accumulate
latency.

### 5.4 Alert lanes

The current `AlertManager` remains the only hazard-output owner. Direct TTS from
detectors is prohibited. System-health and emergency controllers may submit
typed alerts through the same arbitration boundary.

Define explicit lanes:

1. emergency countdown/action;
2. imminent collision/drop;
3. system unavailable/degraded;
4. ordinary obstacle/navigation warning;
5. informational/on-demand speech.

Specify and test interleaving. A fall countdown cannot be permanently evicted
by repeated camera hazards, and a genuine imminent collision cannot wait behind
an old informational sentence.

### 5.5 Emergency delivery state

Replace success-shaped booleans with a state machine:

```text
idle
 -> resolvingLocation
 -> sending
 -> acceptedByModem | rejected | timedOut
 -> delivered | deliveryUnconfirmed

fallback branches:
 -> composerOpened
 -> dialerOpened
 -> failed
```

The native channel returns structured part-by-part results, subscription ID,
error code, and receipt availability without exposing message contents in logs.

---

## 6. Execution rules for Grok

1. Work phase by phase. Do not make the whole plan one unreviewable patch.
2. Before each phase, inspect current source and tests because the worktree may
   have changed since this plan was written.
3. Preserve all unrelated dirty changes. Never run destructive Git commands.
4. Do not commit, push, publish, send SMS, call a number, or change Play Console
   state without explicit user authorization.
5. Real external messages and calls are never part of an automated test.
6. Use fakes only for deterministic software tests; label them as simulated.
7. Do not fabricate fixtures, device results, delivery receipts, frame rates,
   thermal numbers, accessibility results, or user-test outcomes.
8. New thresholds must be named, centralized, logged, and tested.
9. Pure algorithms accept time and inputs explicitly. Avoid hidden wall-clock
   calls and global state.
10. Any altered safety behavior requires a regression test for the causal path.
11. Keep RU, KK, and EN copy synchronized.
12. Run the phase verification commands and record exact results.
13. If a required phone, corpus, consent, credential, or release key is absent,
    implement all safe software preparation, then mark the gate blocked.
14. Never enable generic `assistive` because code compiles. Only the signed
    validation report may authorize it.

---

## 7. Phase 0 — refreshed baseline and evidence freeze

### Work

- Record `git status --short` without changing it.
- Inventory Core and deferred startup initializers.
- Inventory manifest permissions, services, receivers, native channels, and
  actual asset sizes.
- Run and save exact results for:

```text
dart analyze
flutter test --no-pub
flutter build apk --debug
adb devices -l
```

- Run focused Core groups independently so failures are attributable:
  obstacle/depth, alerts/TTS, camera lifecycle, misalignment, fall/SOS,
  accessibility/widget, and navigation.
- Create `docs/bagdar-core-baseline.md` with date, environment, Flutter/Dart
  versions, device state, failure names, APK hash/size, and known missing
  fixtures.
- Re-triage every critical/high finding in the June safety audit as `fixed`,
  `partially fixed`, `still valid`, or `not reproducible`, with current evidence.

### Exit gate

- Baseline is reproducible and contains no invented hardware result.
- Every known failing test has an owner phase and a causal hypothesis.
- No runtime behavior changes in Phase 0.

---

## 8. Phase 1 — freeze Core scope and correct claims

### Work

- Implement `BuildProfile` and `CoreFeaturePolicy`.
- Make the Core profile the release/default candidate.
- Prevent initialization of deferred services from `main.dart`, camera
  orchestration, background services, and settings.
- Hide deferred controls from Core UI while preserving research access in
  internal builds.
- Ignore stale persisted experiment flags when the build policy excludes them.
- Add migration tests proving existing preferences do not enable excluded code.
- Split Core/research manifest permissions if required.
- Remove `RECEIVE_SMS` from the Core artifact when payment SMS is excluded.
- Remove BLE permissions/features from Core unless a Core feature uses them.
- Decide whether Core truly needs `ACCESS_BACKGROUND_LOCATION`; prefer a
  user-started foreground navigation service and minimum scope.
- Update README into two explicit sections: “verified current state” and
  “planned/research”.
- Align Android support claims with the real `minSdk`; do not claim Android 5
  while Gradle requires API 30.
- Remove estimated performance numbers from product claims or label them as
  unverified engineering hypotheses.
- Do not advertise missing Kazakh ASR/OCR/map payloads as shipped.

### Tests

- Core startup does not initialize any deferred service.
- Deferred preferences cannot bypass build policy.
- Core settings expose no deferred toggle.
- Core manifest assertion contains only approved permission set.
- Research build remains compilable if it is retained.

### Exit gate

- There is one auditable definition of Core.
- The Core APK requests only permissions justified by active Core behavior.
- Documentation no longer overstates supported OS, assets, or validation.

---

## 9. Phase 2 — restore a green software baseline

### Work

- Resolve the four `MisalignmentWatchdog` failures by first writing the desired
  timing/state contract. Do not merely change expectations to current output.
- Remove all analyzer issues in `lib`, Core tests, and Core integration code.
  Scratch tooling may use a separate analysis exclusion only with a written
  reason; do not hide application warnings.
- Reconcile obsolete audit tests with the current product invariant.
- Make external-fixture requirements explicit:
  - ordinary developer suite may report a named skip when a private/large
    corpus is absent;
  - release-candidate validation must fail if any required Core fixture is
    absent.
- Add a deterministic command/script that runs the Core verification set.

### Exit gate

- `dart analyze` is clean for Core source/tests.
- full `flutter test --no-pub` has zero failures;
- no Core test is skipped in the release-candidate verification mode;
- debug APK still builds.

---

## 10. Phase 3 — Core health and truthful startup

### Work

- Add the health contracts and `CoreHealthCoordinator`.
- Define capability requirements rather than treating YOLO, depth, and ARCore
  as interchangeable booleans.
- Connect:
  - camera permission/session/image stream;
  - YOLO load/reload/session death;
  - NCNN initialization, per-frame health, session disable, and recovery;
  - orientation/IMU availability;
  - TTS initialization, queue stall, audio interruption, and output route;
  - haptic availability/failure;
  - thermal/memory/battery monitors;
  - GPS/compass and SMS when their modes are active.
- Eliminate duplicated “ready” calculations.
- Delay the ready announcement until required capabilities have resolved.
- Add edge-triggered localized announcements for transitions, with cooldown and
  recovery copy. Example intent, not mandated wording:
  - operational;
  - space analysis limited — continue using a cane;
  - camera unavailable — stop and check the phone;
  - sound unavailable — vibration warnings remain active;
  - system recovered.
- Never announce global readiness when only an optional component is ready.
- Store a bounded health transition log without sensory payloads.
- Expose a simple Core status surface reachable with TalkBack.

### Tests

- full truth table from component state to capability state;
- startup success, slow initialization, permission denial, and timeout;
- YOLO reload rollback failure;
- NCNN invalid frames and session disable;
- TTS unavailable with haptic fallback;
- haptic unavailable with TTS fallback;
- camera stall/recovery;
- recovery announcement deduplication;
- no false ready event during any required-component failure.

### Exit gate

- Every critical Core component failure produces one deterministic state and an
  accessible user consequence.
- Recovery is observable and does not require restarting the app when the
  platform permits recovery.

---

## 11. Phase 4 — camera, lifecycle, and coordinate ownership

### Work

- Make one state machine own camera initialization, stream start/stop, app
  pause/resume, permission revocation, and retries.
- Await and catch `startImageStream` and warm-resume failures.
- Ensure no `system ready` event follows camera-init failure.
- Validate that screen lock, task switch, phone call, and audio-route changes do
  not leave a falsely operational state.
- Enforce one camera owner. Complete the ARCore spike before combining Flutter
  camera frames with ARCore depth.
- For every frame, retain source timestamp, sensor rotation, mirror flag,
  upright dimensions, and crop transform.
- Reject excessive image/depth timestamp delta.
- Reset trackers, alert session state, and stale decisions on a new camera
  session.
- Ensure foreground-service behavior is explicitly user-started, visible, and
  compatible with target Android restrictions.

### Tests

- lifecycle state-transition unit tests;
- delayed/failing stream future;
- resume after permission denial/regrant;
- rotation 0/90/180/270 and front/back mirror contract;
- stale frame and cross-session frame rejection;
- no duplicated camera owner/session;
- an on-device matrix for launch, lock/unlock, background/resume, call, and
  permission revocation.

### Exit gate

- No lifecycle path reports operational with a dead/frozen stream.
- The same image geometry is used by luma, YOLO, depth, and fusion.
- ARCore is either proven synchronized on-device or remains excluded.

---

## 12. Phase 5 — perception and collision-risk validation

### 12.1 NCNN reference contract

- Create a consented, versioned fixture schema containing raw/decoded frame,
  YUV plane metadata, rotation/mirror/crop, model hash, reference output,
  native output, and valid-pixel mask.
- Pin the reference implementation and preprocessing version.
- Cover portrait/landscape, mirror, stride/pixel-stride variants, dark/bright,
  low-texture, thin poles, broad walls, overhead objects, and open paths.
- Compare finite coverage, spatial orientation, rank correlation, edge
  consistency, and temporal stability. Do not accept only a globally averaged
  score that hides a failed case.
- Keep the existing initial rank-correlation threshold of 0.90 unless a written
  evidence-based review changes it.

### 12.2 Generic positive obstacles

- Preserve YOLO independence.
- Validate walls, poles, barriers, boxes/chairs, partial occlusion, overhead
  hazards, and broad near-field occupancy.
- Record the supported minimum apparent pole width and range per provider/device.
- Reject missing/stale/unaligned/low-quality/rolled data rather than emitting an
  empty result.
- Ensure crop remapping and aligned luma-edge evidence remain correct.
- Confirm real rolling N-of-M tracking and ID separation for unrelated objects.

### 12.3 Surface/drop hazards

- Audit existing ground-plane, stairs-down, curb, pothole, dead-zone, glass,
  and slippery heuristics against the canonical `DepthFrame` health contract.
- Keep negative obstacles separate from ordinary positive-obstacle components
  where their evidence and failure modes differ.
- No weather/blur optimization may fully disable a fall/drop detector without
  an announced degradation.
- Remove or demote heuristics that cannot be distinguished from common false
  positives on recorded replay.

### 12.4 Moving threats

- Use YOLO/tracking/motion only when timestamps and geometry match.
- Define approach from measured temporal evidence, not box size alone.
- Test lateral crossing, receding vehicle, stopped vehicle, bicycle, partial
  occlusion, ID switch, and dense crowd.
- Do not claim reliable vehicle distance from class-average object dimensions.

### 12.5 ARCore decision

- On a supported named phone, test whether one native ARCore/Camera2 owner can
  supply synchronized image plus depth without contention.
- Record API support, frame timestamp delta, rotation, depth confidence,
  sustained FPS, temperature, and lifecycle behavior.
- If the spike fails, keep NCNN relative depth and document that metric generic
  detection is unavailable. Do not ship a nominal ARCore provider returning
  unaligned maps.

### Exit gates

- The gates in `generic-obstacle-stack-implementation-plan.md` pass on the
  fixed replay set and every supported release device.
- Median decision latency is at most 500 ms and p95 at most 900 ms after the
  risk condition is met on the supported performance floor.
- Zero center-corridor misses occur on the fixed canonical controlled set per
  release device; this is not generalized into a universal zero-miss claim.
- No more than one false critical occurs in a 30-minute annotated open-path run
  per device/provider; warnings are reported separately.
- A 30-minute sustained run has no crash, silent provider loss, unbounded
  memory growth, or unannounced thermal degradation.
- Generic obstacles remain `shadow` until the complete controlled protocol also
  passes.

---

## 13. Phase 6 — alert arbitration and accessible output

### Work

- Route every detector and risk engine through typed candidates and
  `AlertManager`. Remove direct hazard TTS calls.
- Define one documented precedence/interruption matrix across emergency,
  imminent hazard, health, navigation, and information.
- Scope dedup/cooldowns by stable track and hazard identity.
- Permit a distinct critical threat even when another critical of the same
  category was recently spoken.
- Add stale-message expiry before speech begins.
- Make all session resets explicit on stop/start/mode/language changes.
- Prevent unbounded per-track history.
- Define a small haptic vocabulary for left, center, right, degradation, and
  emergency. Use an explicit critical flag rather than object identity checks.
- Verify minimum critical haptic strength after user scaling.
- Coordinate audio focus, TalkBack, calls, headphones, and Bluetooth route
  changes.
- Keep safety phrases short and action-oriented. Maintain exact RU/KK/EN intent
  parity.
- Never speak exact metres from relative depth and never announce a clear path.

### Required concurrency tests

- two critical hazards in opposite directions;
- drop hazard plus approaching vehicle;
- fall countdown plus repeated stairs warning;
- health degradation during a navigation instruction;
- new track during global/category cooldown;
- TTS stall with haptic fallback;
- call interruption and output-route recovery;
- language change with queued critical speech;
- dense scene without information spam.

### Exit gate

- All priority/interruption behavior is deterministic and documented.
- No critical event is silently discarded; any suppression has a logged reason.
- A blindfolded sighted tester can distinguish urgent direction and system
  degradation without looking at the screen.

---

## 14. Phase 7 — orientation, misalignment, and user handling

### Work

- Write the product contract for too-high, too-low, flat, excessive-roll,
  covered-camera, and unstable-motion states.
- Separate “no detected object” from “camera probably cannot observe the path”.
- Base windows on elapsed time, not assumed callback counts.
- Resolve all existing misalignment test failures against that contract.
- Provide immediate tactile guidance and bounded verbal escalation.
- Reset the episode after realignment, new camera session, or a recent valid
  detection where appropriate.
- Avoid interpreting normal phone movement during a deliberate gesture as a
  sustained misalignment.
- Teach physical phone position during onboarding and provide an on-demand
  “check phone position” action.

### Exit gate

- Unit tests cover all timing boundaries and episode reset paths.
- Named-device tests cover walking, standing, pocket/covered camera, portrait
  rotation, accidental flat placement, and one-handed operation.
- Misalignment never produces a false operational/clear-path state.

---

## 15. Phase 8 — manual SOS and fall safety

### 15.1 Manual SOS

- Collect emergency contact, permission, SIM choice, and a test-mode
  acknowledgement during setup, not during a real emergency.
- Keep a reachable UI control and an accessibility action; a custom gesture is
  supplementary.
- Add native `sentIntent` and, where supported, `deliveryIntent` handling for
  every multipart segment.
- Return structured status and Android error codes.
- Use `SubscriptionManager`/subscription-specific `SmsManager`; do not silently
  fall back to logical SIM slot 0 when no default exists.
- Detect devices without telephony messaging.
- Clearly distinguish modem acceptance from recipient delivery.
- Opening `sms:` or `tel:` is not success and must produce instructions that
  the user still needs to act.
- Bound retries. Do not automatically retry an ambiguous accepted/unconfirmed
  result and risk duplicate emergency messages.
- Label absent/stale location and include its age category without exposing
  precise coordinates in logs.
- Review Google Play's restricted SMS permission declaration. Physical safety
  emergency alerts are an eligible exception, but approval and prominent
  disclosure are still required.

### 15.2 Fall detection

- Convert all fall windows to timestamp/duration logic independent of sensor
  sample frequency.
- Preserve separate fast-tumble and slow-collapse paths.
- Provide a documented degraded path when gyroscope is absent or fails.
- Test phone drops, placing the phone down, sitting quickly, running, stairs,
  vehicle vibration, sensor gaps, and a second fall during lockout.
- Ensure cancellation cannot happen through an accidental single tap. Provide
  a deliberate, TalkBack-compatible cancellation action.
- Keep countdown messages audible/non-evictable without hiding imminent
  collision warnings.
- Validate behavior while screen is locked and the app is backgrounded within
  Android platform restrictions.

### Tests and gates

- Pure state-machine tests with explicit timestamps.
- Native channel instrumentation for sent, failed, timeout, multipart,
  delivery receipt, no receipt, no SIM, and two SIMs.
- No real message is sent without the user's explicit device-test approval.
- Controlled fall-mat tests use a spotter; never use blind participants to find
  basic detector bugs.
- False cancellation and false “delivered” announcements are release blockers.

---

## 16. Phase 9 — accessibility, onboarding, and language truth

### Work

- Reduce onboarding to Core needs: language, purpose/limitations, phone
  position, camera/microphone/location permissions as needed, emergency
  contact/SMS setup, alert demonstration, and a final capability check.
- Request each permission just in time with a plain-language reason.
- Do not mark onboarding complete while a required Core decision is unresolved.
- Audit every Core screen with TalkBack linear navigation and explore-by-touch.
- Ensure every control has semantic role, name, state, hint where necessary,
  predictable focus order, and one focus target.
- Provide at least 48dp touch targets, large text/reflow support, sufficient
  contrast, and no color-only state.
- Ensure gestures have semantic alternatives and do not conflict with TalkBack.
- Test custom TTS together with TalkBack so the two voices do not make Core
  actions unusable.
- Support physical/Bluetooth audio-route changes and calls.
- Validate RU/KK/EN completeness, grammar, brevity, and consistent action intent.
- If a Kazakh ASR/TTS/OCR engine or model asset is missing, announce and display
  the actual fallback; do not claim native support.
- Add an accessible “system status” and “repeat last important message” action.

### Verification

- automated semantics/widget tests;
- Android Accessibility Scanner with issues recorded;
- manual TalkBack walkthrough without looking at the screen;
- Switch Access/keyboard reachability for every Core action;
- text scaling and display-size matrix;
- Samsung TalkBack/Voice Assistant variant when a Samsung release device is
  supported;
- moderated usability sessions only after internal accessibility defects are
  resolved.

Android recommends combining manual accessibility-service testing, analysis
tools, automated tests, and user testing. Automated semantics alone are not the
exit gate.

### Exit gate

- All Core workflows can be completed with TalkBack without an undocumented
  visual step or gesture.
- Every temporary critical/degraded state is announced accessibly.
- Language fallbacks are truthful and functional.

---

## 17. Phase 10 — Core Mobility: one-city offline navigation

Do not begin release validation of this phase until Core Safety is stable. Code
preparation may proceed in parallel only if it cannot affect the safety loop.

### Data and packaging

- Select one named pilot city based on available testers and routes.
- Build an actual OSM-derived pedestrian graph and POI index.
- Define a signed/hashed package manifest with city ID, source/date, schema
  version, app compatibility range, content hashes, size, and license metadata.
- Install atomically: download/copy to temporary location, verify, then switch.
- Preserve the previous valid package on failure.
- Validate corrupt, truncated, unsupported, low-storage, and interrupted installs.
- Keep GTFS/public transit outside the first Mobility RC.

### Routing behavior

- Prioritize pedestrian-accessible edges only when source data actually
  supports the attribute.
- Never name a route “safe”; map completeness cannot prove present-day safety.
- Expose route source date and limitations in accessible help.
- Provide voice and accessible text destination input.
- Handle no result, ambiguous result, and offline missing-package states.
- Use GPS accuracy/age and heading confidence gates.
- Pause directional claims when location is unreliable.
- Implement off-route confirmation and bounded rerouting without speech spam.
- Keep generic obstacle detection active during navigation.
- Arbitrate turns below imminent hazards and emergency speech.

### Validation

- deterministic graph and rerouting tests;
- recorded GPS replay including urban canyon, stationary drift, tunnel/indoor,
  jump, and compass disturbance;
- named-device battery/thermal tests with vision plus navigation;
- supervised routes with simple turns, complex intersections, off-route
  recovery, and loss of GPS;
- never instruct a user to cross based solely on a traffic-light classifier.

### Exit gate

- A real pilot-city package installs, verifies, routes, updates, and rolls back.
- Navigation degradation is clear and does not suppress hazard warnings.
- Supervised route reports contain timestamps, device names, route hashes, and
  observed failures rather than a generic “works” statement.

---

## 18. Phase 11 — performance, packaging, privacy, and store readiness

### Performance

- Measure preprocessing, inference, analysis, tracking, decision, alert enqueue,
  and speech-start latency separately.
- Record sustained FPS, dropped-frame age, CPU/GPU usage where available,
  temperature, memory, battery change, and recovery events.
- Test cold start, 30-minute walking, 30-minute open path, background/resume,
  low battery, hot device, and memory pressure.
- Select cadence from measured named-device evidence; do not retain estimated
  README numbers as release evidence.

### Packaging

- Replace `com.example.bagdar` with the final application ID before public
  distribution and update native channels consistently.
- Configure a real release signing path. Never ship a release signed with the
  debug key.
- Produce release AAB and per-ABI size reports; a universal debug APK size is
  not the product footprint.
- Remove unused ABI/native/model payloads from each delivery configuration.
- Verify R8/ProGuard does not break native callbacks, TFLite, NCNN, SMS
  receivers, or foreground services.
- Generate dependency/license inventory and preserve model licenses/provenance.
- Establish versioned rollback artifacts and symbol mapping storage.

### Privacy and policy

- Minimize permissions per Core profile.
- Add prominent disclosure and privacy policy for camera, microphone, location,
  emergency contact, SMS, and local telemetry.
- Keep field logging opt-in and provide accessible export/delete actions.
- Review Google Play SMS/Call Log declaration for emergency alerts.
- Review foreground-service camera/location declaration and background-location
  requirements for the current target SDK.
- Remove any permission whose only justification is a deferred feature.
- Test permission denial and revocation as ordinary supported states.

### Exit gate

- Signed release candidate builds reproducibly.
- Core artifact permission and asset manifests match actual runtime behavior.
- Release size, supported API level, and device support are factual.
- Required Play declarations and disclosures are prepared, not assumed.

---

## 19. Phase 12 — controlled validation and rollout

### Stage A — bench/lab

- sighted engineers only;
- padded/static obstacles;
- stationary then controlled walking speeds;
- all known camera/lifecycle/failure injections;
- no traffic and no public unsupervised walking.

### Stage B — sighted blindfold protocol

- white cane, sighted spotter, closed route;
- center/left/right obstacles, wall, pole, box, overhead, curb/drop mock;
- deliberate phone misalignment;
- noisy audio route and TalkBack use;
- abort on any silent Core failure.

### Stage C — orientation and mobility specialist

- review warning content, timing, cognitive load, haptics, phone position,
  training language, and protocol safety;
- revise behavior before involving blind participants.

### Stage D — supervised blind-user pilot

- ethics/consent and data-retention plan;
- known, inspected, controlled environments;
- cane/guide dog remains primary;
- spotter intervention log;
- subjective usefulness and alert-fatigue measures;
- no undisclosed raw sensor recording.

### Stage E — closed release cohort

- only named supported devices/build hashes;
- feature can be remotely or locally reverted to shadow/disabled without data
  loss;
- explicit issue/report channel and stop criteria;
- no public safety claims extrapolated from a small pilot.

### Stop/revert rules

Immediately stop the current stage and return the affected feature to shadow if:

- a critical component dies silently;
- the system emits a clear-path/safe-crossing assurance;
- a canonical center obstacle is missed;
- image/depth orientation is wrong;
- an old threat is replayed as current;
- alert arbitration suppresses emergency instructions or a new imminent threat;
- thermal/memory degradation is unannounced;
- SOS claims sent/delivered without the corresponding state evidence;
- app crash, ANR, unbounded memory, or unrecoverable camera stall occurs.

---

## 20. Device matrix

Do not invent device names. Before testing, fill a versioned matrix with the
actual available phones:

| Role | Device/model | SoC/RAM | Android | ARCore Depth | Provider | Result |
| --- | --- | --- | --- | --- | --- | --- |
| supported floor | TBD | TBD | TBD | TBD | NCNN CPU/GPU | blocked |
| mainstream target | TBD | TBD | TBD | TBD | NCNN/ARCore | blocked |
| upper reference | TBD | TBD | TBD | TBD | NCNN/ARCore | blocked |
| Samsung accessibility | TBD | TBD | TBD | TBD | selected | blocked |

For each build store:

- app version/commit or patch hash;
- APK/AAB SHA-256;
- model and map package hashes;
- provider and accelerator;
- test scenario manifest version;
- performance/thermal output;
- test failures and interventions;
- whether assistive output was shadow, supervised, or disabled.

---

## 21. Test architecture

### Pure unit tests

- health truth tables and transition cooldowns;
- coordinate transforms and timestamp freshness;
- generic geometry and negative hazards;
- N-of-M tracks, IDs, approach/recede;
- collision risk and YOLO independence;
- alert concurrency and session reset;
- fall/SOS state machines with fake time;
- navigation graph/reroute logic;
- permission and policy decisions.

### Recorded replay

- manifest-driven frames and annotations;
- deterministic expected observation/risk/alert windows;
- separate positive and open-path corpora;
- no raw personal data in the repository;
- release mode fails when required corpus is missing.

### Flutter integration

- onboarding and permission denial/recovery;
- start/stop/restart Core session;
- TalkBack semantics and focus order where automatable;
- health-state presentation;
- emergency countdown/cancel flows;
- navigation degradation and hazard preemption.

### Android instrumentation/device

- native NCNN/Dart transform parity;
- camera lifecycle and ownership;
- SMS status/dual-SIM/no-SIM without unauthorized real sending;
- foreground service restrictions;
- audio focus/route interruption;
- thermal and sustained operation.

Every test name must describe a user-visible invariant, not an implementation
detail alone.

---

## 22. Documentation artifacts Grok must maintain

- `docs/bagdar-core-baseline.md` — refreshed factual baseline;
- `docs/bagdar-core-scope.md` — Core/research feature and permission matrix;
- `docs/bagdar-core-health-contract.md` — component/capability state machine;
- `docs/bagdar-core-alert-policy.md` — precedence, copy, haptics, cooldowns;
- `docs/bagdar-core-sos-contract.md` — delivery meanings and fall interaction;
- `docs/bagdar-core-device-matrix.md` — named devices and results;
- `docs/bagdar-core-accessibility-report.md` — TalkBack/Scanner/manual evidence;
- `docs/bagdar-core-validation-report.md` — final gate table and authorization;
- existing generic-obstacle validation/camera-decision documents.

Reports use `pass`, `fail`, `partial`, `blocked`, or `not run`. “Pass” requires
the evidence type named by the gate.

---

## 23. Phase verification command set

Adapt paths for Windows without changing the intent:

```text
dart format --output=none --set-exit-if-changed lib test integration_test
dart analyze
flutter test --no-pub
flutter test --no-pub <focused files for the phase>
flutter build apk --debug
git diff --check
git status --short
```

For release phases additionally:

```text
flutter build appbundle --release <Core flavor/options>
flutter build apk --release --split-per-abi <Core flavor/options>
adb devices -l
flutter test integration_test/... -d <named device>
```

Never claim a command passed if it was not run to completion. Record skips,
timeouts, environment failures, and pre-existing failures separately.

---

## 24. Definition of done

### Core Safety RC is complete only when

1. Scope and permission policy exclude deferred features from the Core artifact.
2. Documentation matches actual SDK support, assets, and validation.
3. Analyzer and full Core software suites pass without Core skips.
4. Core health has no known silent critical-component failure.
5. Camera lifecycle and coordinate parity pass on named devices.
6. NCNN reference and replay gates pass.
7. Generic positive obstacles and surface/drop hazards meet controlled gates.
8. Alert arbitration and haptic fallback pass concurrency/device tests.
9. Misalignment tests and field scenarios pass.
10. Manual SOS/fall flows never overstate delivery and pass approved device
    tests.
11. Every Core flow is independently completed with TalkBack.
12. Sustained performance/thermal tests pass on the supported floor.
13. Controlled staged walking protocol passes with documented evidence.
14. Release artifact is correctly identified, signed, minimized, and hashed.
15. `docs/bagdar-core-validation-report.md` explicitly authorizes the exact
    build/provider/device set for supervised assistive use.

### Core Mobility RC additionally requires

1. a real verified pilot-city package;
2. GPS/heading/off-route degradation and replay gates;
3. concurrent navigation plus Core Safety performance evidence;
4. supervised real-route completion evidence;
5. no safe-route/safe-crossing claim;
6. an updated validation report authorizing the exact release scope.

Passing unit tests alone is not completion. A built APK alone is not
completion. One successful demo is not completion.

---

## 25. External policy/reference checkpoints

- Android accessibility testing recommends manual accessibility-service use,
  analysis tools, automated tests, and user testing:
  https://developer.android.com/guide/topics/ui/accessibility/testing
- Android recommends a minimum 48dp touch target:
  https://developer.android.com/guide/topics/ui/accessibility/views/apps-views
- `SmsManager` distinguishes `sentIntent` and `deliveryIntent` and documents
  multi-SIM behavior:
  https://developer.android.com/reference/android/telephony/SmsManager
- Google Play restricts SMS permissions but lists physical safety/emergency SMS
  as an eligible exception requiring declaration/review:
  https://support.google.com/googleplay/android-developer/answer/10208820
- Background location and foreground-service use require minimum scope,
  disclosure, and Play review where applicable:
  https://support.google.com/googleplay/android-developer/answer/9799150
- ARCore Depth must be capability-checked and is disabled by default:
  https://developers.google.com/ar/develop/java/depth/developer-guide

Recheck policy pages at release time because requirements can change.

---

## 26. Required phase report format

After every phase Grok must return:

```text
Phase:
Status: pass | partial | blocked | fail

Changed:
- file: causal change

Safety invariants affected:
- invariant and evidence

Verification:
- exact command: exit/result
- test totals
- device/model/build hash when applicable

Unrelated dirty changes preserved:
- yes/no; explain any overlap

Blocked gates:
- gate: missing evidence or authority

Behavior still disabled/shadow:
- feature and reason

Next safe phase:
- concrete next work
```

Do not compress a blocked hardware gate into “tests pass”.

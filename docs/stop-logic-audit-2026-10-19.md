# Bagdar STOP logic audit — 19 October 2026

The software design is an important part of the problem. The normal camera
path supplies relative scene information, but its planner requires a separate
body-and-floor clearance proof before it can accept a forward corridor. That
proof source is not installed in the normal camera configuration.

This means a better-looking camera picture alone cannot make the current
forward-clearance branch succeed. It does **not** establish that an ordinary
camera is incapable of useful obstacle assistance. It also does not justify
declaring unobserved space clear.

This audit changes research tooling and documentation. The application keeps
its current stationary-inspection and shadow-delivery restrictions.

## Findings in plain language

### 1. The software asks for information its normal camera path does not supply

The app constructs `ConfidenceAuthoritySpatialRuntime` without a passage
configuration in `lib/viewmodels/camera_view_model.dart:186`. The call in
`lib/camera_screen.dart:2284` supplies the relative detector result and tracks,
without `passageObservation` or `cameraTrackInput`.

Inside that runtime, the forward scene is assigned uncertainty of at least
0.65 whenever a separate body-clearance proof is absent. The corridor evaluator
rejects uncertainty above 0.25, and its positive-evidence gate requires at most
0.15. These are software scores, not measured probabilities of a real obstacle.

The audit constructed the most favourable relative-only input: full image
coverage, perfect ground scores, healthy/fresh sensing, valid orientation, and
no obstacle observations or tracks. The result was still:

| Runtime movement input | Obstacle occupancy | Forward uncertainty | Result |
| --- | ---: | ---: | --- |
| Moving | 0 | 0.65 | STOP |
| Stationary | 0 | 0.65 | HOLD |

These are constructed inputs, not camera measurements. They demonstrate that
this restriction is imposed by the software even before camera quality becomes
the limiting factor.

This is a capability gap for future walking guidance. The existing restriction
to stationary inspection already acknowledges that walking assistance is not
authorised. Removing the uncertainty rule would conceal the gap.

### 2. Stored history does not explain away the current clear-scene stops

The audit replays 132 already-known synthetic frames: 66 labelled clear and 66
labelled hazardous. Each snapshot is evaluated in six separate lanes. The
detector output, original tracker history, header, capture time and frame
identity are shared unchanged across those lanes.

| Configuration | Clear STOP | Clear HOLD | Clear CONTINUE | Hazard STOP | Hazard HOLD | Hazard CONTINUE |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Normal app configuration, continuous scene/planner | 66 | 0 | 0 | 66 | 0 | 0 |
| Normal app configuration, fresh scene/planner per frame | 66 | 0 | 0 | 66 | 0 | 0 |
| Normal app configuration, fresh runtime, stationary input | 65 | 1 | 0 | 65 | 1 | 0 |
| Single-view metric experiment, continuous scene/planner | 66 | 0 | 0 | 66 | 0 | 0 |
| Single-view metric experiment, fresh scene/planner per frame | 66 | 0 | 0 | 66 | 0 | 0 |
| Single-view metric experiment, fresh runtime, stationary input | 55 | 11 | 0 | 66 | 0 | 0 |

The 792 rows are repeated evaluations of 132 frames, not 792 independent
observations. Fresh runtimes and substituted stationary inputs are diagnostic
interventions, not proposed recovery policies. The stationary lanes change
only the runtime movement input; detector motion remains `walking` to keep its
observations identical. They do not simulate a complete stationary phone flow.

A further comparison starts a fresh planner on the **same fused scene**. That
also changes zero STOP actions on clear-labelled frames. Resetting a runtime
resets both scene and planner state; it retains the original detector/tracker
history. This audit therefore does not establish that tracker history is
irrelevant.

History still affects collision scores on 40 clear frames in the app lane and
23 in the metric-experiment lane. It changes one app-lane rule description.
Equal STOP actions do not mean equal internal evidence. They show that current
inputs remain insufficient even after those runtime memories are removed.

In the normal continuous app lane, 65 clear frames report an unverified forward
obstruction, and one reports waiting for stationary confirmation. Every clear
frame rejects forward coverage. The metric experiment still has 55 clear
frames with an unverified forward obstruction and 11 with unavailable coverage.
An unverified image component is not a confirmed physical obstacle.

### 3. Our earlier percentage needed context

The earlier 99.3% figure described the **unknown body-grid cells**, not the
whole picture or all required cells.

Across the 66 clear frames, the existing full-cell diagnostic contains:

- 113,256 body cells in the requested corridor;
- 82,639 certified cells, about **73.0%** of the total;
- 30,617 unknown cells, including 30,396 outside the tested camera view.

Thus about 26.8% of all body cells lie outside the view in this experiment.
The camera-visible synthetic input provides substantial information. The
current proof rule requires the entire requested volume and floor, so that
information is still insufficient for a full-clearance certificate.

These are synthetic spatial-grid counts, not percentages of a real phone image.
The source and calculation are saved in `coverage-context.json` in the audit
directory. Floor coverage is a separate requirement.

### 4. The chosen requirement deserves a product-level review

The current experiment requests a centred corridor 0.9 m wide, 1.85 m high,
from 0.2 to 3.5 m ahead, with floor tolerances of 0.05 m. Both body and floor
coverage must reach 100%. All mapped gaps belong to this declared corridor;
the audit does not find an accidental requirement to observe behind the user.

However, tests enforcing those values do not establish that this fixed request
is appropriate for every intended task, user or camera mounting position. The
request is a design choice, not a universal definition of useful assistance.

Detecting a visible obstacle and certifying a full walking corridor are
different capabilities. The next implementation should make that distinction
explicit: report supported obstacle observations and specific sensing gaps
separately from any permission to move. The existing prohibition on walking
assistance should remain tied to the stronger, unestablished capability.

For eventual walking guidance, either a physically validated source must supply
the required proof, or a separately justified assistance contract must be
designed and evaluated. This audit does not select either by lowering coverage
thresholds or increasing the freshness limit.

## Existing correction and present scope

The separate closed-volume control still verifies the existing volume-authority
correction: identical complete synthetic measurements give 14/14 clear
CONTINUE results with the corrected runtime, versus 14/14 clear STOP results
with the confidence-only runtime; 7/7 hazardous frames stop in both. That
correction predates this audit and is not installed by this work.

The new app lanes reproduce the runtime constructor and absent passage inputs,
with ideal pose quality fixed to 1.0. They do not execute the whole Android
camera pipeline. All runtimes submit shadow actions and keep their arbiter
inactive. The reported STOPs are planner decisions, not measured spoken phone
instructions.

No ordinary-camera clearance improvement, independent model accuracy, physical
sensor coverage, phone delay, TalkBack acceptance or walking readiness is
established. No new holdout or neural inference is claimed.

## Reproduction and verification

First create a new baseline directory:

```powershell
powershell -NoProfile -File tool/model_benchmark/check_stop_causes.ps1 -OutputDirectory scratch/stop-logic-baseline-NEW
```

Then run the audit into another new directory:

```powershell
powershell -NoProfile -File tool/model_benchmark/check_stop_logic_audit.ps1 -OutputDirectory scratch/stop-logic-audit-NEW -BaselineReceipt scratch/stop-logic-baseline-NEW/diagnosis.json
```

The audit test is opt-in during general Flutter testing. A small relative-input
probe runs normally; the 132-frame replay requires the script's explicit flags.
Flutter runs serially. Existing output directories are rejected.

Recorded results for this run:

- Baseline: 54 existing tests passed; targeted analysis clean.
- Audit: two tests passed, including all 792 lane evaluations; analysis clean.
- All 132 metric-experiment baseline action/rule, passage and rejection results
  matched the fresh baseline receipt.
- A separate Python verifier checked frame/lane completeness, shared identities,
  unchanged source hashes, baseline correspondence and output boundaries. It
  rejected two altered authority claims and a duplicated intervention matrix.

Evidence is under `scratch/stop-logic-audit-20261019/`:

- `baseline/`: current STOP diagnosis and regression checks;
- `final-verification/audit.json`: all decisions, track associations and raw
  tracker summaries;
- `final-verification/summary.json`, `report.md`: checked counts and comparisons;
- `final-verification/analyze.log`, `tests.log`, `independent-audit.log`;
- `coverage-context.json`: derived context for the earlier coverage percentage;
- `delivery-verification.json`: final artifact hashes and preservation check.

The earlier `first-run/` is retained as an intermediate result. Application
sources and previous experiments are preserved; only new audit tooling and
this report are added. Full Core aggregate, named-device and walking checks
remain outside this targeted software audit.

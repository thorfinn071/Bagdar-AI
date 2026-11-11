# Bagdar AI — engineering case study

**Lead developer:** Nurmukhamed Sabit  
**Focus:** accessible computer vision, on-device AI and Android engineering  
**Project stage:** development prototype (11 November 2026)

> **One-minute summary:** Bagdar explores whether local computer vision, voice feedback and accessible interface design can help people with visual impairments inspect their immediate surroundings. The current application is a **stationary inspection prototype**. It does **not** authorize walking guidance or replace established mobility aids.

## 1. The problem

Visual assistance on a phone has to work under constraints that a conventional object-detection demo can overlook: limited compute, changing lighting, outdated camera observations, inconsistent speech services and a user interface that needs to work with assistive technologies.

The goal of Bagdar is to investigate these constraints in an Android application—not to equate a detected object with a confirmed safe walking route.

## 2. What the repository implements

| Layer | Implementation | Why it matters |
| --- | --- | --- |
| Mobile experience | Flutter/Dart with Android components | Guided onboarding, inspection controls and permission recovery |
| Object perception | YOLOv8n INT8 | On-device object detections without a server round trip |
| Relative depth | MiDaS Small | Experimental relative spatial cues; **not** calibrated distance in metres |
| State and safety | Freshness checks, provider health, orientation checks, conservative decisions | Prevents missing or stale evidence from being presented as clear-path proof |
| Accessible interaction | Russian, Kazakh and English UI text; opt-in speech, voice commands and vibration | Multiple ways to request and receive information |
| Evaluation | Flutter tests, simulator/replay tooling and documented investigation | Makes failure modes and readiness limitations inspectable |

Camera inference runs locally. Offline speech depends on device services and installed voices. Walking assistance remains disabled in the Core build, while experimental decisions stay in shadow mode.

## 3. Engineering decisions

**Explicit uncertainty over false confidence.** “No obstacles reported” is an observation about a frame, not a statement that a route is safe. Camera observations, coverage and movement permission are kept separate. See the [inspection status design](inspection-evidence-status-2026-10-19.md).

**Separate experiments from usable features.** Research-mode perception and simulations can be tested without granting permission for independent mobility. See [Core scope](bagdar-core-scope.md) and the [safety validation report](bagdar-core-validation-report.md).

**Treat lifecycle behavior as part of correctness.** The evaluation tracks disposal, resumed streams, data freshness and the distinction between a successful test and supported field use.

## 4. Evidence and limitations

The repository preserves quantitative **software-test** evidence, not independent real-world safety validation.

- In the [27 October 2026 simulation batch](simulation-lab-continuation-2026-10-27.md), **72 synthetic episodes** were run, delivering **2,232 input frames**; the report recorded **115 YOLO results** and **55 accepted depth results**. These are pipeline and coverage measurements—not object-detection accuracy, user benefit or proof of navigability.
- In the [continuity experiment](quality-and-continuity-evaluation-2026-10-27.md), two looping 30-second streams delivered all **902 expected frame identities** in one Android app process. These streams were repeated synthetic clips, not continuous real-world walks.
- The image-quality experiments also found unresolved weaknesses, including correlated-noise masking and unnecessary rejection of some sharp inputs. These results are documented rather than presented as successes.

**Still unverified:** physical-camera acceptance on named Android devices, a complete TalkBack / accessibility walkthrough, battery and thermal behavior over sustained field sessions, and controlled testing with people who have visual impairments. The [accessibility report](bagdar-core-accessibility-report.md) explicitly marks manual device checks as pending.

## 5. Next milestones

1. Complete supervised stationary camera, spoken output and TalkBack acceptance on physical Android devices.
2. Measure false detections, missed obstacles, rejected frames and latency on independent real scenes.
3. Establish an ethically reviewed, consent-based user evaluation protocol before claiming practical accessibility outcomes.
4. Consider broader navigation research only after relevant safety and validation gates pass.

## Explore the project

- [Source code and build instructions](../README.md)
- [Repository architecture map](repository-structure.md)
- [Documentation catalogue](README.md)
- [Detailed quality and continuity evaluation](quality-and-continuity-evaluation-2026-10-27.md)

---

*This page is a portfolio overview of the engineering and evidence already in the repository; it does not represent a product launch or safety certification.*

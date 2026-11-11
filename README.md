# Bagdar

Bagdar is an Android project exploring how on-device computer vision, speech
and vibration can help people with visual impairments understand their immediate
surroundings. It is built with Flutter and native Android components.

**[Read the engineering case study](docs/portfolio-case-study.md)** — a concise portfolio overview of the problem, architecture, test evidence, failure modes and next steps.

**Status:** development prototype. The current app focuses on guided training
and stationary camera inspection. Walking assistance is a longer-term goal.

## Features

- **Guided onboarding:** language and assistance-mode selection, feedback setup,
  camera-free practice, permission recovery and device checks.
- **On-device vision:** YOLOv8n INT8 object detection and MiDaS Small relative
  depth, with tracking and checks for stale camera results.
- **Stationary inspection:** camera preview, possible-obstacle observations and
  system status, with spoken and vibration feedback.
- **Language and voice support:** Russian, Kazakh and English interface text,
  opt-in spoken onboarding, and voice commands for inspection and settings.
- **Emergency tools:** manual SOS with location handling and a countdown after
  a suspected fall.

## Current scope

Bagdar currently supports development and evaluation of **stationary
inspection**. Walking guidance is disabled; experimental obstacle decisions are
kept in `shadow` mode, where they are evaluated without authorizing movement.
“No obstacles reported” does not establish a clear walking path, and MiDaS
relative depth is not a distance measurement in metres. Bagdar does not replace
a white cane, guide dog or mobility training.

Automated tests, scene replays and Android emulator experiments support the
project. Physical-camera, audible-output and TalkBack acceptance remain pending.
Detection quality, false stops and sustained phone performance also need further
validation. See the [latest evaluation](docs/quality-and-continuity-evaluation-2026-10-27.md)
for measured results and limitations.

Camera inference runs locally. Offline speech availability depends on the
phone's services and installed voices; the experimental Kazakh speech stack is
incomplete. Navigation, maps and other deferred experiments are outside the
current Core workflow. See [Core scope](docs/bagdar-core-scope.md).

## Getting started

Requirements:

- Flutter with Dart compatible with `^3.11.1` in `pubspec.yaml`.
- Android SDK, Java 17 and the Flutter-selected NDK.
- An Android 11+ device (**API 30+**), with USB debugging for physical testing.

From the repository root in PowerShell:

```powershell
flutter doctor
flutter pub get

# Download the native NCNN runtime once.
powershell -File tools/ncnn/download_ncnn_android.ps1

flutter devices
flutter run --flavor core
```

Add `-d <device-id>` if several devices are connected. Dependency and runtime
downloads require internet access; the camera models are bundled in `assets/`.
No model training or conversion is needed for a normal launch.

NCNN binaries are downloaded separately. A build can succeed without the NCNN
wrapper, so check the backend status after launch. See the
[NCNN guide](tools/ncnn/README.md) for details. The checkout must also include
`third_party/flutter_tts/`, which contains the required
[local speech patch](third_party/flutter_tts/BAGDAR_PATCH.md).

Complete onboarding before opening inspection. For a physical test, use the
[stationary-device checklist](docs/stationary-device-acceptance-checklist-2026-10-27.md)
with a sighted operator. Test external SOS actions separately; opening a message
composer does not confirm delivery.

## Development

Core is the default app profile. Build a debug APK and run the developer checks:

The full test suite needs the separately downloaded research fixtures. The
restore command uses your GitHub credentials for the private research release.

```powershell
flutter build apk --debug --flavor core
python tool/datasets/datasets.py restore
flutter analyze --no-pub
flutter test --no-pub --concurrency=1
```

Additional development paths:

- **Research:** `flutter run --flavor research --dart-define=BAGDAR_RESEARCH=true`
  enables the research profile; individual experiments have their own gates.
- **Simulation:** the [simulation lab](tool/simulation/README.md) feeds synthetic
  inputs into the app using a separate build and entry point.
- **Core verification:** [the verifier guide](tool/verify_core.md) describes
  aggregate replay checks and strict `-Rc` fixture requirements.
- **Research data:** [the dataset guide](tool/datasets/README.md) describes
  the private, versioned GitHub release and checksum-verified restoration.

Builds currently use the application ID `com.example.bagdar` and debug signing,
including the release configuration. Android is the development target; other
platform folders do not establish supported releases.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before making changes.

## Next milestones

1. Complete stationary camera, speech, TalkBack and lifecycle acceptance on a
   named Android phone.
2. Improve image-quality handling and measure missed obstacles and false stops
   on independent physical scenes.
3. Measure sustained latency, memory use, thermal behavior and recovery during
   longer sessions.

See the [remaining-work plan](docs/quality-and-continuity-implementation-plan-2026-10-27.md)
for completion criteria.

## Documentation

- [Documentation index](docs/README.md) — plans, protocols and evaluations.
- [Repository map](docs/repository-structure.md) — source layout and preserved evidence.
- [Onboarding flow](docs/bagdar-onboarding-wireflow.md) — first-run training and session checks.
- [Inspection status](docs/inspection-evidence-status-2026-10-19.md) — camera observations and clearance limits.

## License

[MIT](LICENSE). Bundled fonts and third-party code retain their own licenses.

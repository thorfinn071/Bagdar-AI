# VisionGuide AI

VisionGuide AI is a Flutter mobile app for assistive vision support. It combines live camera analysis, object tracking, OCR, speech feedback, voice commands, haptic alerts, GPS waypoints, and SOS messaging into a single workflow.

## What the app does

- Real-time object detection and tracking from the camera stream.
- Distance and direction feedback for nearby objects.
- Offline OCR for reading text in the camera frame.
- Text-to-speech alerts with priority and deduplication.
- Long-press voice commands in Russian and Kazakh.
- Cane mode with vibration patterns for spatial guidance.
- SOS SMS flow with current GPS location.
- Saved waypoints for returning to important places.
- Battery-aware throttling and optional foreground service support.

## Project structure

- `lib/main.dart` — app entry point and startup flow.
- `lib/onboarding_screen.dart` — onboarding, language selection, and start decision.
- `lib/camera_screen.dart` — main camera experience and orchestration.
- `lib/services/` — OCR, TTS, voice commands, battery, SOS, waypoint, settings, foreground service.
- `lib/utils/` — detection, alerting, depth analysis, and decision logic.
- `lib/tracker/` — tracking state and geometry helpers.
- `lib/widgets/` — reusable UI components and overlays.

## Requirements

- Flutter SDK 3.11+
- Android Studio / Xcode depending on target platform
- A real device is strongly recommended for camera, microphone, vibration, and GPS features

## Assets

Make sure these files exist in `assets/` and are listed in `pubspec.yaml`:

- `assets/yolov8n_int8.tflite`
- `assets/labels.txt`
- `assets/midas_v21_small.tflite`

## Permissions

The app uses platform permissions for:

- Camera
- Microphone
- Location
- Background/foreground service behavior on supported platforms

If a feature does not work, check the corresponding permission first.

## Getting started

1. Install Flutter dependencies:

   ```bash
   flutter pub get
   ```

2. Run the app on a connected device:

   ```bash
   flutter run
   ```

3. Follow onboarding on first launch.

## How the startup flow works

- `main()` initializes cached settings.
- The app decides whether to show onboarding or the camera screen.
- After onboarding, the app opens the camera experience directly.

## Notes on architecture

- Shared preferences are wrapped by `SettingsService`.
- Speech output is centralized in `TtsService`.
- Voice recognition is handled separately from TTS.
- Camera analysis is split across detection, OCR, depth analysis, and tracker logic.
- `camera_screen.dart` acts as the orchestration layer for these services.

## Troubleshooting

- **Camera does not start**
  - Check camera permission.
  - Try a physical device instead of an emulator.

- **Voice commands do not work**
  - Check microphone permission.
  - Make sure the device has a speech engine available.

- **OCR or depth analysis is unavailable**
  - Verify that all model assets are present.
  - Re-run `flutter pub get` after changing assets.

- **SOS sending fails**
  - Set the emergency contact in Settings.
  - Check location permission.

## Development tips

- Use `flutter analyze` before committing changes.
- Prefer small, isolated changes in the camera pipeline.
- Keep platform-specific changes under `android/`, `ios/`, or `windows/` as needed.

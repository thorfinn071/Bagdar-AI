import '../../models/strings.dart';
import '../../safety/alerts/feedback_command.dart';
import '../../safety/alerts/feedback_policy.dart';
import '../../safety/planning/corridor_candidate.dart';
import '../../safety/planning/safety_action.dart';
import 'onboarding_state.dart';

class DeviceProbe {
  final ProbeResult camera;
  final ProbeResult thermal;
  const DeviceProbe(this.camera, this.thermal);
}

enum OnboardingSpeechResult {
  played,
  voiceUnavailable,
  engineUnavailable,
  interrupted,
  timedOut,
  failed,
}

abstract interface class OnboardingGateway {
  Future<OnboardingSpeechResult> speak(
    String text,
    AppLanguage language, {
    bool critical = false,
  });
  Future<bool> stopHaptic();
  Future<void> speechRate(double rate);
  Future<CameraAccess> cameraPermission({bool request = false});
  Future<DeviceProbe> checkCamera();
  Future<ProbeResult> checkAlignment();
  Future<bool> openSettings();
  Future<bool> openSpeechSettings();
  Future<void> stop();
}

/// Reuses runtime feedback semantics; training never creates a detector, SMS,
/// location, microphone, recorder or network client.
FeedbackCommand trainingStopCommand(DateTime now) =>
    const FeedbackPolicy().commandFor(
      SafetyAction(
        actionId: 'training-stop-${now.microsecondsSinceEpoch}',
        kind: SafetyActionKind.stopNow,
        cause: 'training_example',
        priority: SafetyPriority.p0Emergency,
        sceneRevision: 0,
        hazardIds: const ['training'],
        evidenceSummary: const {},
        direction: CorridorDirection.forward,
        confidence: 1,
        createdAt: now,
        validUntil: now.add(const Duration(seconds: 15)),
        ruleId: 'TRAINING',
      ),
    )!;

/// Preview never substitutes successful fake hardware for real evidence.
class UnavailableOnboardingGateway implements OnboardingGateway {
  @override
  Future<OnboardingSpeechResult> speak(
    String text,
    AppLanguage language, {
    bool critical = false,
  }) async => OnboardingSpeechResult.engineUnavailable;
  @override
  Future<bool> stopHaptic() async => false;
  @override
  Future<void> speechRate(double rate) async {}
  @override
  Future<CameraAccess> cameraPermission({bool request = false}) async =>
      CameraAccess.restricted;
  @override
  Future<DeviceProbe> checkCamera() async => DeviceProbe(
    ProbeResult(ProbeStatus.unavailable, 'cameraUnavailable', DateTime.now()),
    ProbeResult(ProbeStatus.unavailable, 'thermalUnavailable', DateTime.now()),
  );
  @override
  Future<ProbeResult> checkAlignment() async => ProbeResult(
    ProbeStatus.unavailable,
    'alignmentUnavailable',
    DateTime.now(),
  );
  @override
  Future<bool> openSettings() async => false;
  @override
  Future<bool> openSpeechSettings() async => false;
  @override
  Future<void> stop() async {}
}

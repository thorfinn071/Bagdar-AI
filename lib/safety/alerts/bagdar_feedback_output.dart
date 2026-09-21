import '../../models/strings.dart';
import '../../services/earcon_service.dart';
import '../../services/haptic_service.dart';
import '../../services/tts_service.dart';
import 'feedback_command.dart';
import 'feedback_dispatcher.dart';
import 'haptic_policy.dart';

/// Production output adapter for the unified safety-feedback runtime.
class BagdarFeedbackOutput implements FeedbackOutputPort {
  final TtsService tts;
  final EarconService earcon;
  HapticDeviceCapabilities _hapticCapabilities;

  BagdarFeedbackOutput({
    required this.tts,
    required this.earcon,
    HapticDeviceCapabilities hapticCapabilities =
        const HapticDeviceCapabilities(
          hasVibrator: false,
          hasAmplitudeControl: false,
        ),
  }) : _hapticCapabilities = hapticCapabilities;

  static Future<BagdarFeedbackOutput> create({
    required TtsService tts,
    required EarconService earcon,
  }) async => BagdarFeedbackOutput(
    tts: tts,
    earcon: earcon,
    hapticCapabilities: await HapticService.safetyCapabilities(),
  );

  Future<void> refreshCapabilities() async {
    _hapticCapabilities = await HapticService.safetyCapabilities();
  }

  @override
  HapticDeviceCapabilities get hapticCapabilities => _hapticCapabilities;

  @override
  bool get ttsAvailable => tts.isReady;

  @override
  bool get hapticAvailable => hapticCapabilities.hasVibrator;

  @override
  bool get earconAvailable => earcon.isReady && earcon.isEnabled;

  @override
  Future<bool> speak(FeedbackCommand command) async =>
      tts.submitFeedbackCommand(
        command,
        localizedText: AppStrings.get(command.speechKey),
      );

  @override
  Future<bool> playEarcon(FeedbackEarcon feedback) =>
      earcon.playFeedback(feedback);

  @override
  Future<bool> vibrate(HapticCue cue) => HapticService.emitSafetyCue(cue);

  @override
  Future<void> interruptCurrent() async {
    await tts.stop();
    await earcon.stopAll();
    await HapticService.cancel();
  }

  @override
  Future<void> awaitCompletion(FeedbackCommand command) async {
    if (!ttsAvailable) return;
    await tts.awaitCurrentSpeech();
  }
}

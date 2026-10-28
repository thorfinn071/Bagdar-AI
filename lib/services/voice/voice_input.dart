import '../../models/strings.dart';

int _voiceSessionSequence = 0;

/// Shared across onboarding and inspection so late platform events cannot
/// match an unrelated coordinator's first turn.
int nextVoiceSessionId() => ++_voiceSessionSequence;

enum VoiceInputAvailability {
  ready,
  permissionDenied,
  unsupported,
  unavailable,
}

enum VoiceInputOutcome {
  recognized,
  noSpeech,
  cancelled,
  interrupted,
  unavailable,
  languageUnavailable,
  permissionDenied,
}

/// Identity belongs to one question, never just to an open microphone.
class VoiceInputTurn {
  final int sessionId;
  final int turnId;
  final AppLanguage language;
  final Duration duration;
  const VoiceInputTurn({
    required this.sessionId,
    required this.turnId,
    required this.language,
    this.duration = const Duration(seconds: 8),
  });
}

class VoiceInputResult {
  final int sessionId;
  final int turnId;
  final VoiceInputOutcome outcome;
  final String text;
  final bool isFinal;
  final double? confidence;
  final String backend;
  const VoiceInputResult({
    required this.sessionId,
    required this.turnId,
    required this.outcome,
    this.text = '',
    this.isFinal = true,
    this.confidence,
    this.backend = 'android_on_device',
  });
}

abstract interface class VoiceInput {
  /// Only an explicit user activation may pass requestPermission: true.
  Future<VoiceInputAvailability> prepare({required bool requestPermission});
  Future<VoiceInputResult> listen(
    VoiceInputTurn turn, {
    required void Function() onReady,
  });
  Future<void> cancel();
  Future<void> dispose();
}

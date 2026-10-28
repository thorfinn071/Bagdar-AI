import 'dart:async';

import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_input.dart';

class PendingVoiceTurn {
  final OnboardingVoiceTurn turn;
  final void Function() onReady;
  final result = Completer<OnboardingVoiceResult>();
  PendingVoiceTurn(this.turn, this.onReady);
}

/// Simulated transcripts only. This supplies no device/ASR quality evidence.
class FakeOnboardingVoiceInput implements OnboardingVoiceInput {
  VoiceInputAvailability availability = VoiceInputAvailability.ready;
  final permissionRequests = <bool>[];
  final turns = <PendingVoiceTurn>[];
  PendingVoiceTurn? pending;
  Completer<VoiceInputAvailability>? preparation;
  bool autoReady = true;
  bool completeOnCancel = true;
  bool disposed = false;
  int cancels = 0;

  @override
  Future<VoiceInputAvailability> prepare({
    required bool requestPermission,
  }) async {
    permissionRequests.add(requestPermission);
    final waiting = preparation;
    preparation = null;
    return waiting == null ? availability : await waiting.future;
  }

  @override
  Future<OnboardingVoiceResult> listen(
    OnboardingVoiceTurn turn, {
    required void Function() onReady,
  }) {
    final next = PendingVoiceTurn(turn, onReady);
    turns.add(next);
    pending = next;
    if (autoReady) onReady();
    return next.result.future;
  }

  void answer(
    String text, {
    VoiceInputOutcome outcome = VoiceInputOutcome.recognized,
    bool isFinal = true,
    double? confidence = 0.95,
    int? sessionId,
    int? turnId,
  }) {
    final next = pending!;
    pending = null;
    complete(
      next,
      text,
      outcome: outcome,
      isFinal: isFinal,
      confidence: confidence,
      sessionId: sessionId,
      turnId: turnId,
    );
  }

  void complete(
    PendingVoiceTurn next,
    String text, {
    VoiceInputOutcome outcome = VoiceInputOutcome.recognized,
    bool isFinal = true,
    double? confidence = 0.95,
    int? sessionId,
    int? turnId,
  }) {
    if (identical(pending, next)) pending = null;
    next.result.complete(
      OnboardingVoiceResult(
        sessionId: sessionId ?? next.turn.sessionId,
        turnId: turnId ?? next.turn.turnId,
        text: text,
        outcome: outcome,
        isFinal: isFinal,
        confidence: confidence,
      ),
    );
  }

  @override
  Future<void> cancel() async {
    cancels++;
    if (completeOnCancel && pending != null) {
      answer('', outcome: VoiceInputOutcome.cancelled);
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await cancel();
  }
}

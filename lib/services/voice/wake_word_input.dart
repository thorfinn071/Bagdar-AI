enum WakeWordAvailability {
  ready,
  disabled,
  modelMissing,
  unsupported,
  permissionDenied,
  unavailable,
}

class WakeWordResult {
  final int sessionId;
  final String outcome, backend, keyword;
  final bool released;
  final double? confidence, wordDurationMs;
  final int? ageMs;
  const WakeWordResult({
    required this.sessionId,
    required this.outcome,
    this.backend = '',
    this.keyword = '',
    this.released = false,
    this.confidence,
    this.wordDurationMs,
    this.ageMs,
  });

  bool acceptedFor(int expectedSession) =>
      sessionId == expectedSession &&
      outcome == 'detected' &&
      backend == 'vosk_kz_0_42' &&
      keyword == 'bagdar' &&
      released &&
      confidence != null &&
      confidence!.isFinite &&
      confidence! >= .85 &&
      confidence! <= 1 &&
      wordDurationMs != null &&
      wordDurationMs!.isFinite &&
      wordDurationMs! >= 250 &&
      wordDurationMs! <= 2000 &&
      ageMs != null &&
      ageMs! >= 0 &&
      ageMs! <= 1000;
}

/// Local candidate, separate from command ASR. A detection grants no action.
abstract interface class WakeWordInput {
  Future<WakeWordAvailability> prepare({required bool requestPermission});
  Future<WakeWordResult> listen({
    required int sessionId,
    required Duration duration,
    required void Function() onReady,
  });
  Future<void> cancel();
  Future<void> dispose();
}

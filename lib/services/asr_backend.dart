/// Abstract interface for speech recognition backends. Generalizes
/// `VoiceCommandService` so current `speech_to_text`,
/// `VoskKkRecognizer`, and future Whisper / whisper.cpp backends can
/// coexist behind a single contract.
///
/// Phase 1 — Direction 12 foundations. Concrete implementations live
/// in their own files; `VoiceCommandService` routes through the active
/// backend transparently.
abstract class AsrBackend {
  /// Human-readable identifier for diagnostics and telemetry
  /// (e.g. `'speech_to_text'`, `'vosk_kk'`, `'whisper_tiny'`).
  String get name;

  /// True when the backend has loaded its model / resources and is
  /// ready to accept `start()` calls.
  bool get isReady;

  /// True while the backend is actively transcribing audio.
  bool get isListening;

  /// Initialise the backend. [grammar] is an optional closed-set word
  /// list; backends that don't support grammar restriction ignore it.
  Future<bool> init({List<String>? grammar});

  /// Begin listening. Returns `false` if the backend is not ready or
  /// the microphone is unavailable.
  Future<bool> start();

  /// Stop listening. Idempotent.
  Future<void> stop();

  /// Release all resources. After this call, [isReady] returns false.
  Future<void> dispose();

  /// Fires with the final recognised transcript for each utterance.
  void Function(String text)? onResult;

  /// Fires on unrecoverable errors. The host should fall back to
  /// another backend or inform the user.
  void Function(String error)? onError;
}

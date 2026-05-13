/// Phase 2 of the Kazakh language stack — TTS engine selection.
///
/// `TtsService` resolves the active Kazakh engine via the tiered priority
/// chain described in `plans/bagdar-kazakh-language-stack-1f2668.md`:
///
/// ```
/// 1. system          — vendor / Android System TTS that natively supports
///                      kk-KZ (e.g. user-installed RHVoice APK, Yandex
///                      SpeechKit). Detected via `flutter_tts.getLanguages`.
/// 2. rhvoice         — Bagdar-bundled RHVoice native engine, loaded from
///                      the downloaded `rhvoice-kk-aigul` language pack.
/// 3. espeak          — Bagdar-bundled espeak-ng native engine (ships in
///                      `assets/espeak-ng-data/`, always available).
/// 4. russianFallback — Fail-safe: read Kazakh text through the Russian
///                      TTS voice with Cyrillic phonetics. Preserves the
///                      legacy behavior of Phase 0.
/// ```
///
/// Russian (`ru-RU`) and English (`en-US`) always remain on `flutter_tts`
/// and are not affected by this enum.
enum KkTtsEngine {
  /// Android system TTS engine that natively supports Kazakh.
  system,

  /// Bagdar-bundled RHVoice engine (downloaded as a language pack).
  rhvoice,

  /// Bagdar-bundled espeak-ng engine (ships in APK assets).
  espeak,

  /// Last resort: read Kazakh text using the Russian voice.
  russianFallback,
}

extension KkTtsEngineX on KkTtsEngine {
  /// Stable identifier persisted in logs and used on the native channel.
  String get id => switch (this) {
        KkTtsEngine.system => 'system',
        KkTtsEngine.rhvoice => 'rhvoice',
        KkTtsEngine.espeak => 'espeak',
        KkTtsEngine.russianFallback => 'russianFallback',
      };

  /// Whether speech for this engine is rendered through the
  /// `bagdar/native_tts` MethodChannel (Kotlin + JNI). For `system` and
  /// `russianFallback`, `TtsService` continues to use `flutter_tts`.
  bool get usesNativeBridge =>
      this == KkTtsEngine.rhvoice || this == KkTtsEngine.espeak;

  /// Whether picking this engine still requires `flutter_tts` to be
  /// configured (so that the Dart side has a working `getLanguages` /
  /// `stop` / `setVolume` surface).
  bool get usesFlutterTts =>
      this == KkTtsEngine.system || this == KkTtsEngine.russianFallback;

  /// Translation key for the engine's display label (looked up via
  /// `AppStrings.get`).
  String get labelKey => switch (this) {
        KkTtsEngine.system => 'tts_kk_engine_system',
        KkTtsEngine.rhvoice => 'tts_kk_engine_rhvoice',
        KkTtsEngine.espeak => 'tts_kk_engine_espeak',
        KkTtsEngine.russianFallback => 'tts_kk_engine_fallback_ru',
      };
}

KkTtsEngine? kkTtsEngineFromId(String? id) {
  if (id == null) return null;
  for (final e in KkTtsEngine.values) {
    if (e.id == id) return e;
  }
  return null;
}

/// Capability descriptor for a single engine, as reported by the native
/// `bagdar/native_tts.availableEngines` method. Returned to Dart so
/// `TtsService._resolveKkEngine` can decide which engine to activate.
///
/// Native side computes these by checking:
/// - For `espeak`: presence of the bundled `.so` and `assets/espeak-ng-data/`.
/// - For `rhvoice`: presence of the downloaded `rhvoice-kk-aigul` pack
///   directory and its `.so` binary.
class KkTtsEngineCapability {
  final KkTtsEngine engine;

  /// True if the engine is available *right now* (libs loaded, voice data
  /// present, no fatal load error). The resolver in `TtsService` uses this
  /// as the gate — engines reporting `false` are skipped.
  final bool available;

  /// Optional version string. Mostly for logs / about screen.
  final String version;

  /// Optional supported languages. Native side returns at least `'kk'` for
  /// engines that include the Kazakh voice data.
  final List<String> supportedLanguages;

  /// Optional reason describing why the engine is unavailable (used for
  /// `FieldLogger` diagnostics). Empty when `available == true`.
  final String unavailableReason;

  const KkTtsEngineCapability({
    required this.engine,
    required this.available,
    this.version = '',
    this.supportedLanguages = const [],
    this.unavailableReason = '',
  });

  Map<String, dynamic> toJson() => {
        'engine': engine.id,
        'available': available,
        'version': version,
        'supportedLanguages': supportedLanguages,
        if (unavailableReason.isNotEmpty)
          'unavailableReason': unavailableReason,
      };

  factory KkTtsEngineCapability.fromMap(Map<dynamic, dynamic> map) {
    final id = map['engine']?.toString();
    final engine = kkTtsEngineFromId(id);
    final langs = map['supportedLanguages'];
    return KkTtsEngineCapability(
      engine: engine ?? KkTtsEngine.russianFallback,
      available: map['available'] == true,
      version: map['version']?.toString() ?? '',
      supportedLanguages: langs is List
          ? langs.map((e) => e.toString()).toList(growable: false)
          : const [],
      unavailableReason: map['unavailableReason']?.toString() ?? '',
    );
  }
}

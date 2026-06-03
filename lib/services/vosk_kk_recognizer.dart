import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vosk_flutter_2/vosk_flutter_2.dart';

import 'field_logger.dart';

/// Offline Kazakh speech recognizer backed by a local Vosk acoustic model.
///
/// This wrapper isolates `voice_command_service.dart` from the
/// `vosk_flutter_2` API so the routing layer can swap implementations
/// (e.g. test fakes, future Whisper.cpp) without churn.
///
/// Lifecycle contract:
/// 1. `init(modelDir)` — load model + recognizer. Memory-heavy (~150 MB
///    resident). Call lazily on first kk listen, not at app start.
/// 2. `setGrammar(phrases)` — optional. Pass a closed-set list of allowed
///    utterances to dramatically boost accuracy for the fixed command
///    vocabulary. Pass `null` to enable full LM (open-vocabulary) mode.
/// 3. `start()` / `stop()` — mic streaming. Mic permission must already be
///    granted; `requestPermission()` is provided for convenience.
/// 4. `dispose()` — release all native resources. Idempotent.
///
/// Threading: all `vosk_flutter_2` calls are awaited Futures dispatched to
/// platform code. The Flutter UI isolate is never blocked for more than a
/// model-handle creation (~50 ms after the model is on disk).
class VoskKkRecognizer {
  VoskKkRecognizer._();

  static final VoskKkRecognizer instance = VoskKkRecognizer._();

  /// Vosk-kk small model expects 16 kHz mono PCM input.
  static const int sampleRateHz = 16000;

  /// Special sentinel grammar token that lets Vosk emit "[unk]" when the
  /// user says something outside the closed-set. Keeping this in the
  /// grammar is what makes constrained-vocabulary mode robust to
  /// out-of-grammar speech (otherwise Vosk would force-fit the audio).
  static const String unknownToken = '[unk]';

  VoskFlutterPlugin? _plugin;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speech;

  StreamSubscription<String>? _resultSub;
  StreamSubscription<String>? _partialSub;
  StreamSubscription<dynamic>? _errorSub;

  String? _modelDir;
  List<String>? _grammar;

  bool _initStarted = false;
  Completer<bool>? _initCompleter;
  bool _ready = false;
  bool _listening = false;
  bool _disposed = false;

  /// Latest final-result text (post-JSON-decode). Set just before
  /// [onResult] fires.
  String _lastFinalText = '';

  /// Final-result callback. Receives the plain recognized utterance
  /// (already JSON-decoded), e.g. `"айналада не бар"`. Empty string
  /// indicates silence / unintelligible audio — caller should treat it as
  /// `VoiceCommand.unknown`.
  void Function(String text)? onResult;

  /// Optional partial-result callback. Useful for UI hints; do NOT route
  /// partials to command handlers (they may flicker mid-utterance).
  void Function(String text)? onPartial;

  /// Error callback. Receives a short error key (e.g. `"model_load_failed"`,
  /// `"mic_permission_denied"`, `"start_failed"`).
  void Function(String error)? onError;

  bool get isReady => _ready;
  bool get isListening => _listening;
  String? get modelDir => _modelDir;
  String get lastFinalText => _lastFinalText;

  /// Request microphone permission. Mirrors `VoiceCommandService` so
  /// callers can do the same flow regardless of which backend is active.
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Load the model from [modelDir] and prepare a recognizer.
  ///
  /// [modelDir] must be the absolute path to an extracted Vosk model
  /// directory (the one containing `am/`, `conf/`, `graph/`, etc.).
  ///
  /// Returns true on success. Re-entrant: if already initializing for the
  /// same dir, returns the in-flight future.
  Future<bool> init(String modelDir, {List<String>? grammar}) async {
    if (_disposed) return false;
    if (_ready && _modelDir == modelDir && listEquals(_grammar, grammar)) {
      return true;
    }
    if (_initStarted && _initCompleter != null && _modelDir == modelDir) {
      return _initCompleter!.future;
    }

    _initStarted = true;
    _initCompleter = Completer<bool>();
    final completer = _initCompleter!;

    try {
      
      if (_ready) {
        await _teardownNative();
      }

      final dir = Directory(modelDir);
      if (!await dir.exists()) {
        debugPrint('VoskKkRecognizer: model dir missing: $modelDir');
        onError?.call('model_dir_missing');
        _initStarted = false;
        if (!completer.isCompleted) completer.complete(false);
        return false;
      }

      _plugin = VoskFlutterPlugin.instance();
      _model = await _plugin!.createModel(modelDir);
      _recognizer = await _plugin!.createRecognizer(
        model: _model!,
        sampleRate: sampleRateHz,
        grammar: grammar,
      );
      _speech = await _plugin!.initSpeechService(_recognizer!);

      _attachStreams();

      _modelDir = modelDir;
      _grammar = grammar == null ? null : List<String>.unmodifiable(grammar);
      _ready = true;
      _initStarted = false;

      FieldLogger.instance.log('vosk_kk_model_loaded', {
        'dir': modelDir,
        'grammarSize': grammar?.length ?? 0,
      });
      debugPrint(
        'VoskKkRecognizer: model loaded ($modelDir), '
        'grammar=${grammar?.length ?? "open"}',
      );
      if (!completer.isCompleted) completer.complete(true);
      return true;
    } catch (e, st) {
      debugPrint('VoskKkRecognizer.init failed: $e\n$st');
      onError?.call('model_load_failed');
      FieldLogger.instance.log('vosk_kk_model_load_failed', {
        'error': e.toString(),
      });
      _initStarted = false;
      _ready = false;
      await _teardownNative();
      if (!completer.isCompleted) completer.complete(false);
      return false;
    }
  }

  /// Replace the active grammar without reloading the model. Cheaper than
  /// full re-init when only the closed-vocabulary set changes (e.g.
  /// switching modes).
  Future<bool> setGrammar(List<String>? grammar) async {
    if (_disposed) return false;
    if (!_ready || _model == null || _plugin == null) return false;
    if (listEquals(_grammar, grammar)) return true;

    final wasListening = _listening;
    if (wasListening) await stop();

    try {
      
      
      await _detachStreams();
      try {
        await _speech?.dispose();
      } catch (_) {}
      _speech = null;
      _recognizer = null;

      _recognizer = await _plugin!.createRecognizer(
        model: _model!,
        sampleRate: sampleRateHz,
        grammar: grammar,
      );
      _speech = await _plugin!.initSpeechService(_recognizer!);
      _attachStreams();

      _grammar = grammar == null ? null : List<String>.unmodifiable(grammar);

      if (wasListening) await start();
      return true;
    } catch (e) {
      debugPrint('VoskKkRecognizer.setGrammar failed: $e');
      onError?.call('grammar_swap_failed');
      return false;
    }
  }

  /// Begin streaming mic audio into the recognizer. No-op if already
  /// listening or not initialized.
  Future<bool> start() async {
    if (_disposed || !_ready || _speech == null) return false;
    if (_listening) return true;
    final hasPerm = await Permission.microphone.isGranted;
    if (!hasPerm) {
      final granted = await requestPermission();
      if (!granted) {
        onError?.call('mic_permission_denied');
        return false;
      }
    }
    try {
      await _speech!.start();
      _listening = true;
      return true;
    } catch (e) {
      debugPrint('VoskKkRecognizer.start failed: $e');
      onError?.call('start_failed');
      _listening = false;
      return false;
    }
  }

  /// Stop streaming. Final pending result will fire via [onResult] if the
  /// underlying recognizer emits one during teardown.
  Future<void> stop() async {
    if (!_listening || _speech == null) {
      _listening = false;
      return;
    }
    try {
      await _speech!.stop();
    } catch (e) {
      debugPrint('VoskKkRecognizer.stop failed: $e');
    } finally {
      _listening = false;
    }
  }

  /// Discard partial state (e.g. between commands) without tearing down
  /// the native model.
  Future<void> reset() async {
    if (_disposed || _recognizer == null) return;
    try {
      await _recognizer!.setMaxAlternatives(0);
      
      
    } catch (_) {}
  }

  /// Release all native resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await stop();
    await _teardownNative();
  }

  
  void _attachStreams() {
    if (_speech == null) return;
    _resultSub = _speech!.onResult().listen(
      (raw) {
        final text = _extractTextField(raw, key: 'text');
        _lastFinalText = text;
        onResult?.call(text);
      },
      onError: (e) {
        debugPrint('VoskKkRecognizer: onResult stream error: $e');
        onError?.call('result_stream_error');
      },
    );
    _partialSub = _speech!.onPartial().listen(
      (raw) {
        final text = _extractTextField(raw, key: 'partial');
        if (text.isNotEmpty) onPartial?.call(text);
      },
      onError: (e) {
        debugPrint('VoskKkRecognizer: onPartial stream error: $e');
      },
    );
  }

  Future<void> _detachStreams() async {
    await _resultSub?.cancel();
    await _partialSub?.cancel();
    await _errorSub?.cancel();
    _resultSub = null;
    _partialSub = null;
    _errorSub = null;
  }

  Future<void> _teardownNative() async {
    await _detachStreams();
    try {
      await _speech?.dispose();
    } catch (_) {}
    _speech = null;
    _recognizer = null;
    try {
      _model?.dispose();
    } catch (_) {}
    _model = null;
    _ready = false;
  }

  /// Vosk emits results as JSON strings (`{"text":"..."}` or
  /// `{"partial":"..."}`). Older builds occasionally emit the bare string;
  /// be defensive.
  static String _extractTextField(String raw, {required String key}) {
    if (raw.isEmpty) return '';
    final trimmed = raw.trim();
    if (!trimmed.startsWith('{')) return trimmed;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final v = decoded[key];
        if (v is String) return v.trim();
      }
    } catch (_) {}
    return '';
  }

  
  @visibleForTesting
  void debugInjectFinalResult(String raw) {
    final text = _extractTextField(raw, key: 'text');
    _lastFinalText = text;
    onResult?.call(text);
  }

  @visibleForTesting
  void debugInjectPartial(String raw) {
    final text = _extractTextField(raw, key: 'partial');
    
    
    if (text.isNotEmpty) onPartial?.call(text);
  }

  @visibleForTesting
  static String testExtractText(String raw, String key) =>
      _extractTextField(raw, key: key);
}

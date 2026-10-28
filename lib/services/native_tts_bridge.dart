import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/language_pack.dart';
import '../models/tts_engine.dart';
import 'field_logger.dart';
import 'language_pack_manager.dart';

/// Dart-side bridge to the `bagdar/native_tts` Kotlin plugin.
///
/// Phase 2 of the Kazakh language stack rework uses this bridge to drive
/// the RHVoice and espeak-ng engines from the safety-critical
/// `TtsService` priority queue without disturbing the existing
/// `flutter_tts` integration for ru/en (and for the Kazakh
/// `system`/`russianFallback` paths).
///
/// The bridge is intentionally permissive: when the native side cannot
/// load an engine (lib missing, voice data missing, etc.) it reports the
/// engine as `available = false` and `TtsService._resolveKkEngine()`
/// transparently falls back down the priority chain documented in
/// `lib/models/tts_engine.dart`. This guarantees the app remains
/// functional even before the espeak-ng `.so` and the RHVoice pack ship.
///
/// All speech rendering is fire-and-forget: callers post text via
/// [speak] and listen for [onSpeechStart] / [onSpeechComplete] /
/// [onSpeechError] to drive the existing `TtsService` queue pump. The
/// native side translates PCM into an `AudioTrack` with
/// `USAGE_ASSISTANCE_ACCESSIBILITY` so the `audio_session` configuration
/// established in `TtsService.init` (duck-others + assistance-accessibility
/// attributes) is honored exactly the way `flutter_tts` honors it.
class NativeTtsBridge {
  NativeTtsBridge._({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _method = methodChannel ?? const MethodChannel(_methodChannelName),
      _events = eventChannel ?? const EventChannel(_eventChannelName);

  static const String _methodChannelName = 'bagdar/native_tts';
  static const String _eventChannelName = 'bagdar/native_tts_events';

  /// Folder name inside `LanguagePackManager.packsDir` where the downloaded
  /// RHVoice pack is extracted (matches `LanguagePackIds.rhvoiceKkAigul`).
  static const String rhvoiceKkPackId = LanguagePackIds.rhvoiceKkAigul;

  static NativeTtsBridge _instance = NativeTtsBridge._();

  static NativeTtsBridge get instance => _instance;

  /// Test hook — swap the singleton out with one wired to mock channels.
  @visibleForTesting
  static void debugReplaceInstance(NativeTtsBridge bridge) {
    _instance = bridge;
  }

  /// Reset the singleton back to a freshly-constructed instance bound to
  /// the real platform channels. Used by tests that swapped a mock in.
  @visibleForTesting
  static void debugResetInstance() {
    _instance = NativeTtsBridge._();
  }

  /// Construct a bridge wired to caller-supplied channels. Reserved for
  /// tests; the production code always uses [instance].
  @visibleForTesting
  factory NativeTtsBridge.forTesting({
    required MethodChannel methodChannel,
    EventChannel? eventChannel,
  }) => NativeTtsBridge._(
    methodChannel: methodChannel,
    eventChannel: eventChannel,
  );

  final MethodChannel _method;
  final EventChannel _events;

  StreamSubscription<dynamic>? _eventSub;

  bool _initStarted = false;
  bool _initialized = false;
  bool _eventsAttached = false;

  /// Cached engine capability map. Refreshed on every [init] / [refresh].
  Map<KkTtsEngine, KkTtsEngineCapability> _capabilities = const {};

  /// Engine currently selected on the native side (mirrors what
  /// `TtsService` picked via [setEngine]). Useful for diagnostics and the
  /// `tts_kk_engine_used` field-log event.
  KkTtsEngine? _activeEngine;

  /// Fired when the native side has started rendering the most recent
  /// `speak()` call. `TtsService` uses this to arm its stall watchdog.
  void Function()? onSpeechStart;

  /// Fired when the native side has finished rendering and the
  /// AudioTrack drained.
  void Function()? onSpeechComplete;

  /// Fired when the native side encountered a non-recoverable error
  /// rendering the utterance (engine load failure, AudioTrack init
  /// failure, etc.). The `reason` string is short and stable for logging.
  void Function(String reason)? onSpeechError;
  void Function(String type, String requestId, String? reason)? onSpeechEvent;
  static int _requestSequence = 0;

  /// True once [init] has completed at least once (regardless of which
  /// engines are available).
  bool get isInitialized => _initialized;

  /// Currently active native engine, or `null` if none has been selected.
  KkTtsEngine? get activeEngine => _activeEngine;

  /// Latest capability map keyed by engine.
  Map<KkTtsEngine, KkTtsEngineCapability> get capabilities =>
      Map.unmodifiable(_capabilities);

  /// Best-effort initialization. Probes the native side for available
  /// engines, attaches the event-channel listener, and primes
  /// [_capabilities].
  ///
  /// Re-entrant: subsequent calls return the cached state. Use [refresh]
  /// to force a re-probe (e.g. after a new RHVoice pack is installed).
  Future<void> init() async {
    if (_initialized || _initStarted) return;
    _initStarted = true;
    try {
      await _attachEvents();
      await _probeCapabilities();
      _initialized = true;
    } catch (e, st) {
      debugPrint('NativeTtsBridge.init failed: $e\n$st');
      _capabilities = const {};
    } finally {
      _initStarted = false;
    }
  }

  /// Force a re-probe of engine availability. Call after installing a
  /// language pack (e.g. RHVoice) so the bridge picks up the new lib
  /// without an app restart.
  Future<void> refresh({String? rhvoicePackPath}) async {
    await _probeCapabilities(rhvoicePackPath: rhvoicePackPath);
  }

  /// True when an engine is currently usable. The bridge's `hasXxxKk`
  /// helpers prefer this lookup over a blind invocation so we never spin
  /// up the engine just to check availability.
  bool hasEngine(KkTtsEngine engine) {
    final cap = _capabilities[engine];
    return cap != null && cap.available;
  }

  bool hasEspeakKk() => hasEngine(KkTtsEngine.espeak);

  bool hasRhvoiceKk() => hasEngine(KkTtsEngine.rhvoice);

  KkTtsEngineCapability? capabilityFor(KkTtsEngine engine) =>
      _capabilities[engine];

  /// Activate [engine] on the native side. Required before [speak] for
  /// `rhvoice` / `espeak`. Idempotent.
  Future<bool> setEngine(KkTtsEngine engine) async {
    if (!engine.usesNativeBridge) {
      _activeEngine = null;
      return false;
    }
    final cap = _capabilities[engine];
    if (cap == null || !cap.available) {
      FieldLogger.instance.log('tts_kk_engine_unavailable', {
        'engine': engine.id,
        'reason': cap?.unavailableReason ?? 'not_probed',
      });
      return false;
    }
    try {
      final extra = engine == KkTtsEngine.rhvoice
          ? await _rhvoicePackPath()
          : '';
      final result = await _method.invokeMethod<bool>('setEngine', {
        'engine': engine.id,
        if (extra.isNotEmpty) 'packPath': extra,
      });
      final ok = result == true;
      if (ok) {
        _activeEngine = engine;
        FieldLogger.instance.log('tts_kk_engine_used', {
          'engine': engine.id,
          'version': cap.version,
        });
      }
      return ok;
    } on PlatformException catch (e) {
      debugPrint('NativeTtsBridge.setEngine($engine) failed: $e');
      FieldLogger.instance.log('tts_kk_engine_set_failed', {
        'engine': engine.id,
        'error': e.code,
      });
      return false;
    } catch (e) {
      debugPrint('NativeTtsBridge.setEngine($engine) failed: $e');
      return false;
    }
  }

  /// Synthesize and play [text] via the currently active native engine.
  ///
  /// This call returns once the native side has accepted the request and
  /// queued playback; *not* when playback finishes. Listen for
  /// [onSpeechComplete] / [onSpeechError] for the lifecycle.
  ///
  /// Priority is metadata; ordering/preemption belongs to TtsService. Native
  /// playback is serialized. Cancellation latency requires device measurement.
  Future<bool> speak({
    required String text,
    required String priority,
    String? requestId,
    double rate = 0.5,
    double volume = 1.0,
    double pitch = 1.0,
    double pan = 0.0,
  }) async {
    if (_activeEngine == null || !_activeEngine!.usesNativeBridge) {
      return false;
    }
    final id = requestId ?? 'kk-bridge-${++_requestSequence}';
    try {
      final result = await _method.invokeMethod<bool>('speak', {
        'text': text,
        'priority': priority,
        'requestId': id,
        'rate': rate,
        'volume': volume,
        'pitch': pitch,
        'pan': pan,
      });
      return result == true;
    } on PlatformException catch (e) {
      debugPrint('NativeTtsBridge.speak failed: $e');
      onSpeechEvent?.call('error', id, e.code);
      onSpeechError?.call(e.code);
      return false;
    } catch (e) {
      debugPrint('NativeTtsBridge.speak failed: $e');
      onSpeechEvent?.call('error', id, 'exception');
      onSpeechError?.call('exception');
      return false;
    }
  }

  /// Request cancellation of the current utterance and pending PCM. A method
  /// reply does not establish physical cancellation latency.
  Future<void> stop() async {
    if (_activeEngine == null && !_initialized) return;
    try {
      await _method.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      debugPrint('NativeTtsBridge.stop failed: $e');
    } catch (e) {
      debugPrint('NativeTtsBridge.stop failed: $e');
    }
  }

  Future<void> pause() async {
    if (_activeEngine == null) return;
    try {
      await _method.invokeMethod<void>('pause');
    } catch (e) {
      debugPrint('NativeTtsBridge.pause failed: $e');
    }
  }

  Future<void> resume() async {
    if (_activeEngine == null) return;
    try {
      await _method.invokeMethod<void>('resume');
    } catch (e) {
      debugPrint('NativeTtsBridge.resume failed: $e');
    }
  }

  /// Detach the event subscription and clear callbacks. Intended for
  /// tests / app teardown; production code keeps the singleton alive for
  /// the process lifetime.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    _eventsAttached = false;
    onSpeechStart = null;
    onSpeechComplete = null;
    onSpeechError = null;
    onSpeechEvent = null;
  }

  Future<void> _attachEvents() async {
    if (_eventsAttached) return;
    try {
      _eventSub = _events.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (Object e) {
          debugPrint('NativeTtsBridge event stream error: $e');
        },
      );
      _eventsAttached = true;
    } catch (e) {
      debugPrint('NativeTtsBridge: events unavailable: $e');
    }
  }

  void _handleEvent(dynamic raw) {
    if (raw is! Map) return;
    final type = raw['type']?.toString();
    final id = raw['requestId'];
    if (id is String && id.isNotEmpty && type != null) {
      onSpeechEvent?.call(type, id, raw['reason']?.toString());
    }
    switch (type) {
      case 'start':
        onSpeechStart?.call();
        break;
      case 'complete':
        onSpeechComplete?.call();
        break;
      case 'error':
        final reason = raw['reason']?.toString() ?? 'unknown';
        onSpeechError?.call(reason);
        break;
      default:
        break;
    }
  }

  Future<void> _probeCapabilities({String? rhvoicePackPath}) async {
    try {
      final rhvocPath = rhvoicePackPath ?? await _rhvoicePackPath();
      final raw = await _method.invokeMethod<dynamic>('availableEngines', {
        if (rhvocPath.isNotEmpty) 'rhvoicePackPath': rhvocPath,
      });
      if (raw is List) {
        final out = <KkTtsEngine, KkTtsEngineCapability>{};
        for (final entry in raw) {
          if (entry is Map) {
            final cap = KkTtsEngineCapability.fromMap(entry);
            out[cap.engine] = cap;
          }
        }
        _capabilities = out;
        return;
      }
      _capabilities = const {};
    } on MissingPluginException {
      _capabilities = const {};
    } on PlatformException catch (e) {
      debugPrint('NativeTtsBridge.availableEngines failed: $e');
      _capabilities = const {};
    } catch (e) {
      debugPrint('NativeTtsBridge.availableEngines failed: $e');
      _capabilities = const {};
    }
  }

  Future<String> _rhvoicePackPath() async {
    try {
      final pm = LanguagePackManager.instance;
      if (!pm.isReady) return '';
      if (!pm.isInstalled(rhvoiceKkPackId)) return '';
      return pm.pathFor(rhvoiceKkPackId);
    } catch (_) {
      return '';
    }
  }

  /// Inject a capability map directly. Used by tests that want to drive
  /// `TtsService._resolveKkEngine()` through specific scenarios without a
  /// real native bridge.
  @visibleForTesting
  void debugSetCapabilities(Map<KkTtsEngine, KkTtsEngineCapability> caps) {
    _capabilities = Map.unmodifiable(caps);
    _initialized = true;
  }

  @visibleForTesting
  void debugSetActiveEngine(KkTtsEngine? engine) {
    _activeEngine = engine;
  }

  /// Fire a synthetic lifecycle event as if it had come from the native
  /// side. Drives `TtsService` queue-pump unit tests.
  @visibleForTesting
  void debugFireEvent(Map<String, Object?> event) => _handleEvent(event);
}

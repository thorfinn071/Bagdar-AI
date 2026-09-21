import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import '../../models/constants.dart'
    show kTtsStallTimeout, kHapticTtsStallPattern, kHapticTtsStallIntensities;
import '../../models/speech_job.dart';
import '../../models/strings.dart';
import '../../models/tts_engine.dart';
import '../safety/alerts/feedback_command.dart';
import '../safety/planning/safety_action.dart';
import 'haptic_service.dart';
import 'field_logger.dart';
import 'native_tts_bridge.dart';
import 'settings_service.dart';

class TtsService {
  static const Duration _kCriticalStaleAfter = Duration(seconds: 4);
  static const int _kMaxCriticalQueueLength = 4;

  FlutterTts? _ttsImpl;
  FlutterTts get _tts => _ttsImpl ??= FlutterTts();
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  bool _ready = false;
  bool _speaking = false;
  bool get speaking => _speaking;
  bool get isReady => _ready;
  bool _languageAvailable = true;
  bool _usingEnglishFallback = false;
  bool _testMode = false;
  String _requestedLang = 'ru-RU';
  final List<SpeechJob> _queue = [];

  KkTtsEngine? _activeKkEngine;
  bool _bridgeListenersAttached = false;

  bool? _kkSystemTtsAvailableOverride;

  bool _initStarted = false;
  Completer<void>? _initCompleter;

  bool _currentIsCritical = false;
  DateTime _currentSpeakStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSpeechEndedAt = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _currentSpeechCompleter;

  String? _currentText;
  SpeechPriority? _currentPriority;

  static final TtsService _instance = TtsService._();
  static TtsService get instance => _instance;

  TtsService._();

  @Deprecated('Use TtsService.instance')
  factory TtsService() => _instance;

  @visibleForTesting
  TtsService.forTesting() {
    _ready = true;
    _testMode = true;
  }

  @visibleForTesting
  List<SpeechJob> get queueSnapshot => List.unmodifiable(_queue);

  @visibleForTesting
  void pruneStaleCriticalsForTesting(DateTime now, {Duration? maxAge}) =>
      _pruneStaleCriticals(now, maxAge: maxAge);

  /// Safety audit 2026-06 test hook: puts the *singleton* [instance] into the
  /// same ready/test-mode state as [TtsService.forTesting]. Production code
  /// (e.g. CameraViewModel) always wires to [instance], which is never ready
  /// in a unit-test process (no real platform channel), so [say] would
  /// otherwise no-op before ever reaching [queueSnapshot]. Does not touch any
  /// platform channel.
  @visibleForTesting
  void debugForceTestReady() {
    _ready = true;
    _testMode = true;
  }

  void _pruneStaleCriticals(DateTime now, {Duration? maxAge}) {
    if (maxAge == null) return;
    _queue.removeWhere(
      (j) =>
          j.priority == SpeechPriority.critical &&
          now.difference(j.enqueuedAt) > maxAge,
    );
  }

  void _purgeExpiredJobs(DateTime now) {
    final expired = _queue
        .where((job) => job.isExpiredAt(now))
        .toList(growable: false);
    _queue.removeWhere((job) => job.isExpiredAt(now));
    for (final job in expired) {
      FieldLogger.instance.log('tts_queue_drop', {
        'reason': 'job_ttl_expired',
        'action_id': job.actionId,
        'hazard_id': job.hazardId,
        'priority': job.priority.name,
      });
    }
  }

  void Function()? onAudioRouteInterrupted;
  void Function()? onAudioRouteResumed;
  void Function()? onTtsStall;

  void Function()? onTtsUnavailable;

  DateTime _lastAudioRouteAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _stallTimer;

  bool get languageAvailable => _languageAvailable;
  bool get usingEnglishFallback => _usingEnglishFallback;

  /// Currently active Kazakh TTS engine, or `null` when the requested
  /// language is not Kazakh (or [_resolveKkEngine] has not run yet).
  KkTtsEngine? get activeKkEngine => _activeKkEngine;

  /// True when the active Kazakh engine routes through the native bridge
  /// instead of `flutter_tts`. Used by [_pump], [stop], and
  /// [_interruptAndSpeak] to dispatch correctly.
  bool get _useNativeBackend =>
      _activeKkEngine != null && _activeKkEngine!.usesNativeBridge;

  String _lastText = '';
  int? _lastTrackId;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime get lastSpokenAt => _lastTime;

  double _currentRate = 0.50;
  double _userRateMultiplier = 1.0;
  double _userVolume = 1.0;

  bool _reverseVehicleSuspected = false;
  set reverseVehicleSuspected(bool v) => _reverseVehicleSuspected = v;

  Future<void> setUserRate(double multiplier) async {
    final clamped = multiplier.clamp(0.5, 2.0);
    if ((clamped - _userRateMultiplier).abs() < 0.01) return;
    _userRateMultiplier = clamped;

    _currentRate = -1;
  }

  Future<void> setUserVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0);
    if ((clamped - _userVolume).abs() < 0.01) return;
    _userVolume = clamped;
    if (_ready && !_testMode) {
      try {
        await _tts.setVolume(clamped);
      } catch (_) {}
    }
  }

  static const double _rateCritical = 0.65;
  static const double _rateWarning = 0.50;
  static const double _rateInfo = 0.45;

  static double _rateFor(SpeechPriority p) {
    switch (p) {
      case SpeechPriority.critical:
        return _rateCritical;
      case SpeechPriority.warning:
        return _rateWarning;
      case SpeechPriority.info:
        return _rateInfo;
    }
  }

  Future<void> init() async {
    if (_ready) return;
    if (_initStarted && _initCompleter != null) {
      return _initCompleter!.future;
    }
    _initStarted = true;
    _initCompleter = Completer<void>();
    try {
      _session = await AudioSession.instance;
      await _session?.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: AndroidAudioAttributes(
            usage: AndroidAudioUsage.assistanceAccessibility,
            contentType: AndroidAudioContentType.speech,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
          androidWillPauseWhenDucked: true,
        ),
      );

      await _interruptionSub?.cancel();
      await _noisySub?.cancel();
      _interruptionSub = _session?.interruptionEventStream.listen((event) {
        if (event.begin) {
          _notifyAudioRouteInterrupted();
        } else {
          _recoverFromInterruption();
        }
      });
      _noisySub = _session?.becomingNoisyEventStream.listen((_) {
        _notifyAudioRouteInterrupted();
      });

      _requestedLang = 'ru-RU';
      await _applyLanguage(_requestedLang);
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(_userVolume);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(() {
        _speaking = true;
        _currentSpeakStartedAt = DateTime.now();

        _armStallTimer(_currentText, _currentPriority);
      });
      _tts.setCompletionHandler(() {
        _speaking = false;
        _currentIsCritical = false;
        _lastSpeechEndedAt = DateTime.now();
        _disarmStallTimer();
        _completeCurrentSpeech();
        _pump();
        if (_queue.isEmpty) _session?.setActive(false);
      });
      _tts.setErrorHandler((msg) {
        debugPrint('TtsService: engine error: $msg');
        _speaking = false;
        _currentIsCritical = false;
        _lastSpeechEndedAt = DateTime.now();
        _disarmStallTimer();
        _completeCurrentSpeech();
        _pump();
        if (_queue.isEmpty) _session?.setActive(false);
      });

      _ready = true;

      try {
        await _tts.setVolume(0.0);
        unawaited(_tts.speak('.'));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _tts.stop();
        _speaking = false;
        await _tts.setVolume(_userVolume);
      } catch (_) {}
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }
    } catch (_) {
      _ready = false;
      if (!(_initCompleter?.isCompleted ?? true)) {
        _initCompleter!.complete();
      }
    }
  }

  void _completeCurrentSpeech() {
    final c = _currentSpeechCompleter;
    _currentSpeechCompleter = null;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> awaitCurrentSpeech() async {
    if (_testMode) return;
    if (!_speaking && _queue.isEmpty) return;
    _currentSpeechCompleter ??= Completer<void>();
    await _currentSpeechCompleter!.future;
  }

  /// Wait until the TTS queue is completely drained and no speech is
  /// active. Unlike [awaitCurrentSpeech] which resolves after a single
  /// utterance, this loops until the entire queue is empty.
  Future<void> awaitIdle() async {
    if (_testMode) return;
    while (_speaking || _queue.isNotEmpty) {
      _currentSpeechCompleter ??= Completer<void>();
      await _currentSpeechCompleter!.future;
    }
  }

  Future<void> setLanguage(String bcp47Tag) async {
    await stop();
    _requestedLang = bcp47Tag;
    _usingEnglishFallback = false;
    await _applyLanguage(bcp47Tag);
  }

  void Function()? onKazakhVoiceMissing;

  /// Fired whenever [_resolveKkEngine] commits a new Kazakh engine.
  /// Used by the UI / FieldLogger to surface engine changes (e.g. announce
  /// "using RHVoice for Kazakh") without TtsService itself having to
  /// barge-speak from inside `_applyLanguage`.
  void Function(KkTtsEngine engine)? onKazakhEngineResolved;

  Future<void> preClaimAudioFocus() async {
    if (!_ready) return;
    try {
      await _session?.setActive(true);
    } catch (_) {}
  }

  /// Enumerate available TTS voices. Each voice is a map with at least
  /// 'name' and 'locale' keys. Returns an empty list on failure.
  Future<List<Map<String, String>>> getAvailableVoices() async {
    if (_testMode) return [];
    try {
      final raw = await _tts.getVoices;
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((m) => m.map((k, v) => MapEntry(k.toString(), v.toString())))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  /// Select a specific TTS voice by name and locale.
  Future<void> setVoice(Map<String, String> voice) async {
    if (_testMode) return;
    try {
      await _tts.setVoice(voice);
    } catch (_) {}
  }

  /// Auto-select the highest-quality voice for [bcp47Tag]. Prefers voices
  /// whose name contains quality indicators ('enhanced', 'hq', 'network')
  /// and avoids low-quality markers ('legacy', 'compact').
  Future<void> _selectBestVoice(String bcp47Tag) async {
    if (_testMode) return;
    try {
      final voices = await getAvailableVoices();
      if (voices.isEmpty) return;

      final primary = bcp47Tag.split('-').first.toLowerCase();
      final matching = voices.where((v) {
        final locale = (v['locale'] ?? '').toLowerCase();
        return locale.startsWith(primary);
      }).toList();

      if (matching.isEmpty) return;

      // Score each voice: prefer quality indicators, penalize low-quality ones.
      Map<String, String>? best;
      int bestScore = -999;
      for (final v in matching) {
        final name = (v['name'] ?? '').toLowerCase();
        final voiceLocale = (v['locale'] ?? '').toLowerCase();
        int score = 0;
        if (name.contains('enhanced')) score += 3;
        if (name.contains('hq') || name.contains('high')) score += 2;
        if (name.contains('network')) score += 2;
        if (name.contains('premium')) score += 3;
        if (name.contains('local')) score += 1;
        if (name.contains('legacy')) score -= 3;
        if (name.contains('compact')) score -= 2;

        // For English: strongly penalize Indian accent, prefer US/GB/AU
        if (primary == 'en') {
          if (voiceLocale.contains('en-in') ||
              voiceLocale.contains('en_in') ||
              name.contains('india') ||
              name.contains('hindi')) {
            score -= 5;
          }
          if (voiceLocale.contains('en-us') || voiceLocale.contains('en_us')) {
            score += 2;
          } else if (voiceLocale.contains('en-gb') ||
              voiceLocale.contains('en_gb') ||
              voiceLocale.contains('en-au') ||
              voiceLocale.contains('en_au')) {
            score += 1;
          }
        }

        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }

      if (best != null) {
        await _tts.setVoice({
          'name': best['name'] ?? '',
          'locale': best['locale'] ?? '',
        });
        debugPrint(
          'TtsService: selected voice "${best['name']}" '
          'for $bcp47Tag (score=$bestScore)',
        );
        FieldLogger.instance.log('tts_voice_selected', {
          'voice': best['name'] ?? '',
          'locale': bcp47Tag,
          'score': bestScore,
        });
      }
    } catch (_) {}
  }

  Future<void> _applyLanguage(String bcp47Tag) async {
    if (bcp47Tag == 'kk-KZ') {
      await _resolveKkEngine();
      await _checkLanguageAvailability(bcp47Tag);
      return;
    }

    _activeKkEngine = null;

    try {
      await _tts.setLanguage(bcp47Tag);
    } catch (_) {}
    await _checkLanguageAvailability(bcp47Tag);
    await _selectBestVoice(bcp47Tag);

    if (!_languageAvailable && !_usingEnglishFallback) {
      try {
        await _tts.setLanguage('en-US');
        _usingEnglishFallback = true;
        AppStrings.setAlertLanguage(AppLanguage.en);
        debugPrint(
          'TtsService: fallback to en-US (requested $bcp47Tag unavailable)',
        );
      } catch (_) {}
    } else if (_languageAvailable) {
      AppStrings.setAlertLanguage(null);
    }
  }

  /// Phase 2 — resolve which Kazakh TTS engine should render `kk-KZ`
  /// speech, following the priority chain:
  ///
  ///   1. System TTS engine that natively supports kk-KZ.
  ///   2. Bagdar-bundled RHVoice (downloaded language pack).
  ///   3. Bagdar-bundled espeak-ng (always available once the .so ships).
  ///   4. Russian fallback (legacy behavior — read kk text with the
  ///      ru-RU voice).
  ///
  /// Steps 2/3 are only attempted when [Settings.enableKazakhStackV2] is
  /// true. The resolver is safe to call from any state and is the only
  /// path that mutates [_activeKkEngine].
  Future<KkTtsEngine> _resolveKkEngine() async {
    if (await _systemHasKkVoice()) {
      try {
        if (!_testMode) {
          await _tts.setLanguage('kk-KZ');
        }
      } catch (_) {
        try {
          if (!_testMode) await _tts.setLanguage('kk');
        } catch (_) {}
      }
      _languageAvailable = true;
      _activeKkEngine = KkTtsEngine.system;
      AppStrings.setAlertLanguage(null);
      FieldLogger.instance.log('tts_kk_engine_used', {'engine': 'system'});
      onKazakhEngineResolved?.call(KkTtsEngine.system);
      return KkTtsEngine.system;
    }

    if (_isKazakhStackV2Enabled()) {
      final engine = await _resolveNativeKkEngine();
      if (engine != null) {
        _activeKkEngine = engine;
        AppStrings.setAlertLanguage(null);
        _attachBridgeListeners();
        FieldLogger.instance.log('tts_kk_engine_used', {'engine': engine.id});
        onKazakhEngineResolved?.call(engine);
        return engine;
      }
    }

    debugPrint(
      'TtsService: no kk voice — falling back to ru-RU for Kazakh text',
    );
    if (!_testMode) {
      await _trySetLanguage('ru-RU');
    }
    AppStrings.setAlertLanguage(null);
    onKazakhVoiceMissing?.call();
    _activeKkEngine = KkTtsEngine.russianFallback;
    FieldLogger.instance.log('tts_kk_engine_used', {
      'engine': 'russianFallback',
    });
    onKazakhEngineResolved?.call(KkTtsEngine.russianFallback);
    return KkTtsEngine.russianFallback;
  }

  Future<bool> _systemHasKkVoice() async {
    if (_kkSystemTtsAvailableOverride != null) {
      return _kkSystemTtsAvailableOverride!;
    }
    if (_testMode) return false;
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        final set = langs.map((l) => l.toString().toLowerCase()).toSet();
        return set.contains('kk-kz') || set.any((l) => l.startsWith('kk'));
      }
    } catch (_) {}
    // Also check individual voices for kk support.
    try {
      final voices = await _tts.getVoices;
      if (voices is List) {
        for (final v in voices) {
          if (v is Map) {
            final locale = v['locale']?.toString().toLowerCase() ?? '';
            if (locale.startsWith('kk')) return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  Future<KkTtsEngine?> _resolveNativeKkEngine() async {
    final bridge = NativeTtsBridge.instance;
    if (!bridge.isInitialized) {
      try {
        await bridge.init();
      } catch (_) {}
    }

    Future<bool> activate(KkTtsEngine engine) async {
      if (_testMode) return true;
      return bridge.setEngine(engine);
    }

    if (bridge.hasRhvoiceKk() && await activate(KkTtsEngine.rhvoice)) {
      return KkTtsEngine.rhvoice;
    }
    if (bridge.hasEspeakKk() && await activate(KkTtsEngine.espeak)) {
      return KkTtsEngine.espeak;
    }
    return null;
  }

  bool _isKazakhStackV2Enabled() {
    try {
      return Settings.instance.enableKazakhStackV2;
    } catch (_) {
      return false;
    }
  }

  void _attachBridgeListeners() {
    if (_bridgeListenersAttached) return;
    final bridge = NativeTtsBridge.instance;
    bridge.onSpeechStart = _handleNativeSpeechStart;
    bridge.onSpeechComplete = _handleNativeSpeechComplete;
    bridge.onSpeechError = _handleNativeSpeechError;
    _bridgeListenersAttached = true;
  }

  void _handleNativeSpeechStart() {
    _speaking = true;
    _currentSpeakStartedAt = DateTime.now();
    _armStallTimer(_currentText, _currentPriority);
  }

  void _handleNativeSpeechComplete() {
    _speaking = false;
    _currentIsCritical = false;
    _lastSpeechEndedAt = DateTime.now();
    _disarmStallTimer();
    _completeCurrentSpeech();
    _pump();
    if (_queue.isEmpty) _session?.setActive(false);
  }

  void _handleNativeSpeechError(String reason) {
    debugPrint('TtsService: native bridge error: $reason');
    FieldLogger.instance.log('tts_kk_native_error', {'reason': reason});
    _speaking = false;
    _currentIsCritical = false;
    _lastSpeechEndedAt = DateTime.now();
    _disarmStallTimer();
    _completeCurrentSpeech();
    _pump();
    if (_queue.isEmpty) _session?.setActive(false);
  }

  Future<bool> _trySetLanguage(String tag) async {
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        final lower = tag.toLowerCase();
        final primary = lower.split('-').first;
        final set = langs.map((l) => l.toString().toLowerCase()).toSet();
        if (set.contains(lower) || set.any((l) => l.startsWith(primary))) {
          await _tts.setLanguage(tag);
          _languageAvailable = true;
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  void _notifyAudioRouteInterrupted() {
    final now = DateTime.now();
    if (now.difference(_lastAudioRouteAlertAt) < const Duration(seconds: 15)) {
      return;
    }
    _lastAudioRouteAlertAt = now;
    onAudioRouteInterrupted?.call();
  }

  void _recoverFromInterruption() {
    try {
      _session?.setActive(true);
    } catch (_) {}

    if (!_speaking && _queue.isNotEmpty) {
      _pump();
    }
    onAudioRouteResumed?.call();
  }

  void _armStallTimer([String? text, SpeechPriority? priority]) {
    _stallTimer?.cancel();
    final timeout = _computeStallTimeout(text: text, priority: priority);
    _stallTimer = Timer(timeout, () {
      if (!_speaking) return;
      debugPrint(
        'TtsService: stall detected (${timeout.inMilliseconds}ms) '
        '— resetting speaking flag',
      );
      _speaking = false;
      try {
        _tts.stop();
      } catch (_) {}
      onTtsStall?.call();
      if (_queue.isNotEmpty) _pump();
    });
  }

  Duration _computeStallTimeout({String? text, SpeechPriority? priority}) {
    if (text == null) return kTtsStallTimeout;

    if (priority == SpeechPriority.critical) return kTtsStallTimeout;

    final scaledMs = 4000 + text.length * 70;
    final cappedMs = scaledMs.clamp(kTtsStallTimeout.inMilliseconds, 30000);
    return Duration(milliseconds: cappedMs);
  }

  void _disarmStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  Future<void> _checkLanguageAvailability(String bcp47Tag) async {
    try {
      final langs = await _tts.getLanguages;
      if (langs is List) {
        final primary = bcp47Tag.split('-').first.toLowerCase();
        final set = langs.map((l) => l.toString().toLowerCase()).toSet();
        _languageAvailable =
            set.contains(bcp47Tag.toLowerCase()) ||
            set.any((l) => l.startsWith(primary));
      }
    } catch (_) {
      _languageAvailable = true;
    }
  }

  // Safety audit 2026-06 fix A-5: align with kCriticalRepeatCooldownSafety
  static const Duration _kCriticalDedupWindow = Duration(seconds: 2);
  static const Duration _kWarningDedupWindow = Duration(seconds: 5);
  static const Duration _kInfoDedupWindow = Duration(seconds: 2);

  final Map<String, DateTime> _lastSpokenByText = {};

  void say(
    String text,
    SpeechPriority priority, {
    double pan = 0.0,
    int? trackId,
    String? actionId,
    String? hazardId,
    DateTime? expiresAt,
    bool barge = false,
    bool skipHaptic = false,
  }) {
    final now = DateTime.now();
    if (expiresAt != null && now.isAfter(expiresAt)) {
      FieldLogger.instance.log('tts_queue_drop', {
        'reason': 'incoming_job_ttl_expired',
        'action_id': actionId,
        'hazard_id': hazardId,
        'priority': priority.name,
      });
      return;
    }
    if (!_ready) {
      if (priority == SpeechPriority.critical && text.isNotEmpty) {
        debugPrint(
          'TtsService: critical alert dropped because engine is not ready '
          '— firing fallback haptic + listener',
        );
        try {
          HapticService.vibrate(
            kHapticTtsStallPattern,
            intensities: kHapticTtsStallIntensities,
          );
        } catch (_) {}
        try {
          onTtsUnavailable?.call();
        } catch (_) {}
        FieldLogger.instance.log('tts_unavailable_critical', {
          'text': text,
          'priority': priority.name,
        });
      }
      return;
    }
    if (text.isEmpty) return;
    _currentSpeechCompleter ??= Completer<void>();
    _purgeExpiredJobs(now);
    final rate = _rateFor(priority);

    final dedupWindow = switch (priority) {
      SpeechPriority.critical => _kCriticalDedupWindow,
      SpeechPriority.warning => _kWarningDedupWindow,
      SpeechPriority.info => _kInfoDedupWindow,
    };
    final lastSameTextAt = _lastSpokenByText[text];
    if (priority != SpeechPriority.critical &&
        lastSameTextAt != null &&
        now.difference(lastSameTextAt) < dedupWindow) {
      return;
    }

    if (priority != SpeechPriority.critical &&
        text == _lastText &&
        trackId == _lastTrackId &&
        now.difference(_lastTime) < const Duration(seconds: 2)) {
      return;
    }

    if (priority == SpeechPriority.critical) {
      _pruneStaleCriticals(now, maxAge: _kCriticalStaleAfter);
      _queue.removeWhere((j) => j.priority != SpeechPriority.critical);
      if (trackId != null || actionId != null || hazardId != null) {
        final replaced = _queue
            .where(
              (j) =>
                  j.priority == SpeechPriority.critical &&
                  ((trackId != null && j.trackId == trackId) ||
                      (actionId != null && j.actionId == actionId) ||
                      (hazardId != null && j.hazardId == hazardId)),
            )
            .toList(growable: false);
        _queue.removeWhere(
          (j) =>
              j.priority == SpeechPriority.critical &&
              ((trackId != null && j.trackId == trackId) ||
                  (actionId != null && j.actionId == actionId) ||
                  (hazardId != null && j.hazardId == hazardId)),
        );
        for (final job in replaced) {
          FieldLogger.instance.log('tts_queue_replace', {
            'reason': 'replace_critical_identity',
            'evicted_text': job.text,
            'track_id': trackId,
            'action_id': actionId,
            'hazard_id': hazardId,
            'incoming_text': text,
          });
        }
      }
      if (_queue.any(
        (j) =>
            j.text == text &&
            (trackId == null || j.trackId == null || j.trackId == trackId) &&
            (hazardId == null || j.hazardId == null || j.hazardId == hazardId),
      )) {
        _lastText = text;
        _lastTrackId = trackId;
        _lastTime = now;
        return;
      }
      while (_queue.length >= _kMaxCriticalQueueLength) {
        final evicted = _queue.removeAt(0);
        FieldLogger.instance.log('tts_queue_drop', {
          'reason': 'critical_queue_bounded_evict_oldest',
          'evicted_text': evicted.text,
          'evicted_track_id': evicted.trackId,
          'incoming_text': text,
          'incoming_track_id': trackId,
        });
      }
      _queue.add(
        SpeechJob(
          text,
          priority,
          pan: pan,
          rate: rate,
          trackId: trackId,
          actionId: actionId,
          hazardId: hazardId,
          enqueuedAt: now,
          expiresAt: expiresAt,
          skipHaptic: skipHaptic,
        ),
      );
      _lastText = text;
      _lastTrackId = trackId;
      _lastTime = now;
      _lastSpokenByText[text] = now;
      _gcSpokenTextMap(now);
      FieldLogger.instance.logTtsSay(
        text: text,
        priority: priority.name,
        pan: pan,
        trackId: trackId,
      );
      _interruptAndSpeak(barge: barge);
      return;
    }

    if (priority == SpeechPriority.warning) {
      _queue.removeWhere((j) => j.priority == SpeechPriority.info);
    }

    if (_queue.any((j) => j.text == text)) return;

    if (_queue.length >= 4) {
      int oldestInfoIdx = -1;
      DateTime oldestInfoTime = DateTime.now();
      int oldestWarnIdx = -1;
      DateTime oldestWarnTime = DateTime.now();
      for (int i = 0; i < _queue.length; i++) {
        final job = _queue[i];
        if (job.priority == SpeechPriority.info &&
            job.enqueuedAt.isBefore(oldestInfoTime)) {
          oldestInfoTime = job.enqueuedAt;
          oldestInfoIdx = i;
        } else if (job.priority == SpeechPriority.warning &&
            job.enqueuedAt.isBefore(oldestWarnTime)) {
          oldestWarnTime = job.enqueuedAt;
          oldestWarnIdx = i;
        }
      }

      int? evictIdx;
      String? evictReason;
      if (oldestInfoIdx >= 0) {
        evictIdx = oldestInfoIdx;
        evictReason = 'queue_full_evict_oldest_info';
      } else if (priority == SpeechPriority.warning && oldestWarnIdx >= 0) {
        evictIdx = oldestWarnIdx;
        evictReason = 'queue_full_evict_oldest_warning';
      }

      if (evictIdx != null) {
        final evicted = _queue.removeAt(evictIdx);
        FieldLogger.instance.log('tts_queue_drop', {
          'reason': evictReason,
          'evicted_text': evicted.text,
          'evicted_priority': evicted.priority.name,
          'queued_at': evicted.enqueuedAt.toIso8601String(),
          'incoming_text': text,
          'incoming_priority': priority.name,
        });
      } else {
        FieldLogger.instance.log('tts_queue_drop', {
          'reason': 'queue_full_drop_incoming',
          'evicted_text': text,
          'evicted_priority': priority.name,
        });
        return;
      }
    }

    _queue.add(
      SpeechJob(
        text,
        priority,
        pan: pan,
        rate: rate,
        trackId: trackId,
        actionId: actionId,
        hazardId: hazardId,
        enqueuedAt: now,
        expiresAt: expiresAt,
        skipHaptic: skipHaptic,
      ),
    );
    _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    _lastText = text;
    _lastTrackId = trackId;
    _lastTime = now;
    _lastSpokenByText[text] = now;
    _gcSpokenTextMap(now);
    FieldLogger.instance.logTtsSay(
      text: text,
      priority: priority.name,
      pan: pan,
      trackId: trackId,
    );
    _pump();
  }

  bool submitFeedbackCommand(
    FeedbackCommand command, {
    required String localizedText,
    DateTime? now,
  }) {
    final dispatchAt = now ?? DateTime.now();
    if (command.isExpiredAt(dispatchAt) || localizedText.isEmpty) return false;
    final priority = switch (command.priority) {
      SafetyPriority.p0Emergency => SpeechPriority.critical,
      SafetyPriority.p1Correction ||
      SafetyPriority.p2Degraded => SpeechPriority.warning,
      SafetyPriority.p3Information => SpeechPriority.info,
    };
    say(
      localizedText,
      priority,
      actionId: command.actionId,
      hazardId: command.hazardIds.firstOrNull,
      expiresAt: command.expiresAt,
      barge: command.canInterrupt,
      skipHaptic: true,
      pan: command.pan,
    );
    return _ready;
  }

  void _gcSpokenTextMap(DateTime now) {
    if (_lastSpokenByText.length < 32) return;
    final cutoff = now.subtract(_kCriticalDedupWindow);
    _lastSpokenByText.removeWhere((_, ts) => ts.isBefore(cutoff));
  }

  /// Approximate Kazakh→Russian phonetic transliteration for the
  /// `russianFallback` engine path. Replaces Kazakh-specific Cyrillic
  /// letters with their closest Russian phonetic equivalents so the
  /// ru-RU TTS engine produces intelligible (if imperfect) Kazakh.
  static String transliterateKkToRu(String text) {
    return text
        .replaceAll('ә', 'э')
        .replaceAll('Ә', 'Э')
        .replaceAll('ғ', 'г')
        .replaceAll('Ғ', 'Г')
        .replaceAll('қ', 'к')
        .replaceAll('Қ', 'К')
        .replaceAll('ң', 'нг')
        .replaceAll('Ң', 'Нг')
        .replaceAll('ө', 'о')
        .replaceAll('Ө', 'О')
        .replaceAll('ұ', 'у')
        .replaceAll('Ұ', 'У')
        .replaceAll('ү', 'у')
        .replaceAll('Ү', 'У')
        .replaceAll('һ', 'х')
        .replaceAll('Һ', 'Х')
        .replaceAll('і', 'и')
        .replaceAll('І', 'И');
  }

  void evictTrack(int trackId) {
    final before = _queue.length;
    _queue.removeWhere(
      (j) => j.trackId == trackId && j.priority != SpeechPriority.critical,
    );
    final removed = before - _queue.length;
    if (removed > 0) {
      debugPrint('TtsService: evicted $removed job(s) for track $trackId');
    }
  }

  void evictStale({Duration maxAge = const Duration(seconds: 5)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    final before = _queue.length;
    _queue.removeWhere(
      (j) => j.priority == SpeechPriority.info && j.enqueuedAt.isBefore(cutoff),
    );
    final removed = before - _queue.length;
    if (removed > 0) {
      debugPrint('TtsService: evicted $removed stale info job(s)');
    }
  }

  /// V4.2: Re-enqueue the last critical utterance with barge semantics so
  /// that a hazard alert that was mid-play during a Bluetooth route change is
  /// replayed once the audio path has stabilised.  No-ops if no critical text
  /// is remembered or if the last utterance was not critical.
  void replayLastCritical() {
    final text = _currentText;
    final priority = _currentPriority;
    if (text == null || text.isEmpty || priority != SpeechPriority.critical) {
      return;
    }
    debugPrint('TtsService: replaying last critical after audio route change');
    say(text, SpeechPriority.critical, pan: 0.0, barge: true);
  }

  Future<void> stop() async {
    _disarmStallTimer();
    try {
      await _tts.stop();
    } catch (_) {}
    if (_useNativeBackend) {
      try {
        await NativeTtsBridge.instance.stop();
      } catch (_) {}
    }
    _speaking = false;
    _currentIsCritical = false;
    _lastSpeechEndedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _completeCurrentSpeech();
    _queue.clear();
    _lastSpokenByText.clear();
  }

  Future<void> _interruptAndSpeak({bool barge = false}) async {
    if (_testMode) return;
    if (!barge && _speaking && _currentIsCritical) {
      final age = DateTime.now().difference(_currentSpeakStartedAt);
      if (age < _kCriticalStaleAfter) {
        return;
      }
    }
    try {
      await _tts.stop();
    } catch (_) {}
    if (_useNativeBackend) {
      try {
        await NativeTtsBridge.instance.stop();
      } catch (_) {}
    }
    _speaking = false;
    _currentIsCritical = false;
    _lastSpeechEndedAt = DateTime.fromMillisecondsSinceEpoch(0);
    _completeCurrentSpeech();
    _pump();
  }

  Future<void> _pump() async {
    if (_testMode) return;

    final now = DateTime.now();
    _purgeExpiredJobs(now);
    _pruneStaleCriticals(now, maxAge: _kCriticalStaleAfter);
    _queue.removeWhere(
      (j) =>
          j.priority != SpeechPriority.critical &&
          now.difference(j.enqueuedAt) > const Duration(seconds: 5),
    );
    if (_speaking || _queue.isEmpty) return;

    final nextJob = _queue[0];
    if (nextJob.priority != SpeechPriority.critical) {
      final elapsed = now.difference(_lastSpeechEndedAt);
      const sentenceDelay = Duration(milliseconds: 1000);
      if (elapsed < sentenceDelay) {
        final remaining = sentenceDelay - elapsed;
        Timer(remaining, () {
          if (!_speaking && _queue.isNotEmpty) {
            _pump();
          }
        });
        return;
      }
    }

    final job = _queue.removeAt(0);
    try {
      _speaking = true;
      _currentIsCritical = job.priority == SpeechPriority.critical;
      _currentSpeakStartedAt = DateTime.now();

      _currentText = job.text;
      _currentPriority = job.priority;
      if (_reverseVehicleSuspected && job.priority != SpeechPriority.critical) {
        try {
          _session?.setActive(false);
        } catch (_) {}
      } else {
        await _session?.setActive(true);
      }

      final targetRate = (job.rate * _userRateMultiplier).clamp(0.2, 1.5);
      if ((targetRate - _currentRate).abs() > 0.005) {
        await _tts.setSpeechRate(targetRate);
        _currentRate = targetRate;
      }

      if (job.pan != 0.0) {
        try {
          await (_tts as dynamic).setPan(job.pan);
        } catch (_) {}
      }

      if (job.priority == SpeechPriority.critical && !job.skipHaptic) {
        unawaited(HapticService.vibrate(const [0, 80]));
      }

      if (_useNativeBackend) {
        final ok = await NativeTtsBridge.instance.speak(
          text: job.text,
          priority: job.priority.name,
          rate: targetRate,
          volume: _userVolume,
          pan: job.pan,
        );
        if (!ok) {
          debugPrint(
            'TtsService: native bridge speak() returned false — '
            'demoting kk to russianFallback for this session',
          );
          FieldLogger.instance.log('tts_kk_native_speak_rejected', {
            'engine': _activeKkEngine?.id ?? 'unknown',
            'priority': job.priority.name,
          });
          _activeKkEngine = KkTtsEngine.russianFallback;
          try {
            await _tts.setLanguage('ru-RU');
          } catch (_) {}
          await _tts.speak(transliterateKkToRu(job.text));
        }
      } else {
        final spokenText = (_activeKkEngine == KkTtsEngine.russianFallback)
            ? transliterateKkToRu(job.text)
            : job.text;
        await _tts.speak(spokenText);
      }
    } catch (_) {
      _speaking = false;
      _currentIsCritical = false;
      _completeCurrentSpeech();
      if (_queue.isEmpty) await _session?.setActive(false);
    }
  }

  void dispose() {
    onAudioRouteInterrupted = null;
    onAudioRouteResumed = null;
    onTtsStall = null;
    onKazakhEngineResolved = null;
    _disarmStallTimer();
    _ready = false;
    _initStarted = false;
    _initCompleter = null;
    unawaited(stop());
    unawaited(_interruptionSub?.cancel());
    _interruptionSub = null;
    unawaited(_noisySub?.cancel());
    _noisySub = null;
    try {
      _session?.setActive(false);
    } catch (_) {}
    _session = null;
    try {
      _tts.stop();
    } catch (_) {}
    if (_bridgeListenersAttached) {
      final bridge = NativeTtsBridge.instance;
      bridge.onSpeechStart = null;
      bridge.onSpeechComplete = null;
      bridge.onSpeechError = null;
      _bridgeListenersAttached = false;
    }
  }

  /// Drive [_resolveKkEngine] directly from tests so engine-selection logic
  /// can be exercised without standing up a real `flutter_tts` instance.
  @visibleForTesting
  Future<KkTtsEngine> debugResolveKkEngine() => _resolveKkEngine();

  /// Override the FlutterTts kk-availability probe inside
  /// [_resolveKkEngine]. Set to `true` to simulate a device that ships
  /// with a Kazakh system voice, `false` to force the resolver into the
  /// native / russianFallback branches, or `null` to delegate back to the
  /// real probe.
  @visibleForTesting
  set debugKkSystemTtsAvailableOverride(bool? v) =>
      _kkSystemTtsAvailableOverride = v;

  @visibleForTesting
  void debugSetActiveKkEngine(KkTtsEngine? engine) => _activeKkEngine = engine;
}

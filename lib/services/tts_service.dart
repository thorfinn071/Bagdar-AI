import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import '../../models/constants.dart' show kTtsStallTimeout;
import '../../models/speech_job.dart';
import '../../models/strings.dart';
import 'haptic_service.dart';
import 'field_logger.dart';

class TtsService {
  
  
  
  
  
  static const Duration _kCriticalStaleAfter = Duration(seconds: 4);

  
  
  
  
  FlutterTts? _ttsImpl;
  FlutterTts get _tts => _ttsImpl ??= FlutterTts();
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _noisySub;

  bool _ready = false;
  bool _speaking = false;
  bool _languageAvailable = true;
  bool _usingEnglishFallback = false;
  bool _testMode = false;
  String _requestedLang = 'ru-RU';
  final List<SpeechJob> _queue = [];

  TtsService();

  
  
  
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

  void _pruneStaleCriticals(DateTime now, {Duration? maxAge}) {
    final threshold = maxAge ?? _kCriticalStaleAfter;
    _queue.removeWhere(
      (j) =>
          j.priority == SpeechPriority.critical &&
          now.difference(j.enqueuedAt) > threshold,
    );
  }

  void Function()? onAudioRouteInterrupted;
  void Function()? onAudioRouteResumed;
  void Function()? onTtsStall;

  DateTime _lastAudioRouteAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _stallTimer;

  bool get languageAvailable => _languageAvailable;
  bool get usingEnglishFallback => _usingEnglishFallback;

  String _lastText = '';
  int? _lastTrackId;
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

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
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
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
        _armStallTimer();
      });
      _tts.setCompletionHandler(() {
        _speaking = false;
        _disarmStallTimer();
        _pump();
        if (_queue.isEmpty) _session?.setActive(false);
      });
      _tts.setErrorHandler((msg) {
        debugPrint('TtsService: engine error: $msg');
        _speaking = false;
        _disarmStallTimer();
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
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> setLanguage(String bcp47Tag) async {
    await stop();
    _requestedLang = bcp47Tag;
    _usingEnglishFallback = false;
    await _applyLanguage(bcp47Tag);
  }

  void Function()? onKazakhVoiceMissing;

  Future<void> preClaimAudioFocus() async {
    if (!_ready) return;
    try {
      await _session?.setActive(true);
    } catch (_) {}
  }

  Future<void> _applyLanguage(String bcp47Tag) async {
    if (bcp47Tag == 'kk-KZ') {
      final hasKk = await _trySetLanguage('kk-KZ') ||
          await _trySetLanguage('kk');
      if (!hasKk) {
        debugPrint('TtsService: no kk voice — falling back to ru-RU for Kazakh text');
        await _trySetLanguage('ru-RU');
        AppStrings.setAlertLanguage(null);
        onKazakhVoiceMissing?.call();
        return;
      }
      await _checkLanguageAvailability(bcp47Tag);
      AppStrings.setAlertLanguage(null);
      return;
    }

    try {
      await _tts.setLanguage(bcp47Tag);
    } catch (_) {}
    await _checkLanguageAvailability(bcp47Tag);

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
    if (now.difference(_lastAudioRouteAlertAt) < const Duration(seconds: 2)) {
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

  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(kTtsStallTimeout, () {
      if (!_speaking) return;
      debugPrint('TtsService: stall detected — resetting speaking flag');
      _speaking = false;
      try {
        _tts.stop();
      } catch (_) {}
      onTtsStall?.call();
      if (_queue.isNotEmpty) _pump();
    });
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

  void say(
    String text,
    SpeechPriority priority, {
    double pan = 0.0,
    int? trackId,
  }) {
    if (!_ready || text.isEmpty) return;
    final now = DateTime.now();
    final rate = _rateFor(priority);

    if (priority != SpeechPriority.critical &&
        text == _lastText &&
        trackId == _lastTrackId &&
        now.difference(_lastTime) < const Duration(seconds: 2)) {
      return;
    }

    if (priority == SpeechPriority.critical) {
      
      
      
      
      _queue.removeWhere((j) => j.priority != SpeechPriority.critical);
      if (_queue.any((j) => j.text == text)) {
        _lastText = text;
        _lastTrackId = trackId;
        _lastTime = now;
        return;
      }
      _queue.add(
        SpeechJob(text, priority, pan: pan, rate: rate, trackId: trackId),
      );
      _lastText = text;
      _lastTrackId = trackId;
      _lastTime = now;
      FieldLogger.instance.logTtsSay(
        text: text,
        priority: priority.name,
        pan: pan,
        trackId: trackId,
      );
      _interruptAndSpeak();
      return;
    }

    if (priority == SpeechPriority.warning) {
      _queue.removeWhere((j) => j.priority == SpeechPriority.info);
    }

    if (_queue.any((j) => j.text == text)) return;

    if (_queue.length >= 4) {
      int oldestInfoIdx = -1;
      DateTime oldestTime = DateTime.now();
      for (int i = 0; i < _queue.length; i++) {
        if (_queue[i].priority == SpeechPriority.info &&
            _queue[i].enqueuedAt.isBefore(oldestTime)) {
          oldestTime = _queue[i].enqueuedAt;
          oldestInfoIdx = i;
        }
      }
      if (oldestInfoIdx >= 0) {
        _queue.removeAt(oldestInfoIdx);
      } else {
        return;
      }
    }

    _queue.add(
      SpeechJob(text, priority, pan: pan, rate: rate, trackId: trackId),
    );
    _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    _lastText = text;
    _lastTrackId = trackId;
    _lastTime = now;
    FieldLogger.instance.logTtsSay(
      text: text,
      priority: priority.name,
      pan: pan,
      trackId: trackId,
    );
    _pump();
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

  Future<void> stop() async {
    _disarmStallTimer();
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
    _queue.clear();
  }

  Future<void> _interruptAndSpeak() async {
    if (_testMode) return;
    try {
      await _tts.stop();
    } catch (_) {}
    _speaking = false;
    _pump();
  }

  Future<void> _pump() async {
    if (_testMode) return;
    
    
    _pruneStaleCriticals(DateTime.now());
    if (_speaking || _queue.isEmpty) return;
    final job = _queue.removeAt(0);
    try {
      _speaking = true;
      if (_reverseVehicleSuspected &&
          job.priority != SpeechPriority.critical) {
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

      
      
      
      
      
      if (job.priority == SpeechPriority.critical) {
        unawaited(HapticService.vibrate(const [0, 80]));
      }

      await _tts.speak(job.text);
    } catch (_) {
      _speaking = false;
      if (_queue.isEmpty) await _session?.setActive(false);
    }
  }

  void dispose() {
    onAudioRouteInterrupted = null;
    onAudioRouteResumed = null;
    onTtsStall = null;
    _disarmStallTimer();
    _ready = false;
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
  }
}

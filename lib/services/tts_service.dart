import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audio_session/audio_session.dart';
import '../../models/speech_job.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  AudioSession? _session;

  bool _ready      = false;
  bool _speaking   = false;
  final List<SpeechJob> _queue = [];

  String   _lastText = '';
  DateTime _lastTime = DateTime.fromMillisecondsSinceEpoch(0);

  double _currentRate = 0.50;

  static const double _rateCritical = 0.65;
  static const double _rateWarning  = 0.50;
  static const double _rateInfo     = 0.45;

  static double _rateFor(SpeechPriority p) {
    switch (p) {
      case SpeechPriority.critical: return _rateCritical;
      case SpeechPriority.warning:  return _rateWarning;
      case SpeechPriority.info:     return _rateInfo;
    }
  }

  Future<void> init() async {
    try {
      _session = await AudioSession.instance;
      await _session?.configure(const AudioSessionConfiguration.speech());
      
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(_currentRate);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      _tts.setStartHandler(()  { _speaking = true; });
      _tts.setCompletionHandler(() { 
        _speaking = false; 
        _pump(); 
        if (_queue.isEmpty) _session?.setActive(false); 
      });
      _tts.setErrorHandler((_)   { 
        _speaking = false; 
        _pump(); 
        if (_queue.isEmpty) _session?.setActive(false); 
      });

      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> setLanguage(String bcp47Tag) async {
    await stop();
    try { await _tts.setLanguage(bcp47Tag); } catch (_) {}
  }

  void say(
    String text,
    SpeechPriority priority, {
    double pan     = 0.0,
    int?   trackId,
  }) {
    if (!_ready || text.isEmpty) return;
    final now  = DateTime.now();
    final rate = _rateFor(priority);

    if (priority != SpeechPriority.critical &&
        text == _lastText &&
        now.difference(_lastTime) < const Duration(seconds: 2)) {
      return;
    }

    if (priority == SpeechPriority.critical) {
      _queue.clear();
      _queue.add(SpeechJob(text, priority,
          pan: pan, rate: rate, trackId: trackId));
      _lastText = text;
      _lastTime = now;
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
          oldestTime    = _queue[i].enqueuedAt;
          oldestInfoIdx = i;
        }
      }
      if (oldestInfoIdx >= 0) {
        _queue.removeAt(oldestInfoIdx);
      } else {
        return;
      }
    }

    _queue.add(SpeechJob(text, priority,
        pan: pan, rate: rate, trackId: trackId));
    _queue.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    _lastText = text;
    _lastTime = now;
    _pump();
  }

  void evictTrack(int trackId) {
    final before = _queue.length;
    _queue.removeWhere((j) =>
        j.trackId == trackId &&
        j.priority != SpeechPriority.critical);
    final removed = before - _queue.length;
    if (removed > 0) {
      debugPrint('TtsService: evicted $removed job(s) for track $trackId');
    }
  }

  void evictStale({Duration maxAge = const Duration(seconds: 3)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    final before = _queue.length;
    _queue.removeWhere((j) =>
        j.priority == SpeechPriority.info &&
        j.enqueuedAt.isBefore(cutoff));
    final removed = before - _queue.length;
    if (removed > 0) {
      debugPrint('TtsService: evicted $removed stale info job(s)');
    }
  }

  Future<void> stop() async {
    try { await _tts.stop(); } catch (_) {}
    _speaking = false;
    _queue.clear();
  }

  Future<void> _interruptAndSpeak() async {
    try { await _tts.stop(); } catch (_) {}
    _speaking = false;
    _pump();
  }

  Future<void> _pump() async {
    if (_speaking || _queue.isEmpty) return;
    final job = _queue.removeAt(0);
    try {
      _speaking = true;
      await _session?.setActive(true);

      if (job.rate != _currentRate) {
        await _tts.setSpeechRate(job.rate);
        _currentRate = job.rate;
      }

      if (job.pan != 0.0) {
        try {
          await (_tts as dynamic).setPan(job.pan);
        } catch (_) {}
      }

      await _tts.speak(job.text);
    } catch (_) {
      _speaking = false;
      if (_queue.isEmpty) await _session?.setActive(false);
    }
  }
}

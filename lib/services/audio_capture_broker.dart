import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AudioFrame {
  final Int16List samples;
  final int sampleRate;
  final int channels;
  final DateTime timestamp;

  const AudioFrame({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.timestamp,
  });

  bool get isStereo => channels >= 2;
  int get monoSampleCount => samples.length ~/ channels;
}

class AudioCaptureBroker {
  static const _method = MethodChannel('bagdar/audio_capture');
  static const _event = EventChannel('bagdar/audio_frames');

  StreamSubscription<dynamic>? _sub;
  final StreamController<AudioFrame> _controller =
      StreamController<AudioFrame>.broadcast();

  bool _running = false;
  bool _paused = false;
  bool _stereo = false;
  int _sampleRate = 16000;
  int _channels = 1;

  bool get isRunning => _running;
  bool get isPaused => _paused;
  bool get isStereo => _stereo;
  int get sampleRate => _sampleRate;
  int get channels => _channels;

  Stream<AudioFrame> get frames => _controller.stream;

  Future<bool> start() async {
    if (_running) return true;
    try {
      final result = await _method.invokeMethod<Map>('start');
      if (result == null) return false;
      final started = result['started'] as bool? ?? false;
      if (!started) return false;
      _sampleRate = result['sampleRate'] as int? ?? 16000;
      _channels = result['channels'] as int? ?? 1;
      _stereo = result['isStereo'] as bool? ?? false;
      _running = true;
      _paused = false;
      _sub = _event.receiveBroadcastStream().listen(
        _onFrame,
        onError: (e) => debugPrint('AudioCaptureBroker stream error: $e'),
      );
      return true;
    } catch (e) {
      debugPrint('AudioCaptureBroker start error: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
    _paused = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _method.invokeMethod('stop');
    } catch (_) {}
  }

  Future<void> pause() async {
    if (!_running || _paused) return;
    _paused = true;
    try {
      await _method.invokeMethod('pause');
    } catch (_) {}
  }

  Future<void> resume() async {
    if (!_running || !_paused) return;
    _paused = false;
    try {
      await _method.invokeMethod('resume');
    } catch (_) {}
  }

  void _onFrame(dynamic event) {
    if (event is! Map) return;
    final data = event['data'];
    if (data is! Uint8List) return;
    final ts = event['timestamp'] as int? ?? 0;
    final ch = event['channels'] as int? ?? _channels;
    final sr = event['sampleRate'] as int? ?? _sampleRate;

    final samples = Int16List.view(
      data.buffer,
      data.offsetInBytes,
      data.lengthInBytes ~/ 2,
    );

    _controller.add(AudioFrame(
      samples: samples,
      sampleRate: sr,
      channels: ch,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
    ));
  }

  void dispose() {
    _running = false;
    _paused = false;
    _sub?.cancel();
    _sub = null;
    _controller.close();
    try {
      _method.invokeMethod('stop');
    } catch (_) {}
  }
}

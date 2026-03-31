import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';



enum Earcon {
  objectAppeared,
  objectLeft,
  pathClear,
  approaching,
  modeStreet,
  modeCane,
  modeScan,
  success,
  fail,
}

class EarconService {
  static const int _sampleRate = 44100;

  final Map<Earcon, AudioPlayer> _players = {};

  bool _enabled = true;
  bool _ready   = false;

  Future<void> init() async {
    try {
      await AudioPlayer.global.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          audioFocus:   AndroidAudioFocus.none,
          usageType:    AndroidUsageType.assistanceSonification,
          contentType:  AndroidContentType.sonification,
          isSpeakerphoneOn: false,
        ),
        iOS: AudioContextIOS(
          category:        AVAudioSessionCategory.ambient,
          options:         const {AVAudioSessionOptions.mixWithOthers},
        ),
      ));

      for (final earcon in Earcon.values) {
        final player = AudioPlayer();
        final bytes  = _generate(earcon);
        await player.setSourceBytes(bytes, mimeType: 'audio/wav');
        await player.setVolume(0.85);
        _players[earcon] = player;
      }

      _ready = true;
    } catch (e) {
      debugPrint('EarconService init error: $e');
      _ready = false;
    }
  }

  bool get isEnabled => _enabled;

  Future<void> play(Earcon earcon, {double pan = 0.0}) async {
    if (!_ready || !_enabled) return;
    final player = _players[earcon];
    if (player == null) return;
    try {
      await player.setBalance(pan.clamp(-1.0, 1.0));
      await player.seek(Duration.zero);
      await player.resume();
    } catch (e) {
      debugPrint('EarconService.play error: $e');
    }
  }

  void setEnabled(bool v) => _enabled = v;

  void dispose() {
    for (final p in _players.values) {
      try { p.dispose(); } catch (_) {}
    }
    _players.clear();
  }

  Uint8List _generate(Earcon earcon) {
    switch (earcon) {
      case Earcon.objectAppeared:
        return _buildWav(_singleTone(440, 55, 0.30));
      case Earcon.objectLeft:
        return _buildWav(_sweep(440, 220, 80, 0.25));
      case Earcon.pathClear:
        return _buildWav(_chord([880, 1100, 1320], 40, 30, 0.45));
      case Earcon.approaching:
        return _buildWav(_doubleBeep(220, 45, 35, 0.55));
      case Earcon.modeStreet:
        return _buildWav(_singleTone(523, 70, 0.50));
      case Earcon.modeCane:
        return _buildWav(_singleTone(659, 70, 0.50));
      case Earcon.modeScan:
        return _buildWav(_singleTone(784, 70, 0.50));
      case Earcon.success:
        return _buildWav(_sweep(660, 990, 110, 0.55));
      case Earcon.fail:
        return _buildWav(_sweep(440, 330, 90, 0.45));
    }
  }

  Int16List _singleTone(double freq, int durationMs, double amp) {
    final n = (_sampleRate * durationMs / 1000).round();
    return _applyFade(_sine(freq, n, amp), n);
  }

  Int16List _doubleBeep(
      double freq, int beepMs, int gapMs, double amp) {
    final b = _singleTone(freq, beepMs, amp);
    final g = Int16List((_sampleRate * gapMs / 1000).round());
    final result = Int16List(b.length + g.length + b.length);
    result.setAll(0, b);
    result.setAll(b.length, g);
    result.setAll(b.length + g.length, b);
    return result;
  }

  Int16List _sweep(
      double freqStart, double freqEnd, int durationMs, double amp) {
    final n = (_sampleRate * durationMs / 1000).round();
    final buf = Int16List(n);
    double phase = 0.0;
    for (int i = 0; i < n; i++) {
      final prog = i / n;
      final freq = freqStart + (freqEnd - freqStart) * prog;

      final fade = _fadeEnvelope(i, n);
      buf[i] = (amp * fade * math.sin(phase) * 32767).round()
          .clamp(-32768, 32767);
      phase += 2 * math.pi * freq / _sampleRate;
    }
    return buf;
  }

  Int16List _chord(List<double> freqs, int beepMs, int gapMs, double amp) {
    final beepSamples = (_sampleRate * beepMs / 1000).round();
    final gapSamples  = (_sampleRate * gapMs  / 1000).round();
    final total = freqs.length * beepSamples +
        (freqs.length - 1) * gapSamples;
    final result = Int16List(total);
    int offset = 0;
    for (int i = 0; i < freqs.length; i++) {
      final beep = _singleTone(freqs[i], beepMs, amp);
      result.setAll(offset, beep);
      offset += beepSamples;
      if (i < freqs.length - 1) {
        offset += gapSamples;
      }
    }
    return result;
  }

  Int16List _sine(double freq, int samples, double amp) {
    final buf = Int16List(samples);
    for (int i = 0; i < samples; i++) {
      buf[i] = (amp * math.sin(2 * math.pi * freq * i / _sampleRate) * 32767)
          .round()
          .clamp(-32768, 32767);
    }
    return buf;
  }

  Int16List _applyFade(Int16List buf, int n) {
    final fadeLen = (n * 0.12).round();
    for (int i = 0; i < fadeLen; i++) {
      final env = i / fadeLen;
      buf[i] = (buf[i] * env).round();
    }
    for (int i = n - fadeLen; i < n; i++) {
      final env = (n - i) / fadeLen;
      buf[i] = (buf[i] * env).round();
    }
    return buf;
  }

  double _fadeEnvelope(int i, int n) {
    final fadeLen = (n * 0.12).round();
    if (i < fadeLen)      return i / fadeLen;
    if (i > n - fadeLen)  return (n - i) / fadeLen;
    return 1.0;
  }

  Uint8List _buildWav(Int16List samples) {
    final dataSize   = samples.length * 2;
    final fileSize   = 44 + dataSize;
    final buf        = ByteData(fileSize);

    buf.setUint8(0, 0x52); buf.setUint8(1, 0x49);
    buf.setUint8(2, 0x46); buf.setUint8(3, 0x46);
    buf.setUint32(4,  fileSize - 8, Endian.little);
    buf.setUint8(8,  0x57); buf.setUint8(9,  0x41);
    buf.setUint8(10, 0x56); buf.setUint8(11, 0x45);

    buf.setUint8(12, 0x66); buf.setUint8(13, 0x6D);
    buf.setUint8(14, 0x74); buf.setUint8(15, 0x20);
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20,  1, Endian.little);
    buf.setUint16(22,  1, Endian.little);
    buf.setUint32(24, _sampleRate, Endian.little);
    buf.setUint32(28, _sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);

    buf.setUint8(36, 0x64); buf.setUint8(37, 0x61);
    buf.setUint8(38, 0x74); buf.setUint8(39, 0x61);
    buf.setUint32(40, dataSize, Endian.little);

    for (int i = 0; i < samples.length; i++) {
      buf.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return buf.buffer.asUint8List();
  }
}

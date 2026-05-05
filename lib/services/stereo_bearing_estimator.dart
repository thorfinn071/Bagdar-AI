import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_capture_broker.dart';
import '../models/constants.dart';

enum BearingSide { left, center, right }

class BearingEstimate {
  final BearingSide side;
  final double confidence;
  final DateTime at;

  const BearingEstimate({
    required this.side,
    required this.confidence,
    required this.at,
  });
}

class StereoBearingEstimator {
  static const int _fftSize = kAwmBearingFftSize;
  static const double _highPassCutoff = 200.0;
  static const double _transientMultiplier = kAwmTransientThresholdMultiplier;
  static const int _subWindowSamples = 800;

  late final Float32List _fftRealA;
  late final Float32List _fftImagA;
  late final Float32List _fftRealB;
  late final Float32List _fftImagB;

  double _baselineEnergy = 0.0;
  bool _ready = false;

  bool get isReady => _ready;

  void init() {
    _fftRealA = Float32List(_fftSize);
    _fftImagA = Float32List(_fftSize);
    _fftRealB = Float32List(_fftSize);
    _fftImagB = Float32List(_fftSize);
    _ready = true;
  }

  BearingEstimate? estimate(AudioFrame frame) {
    if (!_ready || !frame.isStereo) return null;

    final monoLen = frame.monoSampleCount;
    if (monoLen < _subWindowSamples * 2) return null;

    final left = Float32List(monoLen);
    final right = Float32List(monoLen);
    for (int i = 0; i < monoLen; i++) {
      left[i] = frame.samples[i * 2] / 32768.0;
      right[i] = frame.samples[i * 2 + 1] / 32768.0;
    }

    _highPass(left, frame.sampleRate);
    _highPass(right, frame.sampleRate);

    final transientIdx = _findTransient(left, right, monoLen);
    if (transientIdx < 0) return null;

    final start = (transientIdx - _fftSize ~/ 2).clamp(0, monoLen - _fftSize);

    for (int i = 0; i < _fftSize; i++) {
      _fftRealA[i] = left[start + i];
      _fftImagA[i] = 0.0;
      _fftRealB[i] = right[start + i];
      _fftImagB[i] = 0.0;
    }

    _fft(_fftRealA, _fftImagA, _fftSize);
    _fft(_fftRealB, _fftImagB, _fftSize);

    for (int i = 0; i < _fftSize; i++) {
      final crossR = _fftRealA[i] * _fftRealB[i] + _fftImagA[i] * _fftImagB[i];
      final crossI = _fftImagA[i] * _fftRealB[i] - _fftRealA[i] * _fftImagB[i];
      final mag = math.sqrt(crossR * crossR + crossI * crossI);
      if (mag > 1e-10) {
        _fftRealA[i] = crossR / mag;
        _fftImagA[i] = crossI / mag;
      } else {
        _fftRealA[i] = 0.0;
        _fftImagA[i] = 0.0;
      }
    }

    _ifft(_fftRealA, _fftImagA, _fftSize);

    int peakIdx = 0;
    double peakVal = -1.0;
    final maxLag = frame.sampleRate ~/ 1000;
    for (int i = 0; i < maxLag && i < _fftSize; i++) {
      if (_fftRealA[i] > peakVal) {
        peakVal = _fftRealA[i];
        peakIdx = i;
      }
    }
    for (int i = _fftSize - maxLag; i < _fftSize; i++) {
      if (_fftRealA[i] > peakVal) {
        peakVal = _fftRealA[i];
        peakIdx = i;
      }
    }

    if (peakVal < 0.1) return null;

    final lag = peakIdx <= _fftSize ~/ 2 ? peakIdx : peakIdx - _fftSize;

    final BearingSide side;
    if (lag.abs() <= 1) {
      side = BearingSide.center;
    } else if (lag > 0) {
      side = BearingSide.right;
    } else {
      side = BearingSide.left;
    }

    return BearingEstimate(
      side: side,
      confidence: peakVal.clamp(0.0, 1.0),
      at: frame.timestamp,
    );
  }

  int _findTransient(Float32List left, Float32List right, int len) {
    int count = 0;
    for (int i = 0; i < len; i += _subWindowSamples) {
      final end = (i + _subWindowSamples).clamp(0, len);
      double windowEnergy = 0.0;
      for (int j = i; j < end; j++) {
        windowEnergy += left[j] * left[j] + right[j] * right[j];
      }
      windowEnergy /= (end - i);

      if (count > 0 && windowEnergy > _baselineEnergy * _transientMultiplier &&
          windowEnergy > 0.001) {
        _baselineEnergy =
            _baselineEnergy * 0.95 + windowEnergy * 0.05;
        return i + _subWindowSamples ~/ 2;
      }

      _baselineEnergy =
          count == 0
              ? windowEnergy
              : _baselineEnergy * 0.95 + windowEnergy * 0.05;
      count++;
    }
    return -1;
  }

  void _highPass(Float32List samples, int sampleRate) {
    final rc = 1.0 / (2.0 * math.pi * _highPassCutoff);
    final dt = 1.0 / sampleRate;
    final alpha = rc / (rc + dt);
    double prev = samples[0];
    double filtered = samples[0];
    for (int i = 1; i < samples.length; i++) {
      filtered = alpha * (filtered + samples[i] - prev);
      prev = samples[i];
      samples[i] = filtered;
    }
  }

  void _fft(Float32List real, Float32List imag, int n) {
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        final tr = real[j]; final ti = imag[j];
        real[j] = real[i]; imag[j] = imag[i];
        real[i] = tr; imag[i] = ti;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) { j -= m; m >>= 1; }
      j += m;
    }
    for (int step = 2; step <= n; step <<= 1) {
      final half = step >> 1;
      final angle = -2.0 * math.pi / step;
      for (int group = 0; group < n; group += step) {
        for (int pair = 0; pair < half; pair++) {
          final wR = math.cos(angle * pair);
          final wI = math.sin(angle * pair);
          final i1 = group + pair;
          final i2 = i1 + half;
          final tR = wR * real[i2] - wI * imag[i2];
          final tI = wR * imag[i2] + wI * real[i2];
          real[i2] = real[i1] - tR;
          imag[i2] = imag[i1] - tI;
          real[i1] += tR;
          imag[i1] += tI;
        }
      }
    }
  }

  void _ifft(Float32List real, Float32List imag, int n) {
    for (int i = 0; i < n; i++) imag[i] = -imag[i];
    _fft(real, imag, n);
    for (int i = 0; i < n; i++) {
      real[i] /= n;
      imag[i] = -imag[i] / n;
    }
  }

  void dispose() {
    _ready = false;
  }
}

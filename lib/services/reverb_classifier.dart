import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_capture_broker.dart';
import '../models/constants.dart';

enum ReverbEnvironment { indoor, outdoor, uncertain }

class ReverbEstimate {
  final ReverbEnvironment env;
  final double confidence;
  final double rt60Proxy;
  final DateTime at;

  const ReverbEstimate({
    required this.env,
    required this.confidence,
    required this.rt60Proxy,
    required this.at,
  });
}

class ReverbClassifier {
  bool _ready = false;
  bool get isReady => _ready;

  void init() {
    _ready = true;
  }

  ReverbEstimate? classify(AudioFrame frame) {
    if (!_ready) return null;

    final mono = _toMono(frame);
    if (mono.length < frame.sampleRate ~/ 4) return null;

    final rt60 = _estimateRt60(mono, frame.sampleRate);
    final centroid = _spectralCentroid(mono, frame.sampleRate);
    final flatness = _spectralFlatness(mono);

    final ReverbEnvironment env;
    double confidence;

    if (rt60 > kAwmReverbIndoorThreshold && centroid < 2000.0) {
      env = ReverbEnvironment.indoor;
      confidence = ((rt60 - kAwmReverbIndoorThreshold) / 0.3).clamp(0.3, 0.9);
      if (flatness < 0.3) confidence += 0.1;
    } else if (rt60 < kAwmReverbOutdoorThreshold && centroid > 1500.0) {
      env = ReverbEnvironment.outdoor;
      confidence =
          ((kAwmReverbOutdoorThreshold - rt60) / 0.15).clamp(0.3, 0.9);
      if (flatness > 0.5) confidence += 0.1;
    } else {
      env = ReverbEnvironment.uncertain;
      confidence = 0.2;
    }

    return ReverbEstimate(
      env: env,
      confidence: confidence.clamp(0.0, 1.0),
      rt60Proxy: rt60,
      at: frame.timestamp,
    );
  }

  Float32List _toMono(AudioFrame frame) {
    if (frame.channels == 1) {
      final out = Float32List(frame.samples.length);
      for (int i = 0; i < frame.samples.length; i++) {
        out[i] = frame.samples[i] / 32768.0;
      }
      return out;
    }
    final monoLen = frame.samples.length ~/ frame.channels;
    final out = Float32List(monoLen);
    for (int i = 0; i < monoLen; i++) {
      double sum = 0.0;
      for (int c = 0; c < frame.channels; c++) {
        sum += frame.samples[i * frame.channels + c];
      }
      out[i] = sum / (frame.channels * 32768.0);
    }
    return out;
  }

  double _estimateRt60(Float32List mono, int sampleRate) {
    final n = mono.length;
    final maxLag = (sampleRate * 0.1).toInt().clamp(1, n ~/ 2);

    double energy = 0.0;
    for (int i = 0; i < n; i++) {
      energy += mono[i] * mono[i];
    }
    if (energy < 1e-10) return 0.0;

    final autocorr = Float32List(maxLag);
    for (int lag = 0; lag < maxLag; lag++) {
      double sum = 0.0;
      for (int i = 0; i < n - lag; i++) {
        sum += mono[i] * mono[i + lag];
      }
      autocorr[lag] = sum / energy;
    }

    int decayIdx = maxLag - 1;
    for (int i = 1; i < maxLag; i++) {
      if (autocorr[i] < 0.1) {
        decayIdx = i;
        break;
      }
    }

    final decayTimeSec = decayIdx / sampleRate.toDouble();
    final rt60 = decayTimeSec * 6.0;

    return rt60.clamp(0.0, 2.0);
  }

  double _spectralCentroid(Float32List mono, int sampleRate) {
    final n = 512.clamp(0, mono.length);
    if (n < 2) return 0.0;

    double weightedSum = 0.0;
    double totalMag = 0.0;
    final freqRes = sampleRate / (n * 2);

    for (int i = 0; i < n; i++) {
      final mag = mono[i].abs();
      final freq = i * freqRes;
      weightedSum += freq * mag;
      totalMag += mag;
    }

    return totalMag > 1e-10 ? weightedSum / totalMag : 0.0;
  }

  double _spectralFlatness(Float32List mono) {
    final n = 256.clamp(0, mono.length);
    if (n < 2) return 0.0;

    double logSum = 0.0;
    double arithmeticSum = 0.0;
    int count = 0;

    for (int i = 0; i < n; i++) {
      final mag = mono[i].abs();
      if (mag > 1e-10) {
        logSum += math.log(mag);
        arithmeticSum += mag;
        count++;
      }
    }

    if (count < 2) return 0.0;
    final geometricMean = math.exp(logSum / count);
    final arithmeticMean = arithmeticSum / count;

    return arithmeticMean > 1e-10
        ? (geometricMean / arithmeticMean).clamp(0.0, 1.0)
        : 0.0;
  }

  void dispose() {
    _ready = false;
  }
}

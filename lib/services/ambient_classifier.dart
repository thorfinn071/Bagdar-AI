import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'audio_capture_broker.dart';
import '../models/constants.dart';

enum BagdarAudioClass {
  vehicle,
  horn,
  siren,
  dog,
  crowd,
  tram,
  bicycle,
  construction,
  silence,
  wind,
  rain,
  trafficFlow,
  unknown,
}

class AmbientClassification {
  final BagdarAudioClass cls;
  final double confidence;
  final DateTime at;

  const AmbientClassification({
    required this.cls,
    required this.confidence,
    required this.at,
  });
}

class AmbientClassifier {
  static const int _melBins = kAwmMelBins;
  static const int _fftSize = kAwmFftSize;
  static const int _hopLength = 160;
  static const int _sampleRate = kAwmSampleRate;

  late final Float32List _melFilterbank;
  late final Float32List _fftReal;
  late final Float32List _fftImag;
  late final Float32List _window;

  bool _ready = false;
  bool get isReady => _ready;

  static const Map<String, BagdarAudioClass> _classMap = {
    'Vehicle': BagdarAudioClass.vehicle,
    'Car': BagdarAudioClass.vehicle,
    'Engine': BagdarAudioClass.vehicle,
    'Truck': BagdarAudioClass.vehicle,
    'Bus': BagdarAudioClass.vehicle,
    'Motor vehicle (road)': BagdarAudioClass.vehicle,
    'Car horn': BagdarAudioClass.horn,
    'Honking': BagdarAudioClass.horn,
    'Vehicle horn, car horn, honking': BagdarAudioClass.horn,
    'Air horn, truck horn': BagdarAudioClass.horn,
    'Siren': BagdarAudioClass.siren,
    'Emergency vehicle': BagdarAudioClass.siren,
    'Ambulance (siren)': BagdarAudioClass.siren,
    'Fire engine, fire truck (siren)': BagdarAudioClass.siren,
    'Police car (siren)': BagdarAudioClass.siren,
    'Civil defense siren': BagdarAudioClass.siren,
    'Dog': BagdarAudioClass.dog,
    'Bark': BagdarAudioClass.dog,
    'Growling': BagdarAudioClass.dog,
    'Bow-wow': BagdarAudioClass.dog,
    'Yip': BagdarAudioClass.dog,
    'Howl': BagdarAudioClass.dog,
    'Crowd': BagdarAudioClass.crowd,
    'Speech': BagdarAudioClass.crowd,
    'Babble': BagdarAudioClass.crowd,
    'Chatter': BagdarAudioClass.crowd,
    'Hubbub, speech noise, speech babble': BagdarAudioClass.crowd,
    'Train': BagdarAudioClass.tram,
    'Rail transport': BagdarAudioClass.tram,
    'Train horn': BagdarAudioClass.tram,
    'Bicycle bell': BagdarAudioClass.bicycle,
    'Bicycle': BagdarAudioClass.bicycle,
    'Jackhammer': BagdarAudioClass.construction,
    'Drill': BagdarAudioClass.construction,
    'Power tool': BagdarAudioClass.construction,
    'Sawing': BagdarAudioClass.construction,
    'Hammer': BagdarAudioClass.construction,
    'Silence': BagdarAudioClass.silence,
    'Wind': BagdarAudioClass.wind,
    'Wind noise (microphone)': BagdarAudioClass.wind,
    'Rustling leaves': BagdarAudioClass.wind,
    'Rain': BagdarAudioClass.rain,
    'Rain on surface': BagdarAudioClass.rain,
    'Raindrop': BagdarAudioClass.rain,
    'Traffic noise, roadway noise': BagdarAudioClass.trafficFlow,
  };

  Future<void> init() async {
    _melFilterbank = Float32List(_melBins * (_fftSize ~/ 2 + 1));
    _computeMelFilterbank();
    _fftReal = Float32List(_fftSize);
    _fftImag = Float32List(_fftSize);
    _window = Float32List(_fftSize);
    for (int i = 0; i < _fftSize; i++) {
      _window[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / (_fftSize - 1));
    }
    _ready = true;
  }

  AmbientClassification? classify(AudioFrame frame) {
    if (!_ready) return null;

    final mono = _toMono(frame);
    if (mono.length < _sampleRate ~/ 2) return null;

    final melSpec = _computeMelSpectrogram(mono);

    final classScores = _runSimpleClassifier(melSpec);

    BagdarAudioClass bestClass = BagdarAudioClass.unknown;
    double bestScore = 0.0;
    classScores.forEach((cls, score) {
      if (score > bestScore) {
        bestScore = score;
        bestClass = cls;
      }
    });

    if (bestScore < kAwmMinConfidence) {
      return AmbientClassification(
        cls: BagdarAudioClass.unknown,
        confidence: bestScore,
        at: frame.timestamp,
      );
    }

    return AmbientClassification(
      cls: bestClass,
      confidence: bestScore,
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

  Float32List _computeMelSpectrogram(Float32List mono) {
    final numFrames = (mono.length - _fftSize) ~/ _hopLength + 1;
    final specBins = _fftSize ~/ 2 + 1;
    final melSpec = Float32List(numFrames * _melBins);

    final powerSpec = Float32List(specBins);

    for (int f = 0; f < numFrames; f++) {
      final offset = f * _hopLength;

      for (int i = 0; i < _fftSize; i++) {
        final idx = offset + i;
        _fftReal[i] = idx < mono.length ? mono[idx] * _window[i] : 0.0;
        _fftImag[i] = 0.0;
      }

      _fft(_fftReal, _fftImag, _fftSize);

      for (int i = 0; i < specBins; i++) {
        powerSpec[i] = _fftReal[i] * _fftReal[i] + _fftImag[i] * _fftImag[i];
      }

      for (int m = 0; m < _melBins; m++) {
        double sum = 0.0;
        for (int k = 0; k < specBins; k++) {
          sum += _melFilterbank[m * specBins + k] * powerSpec[k];
        }
        melSpec[f * _melBins + m] =
            sum > 1e-10 ? (math.log(sum) / math.ln10) * 10.0 : -100.0;
      }
    }
    return melSpec;
  }

  Map<BagdarAudioClass, double> _runSimpleClassifier(Float32List melSpec) {
    final numFrames = melSpec.length ~/ _melBins;
    if (numFrames == 0) return {};

    final avgEnergy = Float32List(_melBins);
    for (int m = 0; m < _melBins; m++) {
      double sum = 0.0;
      for (int f = 0; f < numFrames; f++) {
        sum += melSpec[f * _melBins + m];
      }
      avgEnergy[m] = sum / numFrames;
    }

    double totalEnergy = 0.0;
    for (int m = 0; m < _melBins; m++) {
      totalEnergy += avgEnergy[m];
    }
    final meanEnergy = totalEnergy / _melBins;

    double lowEnergy = 0.0;
    double midEnergy = 0.0;
    double highEnergy = 0.0;
    final lowEnd = _melBins ~/ 4;
    final midEnd = _melBins * 3 ~/ 4;
    for (int m = 0; m < _melBins; m++) {
      if (m < lowEnd) {
        lowEnergy += avgEnergy[m];
      } else if (m < midEnd) {
        midEnergy += avgEnergy[m];
      } else {
        highEnergy += avgEnergy[m];
      }
    }
    lowEnergy /= lowEnd;
    midEnergy /= (midEnd - lowEnd);
    highEnergy /= (_melBins - midEnd);

    double variance = 0.0;
    for (int f = 1; f < numFrames; f++) {
      double frameDiff = 0.0;
      for (int m = 0; m < _melBins; m++) {
        final d = melSpec[f * _melBins + m] - melSpec[(f - 1) * _melBins + m];
        frameDiff += d * d;
      }
      variance += frameDiff / _melBins;
    }
    variance = numFrames > 1 ? variance / (numFrames - 1) : 0.0;

    final scores = <BagdarAudioClass, double>{};

    if (meanEnergy < -60.0) {
      scores[BagdarAudioClass.silence] = 0.8;
      return scores;
    }

    if (lowEnergy > -20.0 && variance > 50.0) {
      scores[BagdarAudioClass.vehicle] = _sigmoid(lowEnergy + 40.0, 0.1);
    }

    if (highEnergy > -15.0 && variance > 200.0) {
      scores[BagdarAudioClass.horn] = _sigmoid(variance - 150.0, 0.01) * 0.7;
    }

    if (variance > 300.0 && highEnergy > -10.0) {
      scores[BagdarAudioClass.siren] = _sigmoid(variance - 250.0, 0.005) * 0.6;
    }

    if (midEnergy > -25.0 && lowEnergy > -30.0 && variance > 100.0) {
      scores[BagdarAudioClass.dog] = _sigmoid(variance - 80.0, 0.01) * 0.5;
    }

    if (midEnergy > -20.0 && variance < 80.0) {
      scores[BagdarAudioClass.crowd] = _sigmoid(midEnergy + 30.0, 0.1) * 0.6;
    }

    if (lowEnergy > -15.0 && variance < 30.0) {
      scores[BagdarAudioClass.trafficFlow] =
          _sigmoid(lowEnergy + 25.0, 0.1) * 0.5;
    }

    if (highEnergy > -10.0 && variance > 150.0) {
      scores[BagdarAudioClass.construction] =
          _sigmoid(highEnergy + 20.0, 0.1) * 0.4;
    }

    if (highEnergy > midEnergy && highEnergy > -20.0 && variance > 50.0) {
      scores[BagdarAudioClass.wind] =
          _sigmoid(highEnergy - midEnergy, 0.1) * 0.4;
    }

    if (scores.isEmpty) {
      scores[BagdarAudioClass.unknown] = 0.3;
    }

    return scores;
  }

  static double _sigmoid(double x, double scale) =>
      1.0 / (1.0 + math.exp(-x * scale));

  void _computeMelFilterbank() {
    final specBins = _fftSize ~/ 2 + 1;
    final fMin = 0.0;
    final fMax = _sampleRate / 2.0;
    final melMin = _hzToMel(fMin);
    final melMax = _hzToMel(fMax);
    final melPoints = Float64List(_melBins + 2);
    for (int i = 0; i < _melBins + 2; i++) {
      melPoints[i] = melMin + i * (melMax - melMin) / (_melBins + 1);
    }
    final freqPoints = Float64List(_melBins + 2);
    for (int i = 0; i < _melBins + 2; i++) {
      freqPoints[i] = _melToHz(melPoints[i]);
    }
    final binPoints = Int32List(_melBins + 2);
    for (int i = 0; i < _melBins + 2; i++) {
      binPoints[i] =
          (freqPoints[i] * _fftSize / _sampleRate).floor().clamp(0, specBins - 1);
    }

    for (int m = 0; m < _melBins; m++) {
      for (int k = binPoints[m]; k < binPoints[m + 1]; k++) {
        if (binPoints[m + 1] != binPoints[m]) {
          _melFilterbank[m * specBins + k] =
              (k - binPoints[m]) / (binPoints[m + 1] - binPoints[m]);
        }
      }
      for (int k = binPoints[m + 1]; k < binPoints[m + 2]; k++) {
        if (binPoints[m + 2] != binPoints[m + 1]) {
          _melFilterbank[m * specBins + k] =
              (binPoints[m + 2] - k) / (binPoints[m + 2] - binPoints[m + 1]);
        }
      }
    }
  }

  static double _hzToMel(double hz) => 2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
  static double _melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

  void _fft(Float32List real, Float32List imag, int n) {
    int j = 0;
    for (int i = 0; i < n; i++) {
      if (i < j) {
        final tr = real[j];
        final ti = imag[j];
        real[j] = real[i];
        imag[j] = imag[i];
        real[i] = tr;
        imag[i] = ti;
      }
      int m = n >> 1;
      while (m >= 1 && j >= m) {
        j -= m;
        m >>= 1;
      }
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
          real[i1] = real[i1] + tR;
          imag[i1] = imag[i1] + tI;
        }
      }
    }
  }

  void dispose() {
    _ready = false;
  }
}

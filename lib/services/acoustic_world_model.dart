import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'audio_capture_broker.dart';
import 'ambient_classifier.dart';
import 'stereo_bearing_estimator.dart';
import 'reverb_classifier.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';

enum AcousticEventType {
  vehicleApproaching,
  hornBlast,
  sirenNearby,
  dogNearby,
  crowdDense,
  constructionNearby,
  tramNearby,
  bicycleNearby,
}

class AcousticEvent {
  final AcousticEventType type;
  final BearingSide? bearing;
  final double confidence;
  final SpeechPriority suggestedPriority;
  final DateTime at;

  const AcousticEvent({
    required this.type,
    this.bearing,
    required this.confidence,
    required this.suggestedPriority,
    required this.at,
  });
}

class AcousticWorldModel {
  final AudioCaptureBroker _broker = AudioCaptureBroker();
  late final AmbientClassifier _classifier;
  late final StereoBearingEstimator _bearingEstimator;
  late final ReverbClassifier _reverbClassifier;

  StreamSubscription<AudioFrame>? _frameSub;
  bool _enabled = true;
  bool _running = false;
  bool _throttled = false;
  int _frameSkipCounter = 0;

  int _reverbCounter = 0;
  static const int _reverbEveryNFrames = 2;

  final ListQueue<AmbientClassification> _classHistory = ListQueue();
  final Map<AcousticEventType, DateTime> _lastEmitAt = {};

  void Function(AcousticEvent event)? onAcousticEvent;
  void Function(ReverbEstimate estimate)? onReverbEstimate;

  bool get isRunning => _running;
  bool get isEnabled => _enabled;
  bool get isStereo => _broker.isStereo;

  Future<void> init() async {
    _classifier = AmbientClassifier();
    _bearingEstimator = StereoBearingEstimator();
    _reverbClassifier = ReverbClassifier();

    await _classifier.init();
    _bearingEstimator.init();
    _reverbClassifier.init();

    if (_enabled) {
      await _startCapture();
    }
  }

  Future<void> _startCapture() async {
    if (_running) return;
    final ok = await _broker.start();
    if (!ok) {
      debugPrint('AcousticWorldModel: audio capture failed to start');
      return;
    }
    _running = true;
    _frameSub = _broker.frames.listen(_onFrame);
    debugPrint(
      'AcousticWorldModel: started (stereo=${_broker.isStereo}, '
      'rate=${_broker.sampleRate})',
    );
  }

  void _onFrame(AudioFrame frame) {
    if (!_enabled || !_running) return;

    if (_throttled) {
      _frameSkipCounter++;
      if (_frameSkipCounter % 2 != 0) return;
    }

    final classification = _classifier.classify(frame);
    if (classification != null) {
      _addToHistory(classification);
      _tryEmitEvent(frame);
    }

    _reverbCounter++;
    if (_reverbCounter >= _reverbEveryNFrames) {
      _reverbCounter = 0;
      final reverb = _reverbClassifier.classify(frame);
      if (reverb != null) {
        onReverbEstimate?.call(reverb);
      }
    }
  }

  void _addToHistory(AmbientClassification classification) {
    _classHistory.addLast(classification);
    while (_classHistory.length > kAwmTemporalFrames) {
      _classHistory.removeFirst();
    }
  }

  void _tryEmitEvent(AudioFrame frame) {
    if (_classHistory.length < 2) return;

    final counts = <BagdarAudioClass, int>{};
    for (final c in _classHistory) {
      counts[c.cls] = (counts[c.cls] ?? 0) + 1;
    }

    BagdarAudioClass? dominantClass;
    int dominantCount = 0;
    double maxConfidence = 0.0;

    counts.forEach((cls, count) {
      if (cls == BagdarAudioClass.unknown ||
          cls == BagdarAudioClass.silence) {
        return;
      }
      if (count >= 2 && count > dominantCount) {
        dominantCount = count;
        dominantClass = cls;
      }
    });

    if (dominantClass == null) return;

    for (final c in _classHistory) {
      if (c.cls == dominantClass && c.confidence > maxConfidence) {
        maxConfidence = c.confidence;
      }
    }

    final eventType = _classToEventType(dominantClass!);
    if (eventType == null) return;

    final cooldown = _cooldownFor(eventType);
    final now = frame.timestamp;
    final lastAt = _lastEmitAt[eventType];
    if (lastAt != null && now.difference(lastAt) < cooldown) return;

    BearingSide? bearing;
    if (_broker.isStereo && _bearingEstimator.isReady) {
      final est = _bearingEstimator.estimate(frame);
      bearing = est?.side;
    }

    final priority = _priorityFor(eventType);

    _lastEmitAt[eventType] = now;
    onAcousticEvent?.call(AcousticEvent(
      type: eventType,
      bearing: bearing,
      confidence: maxConfidence,
      suggestedPriority: priority,
      at: now,
    ));
  }

  static AcousticEventType? _classToEventType(BagdarAudioClass cls) {
    switch (cls) {
      case BagdarAudioClass.vehicle:
      case BagdarAudioClass.trafficFlow:
        return AcousticEventType.vehicleApproaching;
      case BagdarAudioClass.horn:
        return AcousticEventType.hornBlast;
      case BagdarAudioClass.siren:
        return AcousticEventType.sirenNearby;
      case BagdarAudioClass.dog:
        return AcousticEventType.dogNearby;
      case BagdarAudioClass.crowd:
        return AcousticEventType.crowdDense;
      case BagdarAudioClass.construction:
        return AcousticEventType.constructionNearby;
      case BagdarAudioClass.tram:
        return AcousticEventType.tramNearby;
      case BagdarAudioClass.bicycle:
        return AcousticEventType.bicycleNearby;
      case BagdarAudioClass.silence:
      case BagdarAudioClass.wind:
      case BagdarAudioClass.rain:
      case BagdarAudioClass.unknown:
        return null;
    }
  }

  static Duration _cooldownFor(AcousticEventType type) {
    switch (type) {
      case AcousticEventType.vehicleApproaching:
        return kAwmVehicleCooldown;
      case AcousticEventType.hornBlast:
        return kAwmHornCooldown;
      case AcousticEventType.sirenNearby:
        return kAwmSirenCooldown;
      case AcousticEventType.dogNearby:
        return kAwmDogCooldown;
      case AcousticEventType.crowdDense:
        return kAwmCrowdCooldown;
      case AcousticEventType.constructionNearby:
        return kAwmSirenCooldown;
      case AcousticEventType.tramNearby:
        return kAwmVehicleCooldown;
      case AcousticEventType.bicycleNearby:
        return kAwmVehicleCooldown;
    }
  }

  static SpeechPriority _priorityFor(AcousticEventType type) {
    switch (type) {
      case AcousticEventType.hornBlast:
        return SpeechPriority.critical;
      case AcousticEventType.vehicleApproaching:
      case AcousticEventType.sirenNearby:
      case AcousticEventType.tramNearby:
        return SpeechPriority.warning;
      case AcousticEventType.dogNearby:
      case AcousticEventType.crowdDense:
      case AcousticEventType.constructionNearby:
      case AcousticEventType.bicycleNearby:
        return SpeechPriority.info;
    }
  }

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled && !_running) {
      _startCapture();
    } else if (!enabled && _running) {
      _stopCapture();
    }
  }

  void setThrottled(bool throttled) {
    _throttled = throttled;
  }

  Future<void> pause() async {
    await _broker.pause();
  }

  Future<void> resume() async {
    await _broker.resume();
  }

  Future<void> _stopCapture() async {
    _running = false;
    await _frameSub?.cancel();
    _frameSub = null;
    await _broker.stop();
  }

  void reset() {
    _classHistory.clear();
    _lastEmitAt.clear();
    _frameSkipCounter = 0;
    _reverbCounter = 0;
  }

  void dispose() {
    _running = false;
    _enabled = false;
    _frameSub?.cancel();
    _frameSub = null;
    _broker.dispose();
    _classifier.dispose();
    _bearingEstimator.dispose();
    _reverbClassifier.dispose();
    onAcousticEvent = null;
    onReverbEstimate = null;
  }
}

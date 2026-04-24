import 'dart:typed_data';

import '../services/weather_gate.dart';

enum FrameQualityEventType {
  aeTransitionStarted,
  aeTransitionEnded,
  weatherDegraded,
  weatherRecovered,
  cameraBlocked,
  cameraPartiallyBlocked,
  cameraFrozen,
  dropletDetected,
}

class FrameQualityEvent {
  final FrameQualityEventType type;
  final int? frames;
  final double? variance;
  final double? avgLuminosity;
  final int? dirtyRegions;

  const FrameQualityEvent._({
    required this.type,
    this.frames,
    this.variance,
    this.avgLuminosity,
    this.dirtyRegions,
  });

  const FrameQualityEvent.aeStarted()
      : this._(type: FrameQualityEventType.aeTransitionStarted);

  const FrameQualityEvent.aeEnded(int frames)
      : this._(type: FrameQualityEventType.aeTransitionEnded, frames: frames);

  const FrameQualityEvent.weatherDegraded({
    required double variance,
    required double avgLuma,
  }) : this._(
          type: FrameQualityEventType.weatherDegraded,
          variance: variance,
          avgLuminosity: avgLuma,
        );

  const FrameQualityEvent.weatherRecovered({
    required double variance,
    required double avgLuma,
  }) : this._(
          type: FrameQualityEventType.weatherRecovered,
          variance: variance,
          avgLuminosity: avgLuma,
        );

  const FrameQualityEvent.cameraBlocked()
      : this._(type: FrameQualityEventType.cameraBlocked);

  const FrameQualityEvent.partiallyBlocked()
      : this._(type: FrameQualityEventType.cameraPartiallyBlocked);

  const FrameQualityEvent.frozen()
      : this._(type: FrameQualityEventType.cameraFrozen);

  const FrameQualityEvent.droplet(int dirtyRegions)
      : this._(
          type: FrameQualityEventType.dropletDetected,
          dirtyRegions: dirtyRegions,
        );
}

class FrameQualityReport {
  final bool aePipelineFrozen;
  final bool weatherDegraded;
  final List<FrameQualityEvent> events;

  const FrameQualityReport({
    required this.aePipelineFrozen,
    required this.weatherDegraded,
    required this.events,
  });
}

class FrameQualityGuard {
  static const int kLowLuminosityStreak = 45;
  static const double kLuminosityMinValue = 10.0;

  static const int kPartialOcclusionStreak = 20;

  static const double kAeVarianceThreshold = 100.0;
  static const double kAeAvgBrightThreshold = 200.0;
  static const double kAeAvgDarkThreshold = 15.0;
  static const int kAeTransitionMinFrames = 2;
  static const int kAeTransitionMaxFrames = 30;
  static const Duration kAePostTransitionGuard = Duration(milliseconds: 3000);

  static const int kDropletGridSize = 3;
  static const int kDropletGridCount = kDropletGridSize * kDropletGridSize;
  static const double kDropletMinVariance = 50.0;
  static const int kDropletMinStreak = 60;

  static const Duration kFrozenFrameThreshold = Duration(seconds: 5);

  final WeatherGate weatherGate;

  int _lowLuminosityFrames = 0;
  bool _cameraBlockedWarned = false;

  int _partialOcclusionFrames = 0;
  bool _partialOcclusionWarned = false;

  int _aeTransitionFrames = 0;
  DateTime? _aeTransitionEndedAt;

  final List<int> _dropletLowVarStreak =
      List<int>.filled(kDropletGridCount, 0);
  bool _dropletSuspected = false;
  bool _dropletWarned = false;

  int? _lastImageHash;
  late DateTime _lastImageChangeAt;
  bool _cameraFrozenWarned = false;

  FrameQualityGuard({required this.weatherGate, DateTime? initialTime})
      : _lastImageChangeAt = initialTime ?? DateTime.now();

  bool get aeTransitioning =>
      _aeTransitionFrames >= kAeTransitionMinFrames &&
      _aeTransitionFrames <= kAeTransitionMaxFrames;

  bool aePipelineFrozen(DateTime now) {
    if (aeTransitioning) return true;
    final endedAt = _aeTransitionEndedAt;
    if (endedAt == null) return false;
    return now.difference(endedAt) < kAePostTransitionGuard;
  }

  bool get dropletSuspected => _dropletSuspected;
  bool get cameraBlockedWarned => _cameraBlockedWarned;
  bool get cameraFrozenWarned => _cameraFrozenWarned;
  bool get partialOcclusionWarned => _partialOcclusionWarned;
  int get aeTransitionFrames => _aeTransitionFrames;
  int get lowLuminosityFrames => _lowLuminosityFrames;
  List<int> get debugDropletStreaks => List.unmodifiable(_dropletLowVarStreak);

  FrameQualityReport evaluate({
    required Uint8List yPlane,
    required int bytesPerRow,
    required int width,
    required int height,
    required DateTime now,
  }) {
    final events = <FrameQualityEvent>[];
    _runLuminosity(
      yPlane: yPlane,
      bytesPerRow: bytesPerRow,
      width: width,
      height: height,
      now: now,
      events: events,
    );
    _runFrozenFrame(
      yPlane: yPlane,
      bytesPerRow: bytesPerRow,
      width: width,
      height: height,
      now: now,
      events: events,
    );
    return FrameQualityReport(
      aePipelineFrozen: aePipelineFrozen(now),
      weatherDegraded: weatherGate.degraded,
      events: events,
    );
  }

  void _runLuminosity({
    required Uint8List yPlane,
    required int bytesPerRow,
    required int width,
    required int height,
    required DateTime now,
    required List<FrameQualityEvent> events,
  }) {
    if (yPlane.isEmpty) return;

    final w = width;
    final h = height;
    final halfW = w >> 1;
    final halfH = h >> 1;

    double sum = 0;
    double sumSq = 0;
    int count = 0;
    final quadSum = List<double>.filled(4, 0);
    final quadCount = List<int>.filled(4, 0);

    for (int i = 0; i < yPlane.length; i += 100) {
      final v = yPlane[i].toDouble();
      sum += v;
      sumSq += v * v;
      count++;
      final y = i ~/ bytesPerRow;
      final x = i - y * bytesPerRow;
      if (y >= h || x >= w) continue;
      final quad = (y < halfH ? 0 : 2) + (x < halfW ? 0 : 1);
      quadSum[quad] += v;
      quadCount[quad]++;
    }
    if (count == 0) return;

    final avgLuminosity = sum / count;
    final variance = (sumSq / count) - (avgLuminosity * avgLuminosity);

    final isAeTransition = variance < kAeVarianceThreshold &&
        (avgLuminosity > kAeAvgBrightThreshold ||
            avgLuminosity < kAeAvgDarkThreshold);
    if (isAeTransition) {
      if (_aeTransitionFrames == 0) {
        events.add(const FrameQualityEvent.aeStarted());
      }
      _aeTransitionFrames++;
      _aeTransitionEndedAt = null;
    } else {
      if (_aeTransitionFrames >= kAeTransitionMinFrames) {
        _aeTransitionEndedAt = now;
        events.add(FrameQualityEvent.aeEnded(_aeTransitionFrames));
      }
      _aeTransitionFrames = 0;
    }

    if (!isAeTransition) {
      final transition = weatherGate.feed(variance, avgLuminosity);
      switch (transition) {
        case WeatherTransition.degraded:
          events.add(FrameQualityEvent.weatherDegraded(
            variance: variance,
            avgLuma: avgLuminosity,
          ));
          break;
        case WeatherTransition.recovered:
          events.add(FrameQualityEvent.weatherRecovered(
            variance: variance,
            avgLuma: avgLuminosity,
          ));
          break;
        case WeatherTransition.none:
          break;
      }
    }

    if (avgLuminosity < kLuminosityMinValue) {
      _lowLuminosityFrames++;
      if (_lowLuminosityFrames >= kLowLuminosityStreak &&
          !_cameraBlockedWarned) {
        _cameraBlockedWarned = true;
        events.add(const FrameQualityEvent.cameraBlocked());
      }
    } else {
      if (_cameraBlockedWarned) {
        _cameraBlockedWarned = false;
      }
      _lowLuminosityFrames = 0;
    }

    int deadQuads = 0;
    for (int q = 0; q < 4; q++) {
      if (quadCount[q] == 0) continue;
      final avg = quadSum[q] / quadCount[q];
      if (avg < kLuminosityMinValue) deadQuads++;
    }
    final isPartial = deadQuads >= 1 &&
        deadQuads <= 2 &&
        avgLuminosity >= kLuminosityMinValue;
    if (isPartial) {
      _partialOcclusionFrames++;
      if (_partialOcclusionFrames >= kPartialOcclusionStreak &&
          !_partialOcclusionWarned) {
        _partialOcclusionWarned = true;
        events.add(const FrameQualityEvent.partiallyBlocked());
      }
    } else {
      _partialOcclusionFrames = 0;
      if (_partialOcclusionWarned && deadQuads == 0) {
        _partialOcclusionWarned = false;
      }
    }
  }

  void _runFrozenFrame({
    required Uint8List yPlane,
    required int bytesPerRow,
    required int width,
    required int height,
    required DateTime now,
    required List<FrameQualityEvent> events,
  }) {
    final bytes = yPlane;
    if (bytes.length < 10) return;

    final w = width;
    final h = height;
    final rowStride = bytesPerRow;

    final gridCellW = w ~/ kDropletGridSize;
    final gridCellH = h ~/ kDropletGridSize;
    int dirtyRegions = 0;
    final dirtyMask = List<bool>.filled(kDropletGridCount, false);

    for (int gy = 0; gy < kDropletGridSize; gy++) {
      for (int gx = 0; gx < kDropletGridSize; gx++) {
        final gi = gy * kDropletGridSize + gx;
        final yStart = gy * gridCellH;
        final xStart = gx * gridCellW;
        double sum = 0, sqSum = 0;
        int n = 0;
        for (int y = yStart; y < yStart + gridCellH && y < h; y += 8) {
          for (int x = xStart; x < xStart + gridCellW && x < w; x += 8) {
            final idx = y * rowStride + x;
            if (idx >= bytes.length) continue;
            final v = bytes[idx].toDouble();
            sum += v;
            sqSum += v * v;
            n++;
          }
        }
        if (n > 4) {
          final mean = sum / n;
          final variance = (sqSum / n) - mean * mean;
          if (variance < kDropletMinVariance) {
            _dropletLowVarStreak[gi]++;
          } else {
            _dropletLowVarStreak[gi] = 0;
          }
        }
        if (_dropletLowVarStreak[gi] >= kDropletMinStreak) {
          dirtyRegions++;
          dirtyMask[gi] = true;
        }
      }
    }

    _dropletSuspected = dirtyRegions >= 2 && dirtyRegions < kDropletGridCount;
    if (_dropletSuspected && !_dropletWarned) {
      _dropletWarned = true;
      events.add(FrameQualityEvent.droplet(dirtyRegions));
    } else if (!_dropletSuspected && _dropletWarned) {
      _dropletWarned = false;
    }

    int hash = 0;
    final stride = bytes.length ~/ 10;
    for (int i = 0; i < 10; i++) {
      final byteIdx = i * stride;
      if (_dropletSuspected) {
        final px = (byteIdx % rowStride).clamp(0, w - 1);
        final py = (byteIdx ~/ rowStride).clamp(0, h - 1);
        final gx = (px ~/ gridCellW).clamp(0, kDropletGridSize - 1);
        final gy = (py ~/ gridCellH).clamp(0, kDropletGridSize - 1);
        if (dirtyMask[gy * kDropletGridSize + gx]) continue;
      }
      hash = (hash * 31) + bytes[byteIdx];
    }

    if (hash != _lastImageHash) {
      _lastImageHash = hash;
      _lastImageChangeAt = now;
      if (_cameraFrozenWarned) {
        _cameraFrozenWarned = false;
      }
    } else {
      if (now.difference(_lastImageChangeAt) > kFrozenFrameThreshold &&
          !_cameraFrozenWarned) {
        _cameraFrozenWarned = true;
        events.add(const FrameQualityEvent.frozen());
      }
    }
  }
}

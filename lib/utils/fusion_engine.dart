import 'dart:collection';

import '../models/constants.dart';
import 'depth_hazard.dart';

class FusionEngine {
  static const double kCriticalThreshold = kFusionCriticalScore;
  static const double kWarningThreshold = kFusionWarningScore;

  final Map<int, ListQueue<double>> _history = {};
  final Map<int, double> _emaScore = {};
  DateTime _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWarningAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastDeadZoneAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastZoneIdx;

  FusionResult? evaluate({
    required DepthHazard hazard,
    double yoloHazardConf = 0.0,
    required DateTime now,
  }) {
    final zoneIdx = hazard.zone.index;

    if (_lastZoneIdx != null && _lastZoneIdx != zoneIdx) {
      _history.clear();
      _emaScore.clear();
    }
    _lastZoneIdx = zoneIdx;

    final fusionScore = (hazard.midasScore + yoloHazardConf.clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
    final previousEma = _emaScore[zoneIdx] ?? fusionScore;
    final emaScore =
        (kFusionEmaAlpha * fusionScore + (1.0 - kFusionEmaAlpha) * previousEma)
            .clamp(0.0, 1.0);
    _emaScore[zoneIdx] = emaScore;

    final hist = _history.putIfAbsent(zoneIdx, () => ListQueue<double>());
    hist.addLast(emaScore);
    if (hist.length > kFusionTemporalFrames) {
      hist.removeFirst();
    }

    final isDeadZone = hazard.type == DepthHazardType.deadZone;

    if (isDeadZone && emaScore >= kFusionWarningScore) {
      if (now.difference(_lastDeadZoneAt) < kHazardDeadZoneCooldown) {
        return null;
      }
      _lastDeadZoneAt = now;
      return FusionResult(
        level: emaScore >= kFusionCriticalScore
            ? AlertLevel.critical
            : AlertLevel.warning,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    if (emaScore >= kFusionCriticalScore &&
        hist.length >= kFusionTemporalFrames &&
        hist.every((s) => s >= kFusionCriticalScore)) {
      if (now.difference(_lastCriticalAt) < kHazardCriticalCooldown) {
        return null;
      }
      _lastCriticalAt = now;
      _lastWarningAt = now;
      return FusionResult(
        level: AlertLevel.critical,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    if (emaScore >= kFusionWarningScore) {
      if (now.difference(_lastWarningAt) < kHazardWarningCooldown) return null;
      _lastWarningAt = now;
      return FusionResult(
        level: AlertLevel.warning,
        fusionScore: emaScore,
        hazard: hazard,
        stableFrames: hist.length,
      );
    }

    return null;
  }

  void reset() {
    _history.clear();
    _emaScore.clear();
    _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastWarningAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastDeadZoneAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

enum AlertLevel { warning, critical }

class FusionResult {
  final AlertLevel level;
  final double fusionScore;
  final DepthHazard hazard;
  final int stableFrames;

  const FusionResult({
    required this.level,
    required this.fusionScore,
    required this.hazard,
    required this.stableFrames,
  });
}

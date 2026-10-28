import '../../tracker/generic_obstacle_tracker.dart';
import 'camera_fast_motion_types.dart';

/// Diagnostic attribution plus additive metric evidence; never an absence gate.
class SeparatedMotionRisk {
  static Map<String, Object?> track(GenericObstacleTrack t) => {
    'trackId': t.id,
    'relativeTrend': t.approachTrend(),
    'relativeTrendIsMetric': false,
    'relativeHypothesis': t.approachTrend() > 0,
    'explicitApproachMps': t.last.approachRateMps,
    'metricTrackClosingMps': t.metricVelocityMps(),
    'timeToCollisionS': t.last.timeToCollisionS,
    'semanticRiskPresent': t.last.semantic != null,
    'currentlyObserved': t.misses == 0,
    'mayDropRelativeHypothesis': false,
  };

  static Map<String, Object?> frame(
    List<GenericObstacleTrack> tracks,
    FastMetricMotionResult motion,
    int nowUs,
  ) => {
    'tracks': tracks.map(track).toList(),
    'metricEvidenceLive': motion.isLiveAt(nowUs),
    'positiveBodyRelativeRisk': motion.isLiveAt(nowUs) && motion.addsMotionRisk,
    'wholeObjectStationarityCertified': false,
    'relativeHypothesisResolved': false,
    'freeSpaceCertified': false,
  };
}

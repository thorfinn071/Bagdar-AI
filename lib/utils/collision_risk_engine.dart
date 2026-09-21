import '../models/depth_frame.dart';
import '../models/generic_obstacle.dart';
import '../models/generic_obstacle_mode.dart';
import '../services/fall_detector.dart' show MotionState;
import '../tracker/generic_obstacle_tracker.dart';
import '../tracker/tracker.dart' show isVehicle;
import '../utils/depth_hazard.dart';

/// Rule-based, inspectable collision risk. YOLO never lowers geometric risk.
class CollisionRiskEngine {
  CollisionRiskEngine({GenericObstacleConfig? config})
    : config = config ?? GenericObstacleConfig.engineeringDefaults;

  final GenericObstacleConfig config;

  CollisionRiskDecision evaluate({
    required GenericObstacleTrack track,
    required DepthHealth health,
    required MotionState motion,
    required GenericObstacleMode mode,
    required bool relative,
    SemanticMatch? semantic,
  }) {
    final obs = track.last.copyWith(semantic: semantic ?? track.last.semantic);
    final inputs = <String, Object?>{
      'trackId': track.id,
      'hits': track.hits,
      'confirmed': track.confirmed,
      'proximity': obs.relativeProximity,
      'overlap': obs.corridorOverlap,
      'geometry': obs.geometry.name,
      'zone': obs.zone.name,
      'quality': health.components.combined,
      'capability': health.capability.name,
      'relative': relative,
      'motion': motion.name,
      'mode': mode.name,
      'semantic': semantic?.label,
      'semanticConf': semantic?.confidence,
      'edgeOnly': obs.edgeOnly,
      'nearestM': obs.nearestDistanceM,
      'approachTrend': track.approachTrend(),
    };

    if (mode == GenericObstacleMode.off) {
      return CollisionRiskDecision(
        level: null,
        ruleId: 'mode_off',
        inputs: inputs,
        speechKey: '',
        observation: obs,
        emitUserAlert: false,
      );
    }

    if (!health.genericObstacleAvailable ||
        health.capability == DepthCapability.unalignedOrStale ||
        health.capability == DepthCapability.providerUnavailable ||
        health.capability == DepthCapability.temporarilyLowConfidence) {
      return CollisionRiskDecision(
        level: null,
        ruleId: 'depth_unreliable',
        inputs: inputs,
        speechKey: 'spatial_analysis_limited',
        observation: obs,
        emitUserAlert: false,
      );
    }

    if (obs.edgeOnly) {
      return CollisionRiskDecision(
        level: ObstacleRiskLevel.monitor,
        ruleId: 'edge_only_monitor',
        inputs: inputs,
        speechKey: 'generic_obstacle_ahead',
        observation: obs,
        emitUserAlert: false,
      );
    }

    if (!track.confirmed) {
      return CollisionRiskDecision(
        level: ObstacleRiskLevel.monitor,
        ruleId: 'awaiting_n_of_m',
        inputs: inputs,
        speechKey: 'generic_obstacle_ahead',
        observation: obs,
        emitUserAlert: false,
      );
    }

    final receding = track.approachTrend() <= -config.recedeProximityDelta;
    if (receding && motion != MotionState.stationary) {
      return CollisionRiskDecision(
        level: ObstacleRiskLevel.monitor,
        ruleId: 'receding_suppress',
        inputs: inputs,
        speechKey: 'generic_obstacle_ahead',
        observation: obs,
        emitUserAlert: false,
      );
    }

    var level = _baseLevel(obs, relative, track, motion);
    var ruleId = 'geometry_${obs.geometry.name}_${level?.name ?? 'none'}';

    if (relative && level == ObstacleRiskLevel.critical) {
      final centered =
          obs.zone == HazardZone.center ||
          obs.zone == HazardZone.centerLeft ||
          obs.zone == HazardZone.centerRight;
      final strongNear =
          obs.relativeProximity >= config.criticalProximity &&
          obs.corridorOverlap >= 0.20 &&
          track.hits >= config.confirmNeedRelative;
      if (!centered || !strongNear) {
        level = ObstacleRiskLevel.warning;
        ruleId = 'relative_critical_gate';
      }
    }

    // YOLO absence does not reduce [level]. A matched vehicle may raise it
    // after the relative-only critical gate.
    if (semantic != null &&
        semantic.confidence >= config.semanticMinConf &&
        isVehicle(semantic.label)) {
      if (level == ObstacleRiskLevel.warning ||
          level == ObstacleRiskLevel.monitor) {
        level = ObstacleRiskLevel.critical;
        ruleId = 'semantic_vehicle_raise';
      }
    }

    if (level == null || level == ObstacleRiskLevel.monitor) {
      return CollisionRiskDecision(
        level: level,
        ruleId: ruleId,
        inputs: inputs,
        speechKey: 'generic_obstacle_ahead',
        observation: obs,
        emitUserAlert: false,
      );
    }

    final speakSemantic =
        semantic != null && semantic.confidence >= config.semanticMinConf;
    final speechKey = _speechKey(obs, level, speakSemantic ? semantic : null);
    final speakDistance =
        obs.nearestDistanceM != null &&
        !relative &&
        level == ObstacleRiskLevel.critical;

    return CollisionRiskDecision(
      level: level,
      ruleId: ruleId,
      inputs: inputs,
      speechKey: speechKey,
      observation: obs,
      emitUserAlert: mode == GenericObstacleMode.assistive,
      speakDistance: speakDistance,
      spokenSemantic: speakSemantic ? semantic : null,
    );
  }

  ObstacleRiskLevel? _baseLevel(
    GenericObstacleObservation obs,
    bool relative,
    GenericObstacleTrack track,
    MotionState motion,
  ) {
    if (obs.geometry == ObstacleGeometry.overhead &&
        obs.relativeProximity >= config.warningProximity) {
      return obs.relativeProximity >= config.criticalProximity
          ? ObstacleRiskLevel.critical
          : ObstacleRiskLevel.warning;
    }

    final approaching = track.approachTrend() >= config.approachProximityDelta;
    var p = obs.relativeProximity;
    if (approaching) p += 0.05;
    if (obs.zone == HazardZone.center) p += 0.04;
    if (motion == MotionState.running) p += 0.05;
    if (obs.geometry == ObstacleGeometry.thinVertical) {
      // Thin poles: require corridor intersection already encoded in overlap.
      if (obs.corridorOverlap < config.poleMinCorridorOverlap) {
        return ObstacleRiskLevel.monitor;
      }
    }

    if (p >= config.criticalProximity && obs.corridorOverlap >= 0.12) {
      return ObstacleRiskLevel.critical;
    }
    if (p >= config.warningProximity && obs.corridorOverlap >= 0.06) {
      return ObstacleRiskLevel.warning;
    }
    if (p >= config.monitorProximity) return ObstacleRiskLevel.monitor;
    return null;
  }

  String _speechKey(
    GenericObstacleObservation obs,
    ObstacleRiskLevel level,
    SemanticMatch? semantic,
  ) {
    if (obs.geometry == ObstacleGeometry.overhead) {
      return 'generic_obstacle_overhead';
    }
    if (semantic != null && isVehicle(semantic.label)) {
      if (obs.zone == HazardZone.left || obs.zone == HazardZone.centerLeft) {
        return 'generic_vehicle_left';
      }
      if (obs.zone == HazardZone.right || obs.zone == HazardZone.centerRight) {
        return 'generic_vehicle_right';
      }
      return 'generic_vehicle_ahead';
    }
    if (obs.zone == HazardZone.left || obs.zone == HazardZone.centerLeft) {
      return 'generic_obstacle_left';
    }
    if (obs.zone == HazardZone.right || obs.zone == HazardZone.centerRight) {
      return 'generic_obstacle_right';
    }
    if (level == ObstacleRiskLevel.critical) {
      return 'generic_obstacle_stop';
    }
    return 'generic_obstacle_ahead';
  }
}

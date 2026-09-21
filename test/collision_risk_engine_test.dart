import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/models/generic_obstacle_mode.dart';
import 'package:bagdar/services/fall_detector.dart' show MotionState;
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/collision_risk_engine.dart';
import 'package:bagdar/utils/depth_hazard.dart';

GenericObstacleTrack _track({
  required double proximity,
  required int hits,
  bool receding = false,
  ObstacleGeometry geom = ObstacleGeometry.broadSurface,
  HazardZone zone = HazardZone.center,
  bool confirmed = true,
  SemanticMatch? semantic,
}) {
  final hist = receding
      ? <double>[proximity + 0.2, proximity]
      : <double>[proximity - 0.1, proximity];
  final obs = GenericObstacleObservation(
    trackId: 1,
    geometry: geom,
    zone: zone,
    normalizedBounds: const Rect.fromLTWH(0.3, 0.3, 0.4, 0.5),
    corridorOverlap: 0.6,
    confidence: 0.8,
    relativeProximity: proximity,
    source: DepthProviderKind.ncnnRelative,
    semantic: semantic,
    pixelCount: 100,
  );
  return GenericObstacleTrack(
    id: 1,
    last: obs,
    hits: hits,
    misses: 0,
    age: hits,
    proximityHist: hist,
    metricHist: <double?>[null, null],
    timestampUsHist: <int>[0, 800000],
    confirmed: confirmed,
  );
}

DepthHealth get _healthy => const DepthHealth(
  capability: DepthCapability.healthyRelative,
  components: DepthHealthComponents(
    validCoverage: 0.8,
    dynamicRange: 0.7,
    temporalStability: 0.7,
    blurLightGate: 1,
    providerState: 1,
  ),
  genericObstacleAvailable: true,
  provider: DepthProviderKind.ncnnRelative,
);

void main() {
  final engine = CollisionRiskEngine();

  test('YOLO absence does not reduce geometric warning', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.7, hits: 4),
      health: _healthy,
      motion: MotionState.walking,
      mode: GenericObstacleMode.assistive,
      relative: true,
      semantic: null,
    );
    expect(d.level, isNot(ObstacleRiskLevel.monitor));
    expect(d.emitUserAlert, isTrue);
    expect(d.spokenSemantic, isNull);
  });

  test('receding suppresses critical/warning', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.7, hits: 4, receding: true),
      health: _healthy,
      motion: MotionState.walking,
      mode: GenericObstacleMode.assistive,
      relative: true,
    );
    expect(d.ruleId, 'receding_suppress');
    expect(d.emitUserAlert, isFalse);
  });

  test('low-quality depth never creates a critical alert', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.95, hits: 5),
      health: const DepthHealth(
        capability: DepthCapability.temporarilyLowConfidence,
        components: DepthHealthComponents(
          validCoverage: 0.3,
          dynamicRange: 0.1,
          temporalStability: 0.2,
          blurLightGate: 0.1,
          providerState: 1,
        ),
        genericObstacleAvailable: false,
        provider: DepthProviderKind.ncnnRelative,
        rejectionReason: 'ncnn_frame_quality',
      ),
      motion: MotionState.walking,
      mode: GenericObstacleMode.assistive,
      relative: true,
    );
    expect(d.level, isNull);
    expect(d.emitUserAlert, isFalse);
  });

  test('shadow mode logs but does not emit user alerts', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.9, hits: 5),
      health: _healthy,
      motion: MotionState.walking,
      mode: GenericObstacleMode.shadow,
      relative: true,
    );
    expect(d.level, isNotNull);
    expect(d.emitUserAlert, isFalse);
  });

  test('matched vehicle may raise urgency; label only above threshold', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.65, hits: 4),
      health: _healthy,
      motion: MotionState.walking,
      mode: GenericObstacleMode.assistive,
      relative: true,
      semantic: const SemanticMatch(
        yoloTrackId: 3,
        label: 'car',
        confidence: 0.8,
      ),
    );
    expect(d.ruleId, 'semantic_vehicle_raise');
    expect(d.spokenSemantic?.label, 'car');
  });

  test('relative critical requires centered near-field evidence', () {
    final d = engine.evaluate(
      track: _track(proximity: 0.9, hits: 4, zone: HazardZone.left),
      health: _healthy,
      motion: MotionState.walking,
      mode: GenericObstacleMode.assistive,
      relative: true,
    );
    expect(d.level, ObstacleRiskLevel.warning);
    expect(d.ruleId, 'relative_critical_gate');
  });
}

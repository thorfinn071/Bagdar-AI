import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/safety/world/scene_fusion_policy.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:flutter_test/flutter_test.dart';

CameraMetricMotionResult motion() => CameraMetricMotionResult(
  reason: 'visible_patch_intervals',
  sessionGeneration: 1,
  frameId: 2,
  capturedAtUs: 1200000,
  oldestEvidenceTimestampUs: 1000000,
  validUntilUs: 1300000,
  transformId: 'optical',
  candidates: 3,
  unknownPatches: 0,
  patches: [
    for (var i = 0; i < 3; i++)
      MetricPatchMotion(
        previousPixel: [i, 0],
        currentPixel: [i, 1],
        positionLowerM: [0, 2, 1],
        positionUpperM: [.02, 2.02, 1.02],
        velocityLowerMps: [-1, 0, 0],
        velocityUpperMps: [-.8, .1, .1],
        classification: VisiblePatchMotion.lateral,
        possibleBodyIntersection: true,
      ),
  ],
);
LocalSceneUpdate update(int at, {bool existingRisk = false}) =>
    LocalSceneUpdate(
      coordinateMode: SceneCoordinateMode.relative,
      at: DateTime.fromMicrosecondsSinceEpoch(at),
      validUntil: DateTime.fromMicrosecondsSinceEpoch(at + 400000),
      poseQuality: 1,
      sensorHealth: SceneSensorHealth({'geometry': SceneSensorState.healthy}),
      useIndependentEvidenceClocks: true,
      evidence: [
        SpatialEvidence(
          elementId: 'forward',
          coordinateMode: SceneCoordinateMode.relative,
          sourceId: 'geometry',
          source: SpatialEvidenceSource.geometry,
          observedAt: DateTime.fromMicrosecondsSinceEpoch(at),
          validUntil: DateTime.fromMicrosecondsSinceEpoch(at + 400000),
          observedFraction: 1,
          confidence: 1,
          occupancyProbability: existingRisk ? .9 : null,
          unknownProbability: existingRisk ? .8 : null,
          movingThreatRisk: existingRisk ? .8 : null,
        ),
      ],
    );
void set(CameraMetricMotionShadowScene scene, {int frame = 2}) =>
    scene.setMotion(
      motion(),
      sessionGeneration: 1,
      frameId: frame,
      capturedAtUs: 1200000,
      transformId: 'optical',
    );

void main() {
  test('metric lateral risk reaches scene without positive coverage', () {
    final scene = CameraMetricMotionShadowScene();
    set(scene);
    final result = scene.update(update(1202000));
    expect(result.accepted, true);
    expect(
      result.snapshot.polarSectors
          .firstWhere((e) => e.id == 'forward')
          .movingThreatRisk,
      greaterThan(.5),
    );
    expect(result.snapshot.movingThreats.single.intersectionRisk, .9);
    final planner = GuidanceStateMachine();
    final decision = planner.evaluate(
      RelativePolarGrid.fromSnapshot(
        result.snapshot,
        orientationValid: true,
        userMoving: true,
      ),
      now: DateTime.fromMicrosecondsSinceEpoch(1202000),
    );
    expect(decision.action.kind, SafetyActionKind.stopNow);
    expect(decision.action.ruleId, 'SPATIAL-P0-IMMINENT');
  });
  test('mismatched and expired motion is not applied', () {
    final scene = CameraMetricMotionShadowScene();
    set(scene, frame: 3);
    expect(scene.update(update(1202000)).snapshot.movingThreats, isEmpty);
    set(scene);
    expect(scene.update(update(1300001)).snapshot.movingThreats, isEmpty);
  });
  test('motion cannot remove physical risk or unknown history', () {
    final scene = CameraMetricMotionShadowScene();
    scene.update(update(1190000, existingRisk: true));
    set(scene);
    final forward = scene
        .update(update(1202000))
        .snapshot
        .polarSectors
        .firstWhere((e) => e.id == 'forward');
    expect(forward.occupancyProbability, greaterThan(.5));
    expect(forward.unknownProbability, greaterThan(.5));
    expect(forward.movingThreatRisk, greaterThan(.5));
  });
  test('reset and single use prevent carrying authority into a new frame', () {
    final scene = CameraMetricMotionShadowScene();
    set(scene);
    scene.reset();
    expect(scene.update(update(1202000)).snapshot.movingThreats, isEmpty);
    set(scene);
    scene.update(update(1203000));
    expect(scene.update(update(1204000)).snapshot.movingThreats, isEmpty);
  });
}

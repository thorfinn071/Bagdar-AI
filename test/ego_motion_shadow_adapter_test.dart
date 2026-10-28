import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/runtime/ego_motion_shadow_adapter.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'camera_ego_motion_test.dart' as ego;
import 'camera_fast_motion_test.dart' as fast;
import 'camera_scale_metric_motion_contract_test.dart' as fixture;
import 'camera_metric_motion_shadow_scene_test.dart' as base;

void main() {
  for (final fault in [
    'none',
    'frame',
    'session',
    'capture',
    'transform',
    'stale',
  ]) {
    test('additive scene binding: $fault', () {
      final source = ego.source(), scene = CameraMetricMotionShadowScene();
      ego.observe(source, fast.capture(fixture.input(1)));
      final input = fast.capture(fixture.input(2, axis: 2.4));
      final evidence = ego.observe(
        source,
        input,
        walkingPose: ego.pose(input, origin: [0, .1, 0]),
      );
      final at = fault == 'stale' ? 1300001 : 1202000;
      final added = applyEgoMotionShadow(
        evidence,
        scene,
        sessionGeneration: fault == 'session' ? 2 : 1,
        frameId: fault == 'frame' ? 3 : 2,
        capturedAtUs: fault == 'capture' ? 1200001 : 1200000,
        transformId: fault == 'transform' ? 'foreign' : 'optical',
        nowUs: at,
      );
      expect(added, fault == 'none');
      final result = scene.update(base.update(at));
      expect(result.snapshot.movingThreats.isNotEmpty, fault == 'none');
      if (fault == 'none') {
        final decision = GuidanceStateMachine().evaluate(
          RelativePolarGrid.fromSnapshot(
            result.snapshot,
            orientationValid: true,
            userMoving: true,
          ),
          now: DateTime.fromMicrosecondsSinceEpoch(at),
        );
        expect(decision.action.kind, SafetyActionKind.stopNow);
        expect(
          scene.update(base.update(at + 1000)).snapshot.movingThreats,
          isEmpty,
        );
      }
    });
  }
  test(
    'stationary or missing motion cannot remove risk or unknown history',
    () {
      final scene = CameraMetricMotionShadowScene(), source = ego.source();
      scene.update(base.update(1190000, existingRisk: true));
      ego.observe(source, fast.capture(fixture.input(1)));
      final input = fast.capture(fixture.input(2));
      final stationary = ego.observe(source, input);
      expect(
        applyEgoMotionShadow(
          stationary,
          scene,
          sessionGeneration: 1,
          frameId: 2,
          capturedAtUs: 1200000,
          transformId: 'optical',
          nowUs: 1202000,
        ),
        false,
      );
      final forward = scene
          .update(base.update(1202000))
          .snapshot
          .polarSectors
          .firstWhere((e) => e.id == 'forward');
      expect(forward.occupancyProbability, greaterThan(.5));
      expect(forward.unknownProbability, greaterThan(.5));
      expect(forward.movingThreatRisk, greaterThan(.5));
      final missing = source.observe(
        fast.capture(fixture.input(3)),
        pose: null,
        nowUs: 1402000,
      );
      expect(
        applyEgoMotionShadow(
          missing,
          scene,
          sessionGeneration: 1,
          frameId: 3,
          capturedAtUs: 1400000,
          transformId: 'optical',
          nowUs: 1402000,
        ),
        false,
      );
    },
  );
}

import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_cached_scale_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_scale_metric_motion.dart';
import 'package:bagdar/safety/runtime/camera_processing_age_gate.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import 'camera_scale_metric_motion_contract_test.dart' as fixture;
import 'camera_metric_motion_shadow_scene_test.dart' as scene_fixture;

CameraMetricMotionResult packet(CameraMetricMotionInput input, {int? until}) {
  final f = input.camera.depth;
  return CameraMetricMotionResult(
    reason: 'test-visible-threat',
    sessionGeneration: f.sessionGeneration,
    frameId: f.frameId,
    capturedAtUs: f.capturedAtUs,
    oldestEvidenceTimestampUs: f.capturedAtUs - 200000,
    validUntilUs: until ?? f.capturedAtUs + 100000,
    transformId: f.transformId,
    candidates: 3,
    unknownPatches: 0,
    patches: scene_fixture.motion().patches,
  );
}

void main() {
  test(
    'cached source preserves frozen behavior on invalid and ambiguous inputs',
    () {
      final cases = <CameraMetricMotionInput>[
        fixture.input(2),
        fixture.input(2, plain: true),
        fixture.input(2, repeated: true),
        fixture.input(2, missing: true),
        fixture.input(2, unbounded: true),
        fixture.input(2, conflict: true),
        fixture.input(2, healthy: false),
        fixture.input(2, pose: 0),
        fixture.input(2, mismatch: true),
        fixture.input(2, session: 2),
        fixture.input(2, transform: 'changed'),
        fixture.input(2, provider: 'changed'),
        fixture.input(2, cameraId: 'changed'),
        fixture.input(2, distortedPose: true),
        fixture.input(2, positionError: double.nan),
        fixture.input(2, rgbFrameDelta: 1),
        fixture.input(2, rgbTimestampDelta: 1),
      ];
      for (final input in cases) {
        final cached = CameraCachedScaleMetricMotionSource(
          calibration: fixture.calibration,
          relativeModelHash: 'relative',
        );
        final frozen = CameraScaleMetricMotionSource(
          calibration: fixture.calibration,
          relativeModelHash: 'relative',
        );
        cached.observe(fixture.input(1), nowUs: 1002000);
        frozen.observe(fixture.input(1), nowUs: 1002000);
        expect(
          cached.observe(input, nowUs: 1202000).toDiagnosticMap(),
          frozen.observe(input, nowUs: 1202000).toDiagnosticMap(),
        );
      }
    },
  );
  for (final delay in [0, 97999, 98000, 98001, 200000]) {
    test('completion age at 2000+$delay us respects 100 ms boundary', () {
      var now = 1202000, invalidations = 0;
      final gate = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) {
          now += delay;
          return packet(input);
        },
        invalidateProducer: () => invalidations++,
      )..beginSession(1);
      final outcome = gate.process(fixture.input(2));
      final live = delay <= 98000;
      expect(outcome.admitted, live);
      expect(outcome.result?.addsMotionRisk, live ? true : null);
      expect(invalidations, live ? 1 : 2);
      expect(gate.release(outcome).admitted, live);
    });
  }
  test('expired on entry skips compute; future and clock rollback reject', () {
    var now = 1300001, calls = 0;
    final gate = CameraProcessingAgeGate(
      clockUs: () => now,
      compute: (input, {required nowUs}) {
        calls++;
        return packet(input);
      },
      invalidateProducer: () {},
    )..beginSession(1);
    expect(
      gate.process(fixture.input(2)).status,
      CameraProcessingStatus.expiredBeforeCompute,
    );
    expect(calls, 0);
    now = 1299999;
    expect(
      gate.process(fixture.input(3)).status,
      CameraProcessingStatus.rejectedClock,
    );
    now = 1500000;
    expect(
      gate.process(fixture.input(4)).status,
      CameraProcessingStatus.rejectedClock,
    );
    expect(calls, 0);
  });
  test('clock rollback during compute removes fresh-looking result', () {
    var now = 1202000;
    final gate = CameraProcessingAgeGate(
      clockUs: () => now,
      compute: (input, {required nowUs}) {
        now--;
        return packet(input);
      },
      invalidateProducer: () {},
    )..beginSession(1);
    expect(
      gate.process(fixture.input(2)).status,
      CameraProcessingStatus.rejectedClock,
    );
  });
  test('a live completion can expire awaiting dispatch and is single use', () {
    var now = 1202000;
    final gate = CameraProcessingAgeGate(
      clockUs: () => now,
      compute: (input, {required nowUs}) => packet(input),
      invalidateProducer: () {},
    )..beginSession(1);
    final result = gate.process(fixture.input(2));
    now = 1300001;
    expect(
      gate.release(result).status,
      CameraProcessingStatus.expiredBeforeDispatch,
    );
    now = 1402000;
    final fresh = gate.release(gate.process(fixture.input(3)));
    expect(fresh.admitted, true);
    expect(gate.release(fresh).admitted, false);
  });
  test('oldest timestamp expiry cannot be extended by producer', () {
    var now = 1202000;
    final gate = CameraProcessingAgeGate(
      clockUs: () => now,
      compute: (input, {required nowUs}) => packet(input, until: 1300001),
      invalidateProducer: () {},
    )..beginSession(1);
    expect(
      gate.process(fixture.input(2)).status,
      CameraProcessingStatus.rejectedIdentity,
    );
  });
  test(
    'session change inside compute and provider invalidation revoke handle',
    () {
      var now = 1202000;
      late CameraProcessingAgeGate gate;
      gate = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) {
          gate.beginSession(2);
          return packet(input);
        },
        invalidateProducer: () {},
      )..beginSession(1);
      expect(
        gate.process(fixture.input(2)).status,
        CameraProcessingStatus.rejectedSession,
      );
      gate = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) => packet(input),
        invalidateProducer: () {},
      )..beginSession(1);
      final outcome = gate.process(fixture.input(2));
      gate.invalidate();
      expect(gate.release(outcome).admitted, false);
    },
  );
  test(
    'reorder, duplicate, incompatible headers and compute exception fail closed',
    () {
      var now = 1202000;
      final gate = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) => packet(input),
        invalidateProducer: () {},
      )..beginSession(1);
      gate.process(fixture.input(2));
      expect(
        gate.process(fixture.input(2)).status,
        CameraProcessingStatus.rejectedOrder,
      );
      expect(
        gate.process(fixture.input(1)).status,
        CameraProcessingStatus.rejectedOrder,
      );
      now = 1402000;
      expect(
        gate.process(fixture.input(3, rgbFrameDelta: 1)).status,
        CameraProcessingStatus.rejectedIdentity,
      );
      final broken = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) =>
            throw StateError('compute failure'),
        invalidateProducer: () {},
      )..beginSession(1);
      expect(
        broken.process(fixture.input(3)).status,
        CameraProcessingStatus.computeFailed,
      );
    },
  );
  test('completion overrun invalidates actual source pair before recovery', () {
    var now = 1002000, delay = 0;
    final source = CameraCachedScaleMetricMotionSource(
      calibration: fixture.calibration,
      relativeModelHash: 'relative',
    );
    final gate = CameraProcessingAgeGate(
      clockUs: () => now,
      compute: (input, {required nowUs}) {
        final result = source.observe(input, nowUs: nowUs);
        now += delay;
        return result;
      },
      invalidateProducer: source.invalidate,
    )..beginSession(1);
    expect(
      gate.release(gate.process(fixture.input(1))).result!.reason,
      'new_pair_required',
    );
    now = 1202000;
    delay = 100000;
    expect(gate.process(fixture.input(2)).admitted, false);
    now = 1402000;
    delay = 0;
    expect(
      gate.release(gate.process(fixture.input(3))).result!.reason,
      'new_pair_required',
    );
    now = 1602000;
    expect(
      gate.release(gate.process(fixture.input(4))).result!.available,
      true,
    );
  });
  test(
    'expired positive motion never reaches real scene; existing risks persist',
    () {
      var now = 1202000;
      final gate = CameraProcessingAgeGate(
        clockUs: () => now,
        compute: (input, {required nowUs}) {
          now += 100000;
          return packet(input);
        },
        invalidateProducer: () {},
      )..beginSession(1);
      final result = gate.release(gate.process(fixture.input(2)));
      final scene = CameraMetricMotionShadowScene();
      scene.update(scene_fixture.update(1190000, existingRisk: true));
      if (result.admitted) {
        scene.setMotion(
          result.result!,
          sessionGeneration: 1,
          frameId: 2,
          capturedAtUs: 1200000,
          transformId: 'optical',
        );
      }
      final snapshot = scene
          .update(scene_fixture.update(now, existingRisk: true))
          .snapshot;
      expect(
        snapshot.movingThreats.any((e) => e.id.startsWith('visible-motion')),
        false,
      );
      final forward = snapshot.polarSectors.firstWhere(
        (e) => e.id == 'forward',
      );
      expect(forward.unknownProbability, greaterThan(.5));
      expect(forward.occupancyProbability, greaterThan(.5));
      final decision = GuidanceStateMachine().evaluate(
        RelativePolarGrid.fromSnapshot(
          snapshot,
          orientationValid: true,
          userMoving: true,
        ),
        now: DateTime.fromMicrosecondsSinceEpoch(now),
      );
      expect(decision.action.kind, SafetyActionKind.stopNow);
    },
  );
  test(
    'latest queue stays bounded, drops overwritten frames, preserves capture clocks',
    () {
      final queue = CameraLatestFrameQueue()..beginSession(1);
      for (var frame = 1; frame <= 4; frame++) {
        expect(queue.offer(fixture.input(frame), nowUs: 1602000), true);
        expect(queue.pendingCount, 1);
      }
      expect(queue.replacedFrames, 3);
      final input = queue.takeLatest(nowUs: 1602000)!;
      expect(input.camera.depth.frameId, 4);
      expect(input.camera.depth.capturedAtUs, 1600000);
      expect(queue.pendingCount, 0);
      expect(queue.offer(fixture.input(4), nowUs: 1602000), false);
      expect(queue.offer(fixture.input(5), nowUs: 1602000), false);
      expect(queue.offer(fixture.input(5), nowUs: 1800000), true);
      expect(queue.takeLatest(nowUs: 1900001), isNull);
      expect(queue.expiredFrames, 1);
      queue.offer(fixture.input(6), nowUs: 2002000);
      queue.endSession();
      expect(queue.takeLatest(nowUs: 2002000), isNull);
      expect(queue.offer(fixture.input(7), nowUs: 2202000), false);
    },
  );
  test('dropped frames cannot bridge a pair gap above 300 ms', () {
    final source = CameraCachedScaleMetricMotionSource(
      calibration: fixture.calibration,
      relativeModelHash: 'relative',
    );
    source.observe(fixture.input(1), nowUs: 1002000);
    expect(
      source.observe(fixture.input(3), nowUs: 1402000).reason,
      'incompatible_pair_or_interval',
    );
  });
}

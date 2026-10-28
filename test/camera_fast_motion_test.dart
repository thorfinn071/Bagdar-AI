import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_worker.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_shadow_adapter.dart';
import 'package:bagdar/safety/runtime/camera_metric_motion_shadow_scene.dart';
import 'package:bagdar/safety/planning/guidance_state_machine.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/relative_polar_grid.dart';
import 'camera_scale_metric_motion_contract_test.dart' as fixture;
import 'camera_metric_motion_shadow_scene_test.dart' as scene;

const rgbContract = FastRgbContract(
  providerId: 'capture',
  revision: 'v1',
  preprocessId: 'rgb-u8',
);
FastMetricMotionInput capture(
  CameraMetricMotionInput input, {
  String provider = 'capture',
  String revision = 'v1',
  bool healthy = true,
  double confidence = 1,
  int producedDelta = 0,
}) {
  final c = input.camera, h = c.rgbHeader, g = c.imageGeometry;
  return FastMetricMotionInput(
    camera: FastCameraInput(
      depth: c.depth,
      rgbHeader: FastRgbHeader(
        providerId: provider,
        revision: revision,
        preprocessId: 'rgb-u8',
        transformId: h.transformId,
        sessionGeneration: h.sessionGeneration,
        frameId: h.frameId,
        sourceTimestampUs: h.sourceTimestampUs,
        producedAtUs: h.producedAtUs + producedDelta,
        healthy: healthy,
        confidence: confidence,
      ),
      imageGeometry: FastRgbGeometry(
        cameraId: g.cameraId,
        width: g.width,
        height: g.height,
        fx: g.fx,
        fy: g.fy,
        cx: g.cx,
        cy: g.cy,
        rotation: g.rotation,
        originM: g.originM,
      ),
    ),
    rgb: input.rgb,
    positionErrorM: input.positionErrorM,
    angularErrorRad: input.angularErrorRad,
  );
}

void main() {
  test(
    'idle preparation preserves diagnostics and clears with invalidation',
    () {
      final control = CameraFastMetricMotionSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
      );
      final prepared = CameraFastMetricMotionSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
      );
      for (var frame = 1; frame <= 4; frame++) {
        final input = capture(fixture.input(frame, shift: -6 * (frame - 1)));
        final now = input.camera.depth.capturedAtUs + 2000;
        expect(
          prepared.observe(input, nowUs: now).toDiagnosticMap(),
          control.observe(input, nowUs: now).toDiagnosticMap(),
        );
        expect(prepared.prepareNextPair(), true);
        expect(prepared.prepareNextPair(), false);
      }
      prepared.invalidate();
      expect(prepared.prepareNextPair(), false);
      final next = capture(fixture.input(5));
      expect(
        prepared
            .observe(next, nowUs: next.camera.depth.capturedAtUs + 2000)
            .reason,
        'new_pair_required',
      );
    },
  );
  test('transferred RGB/depth is exact, read-only and materialized once', () {
    final input = capture(fixture.input(1)), f = input.camera.depth;
    final rgb = Uint8List.fromList(input.rgb),
        ranges = Float64List.fromList(f.rangeM);
    final storage = TransferableTypedData.fromList([
      rgb,
      Uint8List((8 - rgb.length % 8) % 8),
      ranges,
      Float64List.fromList(f.freeZLowerM),
      Float64List.fromList(f.surfaceZUpperM),
      Uint8List.fromList([for (final v in f.valid) v ? 1 : 0]),
    ]);
    rgb[0] = 0;
    ranges[0] = 0; // construction snapshots the sender's mutable buffers
    FastMetricMotionInput decode() => FastMetricMotionInput.fromTransferable(
      storage: storage,
      metadata: f,
      header: input.camera.rgbHeader,
      geometry: input.camera.imageGeometry,
      positionErrorM: input.positionErrorM,
      angularErrorRad: input.angularErrorRad,
    );
    final restored = decode(), depth = restored.camera.depth;
    expect(restored.rgb, input.rgb);
    expect(depth.rangeM, f.rangeM);
    expect(depth.freeZLowerM, f.freeZLowerM);
    expect(depth.surfaceZUpperM, f.surfaceZUpperM);
    expect(depth.valid, f.valid);
    expect(depth.structurallyValid, true);
    expect(() => restored.rgb[0] = 1, throwsUnsupportedError);
    expect(() => depth.rangeM[0] = 0, throwsUnsupportedError);
    expect(() => depth.valid[0] = false, throwsUnsupportedError);
    expect(decode, throwsA(anything));
  });
  test(
    'worker checks capture identity and rejects forged release tokens',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
      );
      addTearDown(worker.close);
      worker.beginSession(1);
      final genuine = await worker.offer(capture(fixture.input(1)));
      final forged = FastMotionOutcome(
        status: genuine.status,
        result: genuine.result,
        requestId: genuine.requestId,
        revision: genuine.revision,
        sessionGeneration: genuine.sessionGeneration,
        frameId: genuine.frameId,
        capturedAtUs: genuine.capturedAtUs,
        startedAtUs: genuine.startedAtUs,
        completedAtUs: genuine.completedAtUs,
        workerComputeUs: genuine.workerComputeUs,
      );
      expect(worker.release(forged).admitted, false);
      now = 1202000;
      expect(
        (await worker.offer(
          capture(fixture.input(2, rgbFrameDelta: 1)),
        )).status,
        FastMotionStatus.invalidIdentity,
      );
      now = 1402000;
      expect(
        (await worker.offer(
          capture(fixture.input(3), producedDelta: 3000),
        )).status,
        FastMotionStatus.invalidClock,
      );
      now = 1602000;
      expect(
        (await worker.offer(capture(fixture.input(4, mismatch: true)))).status,
        FastMotionStatus.invalidIdentity,
      );
      now = 1802000;
      final recovery = await worker.offer(capture(fixture.input(5)));
      expect(worker.release(recovery).result?.reason, 'new_pair_required');
    },
  );
  test('independent capture produces same motion without NN identity', () {
    final source = CameraFastMetricMotionSource(
      calibration: fixture.calibration,
      rgbContract: rgbContract,
    );
    source.observe(capture(fixture.input(1)), nowUs: 1002000);
    final r = source.observe(
      capture(fixture.input(2, shift: -6)),
      nowUs: 1202000,
    );
    expect(r.addsMotionRisk, true);
    expect(
      r.toDiagnosticMap(),
      fixture
          .pair(fixture.input(1), fixture.input(2, shift: -6))
          .toDiagnosticMap(),
    );
    expect(r.toDiagnosticMap()['freeSpaceCertified'], false);
  });
  test('ambiguity, identity, depth and pose failures never produce risk', () {
    final cases = [
      capture(fixture.input(2, plain: true)),
      capture(fixture.input(2, repeated: true)),
      capture(fixture.input(2, missing: true)),
      capture(fixture.input(2, unbounded: true)),
      capture(fixture.input(2, conflict: true)),
      capture(fixture.input(2, healthy: false)),
      capture(fixture.input(2, pose: 0)),
      capture(fixture.input(2, mismatch: true)),
      capture(fixture.input(2, session: 2)),
      capture(fixture.input(2, transform: 'changed')),
      capture(fixture.input(2, cameraId: 'changed')),
      capture(fixture.input(2, distortedPose: true)),
      capture(fixture.input(2, positionError: double.nan)),
      capture(fixture.input(2, rgbFrameDelta: 1)),
      capture(fixture.input(2, rgbTimestampDelta: 1)),
      capture(fixture.input(2), provider: 'other'),
      capture(fixture.input(2), revision: 'other'),
      capture(fixture.input(2), healthy: false),
      capture(fixture.input(2), confidence: double.nan),
      capture(fixture.input(2), confidence: .89),
      capture(fixture.input(2), producedDelta: 200000),
    ];
    for (final input in cases) {
      final old = CameraFastMetricMotionSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        optimizePixels: false,
      );
      final fast = CameraFastMetricMotionSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
      );
      old.observe(capture(fixture.input(1)), nowUs: 1002000);
      fast.observe(capture(fixture.input(1)), nowUs: 1002000);
      final a = old.observe(input, nowUs: 1202000),
          b = fast.observe(input, nowUs: 1202000);
      expect(b.toDiagnosticMap(), a.toDiagnosticMap());
      expect(b.addsMotionRisk, false);
    }
  });
  test('immutable RGB snapshot preserves invalid bytes for rejection', () {
    final raw = capture(fixture.input(1)), bytes = raw.rgb.toList();
    final snapshot = FastMetricMotionInput(
      camera: raw.camera,
      rgb: bytes,
      positionErrorM: 0,
      angularErrorRad: 0,
    );
    bytes[0] = 0;
    expect(snapshot.rgb, raw.rgb);
    expect(() => snapshot.rgb[0] = 1, throwsUnsupportedError);
    bytes[0] = 999;
    final invalid = FastMetricMotionInput(
      camera: raw.camera,
      rgb: bytes,
      positionErrorM: 0,
      angularErrorRad: 0,
    );
    expect(
      CameraFastMetricMotionSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
      ).observe(invalid, nowUs: 1002000).available,
      false,
    );
  });
  test(
    'persistent isolate feeds real scene/planner and preserves physical history',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
      );
      addTearDown(worker.close);
      worker.beginSession(1);
      expect(
        worker.release(await worker.offer(capture(fixture.input(1)))).admitted,
        true,
      );
      now = 1202000;
      var ownerRan = false;
      final task = worker.offer(capture(fixture.input(2, shift: -6)));
      Timer.run(() => ownerRan = true);
      final outcome = await task;
      expect(ownerRan, true);
      expect(outcome.admitted, true);
      final world = CameraMetricMotionShadowScene();
      world.update(scene.update(1190000, existingRisk: true));
      expect(applyFastMotionShadow(worker, world, outcome), true);
      final result = world.update(scene.update(now));
      final forward = result.snapshot.polarSectors.firstWhere(
        (e) => e.id == 'forward',
      );
      expect(forward.unknownProbability, greaterThan(.5));
      expect(forward.occupancyProbability, greaterThan(.5));
      final action = GuidanceStateMachine()
          .evaluate(
            RelativePolarGrid.fromSnapshot(
              result.snapshot,
              orientationValid: true,
              userMoving: true,
            ),
            now: DateTime.fromMicrosecondsSinceEpoch(now),
          )
          .action;
      expect(action.kind, SafetyActionKind.stopNow);
      expect(applyFastMotionShadow(worker, world, outcome), false);
    },
  );
  test(
    'entry, completion and release age discard stale authority and recover with new pair',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
      );
      addTearDown(worker.close);
      worker.beginSession(1);
      worker.release(await worker.offer(capture(fixture.input(1))));
      now = 1202000;
      final task = worker.offer(capture(fixture.input(2, shift: -6)));
      now = 1300001;
      expect((await task).admitted, false);
      now = 1402000;
      final recovery = await worker.offer(capture(fixture.input(3)));
      expect(worker.release(recovery).result?.reason, 'new_pair_required');
      now = 1602000;
      final fresh = await worker.offer(capture(fixture.input(4, shift: -6)));
      expect(fresh.result?.addsMotionRisk, true);
      now = 1700000;
      expect(worker.release(fresh).admitted, true); // exact 100 ms accepted
      now = 1802000;
      final late = await worker.offer(capture(fixture.input(5)));
      now = 1900001;
      expect(
        worker.release(late).status,
        FastMotionStatus.expiredBeforeRelease,
      );
      now = 2200001;
      expect(
        (await worker.offer(capture(fixture.input(6)))).status,
        FastMotionStatus.expiredBeforeCompute,
      );
    },
  );
  test(
    'latest queue bounds work and rejects cross-session, reorder and clock rollback',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
      );
      addTearDown(worker.close);
      worker.beginSession(1);
      final first = worker.offer(capture(fixture.input(1)));
      now = 1052000;
      final second = worker.offer(
        capture(fixture.input(2, timestamp: 1050000)),
      );
      now = 1102000;
      final third = worker.offer(capture(fixture.input(3, timestamp: 1100000)));
      expect(worker.inFlightCount, 1);
      expect(worker.pendingCount, 1);
      expect((await second).status, FastMotionStatus.replaced);
      expect((await first).admitted, false);
      expect((await third).admitted, true);
      expect(worker.replacedFrames, 1);
      expect(
        (await worker.offer(
          capture(fixture.input(3, timestamp: 1100000)),
        )).status,
        FastMotionStatus.invalidOrder,
      );
      now = 1202000;
      final active = worker.offer(
        capture(fixture.input(4, timestamp: 1200000)),
      );
      worker.beginSession(2);
      expect((await active).admitted, false);
      now = 1252000;
      expect(
        (await worker.offer(
          capture(fixture.input(5, timestamp: 1250000)),
        )).status,
        FastMotionStatus.invalidSession,
      );
      now = 1302000;
      final recovery = await worker.offer(
        capture(fixture.input(1, session: 2, timestamp: 1300000)),
      );
      expect(worker.release(recovery).admitted, true);
      now = 1301000;
      expect(
        (await worker.offer(
          capture(fixture.input(2, session: 2, timestamp: 1350000)),
        )).status,
        FastMotionStatus.invalidClock,
      );
    },
  );
  test(
    'provider loss clears pair, large frame gap is unknown, closed worker rejects',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
      );
      addTearDown(worker.close);
      worker.beginSession(1);
      worker.release(await worker.offer(capture(fixture.input(1))));
      worker.providerLost();
      now = 1202000;
      expect(
        worker
            .release(await worker.offer(capture(fixture.input(2))))
            .result
            ?.reason,
        'new_pair_required',
      );
      now = 1602000;
      expect(
        worker
            .release(await worker.offer(capture(fixture.input(4))))
            .result
            ?.reason,
        'incompatible_pair_or_interval',
      );
      worker.close();
      expect(
        (await worker.offer(capture(fixture.input(5)))).status,
        FastMotionStatus.closed,
      );
    },
  );
}

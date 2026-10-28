import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion_packed.dart';
import 'package:bagdar/safety/perception/camera_fast_metric_motion.dart'
    as baseline;
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_bulk_native_match.dart';
import 'package:bagdar/safety/perception/camera_fast_motion_types.dart';
import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_packed_worker.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_packed_transport.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/runtime/camera_fast_motion_packed_shadow_adapter.dart';
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
String? get nativePath {
  const path = String.fromEnvironment('BAGDAR_FAST_NATIVE_LIBRARY');
  return path.isEmpty ? null : File(path).absolute.path;
}

CameraFastMetricMotionPackedSource loadSource({
  required PassageCalibration calibration,
  required FastRgbContract rgbContract,
  bool optimizePixels = true,
}) {
  final source = CameraFastMetricMotionPackedSource(
    calibration: calibration,
    rgbContract: rgbContract,
    optimizePixels: optimizePixels,
    nativeLibraryPath: nativePath,
  );
  addTearDown(source.dispose);
  return source;
}

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
  for (var width = 1; width <= 8; width++) {
    test(
      'packed payload preserves alignment for width $width and mixed validity',
      () {
        final original = capture(fixture.input(1));
        final metadata = original.camera.depth;
        final rgb = List<int>.generate(width * 3, (i) => (i * 17) % 256);
        final ranges = List<double>.generate(
          width,
          (i) => i == 0 ? -0.0 : i + .125,
        );
        final lower = List<double>.generate(width, (i) => i + .25);
        final upper = List<double>.generate(
          width,
          (i) => i == 0 ? double.nan : i + .5,
        );
        final valid = List<bool>.generate(width, (i) => i.isEven);
        final depth = CameraVisibleDepthFrame(
          width: width,
          height: 1,
          frameId: metadata.frameId,
          capturedAtUs: metadata.capturedAtUs,
          sessionGeneration: metadata.sessionGeneration,
          fx: metadata.fx,
          fy: metadata.fy,
          cx: metadata.cx,
          cy: metadata.cy,
          errorM: metadata.errorM,
          poseQuality: metadata.poseQuality,
          cameraId: metadata.cameraId,
          modelHash: metadata.modelHash,
          transformId: metadata.transformId,
          referenceFrameId: metadata.referenceFrameId,
          units: metadata.units,
          providerHealthy: true,
          rotation: metadata.rotation,
          originM: metadata.originM,
          rangeM: ranges,
          freeZLowerM: lower,
          surfaceZUpperM: upper,
          valid: valid,
        );
        final input = FastMetricMotionInput(
          camera: FastCameraInput(
            depth: depth,
            rgbHeader: original.camera.rgbHeader,
            imageGeometry: original.camera.imageGeometry,
          ),
          rgb: rgb,
          positionErrorM: original.positionErrorM,
          angularErrorRad: original.angularErrorRad,
        );
        final storage = packFastMotionFrame(input);
        rgb[0] = 255;
        ranges[0] = 100;
        valid[0] = false;
        final restored = FastMetricMotionInput.fromTransferable(
          storage: storage,
          metadata: depth,
          header: input.camera.rgbHeader,
          geometry: input.camera.imageGeometry,
          positionErrorM: input.positionErrorM,
          angularErrorRad: input.angularErrorRad,
        );
        expect(restored.rgb, input.rgb);
        expect(restored.camera.depth.rangeM, depth.rangeM);
        expect(1 / restored.camera.depth.rangeM.first, double.negativeInfinity);
        expect(restored.camera.depth.freeZLowerM, depth.freeZLowerM);
        expect(restored.camera.depth.surfaceZUpperM.first.isNaN, true);
        expect(
          restored.camera.depth.surfaceZUpperM.skip(1),
          depth.surfaceZUpperM.skip(1),
        );
        expect(restored.camera.depth.valid, depth.valid);
        expect(
          () => restored.camera.depth.surfaceZUpperM[0] = 1,
          throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'native projected windows cannot wrap through the Int32 ABI',
    () {
      final matcher = CameraFastMotionBulkNativeMatch(nativePath!);
      addTearDown(matcher.dispose);
      final input = capture(fixture.input(1));
      final empty = Float64List(0);
      for (final center in [
        -(1 << 40),
        -(1 << 31),
        1 << 31,
        (1 << 32) + 48,
        1 << 40,
      ]) {
        // No frame is copied for an entirely out-of-image projected window.
        expect(
          matcher.match(
            input,
            empty,
            empty,
            empty,
            empty,
            empty,
            const [],
            const [],
            const [],
            2.5,
            [center, 32],
          ),
          isNull,
        );
        expect(
          matcher.match(
            input,
            empty,
            empty,
            empty,
            empty,
            empty,
            const [],
            const [],
            const [],
            2.5,
            [48, center],
          ),
          isNull,
        );
      }
      expect(matcher.cachedFrames, 0);
      expect(
        () => matcher.prepare(input, empty, empty, empty, empty, empty),
        throwsArgumentError,
      );
    },
    skip: nativePath == null,
  );
  test(
    'load matcher keeps frozen diagnostics across translations and ambiguous textures',
    () {
      for (final shift in [-32, -6, -1, 0, 1, 6, 32]) {
        for (final texture in ['random', 'plain', 'repeated']) {
          final control = baseline.CameraFastMetricMotionSource(
            calibration: fixture.calibration,
            rgbContract: rgbContract,
          );
          final candidate = loadSource(
            calibration: fixture.calibration,
            rgbContract: rgbContract,
          );
          for (var frame = 1; frame <= 3; frame++) {
            final input = capture(
              fixture.input(
                frame,
                shift: shift * (frame - 1),
                plain: texture == 'plain',
                repeated: texture == 'repeated',
              ),
            );
            expect(
              candidate
                  .observe(input, nowUs: input.camera.depth.capturedAtUs + 2000)
                  .toDiagnosticMap(),
              control
                  .observe(input, nowUs: input.camera.depth.capturedAtUs + 2000)
                  .toDiagnosticMap(),
            );
          }
          candidate.dispose();
        }
      }
    },
  );
  test(
    'idle preparation preserves diagnostics and clears with invalidation',
    () {
      final control = loadSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
      );
      final prepared = loadSource(
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
    final storage = packFastMotionFrame(input);
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
      final worker = await CameraFastMotionPackedWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
        nativeLibraryPath: nativePath,
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
    final source = loadSource(
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
      final old = loadSource(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        optimizePixels: false,
      );
      final fast = loadSource(
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
      loadSource(
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
      final worker = await CameraFastMotionPackedWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
        nativeLibraryPath: nativePath,
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
      expect(applyFastMotionPackedShadow(worker, world, outcome), true);
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
      expect(applyFastMotionPackedShadow(worker, world, outcome), false);
    },
  );
  test(
    'entry, completion and release age discard stale authority and recover with new pair',
    () async {
      var now = 1002000;
      final worker = await CameraFastMotionPackedWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
        nativeLibraryPath: nativePath,
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
      final worker = await CameraFastMotionPackedWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
        nativeLibraryPath: nativePath,
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
      final worker = await CameraFastMotionPackedWorker.start(
        calibration: fixture.calibration,
        rgbContract: rgbContract,
        clockUs: () => now,
        nativeLibraryPath: nativePath,
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

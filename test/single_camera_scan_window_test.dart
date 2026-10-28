import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/single_camera_scan_window.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'single_camera_observability_test.dart'
    show opticalFrame, opticalRequest, opticalCalibration;

void main() {
  late SingleCameraScanWindow window;
  setUp(() {
    window = SingleCameraScanWindow(
      request: opticalRequest(),
      sessionGeneration: 1,
    );
  });
  CameraVisibleDepthFrame frame(int id, int capture) =>
      copyVisibleFrame(opticalFrame(), frameId: id, timestamp: capture);
  bool add(
    CameraVisibleDepthFrame f, {
    int? now,
    PassageCalibration? calibration,
  }) => window.admit(
    frame: f,
    calibration: calibration ?? opticalCalibration(),
    context: PassageEvaluationContext(
      nowUs: now ?? f.capturedAtUs + 2000,
      timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
      sessionGeneration: 1,
      frameId: f.frameId,
      rgbTimestampUs: f.capturedAtUs,
      transformId: f.transformId,
    ),
  );
  List<int> ids(int now) =>
      window.inspect(now).frames.map((f) => f.frameId).toList();

  test(
    'original captures survive and oldest expires without renewing its age',
    () {
      expect(add(frame(1, 1000000)), true);
      expect(add(frame(2, 1050000)), true);
      expect(ids(1100000), [1, 2]);
      expect(ids(1100001), [2]);
      expect(window.inspect(1100001).frames.single.capturedAtUs, 1050000);
    },
  );
  test('stale incoming frame clears a previously fresh window', () {
    add(frame(1, 1000000));
    expect(add(frame(2, 1010000), now: 1110001), false);
    expect(ids(1110001), isEmpty);
  });
  test('future incoming frame clears window without poisoning watermark', () {
    add(frame(1, 1000000));
    expect(add(frame(99, 2000000), now: 1010000), false);
    expect(add(frame(2, 1020000)), true);
    expect(ids(1022000), [2]);
  });
  test('replay after invalidation cannot reset accepted order', () {
    add(frame(2, 1020000));
    expect(add(frame(1, 1010000), now: 1023000), false);
    expect(add(frame(2, 1020000), now: 1024000), false);
    expect(add(frame(3, 1030000)), true);
    expect(ids(1032000), [3]);
  });
  test('duplicate captures with increasing IDs still invalidate', () {
    add(frame(1, 1000000));
    expect(add(frame(2, 1000000)), false);
    expect(ids(1002000), isEmpty);
  });
  test('ordering watermark survives complete expiry', () {
    add(frame(1, 1000000));
    expect(ids(1100001), isEmpty);
    expect(add(frame(1, 1110000)), false);
    expect(add(frame(2, 1120000)), true);
  });
  test('clock rollback permanently terminates this clock window', () {
    add(frame(1, 1000000));
    expect(ids(1001999), isEmpty);
    expect(add(frame(2, 1020000)), false);
    expect(ids(1022000), isEmpty);
  });
  test('negative clock terminates without accepting later frames', () {
    expect(ids(-1), isEmpty);
    expect(add(frame(1, 1000000)), false);
  });
  test('lifecycle end clears window and blocks new admission', () {
    add(frame(1, 1000000));
    window.endSession();
    expect(ids(1003000), isEmpty);
    expect(add(frame(2, 1020000)), false);
  });
  test('capacity retains at most twelve immutable original frames', () {
    for (var i = 1; i <= 13; i++) {
      expect(add(frame(i, 1000000 + i * 1000)), true);
    }
    final snapshot = window.inspect(1015000);
    expect(snapshot.frames.length, 12);
    expect(snapshot.frames.first.frameId, 2);
    expect(() => snapshot.frames.clear(), throwsUnsupportedError);
    window.endSession();
    expect(snapshot.frames.length, 12);
    expect(snapshot.canAuthorizeMovement, false);
  });
  test('valid camera identity change starts a new window', () {
    add(frame(1, 1000000));
    expect(
      add(copyVisibleFrame(frame(2, 1010000), cameraId: 'replacement')),
      true,
    );
    expect(ids(1012000), [2]);
  });
  test('intrinsics change cannot mix old pixel geometry into a new window', () {
    add(frame(1, 1000000));
    expect(
      add(
        copyVisibleFrame(
          opticalFrame(focal: 3),
          frameId: 2,
          timestamp: 1010000,
        ),
      ),
      true,
    );
    expect(ids(1012000), [2]);
  });
  test('valid calibration identity change clears prior accumulation', () {
    add(frame(1, 1000000));
    final prior = opticalCalibration();
    final changed = PassageCalibration(
      id: 'new-calibration',
      providerId: prior.providerId,
      modelId: prior.modelId,
      modelHash: prior.modelHash,
      preprocessId: prior.preprocessId,
      referenceFrameId: prior.referenceFrameId,
      transformId: prior.transformId,
      timestampDomain: prior.timestampDomain,
      metricScaleValidated: true,
      alignmentValidated: true,
      floorReferenceValidated: true,
    );
    expect(add(frame(2, 1010000), calibration: changed), true);
    expect(ids(1012000), [2]);
  });
  test(
    'pose changes preserve samples without certifying scene stationarity',
    () {
      add(frame(1, 1000000));
      expect(
        add(copyVisibleFrame(frame(2, 1010000), origin: [0, .1, 1])),
        true,
      );
      final snapshot = window.inspect(1012000);
      expect(snapshot.frames.length, 2);
      expect(snapshot.canAuthorizeMovement, false);
    },
  );
  for (final fault
      in <String, CameraVisibleDepthFrame Function(CameraVisibleDepthFrame)>{
        'relative': (f) =>
            copyVisibleFrame(f, units: PassageUnits.relativeProximity),
        'pose': (f) => copyVisibleFrame(f, pose: .89),
        'provider': (f) => copyVisibleFrame(f, healthy: false),
        'session': (f) => copyVisibleFrame(f, session: 2),
        'model': (f) => copyVisibleFrame(f, modelHash: 'foreign'),
        'reference': (f) => copyVisibleFrame(f, referenceFrame: 'foreign'),
      }.entries) {
    test('${fault.key} failure clears previous accumulation', () {
      add(frame(1, 1000000));
      expect(add(fault.value(frame(2, 1010000))), false);
      expect(ids(1012000), isEmpty);
      expect(add(frame(3, 1020000)), true);
      expect(ids(1022000), [3]);
    });
  }
  test('unverified metric calibration clears accumulated samples', () {
    add(frame(1, 1000000));
    expect(
      add(frame(2, 1010000), calibration: opticalCalibration(metric: false)),
      false,
    );
    expect(ids(1012000), isEmpty);
  });
}

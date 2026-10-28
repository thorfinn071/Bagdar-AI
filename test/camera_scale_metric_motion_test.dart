import 'dart:math';

import 'package:bagdar/safety/perception/camera_metric_motion.dart';
import 'package:bagdar/safety/perception/camera_scale_metric_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'camera_scale_metric_motion_contract_test.dart' as fixture;
import 'harness/camera_scale_motion_benchmark.dart';

// One textured visible plane rendered through pinhole coordinates. Texture
// coordinates belong only to this fixture, never to the producer API.
CameraMetricMotionInput plane(int frame, double axis) {
  final packet = fixture.input(frame, axis: axis);
  final random = Random(967);
  final texture = List.generate(128 * 128 * 3, (_) => random.nextInt(256));
  double tex(double x, double y, int c) {
    final u = x.floor(), v = y.floor(), dx = x - u, dy = y - v;
    double at(int a, int b) =>
        texture[((b % 128) * 128 + a % 128) * 3 + c].toDouble();
    return at(u, v) * (1 - dx) * (1 - dy) +
        at(u + 1, v) * dx * (1 - dy) +
        at(u, v + 1) * (1 - dx) * dy +
        at(u + 1, v + 1) * dx * dy;
  }

  return CameraMetricMotionInput(
    camera: packet.camera,
    rgb: [
      for (var y = 0; y < 64; y++)
        for (var x = 0; x < 96; x++)
          for (var c = 0; c < 3; c++)
            tex(
              64 + (x + .5 - 48) * axis / 2.5 / 2,
              64 + (y + .5 - 32) * axis / 2.5 / 2,
              c,
            ).round(),
    ],
    positionErrorM: packet.positionErrorM,
    angularErrorRad: packet.angularErrorRad,
  );
}

void main() {
  for (final axis in [2.3, 2.7]) {
    test(
      'pinhole scale at depth $axis establishes direction and bounded speed',
      () {
        final source = CameraScaleMetricMotionSource(
          calibration: fixture.calibration,
          relativeModelHash: 'relative',
        );
        source.observe(plane(1, 2.5), nowUs: 1002000);
        final r = source.observe(plane(2, axis), nowUs: 1202000);
        expect(r.available, true);
        final moving = r.patches.where((p) => p.establishesMotion).toList();
        expect(moving.length, greaterThanOrEqualTo(3));
        final velocity = (axis - 2.5) / .2;
        expect(
          moving.every(
            (p) =>
                p.velocityLowerMps[1] <= velocity &&
                p.velocityUpperMps[1] >= velocity,
          ),
          true,
        );
        expect(
          moving.every(
            (p) =>
                p.classification ==
                (axis < 2.5
                    ? VisiblePatchMotion.approaching
                    : VisiblePatchMotion.receding),
          ),
          true,
        );
        expect(r.addsMotionRisk, true);
      },
    );
  }
  test('unsupported scale produces unknown', () {
    final source = CameraScaleMetricMotionSource(
      calibration: fixture.calibration,
      relativeModelHash: 'relative',
    );
    source.observe(plane(1, 2.5), nowUs: 1002000);
    expect(source.observe(plane(2, 1.3), nowUs: 1202000).available, false);
  });
  test(
    'inspected approach is a development regression, never fresh holdout',
    () async {
      final report = await runScaleMotionBenchmark(
        knownRegression: true,
        write: const bool.fromEnvironment('BAGDAR_WRITE_SCALE_MOTION_REPORT'),
      );
      expect(report['summarySplit'], 'known-regression');
      final summary = (report['summaries'] as Map)['scale-motion'] as Map;
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_scale_motion_benchmark.dart';

void main() {
  test(
    'known scale motion corpus regression and shadow runtime',
    () async {
      const write = bool.fromEnvironment('BAGDAR_WRITE_SCALE_MOTION_REPORT');
      const check = bool.fromEnvironment('BAGDAR_CHECK_SCALE_MOTION_REPORT');
      final report = await runScaleMotionBenchmark(
        write: write,
        check: check,
        knownCorpusRegression: !write && !check,
      );
      if (!write && !check) {
        expect(report['evaluationScope'], 'knownCorpusRegression');
      }
      final summary = (report['summaries'] as Map)['scale-motion'] as Map;
      expect(summary['sequences'], 10);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
      final motions = (report['motionSummary'] as Map).values.cast<Map>();
      for (final row in motions.where((r) => r['mode'] == 'scale-motion')) {
        if (['stationary', 'camera-yaw'].contains(row['motionKindLabel'])) {
          final classes = row['patchClassifications'] as Map;
          expect(classes['approaching'], 0);
          expect(classes['receding'], 0);
          expect(classes['lateral'], 0);
        }
        expect((row['correspondenceScores'] as Map)['surfaceMismatch'], 0);
        expect(
          (row['correspondenceScores'] as Map)['falseBackgroundMotion'],
          0,
        );
      }
      expect(report['promotionAllowed'], false);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

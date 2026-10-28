import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_scale_motion_benchmark.dart';

void main() {
  test(
    'metric motion validation, no test decisions',
    () async {
      final report = await runScaleMotionBenchmark(
        developmentOnly: true,
        write: const bool.fromEnvironment('BAGDAR_WRITE_SCALE_MOTION_REPORT'),
      );
      final summary = (report['summaries'] as Map)['scale-motion'] as Map;
      expect(summary['sequences'], 6);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
      expect(report['promotionAllowed'], false);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

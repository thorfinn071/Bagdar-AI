import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_metric_motion_benchmark.dart';

void main() {
  test(
    'metric motion validation, no test decisions',
    () async {
      final report = await runMetricMotionBenchmark(
        developmentOnly: true,
        write: const bool.fromEnvironment('BAGDAR_WRITE_METRIC_MOTION_REPORT'),
      );
      final summary = (report['summaries'] as Map)['metric-motion'] as Map;
      expect(summary['sequences'], 7);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
      expect(report['promotionAllowed'], false);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

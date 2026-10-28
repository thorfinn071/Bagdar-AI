import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_metric_motion_benchmark.dart';

void main() {
  test(
    'known metric motion corpus regression and shadow runtime',
    () async {
      const write = bool.fromEnvironment('BAGDAR_WRITE_METRIC_MOTION_REPORT');
      const check = bool.fromEnvironment('BAGDAR_CHECK_METRIC_MOTION_REPORT');
      final report = await runMetricMotionBenchmark(
        write: write,
        check: check,
        knownCorpusRegression: !write && !check,
      );
      if (!write && !check) {
        expect(report['evaluationScope'], 'knownCorpusRegression');
      }
      final summary = (report['summaries'] as Map)['metric-motion'] as Map;
      expect(summary['sequences'], 10);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
      expect(report['promotionAllowed'], false);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

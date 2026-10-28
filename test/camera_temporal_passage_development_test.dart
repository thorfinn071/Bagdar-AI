import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_temporal_passage_benchmark.dart';

void main() {
  const write = bool.fromEnvironment('BAGDAR_WRITE_TEMPORAL_REPORT');
  test(
    'temporal validation only, no holdout decisions',
    () async {
      final report = await runTemporalPassageBenchmark(
        developmentOnly: true,
        write: write,
      );
      final summary = (report['summaries'] as Map)['associated-stable'] as Map;
      expect(summary['sequences'], 6);
      expect(summary['hazardSequences'], 3);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'previously inspected repeated-RGB regression',
    () async {
      final report = await runTemporalPassageBenchmark(
        knownRegression: true,
        write: write,
      );
      final summary = report['summaries'] as Map;
      expect((summary['associated-stateful'] as Map)['falseStopSequences'], 1);
      expect((summary['associated-stable'] as Map)['falseStopSequences'], 0);
      expect((summary['associated-stable'] as Map)['unjustifiedClearances'], 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

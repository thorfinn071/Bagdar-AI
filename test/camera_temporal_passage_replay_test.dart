import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_temporal_passage_benchmark.dart';

void main() {
  test(
    'known temporal corpus regression, real NCNN frames and shadow decisions',
    () async {
      const write = bool.fromEnvironment('BAGDAR_WRITE_TEMPORAL_REPORT');
      const check = bool.fromEnvironment('BAGDAR_CHECK_TEMPORAL_REPORT');
      final report = await runTemporalPassageBenchmark(
        write: write,
        check: check,
        knownCorpusRegression: !write && !check,
      );
      if (!write && !check) {
        expect(report['evaluationScope'], 'knownCorpusRegression');
      }
      final summary = (report['summaries'] as Map)['associated-stable'] as Map;
      expect(summary['sequences'], 12);
      expect(summary['hazardSequences'], 8);
      expect(summary['unsafeContinueSteps'], 0);
      expect(summary['unjustifiedClearances'], 0);
      expect(report['promotionAllowed'], false);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

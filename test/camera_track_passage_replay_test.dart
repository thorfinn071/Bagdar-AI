import 'package:flutter_test/flutter_test.dart';
import 'camera_visible_passage_replay_test.dart'
    show runVisiblePassageBenchmark;
import 'harness/camera_visible_passage_fixture.dart';

void main() {
  test(
    'known camera track association whole-scene regression, shadow only',
    () {
      const write = bool.fromEnvironment('BAGDAR_WRITE_VISIBLE_REPORT');
      const check = bool.fromEnvironment('BAGDAR_CHECK_VISIBLE_REPORT');
      final report = runVisiblePassageBenchmark(
        inputFixture: VisibleFixture(
          root: 'test/fixtures/spatial_safety/camera-track-passage-v1',
        ),
        reportPath: 'docs/_baseline_logs/camera_track_passage_replay.json',
        timingPath: 'docs/_baseline_logs/camera_track_decision_timing.json',
        ncnnTimingPath: 'docs/_baseline_logs/camera_track_ncnn_timing.json',
        associationExperiment: true,
        write: write,
        check: check,
        knownCorpusRegression: !write && !check,
      );
      if (!write && !check) {
        expect(report['evaluationScope'], 'knownCorpusRegression');
      }
      expect(report['promotionAllowed'], false);
      expect(report['cameraSafetyCriteriaPassed'], true);
      final summaries = report['summaries'] as Map;
      for (final mode in ['visible-scan', 'visible-associated']) {
        final summary = summaries[mode] as Map;
        expect(summary['hazardSequences'], 10);
        expect(summary['onTimeStops'], 10);
        expect(summary['unsafeContinueSteps'], 0);
        expect(summary['unjustifiedClearances'], 0);
        expect(summary['sufficientPassableSequences'], 6);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

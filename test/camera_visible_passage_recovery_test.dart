import 'package:flutter_test/flutter_test.dart';
import 'camera_visible_passage_replay_test.dart'
    show runVisiblePassageBenchmark;
import 'harness/camera_visible_passage_fixture.dart';

const recoveryRoot =
    'test/fixtures/spatial_safety/camera-visible-passage-recovery-v1';

void main() {
  test(
    'predeclared independent recovery scenes and retained hazards',
    () {
      const developmentOnly = bool.fromEnvironment(
        'BAGDAR_VISIBLE_DEVELOPMENT_ONLY',
      );
      final report = runVisiblePassageBenchmark(
        inputFixture: VisibleFixture(root: recoveryRoot),
        reportPath: 'docs/_baseline_logs/camera_visible_passage_recovery.json',
        timingPath: 'docs/_baseline_logs/passage_recovery_decision_timing.json',
        ncnnTimingPath: 'docs/_baseline_logs/passage_recovery_ncnn_timing.json',
        developmentOnly: developmentOnly,
      );
      if (developmentOnly) return;
      final summaries = report['summaries'] as Map;
      final scan = summaries['visible-scan'] as Map;
      expect(scan['hazardSequences'], 6);
      expect(scan['onTimeStops'], 6);
      expect(scan['unsafeContinueSteps'], 0);
      expect(scan['unjustifiedClearances'], 0);
      expect(scan['sufficientPassableSequences'], 6);
      expect(report['cameraSafetyCriteriaPassed'], true);
      expect(report['promotionAllowed'], false);
      // Improvement is measured against the control; it never weakens safety.
      expect(report['falseStopReductionEstablished'], true);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_processing_age_benchmark.dart';

void main() {
  for (final mode in ['functional', 'overload', 'runtime-overrun']) {
    test(
      'processing age $mode replay preserves safety with real shadow runtime',
      () async {
        final r = await runProcessingAgeReplay(
          mode: mode,
          write: const bool.fromEnvironment('BAGDAR_WRITE_PROCESSING_AGE'),
          check: const bool.fromEnvironment('BAGDAR_CHECK_PROCESSING_AGE'),
        );
        final s = r['summary'] as Map;
        expect(s['staleApplications'], 0);
        expect(s['unsafeContinueSteps'], 0);
        expect(s['unjustifiedClearances'], 0);
        if (mode == 'functional') {
          expect(s['identityMatches'], 67);
        } else if (mode == 'overload') {
          expect(s['motionAppliedFrames'], 0);
          expect(s['queueReplaced'], greaterThan(0));
        } else {
          expect(s['expiredResults'], greaterThan(0));
          expect(
            (s['falseStopSequences'] as int) + (s['falseHoldSequences'] as int),
            1,
          );
          expect(s['discardedClearDecisions'], greaterThan(0));
        }
        expect(r['promotionAllowed'], false);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
  if (const bool.fromEnvironment('BAGDAR_MEASURE_PROCESSING_AGE')) {
    test(
      'live pinned NCNN elapsed processing replay publishes measured ages',
      () async {
        final r = await runProcessingAgeReplay(mode: 'measured', write: true);
        final s = r['summary'] as Map;
        expect(s['staleApplications'], 0);
        expect(s['unsafeContinueSteps'], 0);
        expect(s['unjustifiedClearances'], 0);
      },
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}

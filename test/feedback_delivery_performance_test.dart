import 'package:bagdar/core/performance/feedback_delivery_performance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'missing starts stay in counts while bounded timings disclose overwrite',
    () {
      final metrics = FeedbackDeliveryPerformance(capacity: 2);
      for (var i = 0; i < 5; i++) {
        metrics.count('speechRequested');
      }
      for (final us in [1000, 2000, 3000]) {
        metrics.count('speechStarted');
        metrics.record('requestToStart', us);
      }
      metrics.count('speech_timeout');
      metrics.count('speech_error');
      metrics.record('requestToStart', -1);
      final report = metrics.takeWindow();
      expect((report['counts'] as Map)['speechRequested'], 5);
      expect((report['counts'] as Map)['speechStarted'], 3);
      final timing = (report['timings'] as Map)['requestToStart'] as Map;
      expect(timing['totalCount'], 3);
      expect(timing['sampleCount'], 2);
      expect(timing['overwrittenSamples'], 1);
      expect(timing['p95Ms'], 3);
      expect((report['counts'] as Map)['invalidTiming'], 1);
      expect(report['actualVibrationMeasured'], false);
      expect(metrics.takeWindow()['counts'], isEmpty);
    },
  );
}

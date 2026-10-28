import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/performance/perception_performance.dart';

void main() {
  test(
    'completed YOLO, accepted results and pre-dispatch drops stay distinct',
    () {
      final performance = PerceptionPerformance();
      for (var i = 0; i < 3; i++) {
        performance.increment(PerceptionCounter.yoloStarted);
        performance.increment(PerceptionCounter.yoloCompleted);
        performance.record(PerceptionStage.yoloRoundTrip, (i + 1) * 100000);
      }
      performance.increment(PerceptionCounter.yoloAccepted);
      performance.increment(PerceptionCounter.yoloRejected);
      performance.increment(PerceptionCounter.yoloRejected);
      performance.increment(PerceptionCounter.yoloDiscardedBeforeCall);
      final window = performance.takeWindow(elapsedUsForTesting: 1000000);
      expect(window['yoloCompletionFps'], 3);
      expect(window['acceptedYoloFps'], 1);
      final counts = window['counts'] as Map;
      expect(counts['yoloStarted'], 3);
      expect(counts['yoloRejected'], 2);
      expect(counts['yoloDiscardedBeforeCall'], 1);
      expect(
        ((window['stages'] as Map)['yoloRoundTrip'] as Map)['totalCount'],
        3,
      );
      expect(window['captureToDecisionAvailable'], isFalse);
    },
  );

  test('camera FPS cannot inflate useful completion FPS', () {
    final performance = PerceptionPerformance();
    for (var i = 0; i < 30; i++) {
      performance.increment(PerceptionCounter.cameraCallbacks);
    }
    for (var i = 0; i < 4; i++) {
      performance.increment(PerceptionCounter.yoloCompleted);
    }
    performance.increment(PerceptionCounter.skippedBusy);
    final window = performance.takeWindow(elapsedUsForTesting: 1000000);
    expect(window['cameraCallbackFps'], 30);
    expect(window['yoloCompletionFps'], 4);
    expect(window['captureToDecisionAvailable'], isFalse);
    expect(window['latencyOrigin'], 'dart_camera_callback');
    expect(
      (performance.takeWindow(elapsedUsForTesting: 1000000)['counts'] as Map)
          .values,
      everyElement(0),
    );
  });

  test(
    'bounded samples report truncation and keep full outcome count and max',
    () {
      final performance = PerceptionPerformance(sampleCapacity: 4);
      performance.record(PerceptionStage.yoloRoundTrip, 999000);
      for (var i = 1; i <= 10; i++) {
        performance.record(PerceptionStage.yoloRoundTrip, i * 1000);
      }
      final stages = performance.takeWindow()['stages'] as Map;
      final stage = stages['yoloRoundTrip'] as Map;
      expect(stage['totalCount'], 11);
      expect(stage['sampleCount'], 4);
      expect(stage['overwrittenSamples'], 7);
      expect(stage['maxMs'], 999);
      expect(stage['p50Ms'], 8);
      expect(stage['p95Ms'], 10);
    },
  );

  test(
    'rejected depth stays in latency denominator and does not count as accepted',
    () {
      final performance = PerceptionPerformance();
      for (final accepted in [true, false]) {
        performance.recordDepth(
          DepthPerformanceSample(
            sessionGeneration: 1,
            frameId: accepted ? 1 : 2,
            sourceTimestampUs: 1000,
            providerRoundTripUs: 40000,
            callbackToDecisionUs: accepted ? 50000 : 250000,
            providerCalled: true,
            accepted: accepted,
            rejectionReason: accepted ? null : 'stale_observation_latency',
          ),
        );
      }
      final window = performance.takeWindow(elapsedUsForTesting: 1000000);
      expect(window['acceptedDepthFps'], 1);
      final counts = window['counts'] as Map;
      expect(counts['depthRequested'], 2);
      expect(counts['depthCompleted'], 2);
      expect(counts['depthRejected'], 1);
      expect((window['depthRejections'] as Map)['stale'], 1);
      final stages = window['stages'] as Map;
      expect((stages['callbackToDepthDecision'] as Map)['p95Ms'], 250);
    },
  );

  test('unavailable denominator and invalid timing are explicit', () {
    final performance = PerceptionPerformance();
    performance.record(PerceptionStage.yoloRoundTrip, -10);
    final window = performance.takeWindow(elapsedUsForTesting: 0);
    expect(window['yoloCompletionFps'], isNull);
    expect(window['invalidTimingSamples'], 1);
    expect(window['stages'], isEmpty);
    expect(() => PerceptionPerformance(sampleCapacity: 0), throwsArgumentError);
  });

  test(
    'epoch identity is anchored while total age includes earlier waiting',
    () {
      var age = 140000;
      final clock = CallbackFrameTiming.forTesting(1000000, () => age);
      expect(clock.producedAtUs, 1140000);
      age += 50000;
      expect(clock.producedAtUs, 1190000);
    },
  );
}

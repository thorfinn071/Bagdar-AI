import 'dart:async';
import 'dart:math' as math;

/// Measures from Dart callback receipt. Sensor capture is explicitly unknown.
/// The epoch anchor preserves existing frame identity; age uses elapsed time.
class CallbackFrameTiming {
  final int callbackTimestampUs;
  final Stopwatch _elapsed = Stopwatch()..start();
  final int Function()? _testAge;
  final int _initialAgeUs;

  CallbackFrameTiming(this.callbackTimestampUs)
    : _testAge = null,
      _initialAgeUs = 0;

  /// Explicitly timestamped sources, including replay, retain capture age.
  CallbackFrameTiming.withInitialAge(this.callbackTimestampUs, int initialAgeUs)
    : _testAge = null,
      _initialAgeUs = initialAgeUs;

  CallbackFrameTiming.forTesting(this.callbackTimestampUs, int Function() age)
    : _testAge = age,
      _initialAgeUs = 0;

  int get ageUs =>
      _testAge?.call() ?? _initialAgeUs + _elapsed.elapsedMicroseconds;
  int get producedAtUs => callbackTimestampUs + ageUs;
}

enum PerceptionCounter {
  cameraCallbacks,
  yoloStarted,
  yoloCompleted,
  yoloFailed,
  yoloAccepted,
  yoloRejected,
  yoloDiscardedBeforeCall,
  depthRequested,
  depthCompleted,
  depthAccepted,
  depthRejected,
  skippedBusy,
  skippedCadence,
  skippedQuality,
  skippedUnavailable,
  skippedStaggered,
}

enum PerceptionStage {
  callbackWork,
  callbackPreDispatch,
  callbackToYoloDispatch,
  callbackToDepthDispatch,
  yoloRoundTrip,
  callbackToYoloTracks,
  depthProviderRoundTrip,
  callbackToDepthDecision,
  depthWorkerProcessing,
  uiBuild,
  uiRaster,
  eventLoopLag,
}

enum DepthRejection {
  stale,
  timeout,
  busy,
  superseded,
  unavailable,
  clock,
  mismatch,
  other,
}

class EventLoopLagProbe {
  final void Function(int microseconds) onSample;
  final Duration interval;
  Timer? _timer;
  final Stopwatch _clock = Stopwatch();
  int _previousUs = 0;

  EventLoopLagProbe(
    this.onSample, {
    this.interval = const Duration(milliseconds: 100),
  });

  void start() {
    if (_timer != null) return;
    _clock
      ..reset()
      ..start();
    _previousUs = 0;
    _timer = Timer.periodic(interval, (_) {
      final now = _clock.elapsedMicroseconds;
      final lag = math.max(0, now - _previousUs - interval.inMicroseconds);
      _previousUs = now;
      onSample(lag);
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _clock.stop();
  }
}

class DepthPerformanceSample {
  final int sessionGeneration;
  final int frameId;
  final int sourceTimestampUs;
  final int providerRoundTripUs;
  final int callbackToDecisionUs;
  final bool providerCalled;
  final bool accepted;
  final String? rejectionReason;

  const DepthPerformanceSample({
    required this.sessionGeneration,
    required this.frameId,
    required this.sourceTimestampUs,
    required this.providerRoundTripUs,
    required this.callbackToDecisionUs,
    required this.providerCalled,
    required this.accepted,
    this.rejectionReason,
  });
}

class _Samples {
  final List<int> values;
  int count = 0;
  int maxUs = 0;

  _Samples(int capacity) : values = List.filled(capacity, 0);

  void add(int us) {
    values[count % values.length] = us;
    count++;
    maxUs = math.max(maxUs, us);
  }

  Map<String, Object> snapshot() {
    final n = math.min(count, values.length);
    final sorted = values.take(n).toList()..sort();
    double percentile(double fraction) =>
        sorted[math.max(0, (n * fraction).ceil() - 1)] / 1000;
    return {
      'totalCount': count,
      'sampleCount': n,
      'overwrittenSamples': math.max(0, count - n),
      if (n > 0) 'p50Ms': percentile(0.5),
      if (n > 0) 'p95Ms': percentile(0.95),
      if (n > 0) 'p99Ms': percentile(0.99),
      if (n > 0) 'maxMs': maxUs / 1000,
    };
  }

  void reset() {
    count = 0;
    maxUs = 0;
  }
}

/// Bounded telemetry. Counts include all outcomes; percentile samples retain
/// the newest bounded window and report truncation instead of hiding it.
class PerceptionPerformance {
  final int sampleCapacity;
  final Stopwatch _window = Stopwatch()..start();
  final Map<PerceptionCounter, int> _counts = {};
  final Map<PerceptionStage, _Samples> _stages = {};
  final Map<DepthRejection, int> _rejections = {};
  int _invalidSamples = 0;

  PerceptionPerformance({this.sampleCapacity = 256}) {
    if (sampleCapacity < 1 || sampleCapacity > 4096) {
      throw ArgumentError.value(sampleCapacity, 'sampleCapacity');
    }
  }

  void increment(PerceptionCounter counter) =>
      _counts[counter] = (_counts[counter] ?? 0) + 1;

  void record(PerceptionStage stage, int elapsedUs) {
    if (elapsedUs < 0) {
      _invalidSamples++;
      return;
    }
    (_stages[stage] ??= _Samples(sampleCapacity)).add(elapsedUs);
  }

  void recordDepth(DepthPerformanceSample sample) {
    increment(PerceptionCounter.depthRequested);
    if (sample.providerCalled) {
      increment(PerceptionCounter.depthCompleted);
      record(
        PerceptionStage.depthProviderRoundTrip,
        sample.providerRoundTripUs,
      );
    }
    increment(
      sample.accepted
          ? PerceptionCounter.depthAccepted
          : PerceptionCounter.depthRejected,
    );
    if (!sample.accepted) {
      final reason = sample.rejectionReason ?? '';
      final kind = reason.contains('clock')
          ? DepthRejection.clock
          : reason.contains('stale') || reason.contains('latency')
          ? DepthRejection.stale
          : reason.contains('timeout')
          ? DepthRejection.timeout
          : reason.contains('busy')
          ? DepthRejection.busy
          : reason.contains('superseded')
          ? DepthRejection.superseded
          : reason.contains('mismatch') || reason.contains('unaligned')
          ? DepthRejection.mismatch
          : reason.contains('unavailable') ||
                reason.contains('not_ready') ||
                reason.contains('disabled') ||
                reason.contains('worker_')
          ? DepthRejection.unavailable
          : DepthRejection.other;
      _rejections[kind] = (_rejections[kind] ?? 0) + 1;
    }
    // Includes rejected/late attempts, not only surviving accepted results.
    record(
      PerceptionStage.callbackToDepthDecision,
      sample.callbackToDecisionUs,
    );
  }

  Map<String, Object?> takeWindow({int? elapsedUsForTesting}) {
    final durationUs = elapsedUsForTesting ?? _window.elapsedMicroseconds;
    double? rate(PerceptionCounter c) =>
        durationUs > 0 ? (_counts[c] ?? 0) * 1000000 / durationUs : null;
    final result = <String, Object?>{
      'schema': 'bagdar-perception-performance-v1',
      'latencyOrigin': 'dart_camera_callback',
      'captureToDecisionAvailable': false,
      'windowUs': durationUs,
      'cameraCallbackFps': rate(PerceptionCounter.cameraCallbacks),
      'yoloCompletionFps': rate(PerceptionCounter.yoloCompleted),
      'acceptedYoloFps': rate(PerceptionCounter.yoloAccepted),
      'schedule': 'one_start_per_callback_one_active_per_model_no_frame_queue',
      'acceptedDepthFps': rate(PerceptionCounter.depthAccepted),
      'invalidTimingSamples': _invalidSamples,
      'depthRejections': {
        for (final r in DepthRejection.values) r.name: _rejections[r] ?? 0,
      },
      'counts': {
        for (final c in PerceptionCounter.values) c.name: _counts[c] ?? 0,
      },
      'stages': {
        for (final e in _stages.entries) e.key.name: e.value.snapshot(),
      },
    };
    _counts.clear();
    _rejections.clear();
    for (final stage in _stages.values) {
      stage.reset();
    }
    _invalidSamples = 0;
    _window.reset();
    return result;
  }
}

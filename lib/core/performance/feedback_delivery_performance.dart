import 'dart:math' as math;

/// Software milestones only: neither callbacks nor method replies prove the
/// instant at which a person hears audio or feels vibration.
class FeedbackDeliveryPerformance {
  static final instance = FeedbackDeliveryPerformance();
  final int capacity;
  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? _testClock;
  final Map<String, int> _counts = {};
  final Map<String, _Window> _timings = {};

  FeedbackDeliveryPerformance({this.capacity = 256, int Function()? clockUs})
    : _testClock = clockUs {
    if (capacity < 1 || capacity > 4096) throw ArgumentError('capacity');
  }

  int get nowUs => _testClock?.call() ?? _clock.elapsedMicroseconds;
  void count(String name) => _counts[name] = (_counts[name] ?? 0) + 1;

  void record(String name, int elapsedUs) {
    if (elapsedUs < 0) {
      count('invalidTiming');
      return;
    }
    (_timings[name] ??= _Window(capacity)).add(elapsedUs);
  }

  Map<String, Object?> takeWindow() {
    final result = <String, Object?>{
      'schema': 'bagdar-feedback-delivery-v1',
      'origin': 'dart_feedback_dispatch_or_speech_enqueue',
      'actualFirstSoundMeasured': false,
      'actualVibrationMeasured': false,
      'counts': Map<String, int>.of(_counts),
      'timings': {for (final e in _timings.entries) e.key: e.value.snapshot()},
    };
    _counts.clear();
    _timings.clear();
    return result;
  }
}

class _Window {
  final List<int> samples;
  int count = 0;
  int maxUs = 0;
  _Window(int capacity) : samples = List.filled(capacity, 0);

  void add(int value) {
    samples[count++ % samples.length] = value;
    maxUs = math.max(maxUs, value);
  }

  Map<String, Object> snapshot() {
    final retained = math.min(count, samples.length);
    final sorted = samples.take(retained).toList()..sort();
    double percentile(double p) => sorted[(retained * p).ceil() - 1] / 1000;
    return {
      'totalCount': count,
      'sampleCount': retained,
      'overwrittenSamples': count - retained,
      'p50Ms': percentile(.5),
      'p95Ms': percentile(.95),
      'p99Ms': percentile(.99),
      'maxMs': maxUs / 1000,
    };
  }
}

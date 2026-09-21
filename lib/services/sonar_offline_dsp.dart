import 'dart:math' as math;

const int sonarReferenceSampleRateHz = 48000;
const double sonarSpeedOfSoundMps = 343.0;

class SonarWaveformIdentity {
  final int sequence;
  final DateTime capturedAt;
  final int sampleRateHz;
  final String inputRoute;
  final String outputRoute;

  const SonarWaveformIdentity({
    required this.sequence,
    required this.capturedAt,
    required this.sampleRateHz,
    required this.inputRoute,
    required this.outputRoute,
  });

  bool get isValid =>
      sequence >= 0 &&
      capturedAt.isUtc &&
      sampleRateHz == sonarReferenceSampleRateHz &&
      _knownRoute(inputRoute) &&
      _knownRoute(outputRoute);

  static bool _knownRoute(String value) =>
      value.trim().isNotEmpty && !value.toLowerCase().contains('unknown');
}

class SonarOfflineDspInput {
  final SonarWaveformIdentity identity;
  final List<double> reference;
  final List<double> recorded;

  SonarOfflineDspInput({
    required this.identity,
    required List<double> reference,
    required List<double> recorded,
  }) : reference = List.unmodifiable(reference),
       recorded = List.unmodifiable(recorded);
}

class SonarCorrelationPeak {
  final int lagSamples;
  final double correlation;

  const SonarCorrelationPeak({
    required this.lagSamples,
    required this.correlation,
  });
}

class SonarOfflineDspResult {
  final bool accepted;
  final String reason;
  final int? directPathLagSamples;
  final int? echoLagSamples;
  final double? rangeM;
  final double confidence;
  final List<SonarCorrelationPeak> peaks;

  SonarOfflineDspResult({
    required this.accepted,
    required this.reason,
    required this.directPathLagSamples,
    required this.echoLagSamples,
    required this.rangeM,
    required this.confidence,
    required List<SonarCorrelationPeak> peaks,
  }) : peaks = List.unmodifiable(peaks);

  factory SonarOfflineDspResult.rejected(
    String reason, {
    int? directPathLagSamples,
    List<SonarCorrelationPeak> peaks = const <SonarCorrelationPeak>[],
  }) => SonarOfflineDspResult(
    accepted: false,
    reason: reason,
    directPathLagSamples: directPathLagSamples,
    echoLagSamples: null,
    rangeM: null,
    confidence: 0,
    peaks: peaks,
  );
}

/// Deterministic, side-effect-free reference DSP used by the Research gate.
///
/// The direct speaker-to-microphone component is estimated in a bounded early
/// window and removed by least-squares projection. Echo selection is
/// deliberately conservative: among sufficiently strong local maxima it
/// chooses the earliest echo, never a later/stronger multipath return that
/// could make a nearby surface look farther away.
class SonarOfflineDsp {
  final int directPathSearchSamples;
  final int minimumEchoGapSamples;
  final double minimumDirectCorrelation;
  final double minimumEchoCorrelation;
  final double relativePeakFloor;
  final double maximumRangeM;

  const SonarOfflineDsp({
    this.directPathSearchSamples = 24,
    // Keep the search outside the emitted code's direct-path/autocorrelation
    // sidelobes. At 48 kHz this is about 7 cm round-trip range.
    this.minimumEchoGapSamples = 20,
    this.minimumDirectCorrelation = 0.45,
    this.minimumEchoCorrelation = 0.20,
    this.relativePeakFloor = 0.55,
    this.maximumRangeM = 3,
  });

  SonarOfflineDspResult process(SonarOfflineDspInput input) {
    if (!input.identity.isValid) {
      return SonarOfflineDspResult.rejected('invalid_identity');
    }
    if (input.reference.length < 8 ||
        input.recorded.length < input.reference.length * 2 ||
        input.reference.any((value) => !value.isFinite) ||
        input.recorded.any((value) => !value.isFinite)) {
      return SonarOfflineDspResult.rejected('malformed_waveform');
    }
    final refEnergy = _energy(input.reference);
    if (!refEnergy.isFinite || refEnergy <= 1e-9) {
      return SonarOfflineDspResult.rejected('degenerate_reference');
    }

    final lastLag = input.recorded.length - input.reference.length;
    final directEnd = math.min(directPathSearchSamples, lastLag);
    final direct = _strongestPeak(
      input.recorded,
      input.reference,
      startLag: 0,
      endLag: directEnd,
    );
    if (direct == null || direct.correlation < minimumDirectCorrelation) {
      return SonarOfflineDspResult.rejected('direct_path_not_found');
    }

    final cancelled = List<double>.of(input.recorded);
    final scale = _projectionScale(
      cancelled,
      input.reference,
      lag: direct.lagSamples,
      referenceEnergy: refEnergy,
    );
    for (var index = 0; index < input.reference.length; index++) {
      cancelled[direct.lagSamples + index] -= input.reference[index] * scale;
    }

    final maxRoundTripSamples =
        (maximumRangeM * 2 * input.identity.sampleRateHz / sonarSpeedOfSoundMps)
            .ceil();
    final echoStart = direct.lagSamples + minimumEchoGapSamples;
    final echoEnd = math.min(lastLag, direct.lagSamples + maxRoundTripSamples);
    if (echoEnd <= echoStart) {
      return SonarOfflineDspResult.rejected(
        'capture_too_short',
        directPathLagSamples: direct.lagSamples,
      );
    }
    final peaks = _localPeaks(
      cancelled,
      input.reference,
      startLag: echoStart,
      endLag: echoEnd,
    );
    if (peaks.isEmpty) {
      return SonarOfflineDspResult.rejected(
        'no_echo_peak',
        directPathLagSamples: direct.lagSamples,
      );
    }
    final strongest = peaks.map((peak) => peak.correlation).reduce(math.max);
    final threshold = math.max(
      minimumEchoCorrelation,
      strongest * relativePeakFloor,
    );
    final eligible =
        peaks.where((peak) => peak.correlation >= threshold).toList()
          ..sort((a, b) => a.lagSamples.compareTo(b.lagSamples));
    if (eligible.isEmpty) {
      return SonarOfflineDspResult.rejected(
        'echo_below_confidence',
        directPathLagSamples: direct.lagSamples,
        peaks: peaks,
      );
    }
    final selected = eligible.first;
    final roundTripSamples = selected.lagSamples - direct.lagSamples;
    final rangeM =
        roundTripSamples /
        input.identity.sampleRateHz *
        sonarSpeedOfSoundMps /
        2;
    if (!rangeM.isFinite || rangeM <= 0 || rangeM > maximumRangeM) {
      return SonarOfflineDspResult.rejected(
        'range_out_of_bounds',
        directPathLagSamples: direct.lagSamples,
        peaks: peaks,
      );
    }
    return SonarOfflineDspResult(
      accepted: true,
      reason: 'earliest_supported_echo',
      directPathLagSamples: direct.lagSamples,
      echoLagSamples: selected.lagSamples,
      rangeM: rangeM,
      confidence: selected.correlation.clamp(0, 1),
      peaks: peaks,
    );
  }

  SonarCorrelationPeak? _strongestPeak(
    List<double> recorded,
    List<double> reference, {
    required int startLag,
    required int endLag,
  }) {
    SonarCorrelationPeak? best;
    for (var lag = startLag; lag <= endLag; lag++) {
      final correlation = _normalizedCorrelation(recorded, reference, lag);
      if (best == null || correlation > best.correlation) {
        best = SonarCorrelationPeak(lagSamples: lag, correlation: correlation);
      }
    }
    return best;
  }

  List<SonarCorrelationPeak> _localPeaks(
    List<double> recorded,
    List<double> reference, {
    required int startLag,
    required int endLag,
  }) {
    final correlations = <double>[
      for (var lag = startLag; lag <= endLag; lag++)
        _normalizedCorrelation(recorded, reference, lag),
    ];
    final peaks = <SonarCorrelationPeak>[];
    for (var index = 1; index + 1 < correlations.length; index++) {
      final current = correlations[index];
      if (current >= correlations[index - 1] &&
          current > correlations[index + 1] &&
          current >= minimumEchoCorrelation) {
        peaks.add(
          SonarCorrelationPeak(
            lagSamples: startLag + index,
            correlation: current,
          ),
        );
      }
    }
    return peaks;
  }

  double _normalizedCorrelation(
    List<double> recorded,
    List<double> reference,
    int lag,
  ) {
    var dot = 0.0;
    var recordedEnergy = 0.0;
    var referenceEnergy = 0.0;
    for (var index = 0; index < reference.length; index++) {
      final sample = recorded[lag + index];
      final ref = reference[index];
      dot += sample * ref;
      recordedEnergy += sample * sample;
      referenceEnergy += ref * ref;
    }
    final denominator = math.sqrt(recordedEnergy * referenceEnergy);
    if (!denominator.isFinite || denominator <= 1e-12) return 0;
    return (dot / denominator).abs();
  }

  double _projectionScale(
    List<double> recorded,
    List<double> reference, {
    required int lag,
    required double referenceEnergy,
  }) {
    var dot = 0.0;
    for (var index = 0; index < reference.length; index++) {
      dot += recorded[lag + index] * reference[index];
    }
    return dot / referenceEnergy;
  }

  double _energy(List<double> values) =>
      values.fold<double>(0, (sum, value) => sum + value * value);
}

/// Adds sequence/timestamp ordering to the stateless reference DSP.
class SonarOfflineDspSession {
  final SonarOfflineDsp dsp;
  int? _lastSequence;
  DateTime? _lastCapturedAt;

  SonarOfflineDspSession({this.dsp = const SonarOfflineDsp()});

  void reset() {
    _lastSequence = null;
    _lastCapturedAt = null;
  }

  SonarOfflineDspResult process(SonarOfflineDspInput input) {
    final sequence = _lastSequence;
    final capturedAt = _lastCapturedAt;
    if ((sequence != null && input.identity.sequence <= sequence) ||
        (capturedAt != null &&
            !input.identity.capturedAt.isAfter(capturedAt))) {
      reset();
      return SonarOfflineDspResult.rejected('out_of_order_reset');
    }
    _lastSequence = input.identity.sequence;
    _lastCapturedAt = input.identity.capturedAt;
    return dsp.process(input);
  }
}

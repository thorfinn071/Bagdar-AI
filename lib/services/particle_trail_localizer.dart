import 'dart:math' as math;

import '../models/constants.dart';
import '../models/indoor_trail.dart';

/// One hypothesis tracked by the particle filter. Position is expressed
/// as a *step index along the recorded trail*, not as a Cartesian
/// coordinate — the recorded trail is a sequence of (heading, magnitude)
/// observations, and replay only needs to know "where on this path am
/// I right now?" to read the next instruction.
class TrailParticle {
  /// Continuous step position along the trail in [0, sampleCount-1].
  /// May be fractional to model sub-step uncertainty.
  double index;

  /// Unnormalised weight (likelihood × prior). Normalised on each
  /// resample.
  double weight;

  TrailParticle({required this.index, this.weight = 1.0});
}

/// Minimal localisation result returned to `IndoorTrailReplay`.
class TrailLocalization {
  /// Most-likely step index along the recorded trail.
  final double meanIndex;

  /// Uncertainty in step units (standard deviation of the particle
  /// cloud). The replay layer treats a large stddev as "trail lost".
  final double stdIndex;

  /// Effective sample size — small ESS (<25 % of total) is a strong
  /// signal that the filter has lost the trail.
  final double effectiveSampleSize;

  /// Convenience: true when the localiser thinks the user has reached
  /// the recorded destination (last sample) with low uncertainty.
  final bool atDestination;

  const TrailLocalization({
    required this.meanIndex,
    required this.stdIndex,
    required this.effectiveSampleSize,
    required this.atDestination,
  });
}

/// Tiny particle filter that localises the user along a recorded
/// `IndoorTrail`. Designed to be cheap (a few hundred particles, plain
/// Dart math — no native deps) so it can run between camera frames
/// without affecting the safety pipeline.
///
/// Observation model: at each step we observe heading + magnetic
/// magnitude. The likelihood of a particle at step `k` is a product of
/// two von-Mises-ish gaussians on (heading diff, magnitude diff). We
/// deliberately keep this simple — the v1 design ships only when the
/// resulting localisation is empirically stable; otherwise the replay
/// service announces "trail lost" rather than guessing.
class ParticleTrailLocalizer {
  ParticleTrailLocalizer({
    int particleCount = kIndoorTrailParticleCount,
    double headingSigmaDeg = 25.0,
    double magSigmaMicroT = 8.0,
    double stepDriftSigma = 0.4,
    int? seed,
  })  : assert(particleCount >= 16),
        _particles = List<TrailParticle>.generate(
          particleCount,
          (_) => TrailParticle(index: 0),
        ),
        _headingSigma = headingSigmaDeg,
        _magSigma = magSigmaMicroT,
        _stepDriftSigma = stepDriftSigma,
        _rng = math.Random(seed);

  final List<TrailParticle> _particles;
  final double _headingSigma;
  final double _magSigma;
  final double _stepDriftSigma;
  final math.Random _rng;

  /// Step index width considered "at destination".
  static const double _kDestinationTolerance = 1.5;

  /// Recompute everything at the start of a new replay session.
  void reset({int initialSpread = 4}) {
    for (final p in _particles) {
      // Start every particle at the trail head with a small spread so
      // we tolerate the user not being precisely at the entry point.
      p.index = (_rng.nextDouble() * initialSpread).clamp(0.0, double.infinity);
      p.weight = 1.0;
    }
  }

  /// Advance every particle by [stepDelta] steps with a small random
  /// drift, then weight against the [observation] against the recorded
  /// [trail]. Returns the posterior localisation.
  TrailLocalization update({
    required IndoorTrail trail,
    required int stepDelta,
    required double headingDeg,
    required double magMicroT,
  }) {
    if (trail.samples.isEmpty) {
      return const TrailLocalization(
        meanIndex: 0,
        stdIndex: 0,
        effectiveSampleSize: 0,
        atDestination: false,
      );
    }

    final maxIdx = (trail.sampleCount - 1).toDouble();

    // Predict.
    for (final p in _particles) {
      p.index = (p.index + stepDelta + _gaussian() * _stepDriftSigma)
          .clamp(0.0, maxIdx);
    }

    // Weight.
    double sumW = 0;
    for (final p in _particles) {
      final s = _sampleAt(trail, p.index);
      final headingDiff = _angleDiff(headingDeg, s.headingDeg);
      final magDiff = magMicroT - s.magMicroT;
      final w = _gaussianPdf(headingDiff, _headingSigma) *
          _gaussianPdf(magDiff, _magSigma);
      p.weight = w;
      sumW += w;
    }
    if (sumW > 0) {
      for (final p in _particles) {
        p.weight /= sumW;
      }
    } else {
      // Degenerate observation. Fall back to uniform.
      final uniform = 1.0 / _particles.length;
      for (final p in _particles) {
        p.weight = uniform;
      }
    }

    final loc = _summarise(maxIdx);
    if (_effectiveSampleSize() < _particles.length * 0.5) {
      _systematicResample();
    }
    return loc;
  }

  /// Linearly interpolate the trail at a continuous step index.
  IndoorTrailSample _sampleAt(IndoorTrail trail, double index) {
    final i0 = index.floor().clamp(0, trail.sampleCount - 1);
    final i1 = (i0 + 1).clamp(0, trail.sampleCount - 1);
    final s0 = trail.samples[i0];
    final s1 = trail.samples[i1];
    if (i0 == i1) return s0;
    final t = (index - i0).clamp(0.0, 1.0);
    return IndoorTrailSample(
      stepIndex: i0,
      headingDeg: _interpAngle(s0.headingDeg, s1.headingDeg, t),
      magMicroT: s0.magMicroT + (s1.magMicroT - s0.magMicroT) * t,
      accelMag: s0.accelMag + (s1.accelMag - s0.accelMag) * t,
      gyroMag: s0.gyroMag + (s1.gyroMag - s0.gyroMag) * t,
      at: s0.at,
    );
  }

  TrailLocalization _summarise(double maxIdx) {
    double meanIdx = 0;
    for (final p in _particles) {
      meanIdx += p.index * p.weight;
    }
    double varIdx = 0;
    for (final p in _particles) {
      final d = p.index - meanIdx;
      varIdx += p.weight * d * d;
    }
    final stdIdx = math.sqrt(varIdx.clamp(0, double.infinity));
    final ess = _effectiveSampleSize();
    final atDest = (maxIdx - meanIdx).abs() <= _kDestinationTolerance &&
        stdIdx <= _kDestinationTolerance;
    return TrailLocalization(
      meanIndex: meanIdx,
      stdIndex: stdIdx,
      effectiveSampleSize: ess,
      atDestination: atDest,
    );
  }

  double _effectiveSampleSize() {
    double sumSq = 0;
    for (final p in _particles) {
      sumSq += p.weight * p.weight;
    }
    return sumSq <= 0 ? 0 : 1.0 / sumSq;
  }

  /// Low-variance systematic resample.
  void _systematicResample() {
    final n = _particles.length;
    final step = 1.0 / n;
    final start = _rng.nextDouble() * step;
    final cumulative = <double>[];
    double acc = 0;
    for (final p in _particles) {
      acc += p.weight;
      cumulative.add(acc);
    }
    final newIndices = List<double>.filled(n, 0.0);
    var j = 0;
    for (var i = 0; i < n; i++) {
      final u = start + i * step;
      while (j < n - 1 && u > cumulative[j]) {
        j++;
      }
      newIndices[i] = _particles[j].index;
    }
    for (var i = 0; i < n; i++) {
      _particles[i].index = newIndices[i];
      _particles[i].weight = 1.0 / n;
    }
  }

  // -- Math helpers ----------------------------------------------------

  static double _angleDiff(double a, double b) {
    var d = (a - b) % 360.0;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  static double _interpAngle(double a, double b, double t) {
    final d = _angleDiff(b, a);
    return (a + d * t) % 360.0;
  }

  static double _gaussianPdf(double x, double sigma) {
    final s2 = sigma * sigma;
    return math.exp(-0.5 * (x * x) / s2);
  }

  double _gaussian() {
    // Box-Muller. Not perf-critical; ~200 calls per step.
    final u1 = math.max(1e-9, _rng.nextDouble());
    final u2 = _rng.nextDouble();
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}

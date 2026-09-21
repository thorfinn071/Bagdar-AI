import 'feedback_command.dart';

enum HapticSemantic { immediateStop, sensingDegraded, confirmation }

class HapticDeviceCapabilities {
  final bool hasVibrator;
  final bool hasAmplitudeControl;

  const HapticDeviceCapabilities({
    required this.hasVibrator,
    required this.hasAmplitudeControl,
  });
}

class HapticCue {
  final HapticSemantic semantic;
  final List<int> pattern;
  final List<int>? intensities;
  final bool critical;

  HapticCue({
    required this.semantic,
    required List<int> pattern,
    required List<int>? intensities,
    required this.critical,
  }) : pattern = List.unmodifiable(pattern),
       intensities = intensities == null
           ? null
           : List.unmodifiable(intensities);

  int get activeDurationMs {
    var total = 0;
    for (var index = 1; index < pattern.length; index += 2) {
      total += pattern[index];
    }
    return total;
  }
}

class HapticPolicyDecision {
  final HapticCue? cue;
  final String reason;

  const HapticPolicyDecision({required this.cue, required this.reason});
}

class _DutySample {
  final DateTime at;
  final int activeDurationMs;

  const _DutySample(this.at, this.activeDurationMs);
}

/// Three-semantics haptic policy for Core spatial feedback.
///
/// It deliberately has no direction input: left/right is not encoded on a
/// single vibration motor before user validation.
class HapticPolicy {
  final Duration dutyWindow;
  final int maxActiveMsPerWindow;
  final Duration criticalCooldown;
  final Duration criticalEscalationCooldown;
  final Duration degradedCooldown;
  final Duration confirmationCooldown;

  final Map<HapticSemantic, DateTime> _lastEmittedAt =
      <HapticSemantic, DateTime>{};
  final List<_DutySample> _dutySamples = <_DutySample>[];

  HapticPolicy({
    this.dutyWindow = const Duration(seconds: 10),
    this.maxActiveMsPerWindow = 1800,
    this.criticalCooldown = const Duration(milliseconds: 1200),
    this.criticalEscalationCooldown = const Duration(milliseconds: 300),
    this.degradedCooldown = const Duration(seconds: 5),
    this.confirmationCooldown = const Duration(milliseconds: 600),
  }) : assert(maxActiveMsPerWindow > 0);

  HapticPolicyDecision decide(
    FeedbackHapticPattern pattern, {
    required DateTime now,
    required HapticDeviceCapabilities device,
    bool riskIncreased = false,
  }) {
    if (pattern == FeedbackHapticPattern.none) {
      return const HapticPolicyDecision(cue: null, reason: 'no_haptic');
    }
    if (!device.hasVibrator) {
      return const HapticPolicyDecision(cue: null, reason: 'no_vibrator');
    }

    final semantic = switch (pattern) {
      FeedbackHapticPattern.immediateStop => HapticSemantic.immediateStop,
      FeedbackHapticPattern.sensingDegraded => HapticSemantic.sensingDegraded,
      FeedbackHapticPattern.confirmation => HapticSemantic.confirmation,
      FeedbackHapticPattern.none => throw StateError('handled above'),
    };
    final last = _lastEmittedAt[semantic];
    final cooldown = switch (semantic) {
      HapticSemantic.immediateStop =>
        riskIncreased ? criticalEscalationCooldown : criticalCooldown,
      HapticSemantic.sensingDegraded => degradedCooldown,
      HapticSemantic.confirmation => confirmationCooldown,
    };
    if (last != null && now.difference(last) < cooldown) {
      return const HapticPolicyDecision(cue: null, reason: 'semantic_cooldown');
    }

    _pruneDuty(now);
    var cue = _cueFor(semantic, device.hasAmplitudeControl);
    final used = _dutySamples.fold<int>(
      0,
      (sum, sample) => sum + sample.activeDurationMs,
    );
    if (used + cue.activeDurationMs > maxActiveMsPerWindow) {
      if (semantic != HapticSemantic.immediateStop) {
        return const HapticPolicyDecision(
          cue: null,
          reason: 'duty_cycle_budget_exhausted',
        );
      }
      cue = HapticCue(
        semantic: semantic,
        pattern: const <int>[0, 80],
        intensities: device.hasAmplitudeControl ? const <int>[0, 255] : null,
        critical: true,
      );
      if (used + cue.activeDurationMs > maxActiveMsPerWindow) {
        return const HapticPolicyDecision(
          cue: null,
          reason: 'duty_cycle_budget_exhausted',
        );
      }
    }

    _lastEmittedAt[semantic] = now;
    _dutySamples.add(_DutySample(now, cue.activeDurationMs));
    return HapticPolicyDecision(cue: cue, reason: 'emit');
  }

  HapticCue _cueFor(HapticSemantic semantic, bool amplitudeControl) {
    final pattern = switch (semantic) {
      HapticSemantic.immediateStop => const <int>[0, 180, 60, 180, 60, 180],
      HapticSemantic.sensingDegraded => const <int>[0, 160, 100, 160],
      HapticSemantic.confirmation => const <int>[0, 80],
    };
    final intensities = amplitudeControl
        ? switch (semantic) {
            HapticSemantic.immediateStop => const <int>[0, 255, 0, 255, 0, 255],
            HapticSemantic.sensingDegraded => const <int>[0, 190, 0, 190],
            HapticSemantic.confirmation => const <int>[0, 150],
          }
        : null;
    return HapticCue(
      semantic: semantic,
      pattern: pattern,
      intensities: intensities,
      critical: semantic == HapticSemantic.immediateStop,
    );
  }

  void _pruneDuty(DateTime now) {
    _dutySamples.removeWhere(
      (sample) => now.difference(sample.at) >= dutyWindow,
    );
  }
}

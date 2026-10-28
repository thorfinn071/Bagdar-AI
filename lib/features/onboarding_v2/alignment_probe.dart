import '../../services/orientation_service.dart';
import 'onboarding_state.dart';

/// Uses the existing runtime pitch/roll contract. This measures a stationary
/// sensor window; it cannot establish camera direction or obstacle accuracy.
class OnboardingAlignmentProbe {
  static const stableDuration = Duration(seconds: 2);
  static const maxGap = Duration(milliseconds: 600);
  final _samples = <({double pitch, double roll, DateTime at})>[];
  DateTime? _last;
  String _hint = 'alignmentUnavailable';

  void unavailable() {
    _samples.clear();
    _last = null;
    _hint = 'alignmentUnavailable';
  }

  void observe({
    required double pitch,
    required double roll,
    required DateTime at,
  }) {
    if (!pitch.isFinite ||
        !roll.isFinite ||
        (_last != null && !at.isAfter(_last!))) {
      unavailable();
      return;
    }
    if (_last != null && at.difference(_last!) >= maxGap) _samples.clear();
    _last = at;
    _hint = roll.abs() >= OrientationService.kRollExitThreshold
        ? 'alignmentLevel'
        : pitch <= 30
        ? 'alignmentMoreUpright'
        : pitch >= 60
        ? 'alignmentMoreFlat'
        : 'alignmentHoldStill';
    if (_hint != 'alignmentHoldStill') {
      _samples.clear();
      return;
    }
    if (_samples.isNotEmpty &&
        ((pitch - _samples.last.pitch).abs() >= 8 ||
            (roll - _samples.last.roll).abs() >= 8)) {
      _samples.clear();
    }
    _samples.add((pitch: pitch, roll: roll, at: at));
    _samples.removeWhere(
      (sample) => at.difference(sample.at) > const Duration(seconds: 3),
    );
  }

  ProbeResult result(DateTime now) {
    if (_last == null ||
        now.isBefore(_last!) ||
        now.difference(_last!) >= maxGap) {
      return ProbeResult(ProbeStatus.unavailable, 'alignmentUnavailable', now);
    }
    var stable =
        _samples.length >= 15 &&
        _samples.last.at.difference(_samples.first.at) >= stableDuration;
    if (stable) {
      for (final sample in _samples) {
        if ((sample.pitch - _samples.last.pitch).abs() >= 8 ||
            (sample.roll - _samples.last.roll).abs() >= 8) {
          stable = false;
          break;
        }
      }
    }
    return ProbeResult(
      stable ? ProbeStatus.available : ProbeStatus.unavailable,
      stable ? 'alignmentStable' : _hint,
      now,
    );
  }
}

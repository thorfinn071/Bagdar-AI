import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/alignment_probe.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';

void main() {
  final start = DateTime(2026, 10, 1, 12);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));
  void stable(
    OnboardingAlignmentProbe probe, {
    int from = 0,
    int until = 2400,
  }) {
    for (var ms = from; ms <= until; ms += 100) {
      probe.observe(pitch: 45, roll: 0, at: at(ms));
    }
  }

  test('fresh stable samples meet the existing angular bounds', () {
    final probe = OnboardingAlignmentProbe();
    stable(probe);
    expect(probe.result(at(2500)).status, ProbeStatus.available);
    expect(probe.result(at(2500)).reason, 'alignmentStable');
  });

  for (final condition in [
    (30.0, 0.0, 'alignmentMoreUpright'),
    (60.0, 0.0, 'alignmentMoreFlat'),
    (45.0, 25.0, 'alignmentLevel'),
    (45.0, -25.0, 'alignmentLevel'),
  ]) {
    test('reports ${condition.$3} while keeping admission unavailable', () {
      final probe = OnboardingAlignmentProbe();
      for (var ms = 0; ms <= 2400; ms += 100) {
        probe.observe(pitch: condition.$1, roll: condition.$2, at: at(ms));
      }
      expect(probe.result(at(2500)).status, ProbeStatus.unavailable);
      expect(probe.result(at(2500)).reason, condition.$3);
    });
  }

  test(
    'an initially incorrect position can recover with a fresh stable window',
    () {
      final probe = OnboardingAlignmentProbe();
      probe.observe(pitch: 70, roll: 0, at: at(0));
      stable(probe, from: 100);
      expect(probe.result(at(2500)).status, ProbeStatus.available);
    },
  );

  test('too few, short or gapped samples never look stable', () {
    final probe = OnboardingAlignmentProbe();
    stable(probe, until: 1200);
    expect(probe.result(at(1300)).reason, 'alignmentHoldStill');
    stable(probe, from: 2000, until: 2600);
    expect(probe.result(at(2700)).status, ProbeStatus.unavailable);
    final sparse = OnboardingAlignmentProbe();
    for (var ms = 0; ms <= 2400; ms += 400) {
      sparse.observe(pitch: 45, roll: 0, at: at(ms));
    }
    expect(sparse.result(at(2500)).status, ProbeStatus.unavailable);
  });

  test('motion, stale data, future clock and non-finite data fail closed', () {
    final probe = OnboardingAlignmentProbe();
    stable(probe);
    expect(probe.result(at(3000)).status, ProbeStatus.unavailable);
    expect(probe.result(at(2300)).status, ProbeStatus.unavailable);
    probe.observe(pitch: 55, roll: 0, at: at(2500));
    expect(probe.result(at(2600)).reason, 'alignmentHoldStill');
    probe.observe(pitch: double.nan, roll: 0, at: at(2700));
    expect(probe.result(at(2800)).reason, 'alignmentUnavailable');
  });

  test('sensor loss or out-of-order samples invalidate the stable window', () {
    final probe = OnboardingAlignmentProbe();
    stable(probe);
    probe.observe(pitch: 45, roll: 0, at: at(2300));
    expect(probe.result(at(2500)).status, ProbeStatus.unavailable);
    stable(probe, from: 3000, until: 5400);
    probe.unavailable();
    expect(probe.result(at(5500)).status, ProbeStatus.unavailable);
  });
}

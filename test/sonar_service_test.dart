import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/sonar_service.dart';
import 'package:bagdar/models/constants.dart';

void main() {
  group('SonarRangeEstimate', () {
    test('isUsable above minimum confidence', () {
      final estimate = SonarRangeEstimate(
        rangeM: 1.0,
        confidence: 0.6,
        at: DateTime.now(),
      );
      expect(estimate.isUsable, true);
    });

    test('isUsable true above threshold', () {
      final estimate = SonarRangeEstimate(
        rangeM: 1.0,
        confidence: 0.5,
        at: DateTime.now(),
      );
      expect(estimate.isUsable, true);
    });

    test('isUsable false below threshold', () {
      final estimate = SonarRangeEstimate(
        rangeM: 1.0,
        confidence: 0.2,
        at: DateTime.now(),
      );
      expect(estimate.isUsable, false);
    });

    test('isUsable at exact threshold', () {
      final estimate = SonarRangeEstimate(
        rangeM: 1.0,
        confidence: kSonarMinConfidence,
        at: DateTime.now(),
      );
      expect(estimate.isUsable, true);
    });
  });

  group('SonarService', () {
    late SonarService service;

    setUp(() {
      service = SonarService.instance;
      service.resetForTesting();
    });

    test('initial state is idle', () {
      expect(service.state, SonarState.idle);
      expect(service.isActive, false);
      expect(service.lastRangeM, -1);
      expect(service.lastConfidence, 0);
      expect(service.isCalibrated, false);
    });

    test('resetForTesting clears state', () {
      service.resetForTesting();
      expect(service.state, SonarState.idle);
      expect(service.lastRangeM, -1);
    });

    test('kSonarMaxRangeM is reasonable for budget phones', () {
      expect(kSonarMaxRangeM, 3.0);
    });

    test('kSonarMinChirpHz is in ultrasonic range', () {
      expect(kSonarMinChirpHz, greaterThanOrEqualTo(18000));
    });

    test('hazard cooldown is sensible', () {
      expect(kSonarHazardCooldown.inSeconds, greaterThanOrEqualTo(3));
    });
  });
}

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

  group('SonarCapabilityContract', () {
    test('admits only an exact near-ultrasound route', () {
      final capability = SonarCapabilityContract.fromMap({
        'micNearUltrasound': true,
        'speakerNearUltrasound': true,
        'unprocessedInput': true,
        'sampleRateHz': 48000,
        'inputRoute': 'types:15',
        'outputRoute': 'types:2',
      });

      expect(capability.admitted, true);
    });

    test('unknown or missing values fail closed', () {
      expect(SonarCapabilityContract.fromMap(const {}).admitted, false);
      expect(
        SonarCapabilityContract.fromMap({
          'micNearUltrasound': true,
          'speakerNearUltrasound': true,
          'unprocessedInput': false,
          'sampleRateHz': 48000,
          'inputRoute': 'types:15',
          'outputRoute': 'types:2',
        }).admitted,
        false,
      );
    });
  });

  group('SonarCalibrationReport', () {
    Map<String, Object> validReport() => <String, Object>{
      'schemaVersion': 1,
      'chirpCount': 8,
      'sampleRateHz': 48000,
      'directPathCancellationApplied': true,
      'multipathPeakSelectionApplied': true,
      'acousticLevelValidated': true,
      'repeatabilityMadM': 0.08,
      'routeFingerprint': 'types:15|types:2',
    };

    test('admits complete bounded calibration evidence', () {
      expect(SonarCalibrationReport.fromMap(validReport()).admitted, true);
    });

    test('rejects the current prototype without required DSP evidence', () {
      final report = validReport()
        ..['directPathCancellationApplied'] = false
        ..['multipathPeakSelectionApplied'] = false
        ..['acousticLevelValidated'] = false
        ..['repeatabilityMadM'] = -1.0;

      expect(SonarCalibrationReport.fromMap(report).admitted, false);
    });

    test('rejects weak repeatability and an unknown route', () {
      final report = validReport()
        ..['repeatabilityMadM'] = 0.13
        ..['routeFingerprint'] = 'unknown';

      expect(SonarCalibrationReport.fromMap(report).admitted, false);
    });

    test('rejects negative repeatability and a partially unknown route', () {
      final report = validReport()
        ..['repeatabilityMadM'] = -1.0
        ..['routeFingerprint'] = 'unknown|types:2';

      expect(SonarCalibrationReport.fromMap(report).admitted, false);
    });
  });

  group('SonarMultiChirpConsensus', () {
    test('one chirp never creates an observation', () {
      final consensus = SonarMultiChirpConsensus();
      final at = DateTime.utc(2026, 9, 20);

      expect(
        consensus.add(SonarRangeEstimate(rangeM: 0.8, confidence: 0.9, at: at)),
        isNull,
      );
    });

    test('creates a shadow median from four consistent usable chirps', () {
      final consensus = SonarMultiChirpConsensus();
      final at = DateTime.utc(2026, 9, 20);
      final samples = <(double, double)>[
        (0.80, 0.90),
        (0.84, 0.80),
        (0.82, 0.85),
        (0.81, 0.75),
        (2.50, 0.10),
      ];
      SonarShadowObservation? observation;
      for (var index = 0; index < samples.length; index++) {
        observation = consensus.add(
          SonarRangeEstimate(
            rangeM: samples[index].$1,
            confidence: samples[index].$2,
            at: at.add(Duration(milliseconds: index * 200)),
          ),
        );
      }

      expect(observation, isNotNull);
      expect(observation!.rangeM, closeTo(0.815, 0.0001));
      expect(observation.spreadM, closeTo(0.04, 0.0001));
      expect(observation.chirpCount, 4);
      expect(observation.toDiagnosticMap()['delivery'], 'shadow');
    });

    test('rejects inconsistent chirps', () {
      final consensus = SonarMultiChirpConsensus();
      final at = DateTime.utc(2026, 9, 20);
      SonarShadowObservation? observation;
      for (var index = 0; index < 5; index++) {
        observation = consensus.add(
          SonarRangeEstimate(
            rangeM: 0.5 + index * 0.2,
            confidence: 0.9,
            at: at.add(Duration(milliseconds: index * 200)),
          ),
        );
      }

      expect(observation, isNull);
    });

    test('expires an old partial window', () {
      final consensus = SonarMultiChirpConsensus();
      final at = DateTime.utc(2026, 9, 20);
      for (var index = 0; index < 4; index++) {
        expect(
          consensus.add(
            SonarRangeEstimate(
              rangeM: 0.8,
              confidence: 0.9,
              at: at.add(Duration(milliseconds: index * 100)),
            ),
          ),
          isNull,
        );
      }

      expect(
        consensus.add(
          SonarRangeEstimate(
            rangeM: 0.8,
            confidence: 0.9,
            at: at.add(const Duration(seconds: 3)),
          ),
        ),
        isNull,
      );
    });

    test('out-of-order chirp resets consensus', () {
      final consensus = SonarMultiChirpConsensus();
      final at = DateTime.utc(2026, 9, 20);
      for (var index = 0; index < 4; index++) {
        consensus.add(
          SonarRangeEstimate(
            rangeM: 0.8,
            confidence: 0.9,
            at: at.add(Duration(milliseconds: index * 100)),
          ),
        );
      }

      expect(
        consensus.add(
          SonarRangeEstimate(
            rangeM: 0.8,
            confidence: 0.9,
            at: at.add(const Duration(milliseconds: 150)),
          ),
        ),
        isNull,
      );
      for (var index = 4; index < 8; index++) {
        expect(
          consensus.add(
            SonarRangeEstimate(
              rangeM: 0.8,
              confidence: 0.9,
              at: at.add(Duration(milliseconds: index * 100)),
            ),
          ),
          isNull,
        );
      }
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
      expect(service.lastShadowObservation, isNull);
      expect(SonarService.userAlertsEnabled, false);
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

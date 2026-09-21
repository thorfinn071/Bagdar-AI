import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/oscp_service.dart';

void main() {
  group('OscpGatt', () {
    test('service UUID is stable', () {
      expect(OscpGatt.kServiceUuid, '00001810-0000-1000-8000-00805f9b34fb');
    });

    test('range stream UUID is stable', () {
      expect(OscpGatt.kRangeStreamUuid, '00002a6e-0000-1000-8000-00805f9b34fb');
    });
  });

  group('OscpRangeEstimate', () {
    test('isNearField triggers below threshold', () {
      final estimate = OscpRangeEstimate(
        rangeM: 0.8,
        confidence: 0.9,
        at: DateTime.now(),
      );
      expect(estimate.isNearField, true);
    });

    test('isNearField false above threshold', () {
      final estimate = OscpRangeEstimate(
        rangeM: 2.0,
        confidence: 0.9,
        at: DateTime.now(),
      );
      expect(estimate.isNearField, false);
    });
  });

  group('OscpImuSnapshot', () {
    test('isSweepMotion detects fast cane swings', () {
      final imu = OscpImuSnapshot(
        accelMag: 12.0,
        gyroMag: 3.5,
        at: DateTime.now(),
      );
      expect(imu.isSweepMotion, true);
    });

    test('isSweepMotion false for slow motion', () {
      final imu = OscpImuSnapshot(
        accelMag: 9.8,
        gyroMag: 0.5,
        at: DateTime.now(),
      );
      expect(imu.isSweepMotion, false);
    });
  });

  group('OscpService', () {
    late OscpService service;

    setUp(() {
      service = OscpService.instance;
      service.resetForTesting();
    });

    test('initial state is disconnected', () {
      expect(service.connectionState, OscpConnectionState.disconnected);
      expect(service.isConnected, false);
      expect(service.smoothedRangeM, -1);
      expect(service.podBatteryPct, -1);
    });

    test('resetForTesting clears state', () {
      service.resetForTesting();
      expect(service.connectionState, OscpConnectionState.disconnected);
      expect(service.smoothedRangeM, -1);
    });
  });
}

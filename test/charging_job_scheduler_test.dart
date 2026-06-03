import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/charging_job_scheduler.dart';
import 'package:bagdar/utils/performance_throttler.dart';
import 'package:bagdar/services/thermal_monitor.dart';

void main() {
  group('ChargingJobGate', () {
    test('all gates pass when conditions are met', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 80,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, true);
      expect(gate.denyReason, 'ok');
    });

    test('fails when not charging', () {
      const gate = ChargingJobGate(
        charging: false,
        wifiAvailable: true,
        batteryPct: 80,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, false);
      expect(gate.denyReason, 'not_charging');
    });

    test('fails when battery too low', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 30,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, false);
      expect(gate.denyReason, 'low_battery');
    });

    test('fails when thermal is hot', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 80,
        thermal: ThermalSeverity.hot,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, false);
      expect(gate.denyReason, contains('thermal'));
    });

    test('fails when memory is critical', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 80,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.critical,
      );
      expect(gate.allSatisfied, false);
      expect(gate.denyReason, 'memory_critical');
    });

    test('passes with warm thermal', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 80,
        thermal: ThermalSeverity.warm,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, true);
    });

    test('battery at boundary 40 fails', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 40,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, false);
    });

    test('battery at 41 passes', () {
      const gate = ChargingJobGate(
        charging: true,
        wifiAvailable: true,
        batteryPct: 41,
        thermal: ThermalSeverity.normal,
        memory: MemoryPressureLevel.normal,
      );
      expect(gate.allSatisfied, true);
    });
  });

  group('ChargingJobScheduler', () {
    late ChargingJobScheduler scheduler;

    setUp(() {
      scheduler = ChargingJobScheduler.instance;
      scheduler.resetForTesting();
    });

    test('initial state is idle', () {
      expect(scheduler.state, ChargingJobState.idle);
    });

    test('readGates uses providers', () {
      scheduler.isChargingProvider = () => true;
      scheduler.isWifiProvider = () => true;
      scheduler.batteryPctProvider = () => 90;
      scheduler.thermalProvider = () => ThermalSeverity.normal;
      scheduler.memoryProvider = () => MemoryPressureLevel.normal;

      final gate = scheduler.readGates();
      expect(gate.allSatisfied, true);
    });

    test('readGates defaults to conservative when no providers', () {
      scheduler.isChargingProvider = null;
      scheduler.batteryPctProvider = null;
      final gate = scheduler.readGates();
      expect(gate.charging, false);
      expect(gate.batteryPct, 0);
      expect(gate.allSatisfied, false);
    });

    test('cancel from waitingForGates returns to idle', () {
      scheduler.resetForTesting();
      scheduler.cancel();
      expect(scheduler.state, ChargingJobState.idle);
    });

    test('schedule never runs work when all providers are null', () async {
      scheduler.resetForTesting();
      scheduler.isChargingProvider = null;
      scheduler.isWifiProvider = null;
      scheduler.batteryPctProvider = null;
      scheduler.thermalProvider = null;
      scheduler.memoryProvider = null;

      var workCalled = false;
      scheduler.schedule(
        work: (isCancelled) async { workCalled = true; return true; },
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(workCalled, isFalse,
          reason: 'work must not run when providers are null — gates always false');
      expect(scheduler.state, isNot(ChargingJobState.running));
      scheduler.cancel();
    });
  });
}

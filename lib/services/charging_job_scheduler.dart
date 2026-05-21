import 'dart:async';

import 'package:flutter/foundation.dart';

import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'thermal_monitor.dart';
import '../utils/performance_throttler.dart';

/// Gate conditions that must all be satisfied before a training or
/// adapter optimization job may run. Mirrors the plan's requirements:
/// charger connected, Wi-Fi available, battery > 40%, thermal
/// normal/warm, and memory headroom above low threshold.
class ChargingJobGate {
  final bool charging;
  final bool wifiAvailable;
  final int batteryPct;
  final ThermalSeverity thermal;
  final MemoryPressureLevel memory;

  const ChargingJobGate({
    required this.charging,
    required this.wifiAvailable,
    required this.batteryPct,
    required this.thermal,
    required this.memory,
  });

  bool get allSatisfied =>
      charging &&
      batteryPct > 40 &&
      (thermal == ThermalSeverity.normal || thermal == ThermalSeverity.warm) &&
      memory != MemoryPressureLevel.critical;

  String get denyReason {
    if (!charging) return 'not_charging';
    if (batteryPct <= 40) return 'low_battery';
    if (thermal != ThermalSeverity.normal && thermal != ThermalSeverity.warm) {
      return 'thermal_$thermal';
    }
    if (memory == MemoryPressureLevel.critical) return 'memory_critical';
    return 'ok';
  }
}

/// State of the training job scheduler.
enum ChargingJobState {
  idle,
  waitingForGates,
  running,
  completed,
  failed,
}

/// Callback type for the actual training/adapter work. The scheduler
/// calls this when all gates are open; it should return `true` on
/// success and `false` on failure. The function must check for
/// cancellation via [isCancelled] periodically.
typedef ChargingJobWork = Future<bool> Function(bool Function() isCancelled);

/// Scheduler that gates long-running training / adapter optimisation
/// jobs behind charger + thermal + battery + memory conditions.
///
/// Phase 3 — Direction 4. Only one job at a time; managed via the
/// `SensorResource.trainingJob` lease in [SensorSessionCoordinator].
///
/// The scheduler polls gate conditions at [_kPollInterval] and starts
/// the registered work function when all gates open. If any gate
/// closes during execution, the job is cancelled gracefully.
class ChargingJobScheduler {
  ChargingJobScheduler._();

  static final ChargingJobScheduler instance = ChargingJobScheduler._();

  static const Duration _kPollInterval = Duration(seconds: 15);

  ChargingJobState _state = ChargingJobState.idle;
  Timer? _pollTimer;
  SessionLease? _trainingLease;
  bool _cancelRequested = false;

  /// User-provided gate readers. Set these in `CameraViewModel.init()`
  /// or test setup before calling [schedule].
  bool Function()? isChargingProvider;
  bool Function()? isWifiProvider;
  int Function()? batteryPctProvider;
  ThermalSeverity Function()? thermalProvider;
  MemoryPressureLevel Function()? memoryProvider;

  ChargingJobState get state => _state;

  /// Evaluate current gate conditions.
  ChargingJobGate readGates() => ChargingJobGate(
        charging: isChargingProvider?.call() ?? false,
        wifiAvailable: isWifiProvider?.call() ?? false,
        batteryPct: batteryPctProvider?.call() ?? 0,
        thermal: thermalProvider?.call() ?? ThermalSeverity.normal,
        memory: memoryProvider?.call() ?? MemoryPressureLevel.normal,
      );

  /// Schedule a job. Begins polling gate conditions. When all gates
  /// open, acquires a `trainingJob` lease and runs [work]. Returns
  /// immediately; completion is reported via [onComplete].
  void schedule({
    required ChargingJobWork work,
    void Function(bool success)? onComplete,
  }) {
    if (_state == ChargingJobState.running ||
        _state == ChargingJobState.waitingForGates) {
      debugPrint('ChargingJobScheduler: job already in progress');
      return;
    }
    _cancelRequested = false;
    _state = ChargingJobState.waitingForGates;

    FieldLogger.instance.log('charging_job_scheduled', {});

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kPollInterval, (_) {
      _tryStart(work, onComplete);
    });
    _tryStart(work, onComplete);
  }

  void cancel() {
    _cancelRequested = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_state == ChargingJobState.waitingForGates) {
      _state = ChargingJobState.idle;
    }
    SensorSessionCoordinator.instance.release(_trainingLease);
    _trainingLease = null;
    FieldLogger.instance.log('charging_job_cancelled', {});
  }

  void dispose() {
    cancel();
  }

  Future<void> _tryStart(
    ChargingJobWork work,
    void Function(bool success)? onComplete,
  ) async {
    if (_cancelRequested || _state == ChargingJobState.running) return;

    final gates = readGates();
    if (!gates.allSatisfied) {
      FieldLogger.instance.log('charging_job_gate_denied', {
        'reason': gates.denyReason,
      });
      return;
    }

    final grant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.trainingJob,
      priority: SessionPriority.background,
      owner: 'ChargingJobScheduler',
    );
    if (!grant.isGranted) {
      FieldLogger.instance.log('charging_job_lease_denied', {
        'reason': grant.denyReason?.name ?? 'unknown',
      });
      return;
    }
    _trainingLease = grant.lease;

    _pollTimer?.cancel();
    _pollTimer = null;
    _state = ChargingJobState.running;

    FieldLogger.instance.log('charging_job_started', {
      'battery': gates.batteryPct,
      'thermal': gates.thermal.name,
    });

    try {
      final success = await work(() => _cancelRequested);
      _state =
          success ? ChargingJobState.completed : ChargingJobState.failed;
      FieldLogger.instance.log('charging_job_finished', {
        'success': success,
      });
      onComplete?.call(success);
    } catch (e) {
      _state = ChargingJobState.failed;
      FieldLogger.instance.log('charging_job_error', {
        'error': e.toString(),
      });
      onComplete?.call(false);
    } finally {
      SensorSessionCoordinator.instance.release(_trainingLease);
      _trainingLease = null;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    cancel();
    _state = ChargingJobState.idle;
    _cancelRequested = false;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import '../models/external_hazard.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import 'device_capability.dart';
import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'settings_service.dart';

/// OSCP GATT characteristic UUIDs. These match the stable spec defined
/// in the hardware repo. Services outside this file should never need
/// to reference individual UUIDs.
class OscpGatt {
  OscpGatt._();

  static const String kServiceUuid = '00001810-0000-1000-8000-00805f9b34fb';
  static const String kRangeStreamUuid = '00002a6e-0000-1000-8000-00805f9b34fb';
  static const String kImuStreamUuid = '00002a6f-0000-1000-8000-00805f9b34fb';
  static const String kButtonEventUuid = '00002a70-0000-1000-8000-00805f9b34fb';
  static const String kBatteryUuid = '00002a19-0000-1000-8000-00805f9b34fb';
  static const String kFirmwareUuid = '00002a26-0000-1000-8000-00805f9b34fb';
  static const String kCalibrationUuid = '00002a71-0000-1000-8000-00805f9b34fb';
}

/// Smoothed range estimate from the OSCP cane sensor.
class OscpRangeEstimate {
  final double rangeM;
  final double confidence;
  final DateTime at;

  const OscpRangeEstimate({
    required this.rangeM,
    required this.confidence,
    required this.at,
  });

  bool get isNearField => rangeM < kOscpNearFieldThresholdM;
}

/// IMU snapshot from the cane. Used only as auxiliary fall detection
/// signal — never as the primary SOS trigger (risk gate).
class OscpImuSnapshot {
  final double accelMag;
  final double gyroMag;
  final DateTime at;

  const OscpImuSnapshot({
    required this.accelMag,
    required this.gyroMag,
    required this.at,
  });

  bool get isSweepMotion => gyroMag > kOscpSweepGyroThreshold;
}

/// Connection state of the OSCP pod.
enum OscpConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

/// Service that manages the Open Smart-Cane Sensor Pod BLE connection.
///
/// Phase 2 — Direction 7. Communicates with the OSCP pod via the
/// `bagdar/oscp_pod` MethodChannel. The native side handles BLE
/// scanning, GATT connection, packet validation, and reconnection.
///
/// This service:
/// - Connects to a paired OSCP pod on demand.
/// - Receives smoothed range stream and emits near-field hazard events.
/// - Receives cane IMU stream as an auxiliary signal for FallDetector.
/// - Handles button events from the cane (future: voice command trigger).
/// - Monitors pod battery level.
///
/// Risk gate: The app remains fully usable without the pod. OSCP cannot
/// become a required dependency. Cane IMU never makes SOS depend on
/// external hardware.
class OscpService {
  OscpService._();

  static final OscpService instance = OscpService._();

  static const MethodChannel _channel = MethodChannel('bagdar/oscp_pod');

  void Function(ExternalHazardEvent event)? onHazard;
  void Function(OscpImuSnapshot imu)? onImu;
  void Function()? onButtonPress;

  OscpConnectionState _state = OscpConnectionState.disconnected;
  SessionLease? _bleLease;

  double _smoothedRangeM = -1;
  int _podBatteryPct = -1;
  String _firmwareVersion = '';
  DateTime _lastNearFieldAt = DateTime.fromMillisecondsSinceEpoch(0);

  OscpConnectionState get connectionState => _state;
  double get smoothedRangeM => _smoothedRangeM;
  int get podBatteryPct => _podBatteryPct;
  String get firmwareVersion => _firmwareVersion;
  bool get isConnected => _state == OscpConnectionState.connected;

  /// Start scanning for / connecting to the OSCP pod. No-op if the
  /// feature flag is off or the device lacks BLE central.
  Future<bool> connect() async {
    if (_state == OscpConnectionState.connected ||
        _state == OscpConnectionState.connecting) {
      return _state == OscpConnectionState.connected;
    }
    if (!Settings.instance.oscpPod) {
      FieldLogger.instance.logOscpPod('connect_blocked_flag_off');
      return false;
    }

    try {
      final caps = DeviceCapabilityProbe.cached;
      if (!caps.hardware.bleCentral) {
        FieldLogger.instance.logOscpPod('connect_blocked_no_ble');
        return false;
      }
    } catch (_) {
      FieldLogger.instance.logOscpPod('connect_blocked_probe_failed');
      return false;
    }

    final grant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.bluetoothCentral,
      priority: SessionPriority.foregroundFeature,
      owner: 'OscpService',
    );
    if (!grant.isGranted) {
      FieldLogger.instance.logOscpPod('connect_blocked_ble_busy', data: {
        'reason': grant.denyReason?.name ?? 'unknown',
      });
      return false;
    }
    _bleLease = grant.lease;

    _state = OscpConnectionState.scanning;

    try {
      final ok = await _channel.invokeMethod<bool>('connectOscp') ?? false;
      if (!ok) {
        _releaseAndDisconnect();
        FieldLogger.instance.logOscpPod('connect_plugin_failed');
        return false;
      }
      _state = OscpConnectionState.connecting;
      _channel.setMethodCallHandler(_handleNativeCall);
      FieldLogger.instance.logOscpPod('connecting');
      return true;
    } on MissingPluginException {
      _releaseAndDisconnect();
      FieldLogger.instance.logOscpPod('connect_plugin_missing');
      return false;
    } catch (e) {
      _releaseAndDisconnect();
      FieldLogger.instance.logOscpPod('connect_error', data: {
        'error': e.toString(),
      });
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_state == OscpConnectionState.disconnected) return;
    try {
      await _channel.invokeMethod<void>('disconnectOscp');
    } catch (_) {}
    _releaseAndDisconnect();
    FieldLogger.instance.logOscpPod('disconnected');
  }

  void dispose() {
    unawaited(disconnect());
  }

  void _releaseAndDisconnect() {
    SensorSessionCoordinator.instance.release(_bleLease);
    _bleLease = null;
    _state = OscpConnectionState.disconnected;
    _smoothedRangeM = -1;
  }

  void _handleRangeValue(double rawM) {
    if (rawM <= 0 || rawM > 20.0) return;
    if (_smoothedRangeM < 0) {
      _smoothedRangeM = rawM;
    } else {
      _smoothedRangeM =
          _smoothedRangeM * (1 - kOscpRangeEmaAlpha) +
          rawM * kOscpRangeEmaAlpha;
    }

    final now = DateTime.now();
    final estimate = OscpRangeEstimate(
      rangeM: _smoothedRangeM,
      confidence: 0.8,
      at: now,
    );

    if (estimate.isNearField &&
        now.difference(_lastNearFieldAt) >= kOscpNearFieldCooldown) {
      _lastNearFieldAt = now;

      final text =
          '${S.alert('oscp_near_field')}, ~${_smoothedRangeM.toStringAsFixed(1)} ${S.alert('approx_meters')}';
      try {
        onHazard?.call(ExternalHazardEvent(
          source: ExternalHazardSource.oscpPod,
          text: text,
          priority: _smoothedRangeM < 0.5
              ? SpeechPriority.critical
              : SpeechPriority.warning,
          category: AlertCategory.obstacleClose,
          urgency: (1.0 - _smoothedRangeM / kOscpNearFieldThresholdM)
              .clamp(0.3, 0.9),
          distanceM: _smoothedRangeM,
          at: now,
          correlationId: 'oscp_range',
        ));
      } catch (e) {
        FieldLogger.instance.logOscpPod('emit_error', data: {
          'error': e.toString(),
        });
      }
    }
  }

  void _handleImuValue(double accelMag, double gyroMag) {
    final imu = OscpImuSnapshot(
      accelMag: accelMag,
      gyroMag: gyroMag,
      at: DateTime.now(),
    );
    try {
      onImu?.call(imu);
    } catch (_) {}
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onOscpConnected':
        _state = OscpConnectionState.connected;
        _firmwareVersion =
            (call.arguments as Map?)?['firmware'] as String? ?? '';
        FieldLogger.instance.logOscpPod('connected', data: {
          'firmware': _firmwareVersion,
        });
        break;
      case 'onOscpDisconnected':
        _releaseAndDisconnect();
        FieldLogger.instance.logOscpPod('peer_disconnected');
        break;
      case 'onOscpRange':
        final raw = (call.arguments as num?)?.toDouble() ?? -1;
        _handleRangeValue(raw);
        break;
      case 'onOscpImu':
        final args = call.arguments as Map?;
        if (args != null) {
          _handleImuValue(
            (args['accel'] as num?)?.toDouble() ?? 0,
            (args['gyro'] as num?)?.toDouble() ?? 0,
          );
        }
        break;
      case 'onOscpButton':
        try {
          onButtonPress?.call();
        } catch (_) {}
        break;
      case 'onOscpBattery':
        _podBatteryPct = (call.arguments as num?)?.toInt() ?? -1;
        break;
      case 'onOscpError':
        _state = OscpConnectionState.error;
        FieldLogger.instance.logOscpPod('native_error', data: {
          'error': call.arguments?.toString() ?? 'unknown',
        });
        break;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _state = OscpConnectionState.disconnected;
    _smoothedRangeM = -1;
    _podBatteryPct = -1;
    _lastNearFieldAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

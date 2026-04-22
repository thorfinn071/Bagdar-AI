import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';

enum ThermalSeverity { normal, warm, hot, critical }

class ThermalReadings {
  final double? batteryTempC;
  final int? thermalStatus;
  final ThermalSeverity severity;

  const ThermalReadings({
    required this.batteryTempC,
    required this.thermalStatus,
    required this.severity,
  });

  const ThermalReadings.unavailable()
    : batteryTempC = null,
      thermalStatus = null,
      severity = ThermalSeverity.normal;

  bool get isAvailable => batteryTempC != null || thermalStatus != null;

  static ThermalReadings fromMap(Map<dynamic, dynamic>? map) {
    final tempRaw = map?['batteryTempC'];
    final statusRaw = map?['thermalStatus'];
    final temp = tempRaw is num ? tempRaw.toDouble() : null;
    final status = statusRaw is num ? statusRaw.toInt() : null;
    return ThermalReadings(
      batteryTempC: temp,
      thermalStatus: status,
      severity: severityFor(batteryTempC: temp, thermalStatus: status),
    );
  }

  static ThermalSeverity severityFor({
    double? batteryTempC,
    int? thermalStatus,
  }) {
    var severity = ThermalSeverity.normal;

    if (batteryTempC != null) {
      
      
      if (batteryTempC >= kThermalCriticalTempC) {
        severity = ThermalSeverity.critical;
      } else if (batteryTempC >= kThermalHotTempC) {
        severity = ThermalSeverity.hot;
      } else if (batteryTempC >= kThermalWarmTempC) {
        severity = ThermalSeverity.warm;
      }
    }

    if (thermalStatus != null) {
      final mapped = thermalStatus >= kThermalStatusCritical
          ? ThermalSeverity.critical
          : thermalStatus >= kThermalStatusHot
          ? ThermalSeverity.hot
          : thermalStatus >= kThermalStatusWarm
          ? ThermalSeverity.warm
          : ThermalSeverity.normal;
      if (mapped.index > severity.index) {
        severity = mapped;
      }
    }

    return severity;
  }

  @override
  bool operator ==(Object other) {
    return other is ThermalReadings &&
        other.batteryTempC == batteryTempC &&
        other.thermalStatus == thermalStatus &&
        other.severity == severity;
  }

  @override
  int get hashCode => Object.hash(batteryTempC, thermalStatus, severity);
}

class ThermalMonitor {
  static const MethodChannel _channel = MethodChannel('bagdar/device_info');

  Timer? _pollTimer;
  bool _ready = false;
  ThermalReadings _current = const ThermalReadings.unavailable();

  ThermalReadings get current => _current;
  bool get isReady => _ready;
  ThermalSeverity get severity => _current.severity;
  double? get batteryTempC => _current.batteryTempC;
  int? get thermalStatus => _current.thermalStatus;

  void Function(ThermalReadings readings)? onChanged;

  Future<void> init({
    Duration pollInterval = const Duration(seconds: 20),
  }) async {
    _ready = true;
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    if (!Platform.isAndroid) {
      _setCurrent(const ThermalReadings.unavailable());
      return;
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getThermalReadings',
      );
      _setCurrent(ThermalReadings.fromMap(result));
    } catch (e) {
      debugPrint('ThermalMonitor: refresh failed: $e');
      _setCurrent(const ThermalReadings.unavailable());
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ready = false;
  }

  void _setCurrent(ThermalReadings readings) {
    if (readings == _current) return;
    _current = readings;
    onChanged?.call(_current);
  }
}

import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

enum ThrottleLevel { normal, moderate, aggressive, critical }

class BatteryMonitor {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _pollTimer;

  ThrottleLevel _level = ThrottleLevel.normal;
  int _lastBatteryLevel = 100;

  ThrottleLevel get level => _level;
  int get batteryLevel => _lastBatteryLevel;
  void Function(ThrottleLevel level)? onThrottleChanged;

  static ThrottleLevel levelForBatteryLevel(int batteryLevel) {
    if (batteryLevel < 5) return ThrottleLevel.critical;
    if (batteryLevel < 15) return ThrottleLevel.aggressive;
    if (batteryLevel < 30) return ThrottleLevel.moderate;
    return ThrottleLevel.normal;
  }

  int get detectIntervalMs {
    switch (_level) {
      case ThrottleLevel.normal:
        return 140;
      case ThrottleLevel.moderate:
        return 220;
      case ThrottleLevel.aggressive:
        return 320;
      case ThrottleLevel.critical:
        return 450;
    }
  }

  int get midasIntervalMs {
    switch (_level) {
      case ThrottleLevel.normal:
        return 500;
      case ThrottleLevel.moderate:
        return 1000;
      case ThrottleLevel.aggressive:
        return 1800;
      case ThrottleLevel.critical:
        return 2500;
    }
  }

  int get ocrIntervalMs {
    switch (_level) {
      case ThrottleLevel.normal:
        return 8000;
      case ThrottleLevel.moderate:
        return 12000;
      case ThrottleLevel.aggressive:
        return 18000;
      case ThrottleLevel.critical:
        return 0;
    }
  }

  Duration get heartbeatInterval {
    switch (_level) {
      case ThrottleLevel.normal:
        return const Duration(minutes: 3);
      case ThrottleLevel.moderate:
        return const Duration(minutes: 5);
      case ThrottleLevel.aggressive:
        return const Duration(minutes: 10);
      case ThrottleLevel.critical:
        return Duration.zero;
    }
  }

  bool get midasEnabled => true;

  Future<void> init() async {
    try {
      _lastBatteryLevel = await _battery.batteryLevel;
      _updateLevel();

      _stateSub = _battery.onBatteryStateChanged.listen((_) {
        _checkLevel();
      });

      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _checkLevel();
      });
    } catch (e) {
      debugPrint('BatteryMonitor: init error: $e');
    }
  }

  Future<void> _checkLevel() async {
    try {
      _lastBatteryLevel = await _battery.batteryLevel;
      _updateLevel();
    } catch (_) {}
  }

  void _updateLevel() {
    final newLevel = levelForBatteryLevel(_lastBatteryLevel);

    if (newLevel != _level) {
      _level = newLevel;
      debugPrint('BatteryMonitor: throttle → $_level ($_lastBatteryLevel%)');
      onThrottleChanged?.call(_level);
    }
  }

  void dispose() {
    unawaited(_stateSub?.cancel());
    _pollTimer?.cancel();
  }
}

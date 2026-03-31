import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';

enum ThrottleLevel {
  normal,
  moderate,
  aggressive,
}

class BatteryMonitor {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _pollTimer;

  ThrottleLevel _level = ThrottleLevel.normal;
  int _lastBatteryLevel = 100;

  ThrottleLevel get level => _level;
  int get batteryLevel => _lastBatteryLevel;
  void Function(ThrottleLevel level)? onThrottleChanged;

  int get detectIntervalMs {
    switch (_level) {
      case ThrottleLevel.normal:     return 140;
      case ThrottleLevel.moderate:   return 250;
      case ThrottleLevel.aggressive: return 400;
    }
  }

  int get midasIntervalMs {
    switch (_level) {
      case ThrottleLevel.normal:     return 500;
      case ThrottleLevel.moderate:   return 1000;
      case ThrottleLevel.aggressive: return 0;
    }
  }

  bool get midasEnabled => _level != ThrottleLevel.aggressive;

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
    final ThrottleLevel newLevel;
    if (_lastBatteryLevel < 15) {
      newLevel = ThrottleLevel.aggressive;
    } else if (_lastBatteryLevel < 30) {
      newLevel = ThrottleLevel.moderate;
    } else {
      newLevel = ThrottleLevel.normal;
    }

    if (newLevel != _level) {
      _level = newLevel;
      debugPrint('BatteryMonitor: throttle → $_level ($_lastBatteryLevel%)');
      onThrottleChanged?.call(_level);
    }
  }

  void dispose() {
    _stateSub?.cancel();
    _pollTimer?.cancel();
  }
}

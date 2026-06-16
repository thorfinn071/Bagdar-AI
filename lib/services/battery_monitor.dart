import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/constants.dart';

enum ThrottleLevel { normal, moderate, aggressive, critical }

class BatteryMonitor {
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _pollTimer;

  ThrottleLevel _level = ThrottleLevel.normal;
  int _lastBatteryLevel = 100;
  bool _isCharging = false;
  bool _isWifi = false;

  /// V5.4: Tracks which proactive thresholds have already been announced in
  /// the current discharge cycle so they each fire at most once.
  final Set<int> _announcedThresholds = {};

  StreamSubscription<List<ConnectivityResult>>? _connSub;

  ThrottleLevel get level => _level;
  int get batteryLevel => _lastBatteryLevel;

  /// Battery percentage [0–100].
  int get batteryPct => _lastBatteryLevel;

  /// True when the device is plugged in and charging (or full).
  bool get isCharging => _isCharging;

  /// True when the device has a Wi-Fi connection (online data may be used
  /// for optional model-pack downloads).
  bool get isWifi => _isWifi;

  void Function(ThrottleLevel level)? onThrottleChanged;

  /// V5.4: Fires when the battery crosses a proactive-announce threshold
  /// (50 %, 30 %, 15 %) for the first time in a discharge cycle.
  /// The [pct] argument is the threshold that was just crossed.
  void Function(int pct)? onProactiveAnnounce;

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
      final state = await _battery.batteryState;
      _isCharging =
          state == BatteryState.charging || state == BatteryState.full;
      _updateLevel();

      _stateSub = _battery.onBatteryStateChanged.listen((s) {
        _isCharging =
            s == BatteryState.charging || s == BatteryState.full;
        _checkLevel();
      });

      _pollTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        _checkLevel();
      });
    } catch (e) {
      debugPrint('BatteryMonitor: init error: $e');
    }

    try {
      final results = await Connectivity().checkConnectivity();
      _isWifi = results.contains(ConnectivityResult.wifi);

      _connSub = Connectivity()
          .onConnectivityChanged
          .listen((results) {
        _isWifi = results.contains(ConnectivityResult.wifi);
      });
    } catch (e) {
      debugPrint('BatteryMonitor: connectivity init error: $e');
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

    // V5.4: Proactive announcements at 50 %, 30 %, 15 % — once per discharge.
    if (!_isCharging) {
      for (final threshold in const [
        kBattery50AnnounceThreshold,
        kBattery30AnnounceThreshold,
        kBattery15AnnounceThreshold,
      ]) {
        if (_lastBatteryLevel <= threshold &&
            !_announcedThresholds.contains(threshold)) {
          _announcedThresholds.add(threshold);
          onProactiveAnnounce?.call(threshold);
        }
      }
    } else {
      // Reset announce set when charging so thresholds fire again after
      // the user charges and re-discharges.
      _announcedThresholds.clear();
    }

    if (newLevel != _level) {
      _level = newLevel;
      debugPrint('BatteryMonitor: throttle → $_level ($_lastBatteryLevel%)');
      onThrottleChanged?.call(_level);
    }
  }

  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_connSub?.cancel());
    _pollTimer?.cancel();
  }
}

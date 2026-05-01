import 'dart:math' as math;

import '../models/constants.dart';
import '../services/battery_monitor.dart';
import '../services/fall_detector.dart' show MotionState;
import '../services/thermal_monitor.dart';

enum MemoryPressureLevel { normal, low, critical }

class PerformanceThrottler {
  double _avgInfMs = 0;
  DateTime _midasPausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFpsTick = DateTime.now();
  int _frameCount = 0;
  double _detectFps = 0;
  bool _isLowPowerMode = false;
  int _thermalBurstCount = 0;
  static const int _kThermalBurstFrames = 3;
  static const int _kThermalIdleMs = 500;
  
  
  
  
  
  bool _indoorMode = false;
  MotionState _motionState = MotionState.walking;
  MemoryPressureLevel _memory = MemoryPressureLevel.normal;

  ThermalSeverity _committedSeverity = ThermalSeverity.normal;
  DateTime _severityCommitUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeverityTransitionAt = DateTime.fromMillisecondsSinceEpoch(0);

  
  DateTime _gateResumeUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCriticalAlertAt = DateTime.fromMillisecondsSinceEpoch(0);

  double get avgInfMs => _avgInfMs;
  double get detectFps => _detectFps;
  MotionState get motionState => _motionState;
  MemoryPressureLevel get memoryPressure => _memory;
  ThermalSeverity get effectiveSeverity => _committedSeverity;
  DateTime get lastSeverityTransitionAt => _lastSeverityTransitionAt;
  bool get thermalBurstActive =>
      _committedSeverity == ThermalSeverity.critical &&
      _thermalBurstCount < _kThermalBurstFrames;

  void setThermal(ThermalReadings readings, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final raw = readings.severity;
    if (raw.index > _committedSeverity.index) {
      _committedSeverity = raw;
      _severityCommitUntil = t.add(kThermalCommitDwell);
      _lastSeverityTransitionAt = t;
      return;
    }
    if (raw.index == _committedSeverity.index) {
      if (raw != ThermalSeverity.normal) {
        _severityCommitUntil = t.add(kThermalCommitDwell);
      }
      return;
    }
    if (t.isBefore(_severityCommitUntil)) return;
    _committedSeverity = raw;
    _lastSeverityTransitionAt = t;
  }

  void setLowPowerMode(bool enabled) {
    _isLowPowerMode = enabled;
  }

  void setMotionState(MotionState state, {DateTime? now}) {
    
    
    if (_motionState == MotionState.stationary &&
        state != MotionState.stationary) {
      signalActivity(now: now);
    }
    _motionState = state;
  }

  
  
  
  
  void noteCriticalAlert({DateTime? now}) {
    _lastCriticalAlertAt = now ?? DateTime.now();
  }

  
  
  void signalActivity({DateTime? now}) {
    _gateResumeUntil = (now ?? DateTime.now()).add(
      kStationaryGateResumeWindow,
    );
  }

  
  
  bool isStationaryGateActive({DateTime? now}) {
    if (_motionState != MotionState.stationary) return false;
    if (_indoorMode) return false;
    final t = now ?? DateTime.now();
    if (t.isBefore(_gateResumeUntil)) return false;
    if (t.difference(_lastCriticalAlertAt) <
        kStationaryGatePostCriticalBlock) {
      return false;
    }
    return true;
  }

  
  
  
  void setIndoorMode(bool enabled) {
    _indoorMode = enabled;
  }

  bool get isIndoorMode => _indoorMode;

  void setMemoryPressure(MemoryPressureLevel level) {
    _memory = level;
  }

  void update(double ms, DateTime now) {
    if (_avgInfMs == 0) {
      _avgInfMs = ms;
    } else {
      final alpha = ms > _avgInfMs ? 0.35 : 0.10;
      _avgInfMs = _avgInfMs * (1.0 - alpha) + ms * alpha;
    }

    final severity = _committedSeverity;
    final isOverheating =
        severity == ThermalSeverity.critical ||
        _isLowPowerMode ||
        _memory == MemoryPressureLevel.critical;

    if (isOverheating || _avgInfMs > kInfTimeCriticalMs) {
      _midasPausedUntil = now.add(Duration(
        seconds: _isLowPowerMode ? 10 : (severity == ThermalSeverity.critical ? 8 : 5),
      ));
    } else if (_avgInfMs > kInfTimeSlowMs || severity == ThermalSeverity.hot) {
      _midasPausedUntil = now.add(const Duration(seconds: 3));
    } else if (_avgInfMs < kInfTimeFastMs + 20 &&
        now.isAfter(_midasPausedUntil)) {
      _midasPausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }

    _frameCount++;
    final fpsNow = DateTime.now();
    final diffMs = fpsNow.difference(_lastFpsTick).inMilliseconds;
    if (diffMs >= 1000) {
      _detectFps = _frameCount * 1000 / diffMs;
      _frameCount = 0;
      _lastFpsTick = fpsNow;
    }
  }

  bool isMidasPaused(DateTime now) => now.isBefore(_midasPausedUntil);

  Duration detectInterval(int batteryMs) {
    
    
    
    if (isStationaryGateActive()) {
      final gatedMs = math.max(batteryMs, kStationaryGateDetectMs);
      return Duration(
        milliseconds: math.min(gatedMs, kDetectIntervalSafetyCeilingMs),
      );
    }
    final severity = _committedSeverity;
    int thermalPenalty = 0;
    if (severity == ThermalSeverity.warm) {
      thermalPenalty = kThermalPenaltyWarmMs;
    }
    if (severity == ThermalSeverity.hot) thermalPenalty = kThermalPenaltyHotMs;
    if (severity == ThermalSeverity.critical) {
      thermalPenalty = kThermalPenaltyCriticalMs;
    }

    final perfMs = _isLowPowerMode
        ? 500
        : _avgInfMs > kInfTimeCriticalMs
        ? 350
        : _avgInfMs > kInfTimeSlowMs
        ? kHardFrameBudgetMs
        : _avgInfMs > kInfTimeNormalMs
        ? kSoftFrameBudgetMs
        : _avgInfMs < kInfTimeFastMs
        ? 130
        : kTargetFrameBudgetMs;

    
    
    
    final stationaryBias = _indoorMode ? 0 : 150;
    final motionBias = switch (_motionState) {
      MotionState.stationary => stationaryBias,
      MotionState.walking => 0,
      MotionState.unstable => -30,
    };

    final memoryBias = switch (_memory) {
      MemoryPressureLevel.normal => 0,
      MemoryPressureLevel.low => 80,
      MemoryPressureLevel.critical => 200,
    };

    final base = math.max(
      0,
      perfMs + thermalPenalty + motionBias + memoryBias,
    );

    final int requestedMs;
    if (severity == ThermalSeverity.critical && !_isLowPowerMode) {
      if (_thermalBurstCount < _kThermalBurstFrames) {
        _thermalBurstCount++;
        requestedMs = math.max(batteryMs, (perfMs + thermalPenalty ~/ 2));
      } else {
        _thermalBurstCount = 0;
        requestedMs = math.max(batteryMs, _kThermalIdleMs + base);
      }
    } else {
      _thermalBurstCount = 0;
      requestedMs = math.max(batteryMs, base);
    }

    
    
    
    
    return Duration(
      milliseconds: math.min(requestedMs, kDetectIntervalSafetyCeilingMs),
    );
  }

  Duration midasInterval(int batteryMs) {
    if (batteryMs <= 0) return Duration.zero;
    if (_memory == MemoryPressureLevel.critical) return Duration.zero;
    
    
    
    
    if (isStationaryGateActive()) return kStationaryGateMidasOff;
    final severity = _committedSeverity;
    int thermalMultiplier = 1;
    if (severity == ThermalSeverity.warm) thermalMultiplier = 2;
    if (severity == ThermalSeverity.hot) thermalMultiplier = 3;
    if (severity == ThermalSeverity.critical) thermalMultiplier = 5;

    final loadMultiplier = _avgInfMs > kInfTimeCriticalMs
        ? 5
        : _avgInfMs > kInfTimeSlowMs
        ? 4
        : _avgInfMs > kInfTimeNormalMs
        ? 2
        : 1;
    final multiplier = math.max(thermalMultiplier, loadMultiplier);
    return Duration(milliseconds: math.max(batteryMs * multiplier, batteryMs));
  }

  Duration uiInterval() {
    if (_avgInfMs > kInfTimeCriticalMs) {
      return const Duration(milliseconds: 240);
    }
    if (_avgInfMs > kInfTimeSlowMs) return const Duration(milliseconds: 200);
    if (_avgInfMs > kInfTimeNormalMs) return const Duration(milliseconds: 160);
    return const Duration(milliseconds: 120);
  }

  Duration autoOcrInterval(int batteryMs) {
    if (batteryMs <= 0) return Duration.zero;
    final perfMs = _avgInfMs > kInfTimeCriticalMs
        ? 15000
        : _avgInfMs > kInfTimeSlowMs
        ? 12000
        : _avgInfMs > kInfTimeNormalMs
        ? 10000
        : 8000;
    return Duration(milliseconds: math.max(batteryMs, perfMs));
  }

  Duration burstDetectInterval(int batteryMs, ThrottleLevel level) {
    if (level == ThrottleLevel.critical) {
      return Duration(milliseconds: math.min(batteryMs, 220));
    }
    if (level == ThrottleLevel.aggressive) {
      return Duration(milliseconds: math.min(batteryMs, 180));
    }
    final burstMs = _avgInfMs > kInfTimeCriticalMs
        ? (level == ThrottleLevel.moderate ? 160 : 120)
        : _avgInfMs > kInfTimeSlowMs
        ? (level == ThrottleLevel.moderate ? 120 : 90)
        : (level == ThrottleLevel.moderate ? 100 : 50);
    return Duration(milliseconds: math.min(batteryMs, burstMs));
  }

  Duration stallWatchdogThreshold({DateTime? now}) {
    final t = now ?? DateTime.now();
    final transitionAge = t.difference(_lastSeverityTransitionAt);
    if (transitionAge < kThermalTransitionSilence &&
        _committedSeverity.index > ThermalSeverity.normal.index) {
      return kStallWatchdogThresholdCritical;
    }
    switch (_committedSeverity) {
      case ThermalSeverity.normal:
        return kStallWatchdogThresholdNormal;
      case ThermalSeverity.warm:
        return kStallWatchdogThresholdWarm;
      case ThermalSeverity.hot:
        return kStallWatchdogThresholdHot;
      case ThermalSeverity.critical:
        return kStallWatchdogThresholdCritical;
    }
  }
}

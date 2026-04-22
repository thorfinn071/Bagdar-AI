import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import '../utils/performance_throttler.dart';

class MemoryReadings {
  final int availMB;
  final int totalMB;
  final bool lowMemory;
  final MemoryPressureLevel level;

  const MemoryReadings({
    required this.availMB,
    required this.totalMB,
    required this.lowMemory,
    required this.level,
  });

  const MemoryReadings.unavailable()
    : availMB = -1,
      totalMB = -1,
      lowMemory = false,
      level = MemoryPressureLevel.normal;

  bool get isAvailable => availMB >= 0;

  static MemoryPressureLevel levelFor({
    required int availMB,
    required bool lowMemory,
  }) {
    if (availMB < 0) return MemoryPressureLevel.normal;
    if (availMB < kMemoryPressureCriticalMB || lowMemory) {
      return MemoryPressureLevel.critical;
    }
    if (availMB < kMemoryPressureLowMB) {
      return MemoryPressureLevel.low;
    }
    return MemoryPressureLevel.normal;
  }

  static MemoryReadings fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const MemoryReadings.unavailable();
    final availRaw = map['availMB'];
    final totalRaw = map['totalMB'];
    final lowRaw = map['lowMemory'];
    final avail = availRaw is num ? availRaw.toInt() : -1;
    final total = totalRaw is num ? totalRaw.toInt() : -1;
    final low = lowRaw is bool ? lowRaw : false;
    return MemoryReadings(
      availMB: avail,
      totalMB: total,
      lowMemory: low,
      level: levelFor(availMB: avail, lowMemory: low),
    );
  }
}

class MemoryMonitor {
  static const MethodChannel _channel = MethodChannel('bagdar/device_info');

  Timer? _pollTimer;
  bool _ready = false;
  MemoryReadings _current = const MemoryReadings.unavailable();

  MemoryReadings get current => _current;
  bool get isReady => _ready;
  MemoryPressureLevel get level => _current.level;

  void Function(MemoryReadings readings)? onChanged;

  Future<void> init({
    Duration pollInterval = kMemoryPressurePollInterval,
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
      _setCurrent(const MemoryReadings.unavailable());
      return;
    }
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getMemoryInfo',
      );
      _setCurrent(MemoryReadings.fromMap(result));
    } catch (e) {
      debugPrint('MemoryMonitor: refresh failed: $e');
      _setCurrent(const MemoryReadings.unavailable());
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _ready = false;
  }

  void _setCurrent(MemoryReadings readings) {
    final previousLevel = _current.level;
    _current = readings;
    if (readings.level != previousLevel) {
      onChanged?.call(_current);
    }
  }

  @visibleForTesting
  void debugSet(MemoryReadings readings) {
    _setCurrent(readings);
  }
}

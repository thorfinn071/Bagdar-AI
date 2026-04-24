import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/constants.dart';

class StallWatchdog {
  final Duration Function() thresholdProvider;
  final bool Function() isActive;
  final VoidCallback onStall;
  final Duration checkPeriod;

  Timer? _timer;
  DateTime _lastFrameAt = DateTime.now();
  bool _warned = false;

  StallWatchdog({
    required this.thresholdProvider,
    required this.isActive,
    required this.onStall,
    this.checkPeriod = kStallWatchdogPeriod,
  });

  bool get isWarned => _warned;

  void start() {
    stop();
    _lastFrameAt = DateTime.now();
    _warned = false;
    _timer = Timer.periodic(checkPeriod, (_) => evaluate(DateTime.now()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _warned = false;
  }

  void notifyFrameArrived({DateTime? now}) {
    _lastFrameAt = now ?? DateTime.now();
  }

  void clearWarning() {
    _warned = false;
  }

  @visibleForTesting
  void evaluate(DateTime now) {
    if (!isActive()) return;
    final gap = now.difference(_lastFrameAt);
    if (gap >= thresholdProvider() && !_warned) {
      _warned = true;
      onStall();
    }
  }
}

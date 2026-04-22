import 'dart:async';

import '../models/constants.dart';
import 'earcon_service.dart';

class ProximityBeaconService {
  static const Duration _tickInterval = Duration(milliseconds: 50);

  final EarconService _earcon;

  Timer? _timer;
  double _distMeters = double.infinity;
  double _pan = 0.0;
  bool _active = true;
  DateTime _lastPulseAt = DateTime.fromMillisecondsSinceEpoch(0);

  ProximityBeaconService({required EarconService earcon}) : _earcon = earcon;

  void update(double distMeters, double pan) {
    _distMeters = distMeters;
    _pan = pan;
    if (_distMeters <= kBeaconFarDistM) {
      _active = true;
    }
    if (!_active) return;
    if (_distMeters > kBeaconFarDistM) {
      pause();
      return;
    }
    _ensureTicker();
  }

  void pause() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _lastPulseAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void resume() {
    _active = true;
    if (_distMeters <= kBeaconFarDistM) {
      _ensureTicker();
    }
  }

  void dispose() {
    pause();
  }

  double _intervalMs() {
    final dist = _distMeters.clamp(kBeaconNearDistM, kBeaconFarDistM);
    final t = (kBeaconFarDistM - dist) / (kBeaconFarDistM - kBeaconNearDistM);
    final hz = kBeaconMinHz + (kBeaconMaxHz - kBeaconMinHz) * t;
    return 1000.0 / hz;
  }

  void _ensureTicker() {
    if (_timer != null) return;
    _timer = Timer.periodic(_tickInterval, _tick);
  }

  void _tick(Timer timer) {
    if (!_active) {
      timer.cancel();
      _timer = null;
      return;
    }
    if (_distMeters > kBeaconFarDistM) {
      timer.cancel();
      _timer = null;
      return;
    }
    final ms = _intervalMs();
    final now = DateTime.now();
    if (_lastPulseAt.millisecondsSinceEpoch == 0 ||
        now.difference(_lastPulseAt).inMilliseconds >= ms.round()) {
      _lastPulseAt = now;
      _earcon.play(Earcon.proximity, pan: _pan);
    }
  }
}

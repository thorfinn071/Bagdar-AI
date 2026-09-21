import 'dart:async';

import '../models/constants.dart';
import 'earcon_service.dart';
import 'haptic_service.dart';

class ProximityBeaconService {
  static const Duration _tickInterval = Duration(milliseconds: 50);

  /// Base haptic pulse fired alongside each proximity earcon.
  /// `[0, on_ms]` plus a matching `[0, amplitude]` so devices with
  /// amplitude control get a fixed-strength tap rather than the
  /// platform-default max strength.
  static const List<int> _kBaseHapticPattern = [0, 25];
  static const List<int> _kBaseHapticIntensities = [0, 140];

  /// Weather-degraded boost: +30 % duration and amplitude so the user
  /// notices the beacon through a glove, behind a closed jacket, or
  /// in a winter coat pocket — i.e. exactly when visibility is lost
  /// (Safety follow-up M10). Final amplitude clamps inside HapticService.
  static const double _kWeatherDegradedBoost = 1.3;

  final EarconService _earcon;

  Timer? _timer;
  double _distMeters = double.infinity;
  double _pan = 0.0;
  bool _active = true;
  bool _weatherDegraded = false;
  DateTime _lastPulseAt = DateTime.fromMillisecondsSinceEpoch(0);

  ProximityBeaconService({required EarconService earcon}) : _earcon = earcon;

  bool get isWeatherDegraded => _weatherDegraded;

  /// Toggles the +30 % haptic boost applied to each proximity pulse.
  /// Wired from `WeatherGate.degraded` so that whenever the perception
  /// stack is operating with raised gates, the user gets a stronger
  /// non-verbal channel that compensates for the lost visual margin.
  void setWeatherDegraded(bool degraded) {
    _weatherDegraded = degraded;
  }

  void update(double distMeters, double pan, {bool? weatherDegraded}) {
    _distMeters = distMeters;
    _pan = pan;
    if (weatherDegraded != null) {
      _weatherDegraded = weatherDegraded;
    }
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
      final (pattern, intensities) = resolveHapticPulse(_weatherDegraded);
      HapticService.vibrate(pattern, intensities: intensities);
    }
  }

  /// Returns the (pattern, intensities) pair used for the haptic pulse
  /// paired with each proximity earcon. Boosted +30 % when weather is
  /// degraded. Exposed so unit tests can assert the boost ratio without
  /// touching the real `HapticService` static.
  static (List<int>, List<int>) resolveHapticPulse(bool weatherDegraded) {
    if (!weatherDegraded) {
      return (_kBaseHapticPattern, _kBaseHapticIntensities);
    }
    return (
      [
        for (int i = 0; i < _kBaseHapticPattern.length; i++)
          i == 0
              ? _kBaseHapticPattern[i]
              : (_kBaseHapticPattern[i] * _kWeatherDegradedBoost).round().clamp(
                  0,
                  5000,
                ),
      ],
      [
        for (int i = 0; i < _kBaseHapticIntensities.length; i++)
          i == 0
              ? 0
              : (_kBaseHapticIntensities[i] * _kWeatherDegradedBoost)
                    .round()
                    .clamp(1, 255),
      ],
    );
  }
}

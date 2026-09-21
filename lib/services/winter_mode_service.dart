import 'package:flutter/foundation.dart';

import 'settings_service.dart';
import 'thermal_monitor.dart';

/// Cold-weather "Winter Mode" toggle (plan: Winter Mode block).
///
/// Single source of truth for whether the app is in cold-weather operation.
/// Two inputs feed into the effective state:
///
///   1. **Manual user toggle**, persisted in [SettingsService] under
///      `kSettingsKey`. Set by the user via voice / settings UI.
///
///   2. **Auto-detect from battery temperature.** When the Android battery
///      reports a cell temperature at or below [kAutoEnableBatteryTempC] for
///      more than [kAutoEnableMinAge] of polled readings, the service force-
///      enables winter mode regardless of the manual toggle (the device is
///      physically cold — the user is in a cold environment). Auto-detect
///      cannot turn the toggle OFF; only the user can. This keeps the
///      semantics one-directional and predictable.
///
/// While [active] is true, the following must hold elsewhere in the codebase
/// (Winter Mode contract):
///   * `ThermalReadings.severityFor(winterMode: true)` lowers the critical
///     battery-temp threshold to 38 °C.
///   * `DepthPipelineController._isHazardCritical(winterMode: true)` promotes
///     `slippery` to critical regardless of zone.
///   * `GroundPlaneAnalyzer.analyze(winterMode: true)` skips the weather-
///     degraded score-floor bump on `stairsDown` and `nearFieldIntrusion`.
///   * The host emits an extra verbal heartbeat
///     ("плохая видимость — аккуратно") every 60 s while the weather gate is
///     reporting degraded conditions.
///   * `FallCountdownController` scales its cancel window by
///     [kCancelWindowScale] (= 0.7 — 30 % shorter window).
class WinterModeService extends ChangeNotifier {
  static const String kSettingsKey = 'winter_mode_manual';

  /// Battery cell temperature at or below this triggers auto-enable.
  /// Battery cells warm up rapidly under load, so a sub-5 °C reading reliably
  /// means the phone has been in a cold pocket / outdoor air recently.
  static const double kAutoEnableBatteryTempC = 5.0;

  /// Number of consecutive cold readings required before auto-enable trips.
  /// At the default 20 s thermal poll, this is ~40 s of sustained cold —
  /// short enough to react when stepping outside, long enough to ignore a
  /// single transient sensor glitch.
  static const int kAutoEnableMinAge = 2;

  /// 0.7 = 30 % reduction in fall SOS cancel window per the Winter Mode spec.
  static const double kCancelWindowScale = 0.7;

  /// Cadence of the "плохая видимость — аккуратно" verbal heartbeat while
  /// the weather gate is degraded in Winter Mode.
  static const Duration kDegradedHeartbeatInterval = Duration(seconds: 60);

  final SettingsService _settings;

  bool _manualEnabled = false;
  bool _autoEnabled = false;
  int _coldReadingStreak = 0;

  WinterModeService({SettingsService? settings})
    : _settings = settings ?? SettingsService.instance;

  /// Load the persisted manual setting. Must be called after
  /// `SettingsService.instance.init()`.
  void loadFromSettings() {
    if (!_settings.isReady) return;
    _manualEnabled = _settings.winterModeManual;
    notifyListeners();
  }

  /// Effective state: manual OR auto-detected.
  bool get active => _manualEnabled || _autoEnabled;

  bool get isManualEnabled => _manualEnabled;
  bool get isAutoEnabled => _autoEnabled;

  /// User-driven setter. Persists to [SettingsService].
  Future<void> setManualEnabled(bool enabled) async {
    if (enabled == _manualEnabled) return;
    _manualEnabled = enabled;
    if (_settings.isReady) {
      await _settings.setWinterModeManual(enabled);
    }
    notifyListeners();
  }

  /// Feed a thermal reading from [ThermalMonitor]. Updates the auto-detect
  /// streak and may flip [isAutoEnabled].
  void noteThermalReading(ThermalReadings readings) {
    final temp = readings.batteryTempC;
    if (temp == null) {
      _coldReadingStreak = 0;
      if (_autoEnabled) {
        _autoEnabled = false;
        notifyListeners();
      }
      return;
    }

    if (temp <= kAutoEnableBatteryTempC) {
      _coldReadingStreak++;
      if (!_autoEnabled && _coldReadingStreak >= kAutoEnableMinAge) {
        _autoEnabled = true;
        notifyListeners();
      }
    } else {
      _coldReadingStreak = 0;
      if (_autoEnabled) {
        _autoEnabled = false;
        notifyListeners();
      }
    }
  }

  /// Reset auto-detect state (e.g., on dispose or test setup).
  @visibleForTesting
  void resetAutoDetect() {
    _coldReadingStreak = 0;
    _autoEnabled = false;
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/a11y_prefs.dart';
import 'settings_service.dart';

/// Serializes accessibility-relevant SettingsService values to a compact
/// JSON payload that fits inside a QR code (target: ~300 bytes).
///
/// PII (e.g. SOS contact number) is intentionally excluded — the payload
/// is meant to be shown to a sighted helper or scanned across devices,
/// so secrets must never leave the device through this channel.
class SettingsCodec {
  const SettingsCodec._();
  static const SettingsCodec instance = SettingsCodec._();

  /// Schema version. Bump when fields are added/removed in a way that
  /// older clients cannot interpret. Reader rejects payloads with
  /// versions it does not understand.
  static const int schemaVersion = 1;

  /// Builds a snapshot Map from the current [Settings] state.
  Map<String, dynamic> exportToMap() {
    final s = Settings.instance;
    return <String, dynamic>{
      'v': schemaVersion,
      'lang': s.language,
      'speech_rate': _roundDouble(s.speechRate),
      'tts_volume': _roundDouble(s.ttsVolume),
      'earcon_volume': _roundDouble(s.earconVolume),
      'verbosity': s.verbosity.index,
      'alert_freq': s.alertFrequency.index,
      'haptic': s.hapticStrength.index,
      'sos_trigger': s.sosTrigger.index,
      'hand': s.dominantHand.index,
      'classic_gestures': s.classicGestures,
      'pitch_black': s.pitchBlackUi,
      'guide_dog': s.guideDogMode,
    };
  }

  String exportToJson() => jsonEncode(exportToMap());

  /// Decodes the payload, validates schema + ranges, and applies it via
  /// SettingsService setters. Returns true on success, false on rejection.
  /// Unknown keys are silently ignored. Out-of-range values are clamped
  /// to the enum/double range. Missing keys leave existing values intact.
  Future<bool> importFromJson(String json) async {
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      }
    } catch (e) {
      debugPrint('SettingsCodec: jsonDecode failed: $e');
      return false;
    }
    if (map == null) return false;
    return importFromMap(map);
  }

  Future<bool> importFromMap(Map<String, dynamic> map) async {
    final v = map['v'];
    if (v is! int || v != schemaVersion) {
      debugPrint('SettingsCodec: unsupported version=$v');
      return false;
    }
    final s = Settings.instance;
    if (!s.isReady) return false;

    if (map['lang'] is int) {
      final i = (map['lang'] as int).clamp(0, 2);
      await s.setLanguage(i);
    }
    final sr = _readDouble(map['speech_rate']);
    if (sr != null) {
      await s.setSpeechRate(sr.clamp(kSpeechRateMin, kSpeechRateMax));
    }
    final tv = _readDouble(map['tts_volume']);
    if (tv != null) {
      await s.setTtsVolume(tv.clamp(kTtsVolumeMin, kTtsVolumeMax));
    }
    final ev = _readDouble(map['earcon_volume']);
    if (ev != null) {
      await s.setEarconVolume(ev.clamp(kEarconVolumeMin, kEarconVolumeMax));
    }
    if (map['verbosity'] is int) {
      await s.setVerbosity(_clampEnum(map['verbosity'] as int, Verbosity.values));
    }
    if (map['alert_freq'] is int) {
      await s.setAlertFrequency(
        _clampEnum(map['alert_freq'] as int, AlertFrequency.values),
      );
    }
    if (map['haptic'] is int) {
      await s.setHapticStrength(
        _clampEnum(map['haptic'] as int, HapticStrength.values),
      );
    }
    if (map['sos_trigger'] is int) {
      await s.setSosTrigger(
        _clampEnum(map['sos_trigger'] as int, SosTrigger.values),
      );
    }
    if (map['hand'] is int) {
      await s.setDominantHand(
        _clampEnum(map['hand'] as int, DominantHand.values),
      );
    }
    if (map['classic_gestures'] is bool) {
      await s.setClassicGestures(map['classic_gestures'] as bool);
    }
    if (map['pitch_black'] is bool) {
      await s.setPitchBlackUi(map['pitch_black'] as bool);
    }
    if (map['guide_dog'] is bool) {
      await s.setGuideDogMode(map['guide_dog'] as bool);
    }
    return true;
  }

  /// Quickly inspect a payload without applying it. Returns null on
  /// invalid input. Used by import screen for the audio preview.
  Map<String, dynamic>? peek(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) return null;
      final v = decoded['v'];
      if (v is! int || v != schemaVersion) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  static double _roundDouble(double v) => (v * 100).round() / 100.0;

  static double? _readDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  static T _clampEnum<T>(int i, List<T> values) {
    return values[i.clamp(0, values.length - 1)];
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';








class FeatureUsageTracker {
  FeatureUsageTracker._();
  static final FeatureUsageTracker instance = FeatureUsageTracker._();

  static const String _prefsKey = 'feature_usage_v1';
  static const String _tutorialDoneKey = 'tutorial_completed_at';
  static const Duration _persistDebounce = Duration(seconds: 5);

  SharedPreferences? _prefs;
  final Map<String, int> _counts = <String, int>{};
  Timer? _persistTimer;
  bool _dirty = false;

  bool get isReady => _prefs != null;

  Future<void> init({SharedPreferences? prefs}) async {
    _prefs = prefs ?? await SharedPreferences.getInstance();
    _counts.clear();
    final raw = _prefs!.getStringList(_prefsKey) ?? const <String>[];
    for (final entry in raw) {
      final idx = entry.indexOf('=');
      if (idx <= 0) continue;
      final key = entry.substring(0, idx);
      final v = int.tryParse(entry.substring(idx + 1));
      if (v != null && v > 0) _counts[key] = v;
    }
  }

  void increment(String key, {int by = 1}) {
    if (key.isEmpty || by <= 0) return;
    _counts[key] = (_counts[key] ?? 0) + by;
    _dirty = true;
    _scheduleFlush();
  }

  int count(String key) => _counts[key] ?? 0;

  Map<String, int> snapshot() => Map<String, int>.unmodifiable(_counts);

  Future<void> setTutorialCompletedNow() async {
    if (_prefs == null) return;
    await _prefs!.setInt(
      _tutorialDoneKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  DateTime? get tutorialCompletedAt {
    final ms = _prefs?.getInt(_tutorialDoneKey);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> reset() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    _counts.clear();
    _dirty = false;
    await _prefs?.remove(_prefsKey);
    await _prefs?.remove(_tutorialDoneKey);
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    if (!_dirty || _prefs == null) return;
    _dirty = false;
    final entries = _counts.entries
        .where((e) => e.value > 0)
        .map((e) => '${e.key}=${e.value}')
        .toList(growable: false);
    try {
      await _prefs!.setStringList(_prefsKey, entries);
    } catch (e) {
      debugPrint('FeatureUsageTracker: persist failed: $e');
      _dirty = true;
    }
  }

  void _scheduleFlush() {
    if (_prefs == null) return;
    _persistTimer ??= Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(flush());
    });
  }
}


class FeatureUsageKeys {
  FeatureUsageKeys._();

  static String mode(String modeName) => 'mode_used_$modeName';
  static String gesture(String name) => 'gesture_used_$name';
  static String voiceCommand(String cmdName) => 'voice_command_used_$cmdName';

  static const String voiceCommandTotal = 'voice_command_used_total';
  static const String settingsOpened = 'settings_opened';
  static const String sosTriggered = 'sos_triggered';
  static const String sceneNarration = 'scene_narration_triggered';
}

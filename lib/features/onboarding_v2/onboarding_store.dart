import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'onboarding_state.dart';

enum ProgressLoadStatus { loaded, empty, corrupt, unsupported }

class ProgressLoad {
  final ProgressLoadStatus status;
  final OnboardingProgress? progress;
  const ProgressLoad(this.status, [this.progress]);
}

abstract interface class OnboardingStore {
  Future<ProgressLoad> load();
  Future<void> save(OnboardingProgress progress);
}

class PreferencesOnboardingStore implements OnboardingStore {
  static const key = 'bagdar_onboarding_v2_progress';
  final SharedPreferences preferences;
  PreferencesOnboardingStore(this.preferences);

  @override
  Future<ProgressLoad> load() async {
    try {
      final raw = preferences.getString(key);
      if (raw == null) return const ProgressLoad(ProgressLoadStatus.empty);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        return const ProgressLoad(ProgressLoadStatus.corrupt);
      }
      if (json['schema'] is! int || json['contentVersion'] is! int) {
        return const ProgressLoad(ProgressLoadStatus.corrupt);
      }
      if (json['schema'] != onboardingSchema ||
          json['contentVersion'] != onboardingContentVersion) {
        return const ProgressLoad(ProgressLoadStatus.unsupported);
      }
      return ProgressLoad(
        ProgressLoadStatus.loaded,
        OnboardingProgress.fromJson(json),
      );
    } catch (_) {
      return const ProgressLoad(ProgressLoadStatus.corrupt);
    }
  }

  @override
  Future<void> save(OnboardingProgress progress) async {
    // One complete JSON value; no partially updated multi-key module records.
    if (!await preferences.setString(key, jsonEncode(progress.toJson()))) {
      throw StateError('onboarding_write_failed');
    }
  }
}

/// Explicit preview/test adapter. No platform calls or device readiness.
class MemoryOnboardingStore implements OnboardingStore {
  OnboardingProgress? progress;
  @override
  Future<ProgressLoad> load() async => progress == null
      ? const ProgressLoad(ProgressLoadStatus.empty)
      : ProgressLoad(ProgressLoadStatus.loaded, progress);
  @override
  Future<void> save(OnboardingProgress value) async {
    progress = value;
  }
}

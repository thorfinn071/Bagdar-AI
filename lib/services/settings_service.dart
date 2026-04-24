import 'package:shared_preferences/shared_preferences.dart';

import '../models/a11y_prefs.dart';

typedef Settings = SettingsService;

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  static const _kOnboardingDone = 'onboarding_done';
  static const _kOnboardingMode = 'onboarding_mode';
  static const _kLanguage = 'language';
  static const _kUseGpu = 'use_gpu';
  static const _kUseNativeDepthBridge = 'use_native_depth_bridge';
  static const _kUseHardwareDepthMode = 'use_hardware_depth_mode';
  static const _kNumThreads = 'num_threads';
  static const _kFocalLength = 'focal_length';
  static const _kIsCalibrated = 'is_calibrated';
  static const _kPitchBlackUi = 'pitch_black_ui';
  static const _kGuideDogMode = 'guide_dog_mode';
  static const _kFieldLogging = 'field_logging';
  static const _kTutorialSeen = 'tutorial_seen';
  static const _kClassicGestures = 'classic_gestures';
  static const _kSpeechRate = 'a11y_speech_rate';
  static const _kTtsVolume = 'a11y_tts_volume';
  static const _kEarconVolume = 'a11y_earcon_volume';
  static const _kVerbosity = 'a11y_verbosity';
  static const _kAlertFrequency = 'a11y_alert_frequency';
  static const _kHapticStrength = 'a11y_haptic_strength';
  static const _kSosTrigger = 'a11y_sos_trigger';
  static const _kDominantHand = 'a11y_dominant_hand';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get isReady => _prefs != null;

  bool get onboardingDone => _prefs!.getBool(_kOnboardingDone) ?? false;
  String get onboardingMode => _prefs!.getString(_kOnboardingMode) ?? 'street';
  int get language => _prefs!.getInt(_kLanguage) ?? 0;
  bool get useGpu => _prefs!.getBool(_kUseGpu) ?? false;
  bool get useNativeDepthBridge =>
      _prefs!.getBool(_kUseNativeDepthBridge) ?? true;
  bool get useHardwareDepthMode =>
      _prefs!.getBool(_kUseHardwareDepthMode) ?? false;
  int get numThreads => _prefs!.getInt(_kNumThreads) ?? 2;
  double get focalLength => _prefs!.getDouble(_kFocalLength) ?? 1006.0;
  bool get isCalibrated => _prefs!.getBool(_kIsCalibrated) ?? false;
  bool get pitchBlackUi => _prefs!.getBool(_kPitchBlackUi) ?? false;
  bool get guideDogMode => _prefs!.getBool(_kGuideDogMode) ?? false;
  bool get fieldLogging => _prefs!.getBool(_kFieldLogging) ?? false;
  bool get tutorialSeen => _prefs!.getBool(_kTutorialSeen) ?? false;
  bool get classicGestures => _prefs!.getBool(_kClassicGestures) ?? false;

  double get speechRate =>
      (_prefs!.getDouble(_kSpeechRate) ?? kSpeechRateDefault)
          .clamp(kSpeechRateMin, kSpeechRateMax);
  double get ttsVolume =>
      (_prefs!.getDouble(_kTtsVolume) ?? kTtsVolumeDefault)
          .clamp(kTtsVolumeMin, kTtsVolumeMax);
  double get earconVolume =>
      (_prefs!.getDouble(_kEarconVolume) ?? kEarconVolumeDefault)
          .clamp(kEarconVolumeMin, kEarconVolumeMax);

  Verbosity get verbosity {
    final i = _prefs!.getInt(_kVerbosity) ?? Verbosity.normal.index;
    return Verbosity.values[i.clamp(0, Verbosity.values.length - 1)];
  }

  AlertFrequency get alertFrequency {
    final i = _prefs!.getInt(_kAlertFrequency) ?? AlertFrequency.normal.index;
    return AlertFrequency.values[i.clamp(0, AlertFrequency.values.length - 1)];
  }

  HapticStrength get hapticStrength {
    final i = _prefs!.getInt(_kHapticStrength) ?? HapticStrength.normal.index;
    return HapticStrength.values[i.clamp(0, HapticStrength.values.length - 1)];
  }

  SosTrigger get sosTrigger {
    final i = _prefs!.getInt(_kSosTrigger) ?? SosTrigger.twoFingerHold.index;
    return SosTrigger.values[i.clamp(0, SosTrigger.values.length - 1)];
  }

  DominantHand get dominantHand {
    final i = _prefs!.getInt(_kDominantHand) ?? DominantHand.right.index;
    return DominantHand.values[i.clamp(0, DominantHand.values.length - 1)];
  }

  Future<void> setOnboardingDone(bool v) async =>
      _prefs!.setBool(_kOnboardingDone, v);

  Future<void> setOnboardingMode(String v) async =>
      _prefs!.setString(_kOnboardingMode, v);

  Future<void> setLanguage(int v) async => _prefs!.setInt(_kLanguage, v);

  Future<void> setUseGpu(bool v) async => _prefs!.setBool(_kUseGpu, v);

  Future<void> setUseNativeDepthBridge(bool v) async =>
      _prefs!.setBool(_kUseNativeDepthBridge, v);

  Future<void> setUseHardwareDepthMode(bool v) async =>
      _prefs!.setBool(_kUseHardwareDepthMode, v);

  Future<void> setNumThreads(int v) async => _prefs!.setInt(_kNumThreads, v);

  Future<void> setFocalLength(double v) async =>
      _prefs!.setDouble(_kFocalLength, v);

  Future<void> setIsCalibrated(bool v) async =>
      _prefs!.setBool(_kIsCalibrated, v);

  Future<void> setPitchBlackUi(bool v) async =>
      _prefs!.setBool(_kPitchBlackUi, v);

  Future<void> setGuideDogMode(bool v) async =>
      _prefs!.setBool(_kGuideDogMode, v);

  Future<void> setFieldLogging(bool v) async =>
      _prefs!.setBool(_kFieldLogging, v);

  Future<void> setTutorialSeen(bool v) async =>
      _prefs!.setBool(_kTutorialSeen, v);

  Future<void> setClassicGestures(bool v) async =>
      _prefs!.setBool(_kClassicGestures, v);

  Future<void> setSpeechRate(double v) async =>
      _prefs!.setDouble(_kSpeechRate, v.clamp(kSpeechRateMin, kSpeechRateMax));

  Future<void> setTtsVolume(double v) async =>
      _prefs!.setDouble(_kTtsVolume, v.clamp(kTtsVolumeMin, kTtsVolumeMax));

  Future<void> setEarconVolume(double v) async => _prefs!.setDouble(
    _kEarconVolume,
    v.clamp(kEarconVolumeMin, kEarconVolumeMax),
  );

  Future<void> setVerbosity(Verbosity v) async =>
      _prefs!.setInt(_kVerbosity, v.index);

  Future<void> setAlertFrequency(AlertFrequency v) async =>
      _prefs!.setInt(_kAlertFrequency, v.index);

  Future<void> setHapticStrength(HapticStrength v) async =>
      _prefs!.setInt(_kHapticStrength, v.index);

  Future<void> setSosTrigger(SosTrigger v) async =>
      _prefs!.setInt(_kSosTrigger, v.index);

  Future<void> setDominantHand(DominantHand v) async =>
      _prefs!.setInt(_kDominantHand, v.index);

  Future<void> resetAll() async => _prefs!.clear();
}

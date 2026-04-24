import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> resetAll() async => _prefs!.clear();
}

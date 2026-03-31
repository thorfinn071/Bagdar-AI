import 'package:shared_preferences/shared_preferences.dart';

typedef Settings = SettingsService;

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  static const _kOnboardingDone  = 'onboarding_done';
  static const _kOnboardingMode  = 'onboarding_mode';
  static const _kLanguage        = 'language';
  static const _kUseGpu          = 'use_gpu';
  static const _kNumThreads      = 'num_threads';
  static const _kFocalLength     = 'focal_length';
  static const _kIsCalibrated    = 'is_calibrated';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  bool get isReady => _prefs != null;

  bool   get onboardingDone  => _prefs!.getBool(_kOnboardingDone)    ?? false;
  String get onboardingMode  => _prefs!.getString(_kOnboardingMode)  ?? 'street';
  int    get language        => _prefs!.getInt(_kLanguage)           ?? 0;
  bool   get useGpu          => _prefs!.getBool(_kUseGpu)            ?? false;
  int    get numThreads      => _prefs!.getInt(_kNumThreads)         ?? 2;
  double get focalLength     => _prefs!.getDouble(_kFocalLength)     ?? 1006.0;
  bool   get isCalibrated    => _prefs!.getBool(_kIsCalibrated)      ?? false;

  Future<void> setOnboardingDone(bool v)   async =>
      _prefs!.setBool(_kOnboardingDone, v);

  Future<void> setOnboardingMode(String v) async =>
      _prefs!.setString(_kOnboardingMode, v);

  Future<void> setLanguage(int v)          async =>
      _prefs!.setInt(_kLanguage, v);

  Future<void> setUseGpu(bool v)           async =>
      _prefs!.setBool(_kUseGpu, v);

  Future<void> setNumThreads(int v)        async =>
      _prefs!.setInt(_kNumThreads, v);

  Future<void> setFocalLength(double v)    async =>
      _prefs!.setDouble(_kFocalLength, v);

  Future<void> setIsCalibrated(bool v)     async =>
      _prefs!.setBool(_kIsCalibrated, v);

  Future<void> resetAll() async => _prefs!.clear();
}

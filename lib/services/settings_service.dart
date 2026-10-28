import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/core_feature_policy.dart';
import '../models/a11y_prefs.dart';
import '../models/context_mode.dart';
import '../models/generic_obstacle_mode.dart';
import '../models/strings.dart';
import '../theme/bagdar_tokens.dart';
import 'device_capability.dart';

typedef Settings = SettingsService;

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  SharedPreferences? _prefs;

  /// Production uses [CoreFeaturePolicy.current]. Tests that exercise
  /// research-only code paths may swap this; they must reset it.
  CoreFeaturePolicy _policy = CoreFeaturePolicy.current;

  CoreFeaturePolicy get featurePolicy => _policy;

  void debugSetPolicy(CoreFeaturePolicy policy) {
    _policy = policy;
  }

  void debugResetPolicy() {
    _policy = CoreFeaturePolicy.current;
  }

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
  static const _kTapSensitivity = 'a11y_tap_sensitivity';
  static const _kNcnnDisabled = 'ncnn_disabled';
  // V5.3: Cross-session exponential backoff for NCNN failures.
  static const _kNcnnBackoffLevel = 'ncnn_backoff_level';
  static const _kNcnnBackoffUntilMs = 'ncnn_backoff_until_ms';
  static const _kClearPathAnnounce = 'pref_clear_path_announce';
  static const _kBatteryAnnounce = 'pref_battery_announce';
  static const _kModeAnnounce = 'pref_mode_announce';
  static const _kAudioTourSeen = 'audio_tour_seen';
  static const _kSceneNarrationEnabled = 'scene_narration_enabled';
  static const _kPaymentSmsEnabled = 'payment_sms_enabled';
  static const _kCalibrationDeclined = 'calibration_declined';
  static const _kDisclaimerAcknowledged = 'disclaimer_acknowledged';
  static const _kDisclaimerAcknowledgedAt = 'disclaimer_acknowledged_at';
  static const _kWinterModeManual = 'winter_mode_manual';
  static const _kThemeMode = 'theme_mode';
  static const _kSosContactPrompted = 'sos_contact_prompted';

  static const _kEnableKazakhStackV2 = 'enable_kazakh_stack_v2';
  static const _kPreferredRuVoice = 'preferred_ru_voice';
  static const _kPreferredKkVoice = 'preferred_kk_voice';

  static const _kIndoorTrailMemory = 'feature_indoor_trail_memory';
  static const _kMeshBuddyAlerts = 'feature_mesh_buddy_alerts';
  static const _kBazaarMode = 'feature_bazaar_mode';
  static const _kLivestockAwareness = 'feature_livestock_awareness';
  static const _kOscpPod = 'feature_oscp_pod';
  static const _kLocalAsrAdaptation = 'feature_local_asr_adaptation';
  static const _kVlmCompanion = 'feature_vlm_companion';
  static const _kSonarDepth = 'feature_sonar_depth';
  static const _kGenericObstacleMode = 'generic_obstacle_mode';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    if (!_prefs!.containsKey(_kLanguage)) {
      final code = PlatformDispatcher.instance.locale.languageCode
          .toLowerCase();
      final detected = switch (code) {
        'kk' => AppLanguage.kk.index,
        'en' => AppLanguage.en.index,
        _ => AppLanguage.ru.index,
      };
      await _prefs!.setInt(_kLanguage, detected);
    }
    if (!_prefs!.containsKey(_kNumThreads)) {
      await _prefs!.setInt(_kNumThreads, await _autoDetectNumThreads());
    }
  }

  Future<int> _autoDetectNumThreads() async {
    try {
      final caps = await DeviceCapabilityProbe.probe();
      if (caps.isLowEnd) return 2;
      switch (caps.bestDepthTier) {
        case DepthTier.hardware:
        case DepthTier.ncnnVulkan:
          return 4;
        case DepthTier.ncnnCpu:
        case DepthTier.focalLength:
          return 3;
      }
    } catch (_) {
      return 3;
    }
  }

  bool get isReady => _prefs != null;

  bool _deferredAllowed(CoreFeature feature) => _policy.mayInitialize(feature);

  int get language => _prefs!.getInt(_kLanguage) ?? 0;
  bool get useGpu => _prefs!.getBool(_kUseGpu) ?? false;
  bool get useNativeDepthBridge =>
      _prefs!.getBool(_kUseNativeDepthBridge) ?? false;
  bool get useHardwareDepthMode =>
      _prefs!.getBool(_kUseHardwareDepthMode) ?? false;
  int get numThreads => _prefs!.getInt(_kNumThreads) ?? 3;
  double get focalLength => _prefs!.getDouble(_kFocalLength) ?? 1006.0;
  bool get isCalibrated => _prefs!.getBool(_kIsCalibrated) ?? false;
  bool get pitchBlackUi => _prefs!.getBool(_kPitchBlackUi) ?? true;
  bool get guideDogMode => _prefs!.getBool(_kGuideDogMode) ?? false;
  bool get fieldLogging => _prefs!.getBool(_kFieldLogging) ?? false;
  bool get tutorialSeen => _prefs!.getBool(_kTutorialSeen) ?? false;
  bool get sosContactPrompted => _prefs!.getBool(_kSosContactPrompted) ?? false;
  bool get classicGestures => _prefs!.getBool(_kClassicGestures) ?? false;
  bool get ncnnDisabled => _prefs?.getBool(_kNcnnDisabled) ?? false;

  // V5.3: Cross-session exponential backoff getters.
  /// Backoff level: 0=never failed, 1=1hr wait, 2=24hr wait, 3+=7day wait.
  int get ncnnBackoffLevel => _prefs?.getInt(_kNcnnBackoffLevel) ?? 0;

  /// Unix timestamp (ms) before which NCNN init should not be attempted.
  int get ncnnBackoffUntilMs => _prefs?.getInt(_kNcnnBackoffUntilMs) ?? 0;

  double get speechRate =>
      (_prefs!.getDouble(_kSpeechRate) ?? kSpeechRateDefault).clamp(
        kSpeechRateMin,
        kSpeechRateMax,
      );
  double get ttsVolume => (_prefs!.getDouble(_kTtsVolume) ?? kTtsVolumeDefault)
      .clamp(kTtsVolumeMin, kTtsVolumeMax);
  double get earconVolume =>
      (_prefs!.getDouble(_kEarconVolume) ?? kEarconVolumeDefault).clamp(
        kEarconVolumeMin,
        kEarconVolumeMax,
      );

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

  TapSensitivity get tapSensitivity {
    final i = _prefs?.getInt(_kTapSensitivity) ?? TapSensitivity.normal.index;
    return TapSensitivity.values[i.clamp(0, TapSensitivity.values.length - 1)];
  }

  Future<void> setTapSensitivity(TapSensitivity v) async =>
      _prefs?.setInt(_kTapSensitivity, v.index) ?? Future<void>.value();

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

  Future<void> setSosContactPrompted(bool v) async =>
      _prefs!.setBool(_kSosContactPrompted, v);

  Future<void> setClassicGestures(bool v) async =>
      _prefs!.setBool(_kClassicGestures, v);

  Future<void> setSpeechRate(double v) async =>
      _prefs!.setDouble(_kSpeechRate, v.clamp(kSpeechRateMin, kSpeechRateMax));

  // Voice confirmations must preserve the persistence acknowledgement rather
  // than treating a completed Future<void> as proof of a successful write.
  Future<bool> saveVoiceSpeechRate(double value) async =>
      _prefs?.setDouble(_kSpeechRate, value.clamp(kSpeechRateMin, kSpeechRateMax)) ?? false;
  Future<bool> saveVoiceSpeechVolume(double value) async =>
      _prefs?.setDouble(_kTtsVolume, value.clamp(kTtsVolumeMin, kTtsVolumeMax)) ?? false;
  Future<bool> saveVoiceTheme(BagdarThemeName value) async =>
      _prefs?.setString(_kThemeMode, value.id) ?? false;

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

  Future<void> setNcnnDisabled(bool v) async =>
      _prefs?.setBool(_kNcnnDisabled, v) ?? Future<void>.value();

  // V5.3: Persist exponential backoff state.
  Future<void> setNcnnBackoff(int level, int untilMs) async {
    await (_prefs?.setInt(_kNcnnBackoffLevel, level) ?? Future<void>.value());
    await (_prefs?.setInt(_kNcnnBackoffUntilMs, untilMs) ??
        Future<void>.value());
  }

  /// Clears all NCNN backoff state so the next init attempt is allowed
  /// immediately.  Called by the reset depth engine voice command.
  Future<void> resetNcnnBackoff() async {
    await (_prefs?.remove(_kNcnnBackoffLevel) ?? Future<void>.value());
    await (_prefs?.remove(_kNcnnBackoffUntilMs) ?? Future<void>.value());
  }

  bool get clearPathAnnounce => _prefs?.getBool(_kClearPathAnnounce) ?? false;
  Future<void> setClearPathAnnounce(bool v) async =>
      _prefs!.setBool(_kClearPathAnnounce, v);

  bool get batteryAnnounce => _prefs?.getBool(_kBatteryAnnounce) ?? true;
  Future<void> setBatteryAnnounce(bool v) async =>
      _prefs!.setBool(_kBatteryAnnounce, v);

  bool get modeAnnounce => _prefs?.getBool(_kModeAnnounce) ?? true;
  Future<void> setModeAnnounce(bool v) async =>
      _prefs!.setBool(_kModeAnnounce, v);

  bool get audioTourSeen => _prefs?.getBool(_kAudioTourSeen) ?? false;
  Future<void> setAudioTourSeen(bool v) async =>
      _prefs!.setBool(_kAudioTourSeen, v);

  bool get sceneNarrationEnabled =>
      _deferredAllowed(CoreFeature.sceneNarration) &&
      (_prefs?.getBool(_kSceneNarrationEnabled) ?? true);
  Future<void> setSceneNarrationEnabled(bool v) async {
    if (!_deferredAllowed(CoreFeature.sceneNarration)) return;
    await _prefs!.setBool(_kSceneNarrationEnabled, v);
  }

  bool get paymentSmsEnabled =>
      _deferredAllowed(CoreFeature.paymentSms) &&
      (_prefs?.getBool(_kPaymentSmsEnabled) ?? false);
  Future<void> setPaymentSmsEnabled(bool v) async {
    if (!_deferredAllowed(CoreFeature.paymentSms)) return;
    await _prefs!.setBool(_kPaymentSmsEnabled, v);
  }

  bool get calibrationDeclined =>
      _prefs?.getBool(_kCalibrationDeclined) ?? false;
  Future<void> setCalibrationDeclined(bool v) async =>
      _prefs!.setBool(_kCalibrationDeclined, v);

  bool get disclaimerAcknowledged =>
      _prefs?.getBool(_kDisclaimerAcknowledged) ?? false;
  Future<void> setDisclaimerAcknowledged(bool v) async {
    await _prefs!.setBool(_kDisclaimerAcknowledged, v);
    if (v) {
      await _prefs!.setInt(
        _kDisclaimerAcknowledgedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  DateTime? get disclaimerAcknowledgedAt {
    final ms = _prefs?.getInt(_kDisclaimerAcknowledgedAt);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get disclaimerNeedsReprompt {
    if (!disclaimerAcknowledged) return true;
    final at = disclaimerAcknowledgedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(days: 7);
  }

  /// Winter Mode: manual toggle persisted across launches. The effective
  /// active state can also be auto-driven by [WinterModeService] based on
  /// battery temperature; this getter exposes only the user-set bit.
  bool get winterModeManual =>
      _deferredAllowed(CoreFeature.experimentalWinter) &&
      (_prefs?.getBool(_kWinterModeManual) ?? false);
  Future<void> setWinterModeManual(bool v) async {
    if (!_deferredAllowed(CoreFeature.experimentalWinter)) return;
    await _prefs!.setBool(_kWinterModeManual, v);
  }

  /// Visual theme. Default: dark/OLED with electric-yellow accent — chosen
  /// because the majority of target users either run pitch-black mode (so
  /// theme is invisible) or benefit from OLED power savings on budget
  /// devices. Persisted as a string id to remain forward-compatible with
  /// future themes.
  BagdarThemeName get themeMode {
    final id = _prefs?.getString(_kThemeMode);
    return BagdarThemeNameX.fromId(id);
  }

  Future<void> setThemeMode(BagdarThemeName v) async =>
      _prefs?.setString(_kThemeMode, v.id) ?? Future<void>.value();

  /// Developer rollout flag. Default [GenericObstacleMode.shadow].
  /// [GenericObstacleMode.assistive] is rejected until a signed validation
  /// report authorizes a specific build.
  GenericObstacleMode get genericObstacleMode {
    final i =
        _prefs?.getInt(_kGenericObstacleMode) ??
        GenericObstacleMode.shadow.index;
    if (i < 0 || i >= GenericObstacleMode.values.length) {
      return GenericObstacleMode.shadow;
    }
    return sanitizeGenericObstacleMode(GenericObstacleMode.values[i]);
  }

  Future<void> setGenericObstacleMode(GenericObstacleMode v) async =>
      _prefs?.setInt(
        _kGenericObstacleMode,
        sanitizeGenericObstacleMode(v).index,
      ) ??
      Future<void>.value();

  bool get enableKazakhStackV2 =>
      _deferredAllowed(CoreFeature.kazakhStackV2) &&
      (_prefs?.getBool(_kEnableKazakhStackV2) ?? false);

  Future<void> setEnableKazakhStackV2(bool v) async {
    if (!_deferredAllowed(CoreFeature.kazakhStackV2)) return;
    await (_prefs?.setBool(_kEnableKazakhStackV2, v) ?? Future<void>.value());
  }

  /// User-selected TTS voice name for Russian. Empty string means auto.
  String get preferredRuVoice => _prefs?.getString(_kPreferredRuVoice) ?? '';
  Future<void> setPreferredRuVoice(String v) async =>
      _prefs?.setString(_kPreferredRuVoice, v) ?? Future<void>.value();

  /// User-selected TTS voice name for Kazakh. Empty string means auto.
  String get preferredKkVoice => _prefs?.getString(_kPreferredKkVoice) ?? '';
  Future<void> setPreferredKkVoice(String v) async =>
      _prefs?.setString(_kPreferredKkVoice, v) ?? Future<void>.value();

  /// Geomagnetic indoor trail memory (Phase 1 — Direction 6). When on,
  /// `IndoorTrailRecorder` is allowed to capture step+heading+magnetic
  /// signatures and `IndoorTrailReplay` may emit nav prompts.
  bool get indoorTrailMemory =>
      _deferredAllowed(CoreFeature.indoorTrail) &&
      (_prefs?.getBool(_kIndoorTrailMemory) ?? false);
  Future<void> setIndoorTrailMemory(bool v) async {
    if (!_deferredAllowed(CoreFeature.indoorTrail)) return;
    await (_prefs?.setBool(_kIndoorTrailMemory, v) ?? Future<void>.value());
  }

  /// Mesh-net buddy alerts (Phase 2 — Direction 3). When on, the BLE
  /// peer-network plugin starts advertising/scanning. Disabled by
  /// default until the `BleBuddyPlugin` ships and battery/permission
  /// UX is validated.
  bool get meshBuddyAlerts =>
      _deferredAllowed(CoreFeature.bleMesh) &&
      (_prefs?.getBool(_kMeshBuddyAlerts) ?? false);
  Future<void> setMeshBuddyAlerts(bool v) async {
    if (!_deferredAllowed(CoreFeature.bleMesh)) return;
    await (_prefs?.setBool(_kMeshBuddyAlerts, v) ?? Future<void>.value());
  }

  /// Bazaar mode (Phase 1 — Direction 9 sub-mode). Adjusts crowd
  /// suppression / hanging-obstacle priority via threshold tuning;
  /// does not bundle new ML assets.
  bool get bazaarMode =>
      _deferredAllowed(CoreFeature.bazaarLivestock) &&
      (_prefs?.getBool(_kBazaarMode) ?? false);
  Future<void> setBazaarMode(bool v) async {
    if (!_deferredAllowed(CoreFeature.bazaarLivestock)) return;
    await (_prefs?.setBool(_kBazaarMode, v) ?? Future<void>.value());
  }

  /// Livestock awareness (Phase 1 — Direction 9 sub-mode). Enables
  /// localized announcements for cow/sheep/goat/horse/chicken/stray dog
  /// when corresponding labels enter the YOLO label set. Never
  /// reduces vehicle/pedestrian sensitivity.
  bool get livestockAwareness =>
      _deferredAllowed(CoreFeature.bazaarLivestock) &&
      (_prefs?.getBool(_kLivestockAwareness) ?? false);
  Future<void> setLivestockAwareness(bool v) async {
    if (!_deferredAllowed(CoreFeature.bazaarLivestock)) return;
    await (_prefs?.setBool(_kLivestockAwareness, v) ?? Future<void>.value());
  }

  /// Open Smart-Cane Sensor Pod (Phase 2 — Direction 7). When on, the
  /// app attempts to scan for a paired OSCP cane via BLE. The app
  /// remains fully usable when the pod is absent.
  bool get oscpPod =>
      _deferredAllowed(CoreFeature.smartCane) &&
      (_prefs?.getBool(_kOscpPod) ?? false);
  Future<void> setOscpPod(bool v) async {
    if (!_deferredAllowed(CoreFeature.smartCane)) return;
    await (_prefs?.setBool(_kOscpPod, v) ?? Future<void>.value());
  }

  /// Local ASR adaptation (Phase 1 — Direction 12 foundations). When
  /// on, `VoiceAdaptationStore` retains transcripts of successful
  /// commands and (later) audio features for a user-controlled on-device
  /// LoRA adapter. No data leaves the device.
  bool get localAsrAdaptation =>
      _deferredAllowed(CoreFeature.localAsrAdaptation) &&
      (_prefs?.getBool(_kLocalAsrAdaptation) ?? false);
  Future<void> setLocalAsrAdaptation(bool v) async {
    if (!_deferredAllowed(CoreFeature.localAsrAdaptation)) return;
    await (_prefs?.setBool(_kLocalAsrAdaptation, v) ?? Future<void>.value());
  }

  /// On-device VLM companion (Phase 4 — Direction 11). Gated by
  /// charging + thermal + memory; never preempts hazard detection.
  bool get vlmCompanion =>
      _deferredAllowed(CoreFeature.vlmSceneQa) &&
      (_prefs?.getBool(_kVlmCompanion) ?? false);
  Future<void> setVlmCompanion(bool v) async {
    if (!_deferredAllowed(CoreFeature.vlmSceneQa)) return;
    await (_prefs?.setBool(_kVlmCompanion, v) ?? Future<void>.value());
  }

  /// FMCW chirp echolocation depth (Phase 5 — Direction 1).
  /// Experimental; disabled when headphones / call audio / AWM / ASR
  /// own the mic.
  bool get sonarDepth =>
      _deferredAllowed(CoreFeature.sonar) &&
      (_prefs?.getBool(_kSonarDepth) ?? false);
  Future<void> setSonarDepth(bool v) async {
    if (!_deferredAllowed(CoreFeature.sonar)) return;
    await (_prefs?.setBool(_kSonarDepth, v) ?? Future<void>.value());
  }

  /// Effective `ContextMode` derived from the bazaar/livestock feature
  /// flags. Bazaar takes precedence over livestock when both are on
  /// (bazaar tuning is louder); when neither is on the result is
  /// [ContextMode.none].
  ContextMode get contextMode {
    if (bazaarMode) return ContextMode.bazaar;
    if (livestockAwareness) return ContextMode.livestock;
    return ContextMode.none;
  }

  Future<void> resetAll() async => _prefs!.clear();
}

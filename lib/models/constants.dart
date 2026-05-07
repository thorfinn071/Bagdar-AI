class RealDim {
  final String type;
  final double meters;
  const RealDim(this.type, this.meters);
}

const double kDefaultFocalLength = 1006.0;

const String kMapManifestUrl = String.fromEnvironment(
  'VG_MAP_MANIFEST_URL',
  defaultValue:
      'https://umhmnhbcqncmrrpvbbor.supabase.co/storage/v1/object/public/offline-maps/map_packages.json',
);

const Map<String, RealDim> kRealDims = {
  'person': RealDim('height', 1.70),
  'car': RealDim('width', 1.80),
  'bus': RealDim('width', 2.50),
  'truck': RealDim('width', 2.50),
  'motorcycle': RealDim('height', 1.10),
  'bicycle': RealDim('height', 1.00),
  'dog': RealDim('height', 0.50),
  'cat': RealDim('height', 0.30),
  'stop sign': RealDim('width', 0.75),
  'bench': RealDim('width', 1.50),
  'fire hydrant': RealDim('height', 0.60),
  'parking meter': RealDim('height', 1.20),
  'traffic light': RealDim('height', 0.90),
  'backpack': RealDim('height', 0.50),
  'handbag': RealDim('height', 0.30),
  'suitcase': RealDim('height', 0.70),
  'umbrella': RealDim('height', 1.00),
};

const Map<String, double> kClassWeight = {
  'person': 1.0,
  'car': 1.6,
  'bus': 1.8,
  'truck': 2.0,
  'motorcycle': 1.5,
  'bicycle': 1.2,
  'dog': 1.2,
  'cat': 0.6,
  'traffic light': 0.6,
  'stop sign': 0.6,
  'bench': 0.8,
  'fire hydrant': 0.9,
  'parking meter': 0.7,
  'backpack': 0.7,
  'handbag': 0.7,
  'suitcase': 0.8,
  'umbrella': 0.7,
  'chair': 0.8,
  'potted plant': 0.7,
  'bottle': 0.5,
};

/// Hard whitelist of COCO classes that produce alerts.
///
/// Without this filter the YOLO output would feed all 80 COCO labels into
/// `Tracker` -> `AlertManager`, causing the user to hear absurd alerts about
/// `frisbee`, `toothbrush`, `airplane`, `donut`, etc.  The constant alert
/// spam erodes trust in the system and trains users to ignore warnings —
/// the failure mode that ultimately causes injury.
///
/// The whitelist is restricted to navigation-relevant categories: people,
/// vehicles, common street furniture, traffic signs, animals at human scale,
/// carry items (which usually indicate a person), and a small set of indoor
/// hazards (chair, potted plant, bottle).
const Set<String> kAlertClassWhitelist = {
  // pedestrians / animals
  'person',
  'dog',
  'cat',
  // wheeled traffic
  'bicycle',
  'car',
  'motorcycle',
  'bus',
  'truck',
  // signage / street furniture
  'traffic light',
  'fire hydrant',
  'stop sign',
  'parking meter',
  'bench',
  // carry items (proxy for a person nearby)
  'backpack',
  'handbag',
  'suitcase',
  'umbrella',
  // indoor hazards a blind user can collide with
  'chair',
  'potted plant',
  'bottle',
};

/// Per-class minimum YOLO confidence required for an alert to fire.
///
/// YOLOv8n INT8 has wildly unequal per-class precision. A single uniform
/// 0.45 threshold over-detects weak classes (false positives) and
/// under-detects strong/danger-critical classes (missed pedestrians at
/// dusk).  These thresholds are tuned around the published per-class mAP
/// of YOLOv8 on COCO and the safety asymmetry: a missed pedestrian or
/// vehicle is far worse than a missed bench.
const Map<String, double> kClassMinConf = {
  // Danger-critical, high precision in YOLOv8n: keep the bar low so we
  // catch them at distance / in clutter.
  'person': 0.40,
  'car': 0.40,
  'bus': 0.40,
  'truck': 0.40,
  'motorcycle': 0.40,
  'bicycle': 0.42,
  // Animals — medium precision.
  'dog': 0.45,
  'cat': 0.50,
  // Signs and traffic infrastructure — must be confident before we say
  // "stop sign" or "traffic light".
  'traffic light': 0.50,
  'stop sign': 0.55,
  'fire hydrant': 0.55,
  'parking meter': 0.55,
  'bench': 0.50,
  // Carry items / indoor hazards — narrow false-positive budget.
  'backpack': 0.55,
  'handbag': 0.60,
  'suitcase': 0.55,
  'umbrella': 0.55,
  'chair': 0.55,
  'potted plant': 0.60,
  'bottle': 0.65,
};

/// Default minimum confidence applied to a whitelisted class that has no
/// explicit entry in [kClassMinConf]. Intentionally conservative.
const double kDefaultClassMinConf = 0.50;

/// Returns the per-class confidence floor below which a YOLO detection
/// must be discarded before it ever reaches the tracker.
double minConfFor(String label) =>
    kClassMinConf[label] ?? kDefaultClassMinConf;

const int kZoneCount = 5;
const int kTrackMaxAge = 6;
const double kTrackMatchDist = 70.0;
const double kIoUMatchThreshold = 0.2;
const int kTrackConfirmFrames = 2;
const int kApproachHistLen = 6;
const double kApproachMinDtSec = 0.35;
const double kVehApproachAreaRateT = 0.22;
const double kVehApproachHeightRateT = 0.14;

const double kPedApproachAreaRateT = 0.08;
const double kPedApproachHeightRateT = 0.06;









const double kVehTurnAngVelThreshold = 0.3;
const double kVehTurnDistThreshold = 5.0;
const double kVehTurnCurvatureThreshold = 0.05;
const int kVehTurnMinCenterHist = 3;
const double kVehTurnMinDisplacementPx = 1.5;

const double kDetConfThreshold = 0.35;

const double kMinBboxAreaRatio = 0.004;
const double kMinAlertConf = 0.50;
const double kHighConfLevel = 0.70;
const double kConfEmaAlpha = 0.20;

const double kDistVeryCloseT = 0.26;
const double kDistCloseT = 0.13;
const double kFarAreaMax = 0.030;
const double kFarHeightMax = 0.22;
const double kAbsFarArea = 0.018;
const double kAbsFarHeight = 0.16;

const Duration kCriticalCooldown = Duration(milliseconds: 800);
const Duration kCriticalRepeatCooldownDefault = Duration(milliseconds: 4000);
const Duration kCriticalRepeatCooldownSafety = Duration(milliseconds: 2000);
const Duration kWarningCooldown = Duration(seconds: 3);
const Duration kInfoCooldown = Duration(seconds: 10);
const Duration kPersonCooldown = Duration(seconds: 15);
const Duration kIndoorPersonCooldown = Duration(seconds: 15);
const int kIndoorCrowdPersonThreshold = 3;
const Duration kApproachCooldown = Duration(milliseconds: 2500);
const double kApproachingLabelThreatMaxDistM = 15.0;
const Duration kStaticObjectCooldown = Duration(seconds: 20);

const Duration kClearAnnounceDuration = Duration(milliseconds: 1200);

const Duration kEmptyConfirmDuration = Duration(milliseconds: 2500);
const Duration kEmptyConfirmDurationCane = Duration(seconds: 4);

const Duration kPostCriticalClearDelay = Duration(seconds: 5);

const Duration kVibrateCooldown = Duration(milliseconds: 1500);

const Duration kCaneVibrateCooldown = Duration(milliseconds: 150);

const Duration kCaneVeryCloseCooldown = Duration(milliseconds: 200);
const Duration kCaneCloseCooldown = Duration(milliseconds: 450);
const Duration kCaneFarCooldown = Duration(milliseconds: 850);

const List<int> kHapticFarLeft = [0, 40, 30, 80];
const List<int> kHapticFarCenter = [0, 60, 30, 60];
const List<int> kHapticFarRight = [0, 80, 30, 40];

const List<int> kHapticCloseLeft = [0, 60, 30, 140];
const List<int> kHapticCloseCenter = [0, 100, 30, 100];
const List<int> kHapticCloseRight = [0, 140, 30, 60];
const List<int> kHapticCriticalCooldownPattern = [0, 80, 30, 80, 30, 80];
const List<int> kHapticCriticalCooldownIntensities = [0, 255, 0, 255, 0, 255];

const List<int> kHapticVcLeft = [0, 80, 40, 200, 60, 200];
const List<int> kHapticVcCenter = [0, 200, 40, 80, 40, 200];
const List<int> kHapticVcRight = [0, 200, 40, 200, 60, 80];
const List<int> kHapticPathClear = [0, 60, 60, 60, 60, 60];

const double kGuideMinCenterThreat = 2.5;

const double kGuideImprovementRatio = 1.3;

const double kGuideImprovementAbs = 0.8;

const int kHintStableFrames = 3;

const Duration kGuideCooldown = Duration(seconds: 5);

const Duration kMidasInterval = Duration(milliseconds: 800);

const double kMidasMinCoverage = 0.12;

const double kMidasDropRatio = 0.30;




const int kMidasStuckTimeoutMs = 3000;

const double kFusionWarningScore = 0.50;

const double kFusionCriticalScore = 0.58;

const int kFusionTemporalFrames = 5;

const Duration kHazardCriticalCooldown = Duration(milliseconds: 500);
const Duration kHazardWarningCooldown = Duration(seconds: 4);

/// Cooldown between successive dead-zone hazard alerts.
///
/// Safety audit 3.6: previously `Duration.zero`, which let dead-zone
/// hazards fire on every analyzer frame.  The detector already has a
/// `_kDeadZoneConfirmFrames=3` warm-up before the *first* fire; this
/// cooldown enforces a minimum gap between *repeats* so the user is not
/// hammered with the same caution multiple times per second.
const Duration kHazardDeadZoneCooldown = Duration(seconds: 1);

const Duration kHazardCooldown = kHazardWarningCooldown;

const double kFusionEmaAlpha = 0.12;

const Duration kHeartbeatInterval = Duration(seconds: 30);
const Duration kHeartbeatIntervalPitchBlack = Duration(seconds: 30);

/// Maximum time a single TTS utterance is allowed to take before the
/// stall watchdog fires.
///
/// Safety audit 7.2: previously 10 s, which is a lifetime in traffic if
/// the TTS engine has hung mid-sentence.  Most safety-critical alerts
/// ("Stop!", "Cars approaching") render in under 2 s; longer utterances
/// (info-priority scene narration) are not safety-critical and can be
/// truncated without harm.
///
/// 4 s is the longest a critical alert utterance has any business taking
/// on a working TTS engine.  When this fires, the watchdog stops the
/// engine, plays an earcon, and emits a distinctive haptic pattern so
/// the user is alerted to the failure even if no speech is heard.
const Duration kTtsStallTimeout = Duration(seconds: 4);

/// Distinctive haptic pattern fired when the TTS stall watchdog trips.
///
/// Three strong, slightly spaced pulses — deliberately unlike any other
/// haptic pattern in the app so the user can recognize "TTS just died,
/// the world I cannot see has not gone silent in a good way".
const List<int> kHapticTtsStallPattern = [0, 220, 100, 220, 100, 220];
const List<int> kHapticTtsStallIntensities = [0, 255, 0, 255, 0, 255];

const Duration kSosTwoFingerHold = Duration(milliseconds: 1500);
const int kSosRetries = 3;
const Duration kSosRetryDelay = Duration(seconds: 2);
const Duration kSosCachedPositionMaxAge = Duration(minutes: 5);

const double kVoiceSpeechRateStep = 0.15;
const double kVoiceVolumeStep = 0.1;

const double kBeaconFarDistM = 3.0;
const double kBeaconNearDistM = 0.4;
const double kBeaconMaxHz = 8.0;
const double kBeaconMinHz = 0.5;

const double kHardwareDepthMinConfidence = 0.30;
const double kHardwareDepthMinMeanMeters = 0.30;
const double kHardwareDepthMaxMeanMeters = 25.0;
const int kHardwareDepthLowConfFrames = 5;





const double kHardwareDepthHighConfThreshold = 0.7;
const Duration kHardwareDepthHighConfStreakForDispose = Duration(seconds: 30);

const int kTargetDetectFps = 7;
const int kMinAcceptableDetectFps = 3;
const int kTargetFrameBudgetMs = 140;
const int kSoftFrameBudgetMs = 200;
const int kHardFrameBudgetMs = 280;







const int kDetectIntervalSafetyCeilingMs = 500;







const int kStationaryGateDetectMs = 300;
const Duration kStationaryGateResumeWindow = Duration(seconds: 5);
const Duration kStationaryGatePostCriticalBlock = Duration(seconds: 5);
const Duration kStationaryGateMidasOff = Duration(hours: 1);

const double kThermalWarmTempC = 37.0;
const double kThermalHotTempC = 40.0;
const double kThermalCriticalTempC = 43.0;
const int kThermalStatusWarm = 2;
const int kThermalStatusHot = 3;
const int kThermalStatusCritical = 4;

const int kThermalPenaltyWarmMs = 30;
const int kThermalPenaltyHotMs = 80;
const int kThermalPenaltyCriticalMs = 120;

const Duration kThermalCommitDwell = Duration(seconds: 60);
const Duration kThermalTransitionSilence = Duration(seconds: 3);

const double kInfTimeFastMs = 90.0;
const double kInfTimeNormalMs = 130.0;
const double kInfTimeSlowMs = 180.0;
const double kInfTimeCriticalMs = 240.0;

const int kMemoryPressureLowMB = 400;
const int kMemoryPressureCriticalMB = 250;
const Duration kMemoryPressurePollInterval = Duration(seconds: 15);
const Duration kMemoryPressureRecoveryWindow = Duration(seconds: 10);

const Duration kStallWatchdogPeriod = Duration(milliseconds: 500);
const Duration kStallWatchdogThresholdNormal = Duration(milliseconds: 2000);
const Duration kStallWatchdogThresholdWarm = Duration(milliseconds: 2500);
const Duration kStallWatchdogThresholdHot = Duration(milliseconds: 3000);
const Duration kStallWatchdogThresholdCritical = Duration(milliseconds: 4000);

const double kSwipeStrongVelocity = 500.0;
const double kSwipeWeakVelocity = 150.0;
const Duration kWeakGestureCooldown = Duration(seconds: 10);

const Duration kPaymentSmsDedupWindow = Duration(seconds: 30);
const int kPaymentSmsMaxSenderNameLen = 48;
const int kPaymentSmsMaxBodyLen = 800;

const int kObjectMemoryMaxItems = 200;
const int kObjectMemoryEmbedDimYHist = 16;
const int kObjectMemoryRememberTimeoutMs = 4000;
const double kObjectMemoryRememberStableSimilarity = 0.85;
const int kObjectMemoryRememberMinFrames = 3;
const double kObjectMemoryRememberMinAreaRatio = 0.04;
const double kObjectMemoryRememberCentralityRatio = 0.6;
const double kObjectMemoryBlendAlpha = 0.3;
const double kObjectMemoryYHistMatchThreshold = 0.82;
const int kObjectFinderMaxSessionMs = 60000;
const Duration kObjectFinderTtsCooldown = Duration(seconds: 2);
const Duration kObjectFinderHapticCooldown = Duration(milliseconds: 500);
const int kObjectFinderLostAnnounceMs = 6000;
const double kObjectFinderFoundDistM = 0.6;
const int kObjectFinderFoundSteadyFrames = 5;
const double kObjectFinderCenterCropRatio = 0.4;
const Duration kObjectFinderFeedThrottle = Duration(milliseconds: 200);

const int kEventGridW = 80;
const int kEventGridH = 60;
const int kEventDiffThreshold = 18;
const double kEventBaselineMultiplier = 4.0;
const double kEventBaselineEmaAlpha = 0.05;
const double kEventGlobalPanFrac = 0.40;
const int kEventMinBlobArea = 4;
const double kEventMaxBlobAreaFrac = 0.20;
const int kEventMaxBlobsPerFrame = 16;
const int kEventMaxLabels = 256;
const double kEventMatchRadiusPx = 12.0;
const int kEventMinPersistFrames = 3;
const int kEventPersonMinPersistFrames = 4;
const double kEventVehicleVxPxS = 220.0;
const double kEventCriticalVxPxS = 350.0;
const double kEventVehicleAspectMin = 1.4;
const double kEventPersonAspectMax = 0.9;
const double kEventVehicleCyFracLo = 0.30;
const double kEventVehicleCyFracHi = 0.85;
const double kEventPersonCyFracLo = 0.40;
const double kEventPersonCyFracHi = 0.95;
const double kEventCriticalCenterFracLo = 0.20;
const double kEventCriticalCenterFracHi = 0.80;
const Duration kEventCriticalCooldown = Duration(milliseconds: 1500);
const Duration kEventSoftCooldown = Duration(milliseconds: 2500);

const int kAwmSampleRate = 16000;
const int kAwmWindowSamples = 16000;
const double kAwmClassifyHz = 1.0;
const double kAwmClassifyHzThrottled = 0.5;
const int kAwmTemporalFrames = 3;
const double kAwmMinConfidence = 0.35;
const Duration kAwmVehicleCooldown = Duration(seconds: 3);
const Duration kAwmHornCooldown = Duration(seconds: 5);
const Duration kAwmSirenCooldown = Duration(seconds: 8);
const Duration kAwmDogCooldown = Duration(seconds: 8);
const Duration kAwmCrowdCooldown = Duration(seconds: 15);
const double kAwmReverbIndoorThreshold = 0.4;
const double kAwmReverbOutdoorThreshold = 0.2;
const int kAwmMelBins = 64;
const int kAwmFftSize = 512;
const int kAwmBearingFftSize = 256;
const double kAwmTransientThresholdMultiplier = 3.0;

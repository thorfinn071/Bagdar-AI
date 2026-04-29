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
  'traffic light': 0.6,
  'stop sign': 0.6,
  'bench': 0.8,
  'fire hydrant': 0.9,
  'parking meter': 0.7,
  'backpack': 0.7,
  'handbag': 0.7,
  'suitcase': 0.8,
  'umbrella': 0.7,
};

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

const Duration kCriticalCooldown = Duration(milliseconds: 1400);
const Duration kWarningCooldown = Duration(seconds: 3);
const Duration kInfoCooldown = Duration(seconds: 5);
const Duration kPersonCooldown = Duration(seconds: 8);
const Duration kApproachCooldown = Duration(milliseconds: 2500);

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

const List<int> kHapticVcLeft = [0, 80, 40, 200, 60, 200];
const List<int> kHapticVcCenter = [0, 200, 40, 80, 40, 200];
const List<int> kHapticVcRight = [0, 200, 40, 200, 60, 80];
const List<int> kHapticPathClear = [0, 60, 60, 60, 60, 60];

const double kGuideMinCenterThreat = 1.8;

const double kGuideImprovementRatio = 1.3;

const double kGuideImprovementAbs = 0.8;

const int kHintStableFrames = 3;

const Duration kGuideCooldown = Duration(seconds: 5);

const Duration kMidasInterval = Duration(milliseconds: 500);

const double kMidasMinCoverage = 0.12;

const double kMidasDropRatio = 0.30;




const int kMidasStuckTimeoutMs = 3000;

const double kFusionWarningScore = 0.50;

const double kFusionCriticalScore = 0.58;

const int kFusionTemporalFrames = 4;

const Duration kHazardCriticalCooldown = Duration(milliseconds: 500);
const Duration kHazardWarningCooldown = Duration(seconds: 4);
const Duration kHazardDeadZoneCooldown = Duration.zero;

const Duration kHazardCooldown = kHazardWarningCooldown;

const double kFusionEmaAlpha = 0.20;

const Duration kHeartbeatInterval = Duration(seconds: 30);
const Duration kHeartbeatIntervalPitchBlack = Duration(seconds: 30);

const Duration kTtsStallTimeout = Duration(seconds: 10);

const Duration kSosTwoFingerHold = Duration(milliseconds: 1500);

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







const int kDetectIntervalSafetyCeilingMs = 550;







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

const Duration kStallWatchdogPeriod = Duration(milliseconds: 250);
const Duration kStallWatchdogThresholdNormal = Duration(milliseconds: 1200);
const Duration kStallWatchdogThresholdWarm = Duration(milliseconds: 1500);
const Duration kStallWatchdogThresholdHot = Duration(milliseconds: 1800);
const Duration kStallWatchdogThresholdCritical = Duration(milliseconds: 2400);

const double kSwipeStrongVelocity = 500.0;
const double kSwipeWeakVelocity = 150.0;
const Duration kWeakGestureCooldown = Duration(seconds: 10);

class RealDim {
  final String type;
  final double meters;
  const RealDim(this.type, this.meters);
}

const double kDefaultFocalLength = 1006.0;

const Map<String, RealDim> kRealDims = {
  'person':         RealDim('height', 1.70),
  'car':            RealDim('width',  1.80),
  'bus':            RealDim('width',  2.50),
  'truck':          RealDim('width',  2.50),
  'motorcycle':     RealDim('height', 1.10),
  'bicycle':        RealDim('height', 1.00),
  'dog':            RealDim('height', 0.50),
  'cat':            RealDim('height', 0.30),
  'stop sign':      RealDim('width',  0.75),
  'bench':          RealDim('width',  1.50),
  'fire hydrant':   RealDim('height', 0.60),
  'parking meter':  RealDim('height', 1.20),
  'traffic light':  RealDim('height', 0.90),
  'backpack':       RealDim('height', 0.50),
  'handbag':        RealDim('height', 0.30),
  'suitcase':       RealDim('height', 0.70),
  'umbrella':       RealDim('height', 1.00),
};

const Map<String, double> kClassWeight = {
  'person':        1.0,
  'car':           1.6,
  'bus':           1.8,
  'truck':         2.0,
  'motorcycle':    1.5,
  'bicycle':       1.2,
  'dog':           1.2,
  'traffic light': 0.6,
  'stop sign':     0.6,
  'bench':         0.8,
  'fire hydrant':  0.9,
  'parking meter': 0.7,
  'backpack':      0.7,
  'handbag':       0.7,
  'suitcase':      0.8,
  'umbrella':      0.7,
};

const int    kZoneCount              = 5;
const int    kTrackMaxAge            = 12;
const double kTrackMatchDist         = 70.0;
const double kIoUMatchThreshold      = 0.2;
const int    kTrackConfirmFrames     = 2;
const int    kApproachHistLen        = 6;
const double kApproachMinDtSec       = 0.35;
const double kVehApproachAreaRateT   = 0.22;
const double kVehApproachHeightRateT = 0.14;

const double kPedApproachAreaRateT   = 0.08;
const double kPedApproachHeightRateT = 0.06;

const double kDetConfThreshold   = 0.35;

const double kMinBboxAreaRatio   = 0.004;
const double kMinAlertConf = 0.50;
const double kHighConfLevel = 0.70;
const double kConfEmaAlpha = 0.20;

const double kDistVeryCloseT  = 0.26;
const double kDistCloseT      = 0.13;
const double kFarAreaMax      = 0.030;
const double kFarHeightMax    = 0.22;
const double kAbsFarArea      = 0.018;
const double kAbsFarHeight    = 0.16;

const Duration kCriticalCooldown  = Duration(milliseconds: 1400);
const Duration kWarningCooldown   = Duration(seconds: 3);
const Duration kInfoCooldown      = Duration(seconds: 5);
const Duration kPersonCooldown    = Duration(seconds: 8);
const Duration kApproachCooldown  = Duration(milliseconds: 1400);

const Duration kClearAnnounceDuration = Duration(milliseconds: 1200);

const Duration kEmptyConfirmDuration     = Duration(milliseconds: 2500);
const Duration kEmptyConfirmDurationCane = Duration(seconds: 4);

const Duration kPostCriticalClearDelay = Duration(seconds: 5);

const Duration kVibrateCooldown = Duration(milliseconds: 600);

const Duration kCaneVibrateCooldown = Duration(milliseconds: 150);

const Duration kCaneVeryCloseCooldown = Duration(milliseconds: 200);
const Duration kCaneCloseCooldown     = Duration(milliseconds: 450);
const Duration kCaneFarCooldown       = Duration(milliseconds: 850);

const List<int> kHapticFarLeft    = [0,  40, 30,  80];
const List<int> kHapticFarCenter  = [0,  60, 30,  60];
const List<int> kHapticFarRight   = [0,  80, 30,  40];

const List<int> kHapticCloseLeft   = [0,  60, 30, 140];
const List<int> kHapticCloseCenter = [0, 100, 30, 100];
const List<int> kHapticCloseRight  = [0, 140, 30,  60];

const List<int> kHapticVcLeft   = [0,  80, 40, 200, 60, 200];
const List<int> kHapticVcCenter = [0, 200, 40,  80, 40, 200];
const List<int> kHapticVcRight  = [0, 200, 40, 200, 60,  80];
const List<int> kHapticPathClear = [0, 60, 60, 60, 60, 60];

const double kGuideMinCenterThreat  = 1.8;

const double kGuideImprovementRatio = 1.3;

const double kGuideImprovementAbs   = 0.8;

const int kHintStableFrames = 3;

const Duration kGuideCooldown = Duration(seconds: 5);

const Duration kMidasInterval = Duration(milliseconds: 500);

const double kMidasMinCoverage = 0.12;

const double kMidasDropRatio = 0.30;

const double kFusionWarningScore = 0.45;

const double kFusionCriticalScore = 0.75;

const int kFusionTemporalFrames = 3;

const Duration kHazardCooldown = Duration(seconds: 3);
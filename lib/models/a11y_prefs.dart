enum Verbosity { minimal, normal, detailed }

enum AlertFrequency { rare, normal, frequent }

enum HapticStrength { weak, normal, strong }

enum SosTrigger { twoFingerHold, tripleTap, shake }

enum DominantHand { right, left }

extension AlertFrequencyX on AlertFrequency {
  double get multiplier {
    switch (this) {
      case AlertFrequency.rare:
        return 2.0;
      case AlertFrequency.normal:
        return 1.0;
      case AlertFrequency.frequent:
        return 0.5;
    }
  }
}

extension HapticStrengthX on HapticStrength {
  double get multiplier {
    switch (this) {
      case HapticStrength.weak:
        return 0.6;
      case HapticStrength.normal:
        return 1.0;
      case HapticStrength.strong:
        return 1.3;
    }
  }
}

const double kSpeechRateMin = 0.6;
const double kSpeechRateMax = 1.5;
const double kSpeechRateDefault = 1.0;

const double kTtsVolumeMin = 0.5;
const double kTtsVolumeMax = 1.0;
const double kTtsVolumeDefault = 1.0;

const double kEarconVolumeMin = 0.0;
const double kEarconVolumeMax = 1.0;
const double kEarconVolumeDefault = 0.85;

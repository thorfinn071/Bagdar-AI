import 'fall_detector.dart';





























enum IndoorState { unknown, street, indoor }

enum IndoorTransition { none, enteredIndoor, exitedIndoor }

class IndoorGate {
  
  
  static const double _kGoodAccuracyM = 15.0;
  static const double _kPoorAccuracyM = 30.0;

  
  
  static const int _kFreshSec = 30;
  static const int _kStaleSec = 60;

  
  
  static const int _kEnterConfirmations = 15;
  static const int _kExitGpsConfirmations = 8;
  static const int _kExitWalkingFrames = 5;

  IndoorState _state = IndoorState.unknown;
  int _poorStreak = 0;
  int _goodStreak = 0;
  int _walkingStreak = 0;

  IndoorState get state => _state;

  
  int get poorStreak => _poorStreak;
  int get goodStreak => _goodStreak;
  int get walkingStreak => _walkingStreak;

  
  
  
  
  
  IndoorTransition feed({
    required double? gpsAccuracyM,
    required int? gpsAgeSec,
    required MotionState motion,
    required DateTime now,
  }) {
    final quality = _classifyGps(gpsAccuracyM, gpsAgeSec);

    
    if (quality == _GpsQuality.middle) {
      return IndoorTransition.none;
    }

    if (quality == _GpsQuality.poor) {
      
      
      
      
      if (motion == MotionState.walking) {
        _poorStreak = 0;
      } else {
        _poorStreak++;
      }
      _goodStreak = 0;
    } else {
      
      _poorStreak = 0;
      _goodStreak++;
    }

    
    
    
    if (motion == MotionState.walking) {
      _walkingStreak++;
    } else {
      _walkingStreak = 0;
    }

    switch (_state) {
      case IndoorState.unknown:
      case IndoorState.street:
        if (_poorStreak >= _kEnterConfirmations) {
          _state = IndoorState.indoor;
          _poorStreak = 0;
          _goodStreak = 0;
          _walkingStreak = 0;
          return IndoorTransition.enteredIndoor;
        }
        
        
        
        if (_state == IndoorState.unknown && _goodStreak >= 1) {
          _state = IndoorState.street;
        }
        return IndoorTransition.none;

      case IndoorState.indoor:
        final gpsExit = _goodStreak >= _kExitGpsConfirmations;
        final walkExit = _walkingStreak >= _kExitWalkingFrames;
        if (gpsExit || walkExit) {
          _state = IndoorState.street;
          _poorStreak = 0;
          _goodStreak = 0;
          _walkingStreak = 0;
          return IndoorTransition.exitedIndoor;
        }
        return IndoorTransition.none;
    }
  }

  
  
  
  void reset() {
    _state = IndoorState.unknown;
    _poorStreak = 0;
    _goodStreak = 0;
    _walkingStreak = 0;
  }

  static _GpsQuality _classifyGps(double? accuracyM, int? ageSec) {
    if (accuracyM == null) return _GpsQuality.poor;
    if (ageSec != null && ageSec > _kStaleSec) return _GpsQuality.poor;
    if (accuracyM > _kPoorAccuracyM) return _GpsQuality.poor;
    if (accuracyM < _kGoodAccuracyM &&
        (ageSec == null || ageSec < _kFreshSec)) {
      return _GpsQuality.good;
    }
    return _GpsQuality.middle;
  }
}

enum _GpsQuality { good, middle, poor }




enum WeatherTransition {
  none,

  
  
  
  degraded,

  
  
  
  recovered,
}



















class WeatherGate {
  
  
  static const double _kVarLow = 200.0;

  
  
  static const double _kVarHigh = 400.0;

  
  
  
  
  static const double _kAvgHigh = 150.0;

  
  
  
  
  static const int _kConfirmIn = 10;

  
  
  
  static const int _kConfirmOut = 30;

  int _degradedStreak = 0;
  int _recoveredStreak = 0;
  bool _degraded = false;

  
  
  
  bool get degraded => _degraded;

  
  
  
  WeatherTransition feed(double variance, double avgLuminosity) {
    final isLowVis = variance < _kVarLow && avgLuminosity > _kAvgHigh;
    final isClearlyOk = variance > _kVarHigh;

    if (isLowVis) {
      _degradedStreak++;
      _recoveredStreak = 0;
    } else if (isClearlyOk) {
      _recoveredStreak++;
      _degradedStreak = 0;
    } else {
      
      
      
    }

    if (!_degraded && _degradedStreak >= _kConfirmIn) {
      _degraded = true;
      _degradedStreak = 0;
      _recoveredStreak = 0;
      return WeatherTransition.degraded;
    }
    if (_degraded && _recoveredStreak >= _kConfirmOut) {
      _degraded = false;
      _degradedStreak = 0;
      _recoveredStreak = 0;
      return WeatherTransition.recovered;
    }
    return WeatherTransition.none;
  }

  
  
  
  void reset() {
    _degradedStreak = 0;
    _recoveredStreak = 0;
    _degraded = false;
  }
}

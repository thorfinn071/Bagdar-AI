import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassService {
  StreamSubscription<CompassEvent>? _sub;
  double _heading = 0;
  bool _available = false;

  double get heading => _heading;
  bool get isAvailable => _available;

  final StreamController<double> _controller =
      StreamController<double>.broadcast();
  Stream<double> get headingStream => _controller.stream;

  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _throttle = Duration(milliseconds: 500);

  Future<bool> init() async {
    try {
      final stream = FlutterCompass.events;
      if (stream == null) {
        debugPrint('CompassService: compass not available');
        _available = false;
        return false; 
      }
      _available = true;
      _sub = FlutterCompass.events?.listen((event) {
        final h = event.heading;
        if (h == null) return;
        _heading = h;
        final now = DateTime.now();
        if (now.difference(_lastEmit) >= _throttle) {
          _lastEmit = now;
          _controller.add(h);
        }
      });
      debugPrint('CompassService: initialized');
      return true;
    } catch (e) {
      debugPrint('CompassService: init error $e');
      _available = false;
      return false;
    }
  }

  double bearingTo(double fromLat, double fromLng, double toLat, double toLng) {
    final dLng = _toRad(toLng - fromLng);
    final y = sin(dLng) * cos(_toRad(toLat));
    final x =
        cos(_toRad(fromLat)) * sin(_toRad(toLat)) -
        sin(_toRad(fromLat)) * cos(_toRad(toLat)) * cos(dLng);
    return (_toDeg(atan2(y, x)) + 360) % 360;
  }

  String relativeDirection(double compassHeading, double targetBearing) {
    
    double diff = ((targetBearing - compassHeading) % 360 + 360) % 360;
    if (diff <= 20 || diff >= 340) return 'straight';
    if (diff > 20 && diff <= 60) return 'slight_right';
    if (diff > 60 && diff <= 150) return 'right';
    if (diff > 150 && diff <= 210) return 'behind';
    if (diff > 210 && diff <= 300) return 'left';
    return 'slight_left';
  }

  double relativeDegrees(double compassHeading, double targetBearing) {
    double diff = ((targetBearing - compassHeading) % 360 + 360) % 360;
    if (diff > 180) diff -= 360;
    return diff;
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  double _toRad(double deg) => deg * pi / 180;
  double _toDeg(double rad) => rad * 180 / pi;
}

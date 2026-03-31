import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Waypoint {
  final String name;
  final double lat;
  final double lng;
  final DateTime created;

  const Waypoint({
    required this.name,
    required this.lat,
    required this.lng,
    required this.created,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': lat,
    'lng': lng,
    'created': created.toIso8601String(),
  };

  factory Waypoint.fromJson(Map<String, dynamic> json) => Waypoint(
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    created: DateTime.parse(json['created'] as String),
  );

  double distanceTo(double otherLat, double otherLng) =>
      Geolocator.distanceBetween(lat, lng, otherLat, otherLng);
}

class WaypointService {
  static const String _prefsKey = 'vg_waypoints';
  static const double kProximityRadius = 50.0;

  final List<Waypoint> _waypoints = [];
  Timer? _proximityTimer;

  void Function(Waypoint waypoint)? onNearWaypoint;

  List<Waypoint> get waypoints => List.unmodifiable(_waypoints);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey) ?? [];
      _waypoints.clear();
      for (final s in raw) {
        try {
          _waypoints.add(Waypoint.fromJson(
              json.decode(s) as Map<String, dynamic>));
        } catch (_) {}
      }
      debugPrint('WaypointService: loaded ${_waypoints.length} waypoint(s)');
    } catch (e) {
      debugPrint('WaypointService: init error: $e');
    }
  }

  Future<Waypoint?> saveCurrentLocation(String name) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      final wp = Waypoint(
        name: name,
        lat: pos.latitude,
        lng: pos.longitude,
        created: DateTime.now(),
      );

      _waypoints.add(wp);
      await _persist();
      debugPrint('WaypointService: saved "$name" at '
          '${pos.latitude}, ${pos.longitude}');
      return wp;
    } catch (e) {
      debugPrint('WaypointService: saveCurrentLocation error: $e');
      return null;
    }
  }

  Future<void> delete(String name) async {
    _waypoints.removeWhere((w) => w.name == name);
    await _persist();
  }

  void startProximityMonitor({int intervalSec = 30}) {
    _proximityTimer?.cancel();
    _proximityTimer = Timer.periodic(
      Duration(seconds: intervalSec),
      (_) => _checkProximity(),
    );
  }

  void stopProximityMonitor() {
    _proximityTimer?.cancel();
    _proximityTimer = null;
  }

  final Set<String> _announced = {};

  Future<void> _checkProximity() async {
    if (_waypoints.isEmpty || onNearWaypoint == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 5),
        ),
      );

      for (final wp in _waypoints) {
        final dist = wp.distanceTo(pos.latitude, pos.longitude);

        if (_announced.contains(wp.name)) {
          if (dist > kProximityRadius * 3) {
            _announced.remove(wp.name);
          }
          continue;
        }

        if (dist <= kProximityRadius) {
          _announced.add(wp.name);
          onNearWaypoint?.call(wp);
        }
      }
    } catch (_) {}
  }

  void resetAnnounced() => _announced.clear();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      _waypoints.map((w) => json.encode(w.toJson())).toList(),
    );
  }

  void dispose() {
    _proximityTimer?.cancel();
  }
}

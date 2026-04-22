import 'dart:math';

import 'package:geolocator/geolocator.dart';

enum Maneuver {
  straight,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  uTurn,
  arrive,
}

enum TrafficLightColor { red, yellow, green, unknown }

enum TransitLegType { walk, bus, trolleybus, tram, metro }

class Place {
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String category;
  final int distanceMeters;

  const Place({
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
    this.category = '',
    this.distanceMeters = 0,
  });
}

class RouteStep {
  final String instruction;
  final int distanceMeters;
  final int durationSeconds;
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final Maneuver maneuver;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    required this.maneuver,
  });

  double distanceFromPoint(double lat, double lng) =>
      Geolocator.distanceBetween(lat, lng, startLat, startLng);
}

class NavRoute {
  final List<RouteStep> steps;
  final int totalDistanceMeters;
  final int totalDurationSeconds;
  final String destinationName;

  const NavRoute({
    required this.steps,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    this.destinationName = '',
  });
}

class TransitStop {
  final String name;
  final double lat;
  final double lng;
  final List<String> routes;

  const TransitStop({
    required this.name,
    required this.lat,
    required this.lng,
    this.routes = const [],
  });

  double distanceTo(double otherLat, double otherLng) =>
      Geolocator.distanceBetween(lat, lng, otherLat, otherLng);
}

class TransitLeg {
  final TransitLegType type;
  final String? routeName;
  final String? routeNumber;
  final TransitStop? departureStop;
  final TransitStop? arrivalStop;
  final List<TransitStop> intermediateStops;
  final List<RouteStep> walkSteps;
  final int distanceMeters;
  final int durationSeconds;

  const TransitLeg({
    required this.type,
    this.routeName,
    this.routeNumber,
    this.departureStop,
    this.arrivalStop,
    this.intermediateStops = const [],
    this.walkSteps = const [],
    this.distanceMeters = 0,
    this.durationSeconds = 0,
  });

  bool get isWalk => type == TransitLegType.walk;
  int get stopCount => intermediateStops.length;
}

class TransitRoute {
  final List<TransitLeg> legs;
  final int totalDistanceMeters;
  final int totalDurationSeconds;
  final String destinationName;

  const TransitRoute({
    required this.legs,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    this.destinationName = '',
  });
}

double bearingBetween(double lat1, double lng1, double lat2, double lng2) {
  final dLng = _toRad(lng2 - lng1);
  final y = sin(dLng) * cos(_toRad(lat2));
  final x =
      cos(_toRad(lat1)) * sin(_toRad(lat2)) -
      sin(_toRad(lat1)) * cos(_toRad(lat2)) * cos(dLng);
  final bearing = atan2(y, x);
  return (_toDeg(bearing) + 360) % 360;
}

double _toRad(double deg) => deg * pi / 180;
double _toDeg(double rad) => rad * 180 / pi;

Maneuver maneuverFromAngle(double angleDeg) {
  final a = ((angleDeg % 360) + 360) % 360;
  if (a <= 30 || a >= 330) return Maneuver.straight;
  if (a > 30 && a <= 60) return Maneuver.slightRight;
  if (a > 60 && a <= 150) return Maneuver.turnRight;
  if (a > 150 && a <= 210) return Maneuver.uTurn;
  if (a > 210 && a <= 300) return Maneuver.turnLeft;
  return Maneuver.slightLeft;
}

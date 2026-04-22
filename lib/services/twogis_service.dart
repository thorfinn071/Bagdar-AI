import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/nav_models.dart';

class TwoGisService {
  static const String _prefsKeyApi = 'vg_2gis_api_key';
  static const String _baseCatalog = 'https://catalog.api.2gis.com/3.0';
  static const String _baseRouting =
      'https://routing.api.2gis.com/routing/7.0.0/global';

  String? _apiKey;
  final http.Client _client = http.Client();

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString(_prefsKeyApi);
    debugPrint('TwoGisService: apiKey=${_apiKey != null ? "set" : "not set"}');
  }

  Future<bool> setApiKey(String key) async {
    if (key.trim().isEmpty) return false;
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyApi, _apiKey!);
    return true;
  }

  Future<List<Place>> searchPlaces(
    String query,
    double lat,
    double lng, {
    int radiusMeters = 2000,
    int limit = 5,
  }) async {
    if (!hasApiKey) return [];
    try {
      final uri = Uri.parse('$_baseCatalog/items').replace(
        queryParameters: {
          'q': query,
          'point': '$lng,$lat',
          'radius': '$radiusMeters',
          'sort_point': '$lng,$lat',
          'sort': 'distance',
          'page_size': '$limit',
          'key': _apiKey!,
          'fields': 'items.point,items.address_name,items.rubrics',
          'type': 'branch,building',
        },
      );

      
      
      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        debugPrint('TwoGisService.searchPlaces: HTTP ${resp.statusCode}');
        return [];
      }

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      if (result == null) return [];

      final items = result['items'] as List<dynamic>? ?? [];
      return _parsePlaces(items, lat, lng);
    } catch (e) {
      debugPrint('TwoGisService.searchPlaces error: $e');
      return [];
    }
  }

  Future<NavRoute?> getWalkRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String destinationName = '',
  }) async {
    if (!hasApiKey) return null;
    try {
      final reqBody = json.encode({
        'points': [
          {'type': 'walking', 'lat': fromLat, 'lon': fromLng},
          {'type': 'walking', 'lat': toLat, 'lon': toLng},
        ],
        'type': 'pedestrian',
        'locale': 'ru',
      });

      final uri = Uri.parse('$_baseRouting?key=$_apiKey');
      final resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: reqBody,
          )
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode != 200) {
        debugPrint('TwoGisService.getWalkRoute: HTTP ${resp.statusCode}');
        return null;
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      return _parseWalkRoute(data, destinationName);
    } catch (e) {
      debugPrint('TwoGisService.getWalkRoute error: $e');
      return null;
    }
  }

  Future<List<TransitStop>> getNearestStops(
    double lat,
    double lng, {
    int radiusMeters = 500,
    int limit = 5,
  }) async {
    if (!hasApiKey) return [];
    try {
      final uri = Uri.parse('$_baseCatalog/items').replace(
        queryParameters: {
          'q': 'остановка',
          'point': '$lng,$lat',
          'radius': '$radiusMeters',
          'sort_point': '$lng,$lat',
          'sort': 'distance',
          'page_size': '$limit',
          'key': _apiKey!,
          'type': 'station',
          'fields': 'items.point,items.routes',
        },
      );

      final resp = await _client.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];

      final body = json.decode(resp.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      if (result == null) return [];

      final items = result['items'] as List<dynamic>? ?? [];
      return _parseStops(items);
    } catch (e) {
      debugPrint('TwoGisService.getNearestStops error: $e');
      return [];
    }
  }

  Future<TransitRoute?> getTransitRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String destinationName = '',
  }) async {
    if (!hasApiKey) return null;
    try {
      final reqBody = json.encode({
        'points': [
          {'type': 'walking', 'lat': fromLat, 'lon': fromLng},
          {'type': 'walking', 'lat': toLat, 'lon': toLng},
        ],
        'type': 'jam_statistic_pedestrian_public_transport',
        'locale': 'ru',
      });

      final uri = Uri.parse('$_baseRouting?key=$_apiKey');
      final resp = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: reqBody,
          )
          .timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) {
        debugPrint('TwoGisService.getTransitRoute: HTTP ${resp.statusCode}');
        return null;
      }

      final data = json.decode(resp.body) as Map<String, dynamic>;
      return _parseTransitRoute(data, destinationName);
    } catch (e) {
      debugPrint('TwoGisService.getTransitRoute error: $e');
      return null;
    }
  }

  List<Place> _parsePlaces(List<dynamic> items, double refLat, double refLng) {
    final places = <Place>[];
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final point = m['point'] as Map<String, dynamic>?;
      if (point == null) continue;

      final pLat = (point['lat'] as num).toDouble();
      final pLng = (point['lon'] as num).toDouble();

      String category = '';
      final rubrics = m['rubrics'] as List<dynamic>?;
      if (rubrics != null && rubrics.isNotEmpty) {
        category =
            (rubrics[0] as Map<String, dynamic>)['name'] as String? ?? '';
      }

      places.add(
        Place(
          name: m['name'] as String? ?? '',
          lat: pLat,
          lng: pLng,
          address: m['address_name'] as String? ?? '',
          category: category,
          distanceMeters: _approxDist(refLat, refLng, pLat, pLng),
        ),
      );
    }
    return places;
  }

  List<TransitStop> _parseStops(List<dynamic> items) {
    final stops = <TransitStop>[];
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final point = m['point'] as Map<String, dynamic>?;
      if (point == null) continue;

      final routes = <String>[];
      final routeList = m['routes'] as List<dynamic>?;
      if (routeList != null) {
        for (final r in routeList) {
          final name = (r as Map<String, dynamic>)['name'] as String?;
          if (name != null) routes.add(name);
        }
      }

      stops.add(
        TransitStop(
          name: m['name'] as String? ?? '',
          lat: (point['lat'] as num).toDouble(),
          lng: (point['lon'] as num).toDouble(),
          routes: routes,
        ),
      );
    }
    return stops;
  }

  NavRoute? _parseWalkRoute(Map<String, dynamic> data, String destName) {
    try {
      final routes = data['result'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes[0] as Map<String, dynamic>;
      final totalDist = (route['total_distance'] as num?)?.toInt() ?? 0;
      final totalDur = (route['total_duration'] as num?)?.toInt() ?? 0;

      final legs = route['legs'] as List<dynamic>? ?? [];
      final steps = <RouteStep>[];

      for (final leg in legs) {
        final legMap = leg as Map<String, dynamic>;
        final legSteps = legMap['steps'] as List<dynamic>? ?? [];

        for (final s in legSteps) {
          final sm = s as Map<String, dynamic>;
          final step = _parseStep(sm);
          if (step != null) steps.add(step);
        }
      }

      if (steps.isEmpty) return null;

      return NavRoute(
        steps: steps,
        totalDistanceMeters: totalDist,
        totalDurationSeconds: totalDur,
        destinationName: destName,
      );
    } catch (e) {
      debugPrint('TwoGisService._parseWalkRoute error: $e');
      return null;
    }
  }

  TransitRoute? _parseTransitRoute(Map<String, dynamic> data, String destName) {
    try {
      final routes = data['result'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes[0] as Map<String, dynamic>;
      final totalDist = (route['total_distance'] as num?)?.toInt() ?? 0;
      final totalDur = (route['total_duration'] as num?)?.toInt() ?? 0;

      final rawLegs = route['legs'] as List<dynamic>? ?? [];
      final legs = <TransitLeg>[];

      for (final rl in rawLegs) {
        final lm = rl as Map<String, dynamic>;
        final leg = _parseTransitLeg(lm);
        if (leg != null) legs.add(leg);
      }

      if (legs.isEmpty) return null;

      return TransitRoute(
        legs: legs,
        totalDistanceMeters: totalDist,
        totalDurationSeconds: totalDur,
        destinationName: destName,
      );
    } catch (e) {
      debugPrint('TwoGisService._parseTransitRoute error: $e');
      return null;
    }
  }

  TransitLeg? _parseTransitLeg(Map<String, dynamic> lm) {
    final type = lm['type'] as String? ?? 'walking';
    final dist = (lm['distance'] as num?)?.toInt() ?? 0;
    final dur = (lm['duration'] as num?)?.toInt() ?? 0;

    if (type == 'walking' || type == 'pedestrian') {
      final rawSteps = lm['steps'] as List<dynamic>? ?? [];
      final walkSteps = <RouteStep>[];
      for (final s in rawSteps) {
        final step = _parseStep(s as Map<String, dynamic>);
        if (step != null) walkSteps.add(step);
      }
      return TransitLeg(
        type: TransitLegType.walk,
        walkSteps: walkSteps,
        distanceMeters: dist,
        durationSeconds: dur,
      );
    }

    final transport = lm['transport'] as Map<String, dynamic>?;
    TransitLegType legType = TransitLegType.bus;
    String? routeName;
    String? routeNumber;

    if (transport != null) {
      final tType = transport['type'] as String? ?? '';
      if (tType.contains('trolleybus')) {
        legType = TransitLegType.trolleybus;
      } else if (tType.contains('tram')) {
        legType = TransitLegType.tram;
      } else if (tType.contains('metro') || tType.contains('subway')) {
        legType = TransitLegType.metro;
      }
      routeName = transport['name'] as String?;
      routeNumber = transport['number'] as String?;
    }

    TransitStop? depStop;
    TransitStop? arrStop;
    final intermediates = <TransitStop>[];

    final platforms = lm['platforms'] as List<dynamic>?;
    if (platforms != null && platforms.isNotEmpty) {
      depStop = _stopFromPlatform(platforms.first as Map<String, dynamic>);
      if (platforms.length > 1) {
        arrStop = _stopFromPlatform(platforms.last as Map<String, dynamic>);
      }
      for (int i = 1; i < platforms.length - 1; i++) {
        final s = _stopFromPlatform(platforms[i] as Map<String, dynamic>);
        if (s != null) intermediates.add(s);
      }
    }

    final stops = lm['stops'] as List<dynamic>?;
    if (stops != null && depStop == null) {
      if (stops.isNotEmpty) {
        depStop = _stopFromMap(stops.first as Map<String, dynamic>);
      }
      if (stops.length > 1) {
        arrStop = _stopFromMap(stops.last as Map<String, dynamic>);
      }
      for (int i = 1; i < stops.length - 1; i++) {
        final s = _stopFromMap(stops[i] as Map<String, dynamic>);
        if (s != null) intermediates.add(s);
      }
    }

    return TransitLeg(
      type: legType,
      routeName: routeName,
      routeNumber: routeNumber,
      departureStop: depStop,
      arrivalStop: arrStop,
      intermediateStops: intermediates,
      distanceMeters: dist,
      durationSeconds: dur,
    );
  }

  TransitStop? _stopFromPlatform(Map<String, dynamic> p) {
    final point = p['point'] as Map<String, dynamic>?;
    if (point == null) return null;
    return TransitStop(
      name: p['name'] as String? ?? '',
      lat: (point['lat'] as num).toDouble(),
      lng: (point['lon'] as num).toDouble(),
    );
  }

  TransitStop? _stopFromMap(Map<String, dynamic> s) {
    final lat = (s['lat'] as num?)?.toDouble();
    final lng =
        (s['lon'] as num?)?.toDouble() ?? (s['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return TransitStop(name: s['name'] as String? ?? '', lat: lat, lng: lng);
  }

  RouteStep? _parseStep(Map<String, dynamic> sm) {
    final instr =
        sm['instruction'] as String? ?? sm['street_name'] as String? ?? '';
    final dist = (sm['distance'] as num?)?.toInt() ?? 0;
    final dur = (sm['duration'] as num?)?.toInt() ?? 0;

    final startPoint = sm['start_point'] as Map<String, dynamic>?;
    final endPoint = sm['end_point'] as Map<String, dynamic>?;

    final sLat = (startPoint?['lat'] as num?)?.toDouble() ?? 0;
    final sLng = (startPoint?['lon'] as num?)?.toDouble() ?? 0;
    final eLat = (endPoint?['lat'] as num?)?.toDouble() ?? 0;
    final eLng = (endPoint?['lon'] as num?)?.toDouble() ?? 0;

    final maneuverStr = sm['maneuver'] as String? ?? 'straight';
    final maneuver = _maneuverFromString(maneuverStr);

    return RouteStep(
      instruction: instr,
      distanceMeters: dist,
      durationSeconds: dur,
      startLat: sLat,
      startLng: sLng,
      endLat: eLat,
      endLng: eLng,
      maneuver: maneuver,
    );
  }

  Maneuver _maneuverFromString(String s) {
    final l = s.toLowerCase();
    if (l.contains('slight_left') || l.contains('немного лев')) {
      return Maneuver.slightLeft;
    }
    if (l.contains('slight_right') || l.contains('немного прав')) {
      return Maneuver.slightRight;
    }
    if (l.contains('left') || l.contains('лев')) return Maneuver.turnLeft;
    if (l.contains('right') || l.contains('прав')) return Maneuver.turnRight;
    if (l.contains('uturn') || l.contains('разворот')) return Maneuver.uTurn;
    if (l.contains('arrive') || l.contains('прибы')) return Maneuver.arrive;
    return Maneuver.straight;
  }

  int _approxDist(double lat1, double lng1, double lat2, double lng2) {
    const mPerDegLat = 111320.0;
    final dLat = (lat2 - lat1) * mPerDegLat;
    final dLng = (lng2 - lng1) * mPerDegLat * 0.7;
    return sqrt(dLat * dLat + dLng * dLng).round();
  }

  void dispose() {
    _client.close();
  }
}

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/strings.dart';

class GtfsRoute {
  final String routeId;
  final String routeNumber;
  final String routeName;
  final String routeType;
  final String startTime;
  final String endTime;
  final int intervalMinutes;

  const GtfsRoute({
    required this.routeId,
    required this.routeNumber,
    this.routeName = '',
    this.routeType = 'bus',
    this.startTime = '',
    this.endTime = '',
    this.intervalMinutes = 0,
  });
}

class GtfsStop {
  final String stopId;
  final String name;
  final String nameKk;
  final double lat;
  final double lng;
  final List<String> routeNumbers;

  const GtfsStop({
    required this.stopId,
    required this.name,
    this.nameKk = '',
    required this.lat,
    required this.lng,
    this.routeNumbers = const [],
  });

  double distanceTo(double otherLat, double otherLng) {
    const R = 6371000.0;
    final dLat = (otherLat - lat) * pi / 180;
    final dLng = (otherLng - lng) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat * pi / 180) *
            cos(otherLat * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }
}

class GtfsStopTime {
  final String stopName;
  final String arrivalTime;
  final String departureTime;
  final int stopSequence;

  const GtfsStopTime({
    required this.stopName,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopSequence,
  });
}

class GtfsTransitPlan {
  final GtfsStop departureStop;
  final GtfsStop arrivalStop;
  final List<GtfsStop> intermediateStops;
  final String routeNumber;
  final String routeName;

  const GtfsTransitPlan({
    required this.departureStop,
    required this.arrivalStop,
    required this.intermediateStops,
    required this.routeNumber,
    required this.routeName,
  });
}

class GtfsService {
  Database? _db;
  DateTime? _dbUpdatedAt;

  static const Duration _staleAfter = Duration(days: 90);

  bool get isReady => _db != null;
  DateTime? get updatedAt => _dbUpdatedAt;
  bool get isStale => isTimestampStale(_dbUpdatedAt);

  static bool isTimestampStale(DateTime? timestamp, [DateTime? now]) {
    if (timestamp == null) return false;
    final reference = now ?? DateTime.now();
    return reference.difference(timestamp) > _staleAfter;
  }

  static const double _metersPerDegreeLat = 111320.0;

  Future<void> init(String dbPath) async {
    final file = File(dbPath);
    if (!await file.exists()) {
      throw FileSystemException('GTFS database not found', dbPath);
    }
    _db = await openDatabase(dbPath, readOnly: true);
    _dbUpdatedAt = await file.lastModified();
    debugPrint('GtfsService: opened $dbPath');
  }

  Future<List<GtfsRoute>> getRoutesForStop(String stopName) async {
    if (_db == null) return [];
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT DISTINCT r.route_id, r.route_number, r.route_name, r.route_type,
               r.start_time, r.end_time, r.interval_minutes
        FROM routes r
        JOIN stop_routes sr ON sr.route_id = r.route_id
        JOIN stops s ON s.stop_id = sr.stop_id
        WHERE s.name LIKE ? OR s.name_kk LIKE ?
        ORDER BY r.route_number
      ''',
        ['%$stopName%', '%$stopName%'],
      );

      return rows
          .map(
            (r) => GtfsRoute(
              routeId: r['route_id'] as String? ?? '',
              routeNumber: r['route_number'] as String? ?? '',
              routeName: r['route_name'] as String? ?? '',
              routeType: r['route_type'] as String? ?? 'bus',
              startTime: r['start_time'] as String? ?? '',
              endTime: r['end_time'] as String? ?? '',
              intervalMinutes: r['interval_minutes'] as int? ?? 0,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('GtfsService.getRoutesForStop error: $e');
      return [];
    }
  }

  Future<GtfsRoute?> getRoute(String routeNumber) async {
    if (_db == null) return null;
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT route_id, route_number, route_name, route_type,
               start_time, end_time, interval_minutes
        FROM routes
        WHERE route_number = ?
        LIMIT 1
      ''',
        [routeNumber],
      );

      if (rows.isEmpty) return null;
      final r = rows.first;
      return GtfsRoute(
        routeId: r['route_id'] as String? ?? '',
        routeNumber: r['route_number'] as String? ?? '',
        routeName: r['route_name'] as String? ?? '',
        routeType: r['route_type'] as String? ?? 'bus',
        startTime: r['start_time'] as String? ?? '',
        endTime: r['end_time'] as String? ?? '',
        intervalMinutes: r['interval_minutes'] as int? ?? 0,
      );
    } catch (e) {
      debugPrint('GtfsService.getRoute error: $e');
      return null;
    }
  }

  Future<List<GtfsStopTime>> getStopsForRoute(String routeNumber) async {
    if (_db == null) return [];
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT s.name AS stop_name, st.arrival_time, st.departure_time, st.stop_sequence
        FROM stop_times st
        JOIN stops s ON s.stop_id = st.stop_id
        JOIN trips t ON t.trip_id = st.trip_id
        JOIN routes r ON r.route_id = t.route_id
        WHERE r.route_number = ?
        GROUP BY st.stop_sequence
        ORDER BY st.stop_sequence
      ''',
        [routeNumber],
      );

      return rows
          .map(
            (r) => GtfsStopTime(
              stopName: r['stop_name'] as String? ?? '',
              arrivalTime: r['arrival_time'] as String? ?? '',
              departureTime: r['departure_time'] as String? ?? '',
              stopSequence: r['stop_sequence'] as int? ?? 0,
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('GtfsService.getStopsForRoute error: $e');
      return [];
    }
  }

  Future<List<GtfsStop>> getNearestStops(
    double lat,
    double lng, {
    int radiusMeters = 500,
    int limit = 5,
  }) async {
    if (_db == null) return [];

    final dLat = radiusMeters / _metersPerDegreeLat;
    final dLng =
        radiusMeters /
        (_metersPerDegreeLat * cos(lat * pi / 180)).abs().clamp(
          0.0001,
          double.infinity,
        );

    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT s.stop_id, s.name, s.name_kk, s.lat, s.lng,
               GROUP_CONCAT(DISTINCT r.route_number) AS route_numbers
        FROM stops s
        LEFT JOIN stop_routes sr ON sr.stop_id = s.stop_id
        LEFT JOIN routes r ON r.route_id = sr.route_id
        WHERE s.lat BETWEEN ? AND ?
          AND s.lng BETWEEN ? AND ?
        GROUP BY s.stop_id
      ''',
        [lat - dLat, lat + dLat, lng - dLng, lng + dLng],
      );

      final stops = <_ScoredGtfsStop>[];
      for (final row in rows) {
        final sLat = (row['lat'] as num).toDouble();
        final sLng = (row['lng'] as num).toDouble();
        final dist = _haversine(lat, lng, sLat, sLng);

        if (dist <= radiusMeters) {
          final routeStr = row['route_numbers'] as String? ?? '';
          stops.add(
            _ScoredGtfsStop(
              stop: GtfsStop(
                stopId: row['stop_id'] as String? ?? '',
                name: row['name'] as String? ?? '',
                nameKk: row['name_kk'] as String? ?? '',
                lat: sLat,
                lng: sLng,
                routeNumbers: routeStr.isEmpty ? [] : routeStr.split(','),
              ),
              distance: dist,
            ),
          );
        }
      }

      stops.sort((a, b) => a.distance.compareTo(b.distance));
      return stops.take(limit).map((e) => e.stop).toList();
    } catch (e) {
      debugPrint('GtfsService.getNearestStops error: $e');
      return [];
    }
  }

  Future<GtfsTransitPlan?> findDirectTransitPlan({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    int walkRadiusMeters = 600,
  }) async {
    if (_db == null) return null;
    final originStops = await getNearestStops(
      fromLat,
      fromLng,
      radiusMeters: walkRadiusMeters,
      limit: 5,
    );
    final destStops = await getNearestStops(
      toLat,
      toLng,
      radiusMeters: walkRadiusMeters,
      limit: 5,
    );
    if (originStops.isEmpty || destStops.isEmpty) return null;

    for (final oStop in originStops) {
      for (final dStop in destStops) {
        final result = await _findRouteBetween(oStop.stopId, dStop.stopId);
        if (result != null) {
          final routeInfo = await getRoute(result.$1);
          return GtfsTransitPlan(
            departureStop: oStop,
            arrivalStop: dStop,
            intermediateStops: result.$2,
            routeNumber: routeInfo?.routeNumber ?? '',
            routeName: routeInfo?.routeName ?? '',
          );
        }
      }
    }
    return null;
  }

  Future<(String routeId, List<GtfsStop>)?> _findRouteBetween(
    String originStopId,
    String destStopId,
  ) async {
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT st1.trip_id, st1.stop_sequence AS orig_seq,
               st2.stop_sequence AS dest_seq, t.route_id
        FROM stop_times st1
        JOIN stop_times st2 ON st2.trip_id = st1.trip_id
        JOIN trips t ON t.trip_id = st1.trip_id
        WHERE st1.stop_id = ? AND st2.stop_id = ?
          AND st1.stop_sequence < st2.stop_sequence
        LIMIT 1
      ''',
        [originStopId, destStopId],
      );

      if (rows.isEmpty) return null;
      final tripId = rows.first['trip_id'] as String;
      final origSeq = rows.first['orig_seq'] as int;
      final destSeq = rows.first['dest_seq'] as int;
      final routeId = rows.first['route_id'] as String;
      final intermediate = await _getStopsBetween(
        tripId,
        origSeq + 1,
        destSeq - 1,
      );
      return (routeId, intermediate);
    } catch (e) {
      debugPrint('GtfsService._findRouteBetween error: $e');
      return null;
    }
  }

  Future<List<GtfsStop>> _getStopsBetween(
    String tripId,
    int fromSeq,
    int toSeq,
  ) async {
    if (fromSeq > toSeq) return [];
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT s.stop_id, s.name, s.name_kk, s.lat, s.lng
        FROM stop_times st
        JOIN stops s ON s.stop_id = st.stop_id
        WHERE st.trip_id = ?
          AND st.stop_sequence >= ? AND st.stop_sequence <= ?
        ORDER BY st.stop_sequence
      ''',
        [tripId, fromSeq, toSeq],
      );

      return rows
          .map(
            (r) => GtfsStop(
              stopId: r['stop_id'] as String? ?? '',
              name: r['name'] as String? ?? '',
              nameKk: r['name_kk'] as String? ?? '',
              lat: (r['lat'] as num).toDouble(),
              lng: (r['lng'] as num).toDouble(),
            ),
          )
          .toList();
    } catch (e) {
      debugPrint('GtfsService._getStopsBetween error: $e');
      return [];
    }
  }

  Future<int?> getNextDepartureMinutes(String routeNumber) async {
    final route = await getRoute(routeNumber);
    if (route == null || route.intervalMinutes <= 0) return null;

    final now = DateTime.now();
    final currentMin = now.hour * 60 + now.minute;

    if (route.startTime.isNotEmpty && route.endTime.isNotEmpty) {
      final start = _parseTimeMin(route.startTime);
      final end = _parseTimeMin(route.endTime);
      if (start != null && end != null) {
        final running = end < start
            ? (currentMin >= start || currentMin <= end)
            : (currentMin >= start && currentMin <= end);
        if (!running) return null;
      }
    }

    final elapsed = currentMin % route.intervalMinutes;
    return route.intervalMinutes - elapsed;
  }

  static int? _parseTimeMin(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  Future<String> getScheduleSummary(String routeNumber) async {
    final route = await getRoute(routeNumber);
    if (route == null) return '';

    final stops = await getStopsForRoute(routeNumber);
    final stopCount = stops.length;

    final parts = <String>[];
    parts.add(
      '${route.routeName.isNotEmpty ? route.routeName : S.get('gtfs_route_info')} ${route.routeNumber}',
    );

    if (route.startTime.isNotEmpty && route.endTime.isNotEmpty) {
      parts.add(
        '${S.get('gtfs_working_hours')}: ${route.startTime} — ${route.endTime}',
      );
    }

    if (route.intervalMinutes > 0) {
      parts.add(
        '${S.get('gtfs_interval')}: ${route.intervalMinutes} ${S.get('gtfs_minutes')}',
      );
    }

    if (stopCount > 0) {
      parts.add('${S.get('gtfs_stops_count')}: $stopCount');
      if (stops.length >= 2) {
        parts.add('${S.get('gtfs_from')}: ${stops.first.stopName}');
        parts.add('${S.get('gtfs_to')}: ${stops.last.stopName}');
      }
    }

    return parts.join('. ');
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  void dispose() {
    _db?.close();
    _db = null;
  }
}

class _ScoredGtfsStop {
  final GtfsStop stop;
  final double distance;
  const _ScoredGtfsStop({required this.stop, required this.distance});
}

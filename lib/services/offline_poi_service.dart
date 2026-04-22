import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/nav_models.dart';

class OfflinePoiService {
  Database? _db;

  bool get isReady => _db != null;

  static const double _metersPerDegreeLat = 111320.0;

  Future<void> init(String dbPath) async {
    _db = await openDatabase(dbPath, readOnly: true);
    debugPrint('OfflinePoiService: opened $dbPath');
  }

  Future<List<Place>> searchPlaces(
    String query,
    double lat,
    double lng, {
    int radiusMeters = 2000,
    int limit = 10,
  }) async {
    if (_db == null || query.trim().isEmpty) return [];

    final dLat = radiusMeters / _metersPerDegreeLat;
    final dLng =
        radiusMeters /
        (_metersPerDegreeLat * cos(lat * pi / 180)).abs().clamp(
          0.0001,
          double.infinity,
        );

    final minLat = lat - dLat;
    final maxLat = lat + dLat;
    final minLng = lng - dLng;
    final maxLng = lng + dLng;

    final ftsQuery = _buildFtsQuery(query);

    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT p.id, p.name, p.name_kk, p.lat, p.lng, p.address, p.category
        FROM poi p
        JOIN poi_fts f ON f.rowid = p.id
        WHERE p.lat BETWEEN ? AND ?
          AND p.lng BETWEEN ? AND ?
          AND poi_fts MATCH ?
        LIMIT ?
      ''',
        [minLat, maxLat, minLng, maxLng, ftsQuery, limit * 3],
      );

      var places = <_ScoredPlace>[];
      for (final row in rows) {
        final pLat = (row['lat'] as num).toDouble();
        final pLng = (row['lng'] as num).toDouble();
        final dist = _haversine(lat, lng, pLat, pLng);

        if (dist <= radiusMeters) {
          places.add(
            _ScoredPlace(
              place: Place(
                name: row['name'] as String? ?? '',
                lat: pLat,
                lng: pLng,
                address: row['address'] as String? ?? '',
                category: row['category'] as String? ?? '',
                distanceMeters: dist.round(),
              ),
              distance: dist,
            ),
          );
        }
      }

      if (places.isEmpty) {
        places = await _searchByLike(
          query,
          minLat,
          maxLat,
          minLng,
          maxLng,
          lat,
          lng,
          radiusMeters,
          limit,
        );
      }

      places.sort((a, b) => a.distance.compareTo(b.distance));
      return places.take(limit).map((e) => e.place).toList();
    } catch (e) {
      debugPrint('OfflinePoiService.searchPlaces error: $e');
      return [];
    }
  }

  Future<List<_ScoredPlace>> _searchByLike(
    String query,
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
    double refLat,
    double refLng,
    int radiusMeters,
    int limit,
  ) async {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];
    final like = '%$q%';
    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT p.id, p.name, p.name_kk, p.lat, p.lng, p.address, p.category
        FROM poi p
        WHERE p.lat BETWEEN ? AND ?
          AND p.lng BETWEEN ? AND ?
          AND (LOWER(p.name) LIKE ?
            OR LOWER(p.name_kk) LIKE ?
            OR LOWER(p.category) LIKE ?)
        LIMIT ?
      ''',
        [minLat, maxLat, minLng, maxLng, like, like, like, limit * 5],
      );

      final places = <_ScoredPlace>[];
      for (final row in rows) {
        final pLat = (row['lat'] as num).toDouble();
        final pLng = (row['lng'] as num).toDouble();
        final dist = _haversine(refLat, refLng, pLat, pLng);
        if (dist <= radiusMeters) {
          places.add(
            _ScoredPlace(
              place: Place(
                name: row['name'] as String? ?? '',
                lat: pLat,
                lng: pLng,
                address: row['address'] as String? ?? '',
                category: row['category'] as String? ?? '',
                distanceMeters: dist.round(),
              ),
              distance: dist,
            ),
          );
        }
      }

      final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      places.sort((a, b) {
        final aLev = _minWordLevenshtein(words, a.place.name.toLowerCase());
        final bLev = _minWordLevenshtein(words, b.place.name.toLowerCase());
        if (aLev != bLev) return aLev.compareTo(bLev);
        return a.distance.compareTo(b.distance);
      });
      return places;
    } catch (e) {
      debugPrint('OfflinePoiService._searchByLike error: $e');
      return [];
    }
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    final dp = List<int>.generate(n + 1, (i) => i);
    for (int i = 1; i <= m; i++) {
      int prev = dp[0];
      dp[0] = i;
      for (int j = 1; j <= n; j++) {
        final tmp = dp[j];
        dp[j] = a[i - 1] == b[j - 1]
            ? prev
            : 1 + [prev, dp[j], dp[j - 1]].reduce((x, y) => x < y ? x : y);
        prev = tmp;
      }
    }
    return dp[n];
  }

  static int _minWordLevenshtein(List<String> words, String target) {
    if (words.isEmpty) return target.length;
    int best = words
        .map((w) => _levenshtein(w, target))
        .reduce((a, b) => a < b ? a : b);
    final full = _levenshtein(words.join(' '), target);
    return best < full ? best : full;
  }

  Future<List<TransitStop>> getNearestStops(
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

    final minLat = lat - dLat;
    final maxLat = lat + dLat;
    final minLng = lng - dLng;
    final maxLng = lng + dLng;

    try {
      final rows = await _db!.rawQuery(
        '''
        SELECT s.id, s.name, s.name_kk, s.lat, s.lng, s.routes
        FROM transit_stops s
        WHERE s.lat BETWEEN ? AND ?
          AND s.lng BETWEEN ? AND ?
        LIMIT ?
      ''',
        [minLat, maxLat, minLng, maxLng, limit * 3],
      );

      final stops = <_ScoredStop>[];
      for (final row in rows) {
        final sLat = (row['lat'] as num).toDouble();
        final sLng = (row['lng'] as num).toDouble();
        final dist = _haversine(lat, lng, sLat, sLng);

        if (dist <= radiusMeters) {
          final routesStr = row['routes'] as String? ?? '';
          final routes = routesStr.isEmpty ? <String>[] : routesStr.split(',');

          stops.add(
            _ScoredStop(
              stop: TransitStop(
                name: row['name'] as String? ?? '',
                lat: sLat,
                lng: sLng,
                routes: routes,
              ),
              distance: dist,
            ),
          );
        }
      }

      stops.sort((a, b) => a.distance.compareTo(b.distance));
      return stops.take(limit).map((e) => e.stop).toList();
    } catch (e) {
      debugPrint('OfflinePoiService.getNearestStops error: $e');
      return [];
    }
  }

  String _buildFtsQuery(String raw) {
    final words = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\sа-яёәіңғүұқөһА-ЯЁӘІҢҒҮҰҚӨҺ]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toList();

    if (words.isEmpty) return raw;
    return words.map((w) => '$w*').join(' ');
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

class _ScoredPlace {
  final Place place;
  final double distance;
  const _ScoredPlace({required this.place, required this.distance});
}

class _ScoredStop {
  final TransitStop stop;
  final double distance;
  const _ScoredStop({required this.stop, required this.distance});
}

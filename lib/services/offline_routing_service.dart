import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/nav_models.dart';
import 'ch_router.dart';
import 'offline_poi_service.dart';

abstract class RoutingProvider {
  Future<void> init(String mapDataPath);
  Future<NavRoute?> getWalkRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String destinationName,
  });
  Future<List<Place>> searchPlaces(
    String query,
    double lat,
    double lng, {
    int radiusMeters,
  });
  Future<List<TransitStop>> getNearestStops(
    double lat,
    double lng, {
    int radiusMeters,
  });
  bool get isReady;
  void dispose();
}

class OfflineRoutingService implements RoutingProvider {
  CHRouter? _router;
  OfflinePoiService? _poi;

  @override
  bool get isReady => _router != null && _router!.isReady;

  bool get poiReady => _poi != null;

  @override
  Future<void> init(String mapDataPath) async {
    try {
      _router = CHRouter();
      await _router!.loadGraph('$mapDataPath/graph.bin');
      debugPrint('OfflineRoutingService: graph loaded');
    } catch (e) {
      debugPrint('OfflineRoutingService: graph load failed: $e');
      _router = null;
    }

    try {
      _poi = OfflinePoiService();
      await _poi!.init('$mapDataPath/poi.db');
      debugPrint('OfflineRoutingService: POI db loaded');
    } catch (e) {
      debugPrint('OfflineRoutingService: POI db load failed: $e');
      _poi = null;
    }
  }

  @override
  Future<NavRoute?> getWalkRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng, {
    String destinationName = '',
  }) async {
    if (_router == null || !_router!.isReady) return null;
    return _router!.findRoute(
      fromLat,
      fromLng,
      toLat,
      toLng,
      destinationName: destinationName,
    );
  }

  @override
  Future<List<Place>> searchPlaces(
    String query,
    double lat,
    double lng, {
    int radiusMeters = 2000,
  }) async {
    if (_poi == null) return [];
    return _poi!.searchPlaces(query, lat, lng, radiusMeters: radiusMeters);
  }

  @override
  Future<List<TransitStop>> getNearestStops(
    double lat,
    double lng, {
    int radiusMeters = 500,
  }) async {
    if (_poi == null) return [];
    return _poi!.getNearestStops(lat, lng, radiusMeters: radiusMeters);
  }

  @override
  void dispose() {
    _router?.dispose();
    _poi?.dispose();
    _router = null;
    _poi = null;
  }
}

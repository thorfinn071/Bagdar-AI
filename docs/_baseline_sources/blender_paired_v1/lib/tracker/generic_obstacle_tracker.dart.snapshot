import 'dart:math' as math;
import 'dart:ui';

import '../models/depth_frame.dart';
import '../models/generic_obstacle.dart';
import '../utils/depth_hazard.dart';

class GenericObstacleTrack {
  final int id;
  GenericObstacleObservation last;
  int hits;
  int misses;
  int age;
  final List<double> proximityHist;
  final List<double?> metricHist;
  final List<int> timestampUsHist;
  final List<bool> hitWindow;
  bool confirmed;

  GenericObstacleTrack({
    required this.id,
    required this.last,
    required this.hits,
    required this.misses,
    required this.age,
    required this.proximityHist,
    required this.metricHist,
    required this.timestampUsHist,
    required this.confirmed,
    List<bool>? hitWindow,
  }) : hitWindow = hitWindow ?? <bool>[true];

  double get meanProximity {
    if (proximityHist.isEmpty) return last.relativeProximity;
    var s = 0.0;
    for (final v in proximityHist) {
      s += v;
    }
    return s / proximityHist.length;
  }

  /// Positive = approaching (proximity increasing / range decreasing).
  double approachTrend() {
    if (proximityHist.length < 2) return 0;
    return proximityHist.last - proximityHist.first;
  }

  double? metricVelocityMps() {
    if (metricHist.length < 2 || timestampUsHist.length < 2) return null;
    final a = metricHist.first;
    final b = metricHist.last;
    if (a == null || b == null) return null;
    final dt = (timestampUsHist.last - timestampUsHist.first) / 1e6;
    if (dt < 1e-3) return null;
    return (a - b) / dt; // positive = closing
  }
}

/// Associates geometric components across frames. IDs are stable so alert
/// cooldown can key a hazard, not only a global category.
class GenericObstacleTracker {
  GenericObstacleTracker({GenericObstacleConfig? config})
    : config = config ?? GenericObstacleConfig.engineeringDefaults;

  final GenericObstacleConfig config;
  final List<GenericObstacleTrack> _tracks = <GenericObstacleTrack>[];
  int _nextId = 1;

  List<GenericObstacleTrack> get tracks =>
      List<GenericObstacleTrack>.unmodifiable(_tracks);

  void reset() {
    _tracks.clear();
    _nextId = 1;
  }

  List<GenericObstacleTrack> update({
    required List<GenericObstacleObservation> observations,
    required int timestampUs,
    required bool relative,
  }) {
    final used = List<bool>.filled(observations.length, false);
    final matched = <int>{};

    for (final track in _tracks) {
      var best = -1;
      var bestScore = 0.0;
      for (int i = 0; i < observations.length; i++) {
        if (used[i]) continue;
        final s = _score(track.last, observations[i]);
        if (s > bestScore) {
          bestScore = s;
          best = i;
        }
      }
      if (best >= 0 && bestScore >= 0.25) {
        used[best] = true;
        matched.add(track.id);
        _observe(track, observations[best], timestampUs, relative);
      } else {
        track.misses++;
        track.age++;
        _recordWindowHit(track, false, relative);
      }
    }

    _tracks.removeWhere((t) => t.misses >= config.expireMissedFrames);

    for (int i = 0; i < observations.length; i++) {
      if (used[i]) continue;
      final obs = observations[i];
      final id = _nextId++;
      final track = GenericObstacleTrack(
        id: id,
        last: obs.copyWith(trackId: id),
        hits: 1,
        misses: 0,
        age: 1,
        proximityHist: <double>[obs.relativeProximity],
        metricHist: <double?>[obs.nearestDistanceM],
        timestampUsHist: <int>[timestampUs],
        confirmed: false,
        hitWindow: <bool>[true],
      );
      _maybeConfirm(track, relative);
      _tracks.add(track);
    }

    return tracks;
  }

  void _observe(
    GenericObstacleTrack track,
    GenericObstacleObservation obs,
    int timestampUs,
    bool relative,
  ) {
    track.last = obs.copyWith(trackId: track.id);
    track.hits++;
    track.misses = 0;
    track.age++;
    track.proximityHist.add(obs.relativeProximity);
    track.metricHist.add(obs.nearestDistanceM);
    track.timestampUsHist.add(timestampUs);
    _recordWindowHit(track, true, relative);
    final cap = relative
        ? config.confirmWindowRelative
        : config.confirmWindowMetric;
    while (track.proximityHist.length > cap) {
      track.proximityHist.removeAt(0);
      track.metricHist.removeAt(0);
      track.timestampUsHist.removeAt(0);
    }
    _maybeConfirm(track, relative);
  }

  void _maybeConfirm(GenericObstacleTrack track, bool relative) {
    final need = relative
        ? config.confirmNeedRelative
        : config.confirmNeedMetric;
    final recentHits = track.hitWindow.where((hit) => hit).length;
    if (track.hitWindow.isNotEmpty &&
        track.hitWindow.last &&
        recentHits >= need) {
      track.confirmed = true;
    }
  }

  void _recordWindowHit(GenericObstacleTrack track, bool hit, bool relative) {
    final cap = relative
        ? config.confirmWindowRelative
        : config.confirmWindowMetric;
    track.hitWindow.add(hit);
    while (track.hitWindow.length > cap) {
      track.hitWindow.removeAt(0);
    }
  }

  double _score(GenericObstacleObservation a, GenericObstacleObservation b) {
    final iou = _iou(a.normalizedBounds, b.normalizedBounds);
    final dx = a.normalizedBounds.center.dx - b.normalizedBounds.center.dx;
    final dy = a.normalizedBounds.center.dy - b.normalizedBounds.center.dy;
    final centroidDistance = math.sqrt(dx * dx + dy * dy);
    if (iou < config.trackMinIou &&
        centroidDistance > config.trackMaxCentroidDistance) {
      return 0.0;
    }
    final prox = 1.0 - (a.relativeProximity - b.relativeProximity).abs();
    final zoneBonus = a.zone == b.zone
        ? 0.15
        : _adjacent(a.zone, b.zone)
        ? 0.05
        : 0.0;
    final geomBonus = a.geometry == b.geometry ? 0.1 : 0.0;
    return (0.55 * iou + 0.20 * prox.clamp(0.0, 1.0) + zoneBonus + geomBonus)
        .clamp(0.0, 1.0);
  }

  bool _adjacent(HazardZone a, HazardZone b) => (a.index - b.index).abs() == 1;

  double _iou(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.isEmpty) return 0;
    final inter = i.width * i.height;
    final union = a.width * a.height + b.width * b.height - inter;
    if (union <= 1e-9) return 0;
    return (inter / union).clamp(0.0, 1.0);
  }
}

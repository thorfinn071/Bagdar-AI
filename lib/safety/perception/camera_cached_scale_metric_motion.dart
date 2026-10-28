import 'dart:math' as math;
import 'dart:typed_data';
import 'camera_metric_motion.dart';
import 'observation_header.dart';
import 'passage_clearance.dart';

/// Experimental local photometric correspondence, bounded by visible metric
/// depth and calibrated pose. Unknown matches are never zero velocity/free space.
/// Does not mutate the relative tracker, planner or their historical risks.
class CameraCachedScaleMetricMotionSource {
  // Per-observation caches are bounded to the two immutable input frames.
  // No computed evidence or identity survives invalidation or a new pair.
  final _axes = <CameraMetricMotionInput, _AxisCache>{};
  final _boundsByFrame = <CameraMetricMotionInput, Map<int, _Bounds?>>{};

  final PassageCalibration calibration;
  final String relativeModelHash;
  final bool enableScaleMatching;
  CameraMetricMotionInput? _previous;
  static const patchRadius = 2, searchRadius = 32, maximumFeatures = 48;
  static const minimumMotionMps = .20;

  CameraCachedScaleMetricMotionSource({
    required this.calibration,
    required this.relativeModelHash,
    this.enableScaleMatching = true,
  });

  void invalidate() {
    _previous = null;
    _axes.clear();
    _boundsByFrame.clear();
  }

  CameraMetricMotionResult observe(
    CameraMetricMotionInput input, {
    required int nowUs,
  }) {
    _axes.clear();
    _boundsByFrame.clear();
    final f = input.camera.depth;
    CameraMetricMotionResult result(
      String reason, {
      int candidates = 0,
      int unknown = 0,
      List<MetricPatchMotion> patches = const [],
      int? oldest,
    }) => CameraMetricMotionResult(
      reason: reason,
      sessionGeneration: f.sessionGeneration,
      frameId: f.frameId,
      capturedAtUs: f.capturedAtUs,
      oldestEvidenceTimestampUs: oldest ?? f.capturedAtUs,
      validUntilUs: math.min(
        f.capturedAtUs + 100000,
        (oldest ?? f.capturedAtUs) + 400000,
      ),
      transformId: f.transformId,
      candidates: candidates,
      unknownPatches: unknown,
      patches: patches,
    );
    if (!_valid(input, nowUs)) {
      invalidate();
      return result('invalid_identity_projection_pose_depth_or_age');
    }
    final previous = _previous;
    _previous = input;
    if (previous == null) return result('new_pair_required');
    final p = previous.camera.depth;
    final dtUs = f.capturedAtUs - p.capturedAtUs;
    if (!_sameSession(previous, input) ||
        f.frameId <= p.frameId ||
        dtUs < 50000 ||
        dtUs > 300000) {
      // The current valid frame may start a new pair; no old authority survives.
      return result('incompatible_pair_or_interval');
    }
    final features = _features(previous), patches = <MetricPatchMotion>[];
    var unknown = 0;
    final destinations = <int>{};
    final duplicateDestinations = <int>{};
    for (final xy in features) {
      final a = _bounds(previous, xy[0], xy[1]);
      if (a == null) {
        unknown++;
        continue;
      }
      final projected = _project(input, a.center);
      if (projected == null) {
        unknown++;
        continue;
      }
      final match = _match(previous, xy, input, projected);
      if (match == null) {
        unknown++;
        continue;
      }
      final b = _bounds(input, match[0], match[1]);
      if (b == null) {
        unknown++;
        continue;
      }
      final backProjected = _project(previous, b.center);
      if (backProjected == null) {
        unknown++;
        continue;
      }
      final reverse = _match(input, match, previous, backProjected);
      if (reverse == null ||
          (reverse[0] - xy[0]).abs() > 1 ||
          (reverse[1] - xy[1]).abs() > 1) {
        unknown++;
        continue;
      }
      final dt = dtUs / 1e6;
      final lower = List.generate(3, (j) => (b.lower[j] - a.upper[j]) / dt);
      final upper = List.generate(3, (j) => (b.upper[j] - a.lower[j]) / dt);
      // Unbounded speed can indicate a wrong patch, depth or pose correspondence.
      if (List.generate(
        3,
        (j) => math.max(lower[j].abs(), upper[j].abs()),
      ).any((v) => v > 5)) {
        unknown++;
        continue;
      }
      final classification = upper[1] < -minimumMotionMps
          ? VisiblePatchMotion.approaching
          : lower[1] > minimumMotionMps
          ? VisiblePatchMotion.receding
          : upper[0] < -minimumMotionMps || lower[0] > minimumMotionMps
          ? VisiblePatchMotion.lateral
          : List.generate(
              3,
              (j) =>
                  lower[j] >= -minimumMotionMps && upper[j] <= minimumMotionMps,
            ).every((x) => x)
          ? VisiblePatchMotion.consistentWithStationary
          : VisiblePatchMotion.uncertain;
      final key = match[1] * f.width + match[0];
      if (!destinations.add(key)) duplicateDestinations.add(key);
      patches.add(
        MetricPatchMotion(
          previousPixel: List.unmodifiable(xy),
          currentPixel: List.unmodifiable(match),
          positionLowerM: List.unmodifiable(b.lower),
          positionUpperM: List.unmodifiable(b.upper),
          velocityLowerMps: List.unmodifiable(lower),
          velocityUpperMps: List.unmodifiable(upper),
          classification: classification,
          possibleBodyIntersection: _intersects(b, lower, upper),
        ),
      );
    }
    patches.removeWhere((v) {
      final duplicate = duplicateDestinations.contains(
        v.currentPixel[1] * f.width + v.currentPixel[0],
      );
      if (duplicate) unknown++;
      return duplicate;
    });
    return result(
      patches.isEmpty
          ? 'no_unambiguous_visible_metric_matches'
          : 'visible_patch_intervals',
      candidates: features.length,
      unknown: unknown,
      patches: patches,
      oldest: p.capturedAtUs,
    );
  }

  bool _valid(CameraMetricMotionInput i, int nowUs) {
    final c = i.camera, f = c.depth, h = c.rgbHeader, g = c.imageGeometry;
    bool same(List<double> a, List<double> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (j) => a[j].isFinite && b[j].isFinite && (a[j] - b[j]).abs() < 1e-6,
        ).every((v) => v);
    return f.structurallyValid &&
        calibration.metricScaleValidated &&
        calibration.alignmentValidated &&
        calibration.floorReferenceValidated &&
        calibration.timestampDomain ==
            PassageTimestampDomain.utcEpochMicroseconds &&
        h.health == ObservationHealth.healthy &&
        h.modelId == 'midas-small-ncnn' &&
        h.modelHash == relativeModelHash &&
        relativeModelHash.isNotEmpty &&
        h.preprocessId == 'rgb01-chw-256-nearest-stretch-no-crop-v1' &&
        h.frameId == f.frameId &&
        h.sessionGeneration == f.sessionGeneration &&
        h.sourceTimestampUs == f.capturedAtUs &&
        h.transformId == f.transformId &&
        f.transformId == calibration.transformId &&
        f.modelHash == calibration.modelHash &&
        f.referenceFrameId == calibration.referenceFrameId &&
        h.producedAtUs >= f.capturedAtUs &&
        h.producedAtUs <= nowUs &&
        nowUs >= f.capturedAtUs &&
        nowUs - f.capturedAtUs <= 100000 &&
        f.cameraId == g.cameraId &&
        f.width == g.width &&
        f.height == g.height &&
        same([f.fx, f.fy, f.cx, f.cy], [g.fx, g.fy, g.cx, g.cy]) &&
        same(f.rotation, g.rotation) &&
        same(f.originM, g.originM) &&
        i.rgb.length == f.width * f.height * 3 &&
        i.rgb.every((b) => b >= 0 && b <= 255) &&
        i.positionErrorM.isFinite &&
        i.positionErrorM >= 0 &&
        i.positionErrorM <= .1 &&
        i.angularErrorRad.isFinite &&
        i.angularErrorRad >= 0 &&
        i.angularErrorRad <= .02;
  }

  bool _sameSession(CameraMetricMotionInput a, CameraMetricMotionInput b) {
    final p = a.camera.depth,
        q = b.camera.depth,
        h = a.camera.rgbHeader,
        k = b.camera.rgbHeader;
    return p.sessionGeneration == q.sessionGeneration &&
        p.cameraId == q.cameraId &&
        p.modelHash == q.modelHash &&
        p.transformId == q.transformId &&
        p.referenceFrameId == q.referenceFrameId &&
        h.providerId == k.providerId &&
        h.modelHash == k.modelHash &&
        h.preprocessId == k.preprocessId &&
        p.width == q.width &&
        p.height == q.height &&
        p.fx == q.fx &&
        p.fy == q.fy &&
        p.cx == q.cx &&
        p.cy == q.cy;
  }

  _Bounds? _bounds(CameraMetricMotionInput i, int x, int y) {
    final key = y * i.camera.depth.width + x;
    final cache = _boundsByFrame.putIfAbsent(i, () => <int, _Bounds?>{});
    if (cache.containsKey(key)) return cache[key];
    return cache[key] = _uncachedBounds(i, x, y);
  }

  _Bounds? _uncachedBounds(CameraMetricMotionInput i, int x, int y) {
    final f = i.camera.depth, index = y * f.width + x;
    if (x < 1 ||
        y < 1 ||
        x >= f.width - 1 ||
        y >= f.height - 1 ||
        !f.valid[index]) {
      return null;
    }
    var z0 = f.freeZLowerM[index],
        z1 = f.surfaceZUpperM[index],
        range = f.rangeM[index];
    final axis =
        range /
        math.sqrt(
          1 +
              math.pow((x + .5 - f.cx) / f.fx, 2) +
              math.pow((y + .5 - f.cy) / f.fy, 2),
        );
    if (!range.isFinite ||
        range <= 0 ||
        !z0.isFinite ||
        !z1.isFinite ||
        z0 <= 0 ||
        z1 < z0 ||
        axis < z0 - f.errorM - 1e-5 ||
        axis > z1 + f.errorM + 1e-5) {
      return null;
    }
    // Registration tolerance also covers neighbouring depths. An occlusion
    // boundary or a hole cannot borrow the centre pixel's surface bound.
    for (var v = y - 1; v <= y + 1; v++) {
      for (var u = x - 1; u <= x + 1; u++) {
        final k = v * f.width + u;
        final a = f.freeZLowerM[k], b = f.surfaceZUpperM[k], r = f.rangeM[k];
        final z =
            r /
            math.sqrt(
              1 +
                  math.pow((u + .5 - f.cx) / f.fx, 2) +
                  math.pow((v + .5 - f.cy) / f.fy, 2),
            );
        if (!f.valid[k] ||
            !a.isFinite ||
            !b.isFinite ||
            !r.isFinite ||
            a <= 0 ||
            b < a ||
            z < a - f.errorM - 1e-5 ||
            z > b + f.errorM + 1e-5) {
          return null;
        }
        z0 = math.min(z0, a);
        z1 = math.max(z1, b);
        range = math.max(range, r);
      }
    }
    final lo = List.filled(3, double.infinity),
        hi = List.filled(3, -double.infinity);
    // Pixel footprint plus one-pixel registration tolerance in both images.
    for (final u in [x - 1.0, x + 2.0]) {
      for (final v in [y - 1.0, y + 2.0]) {
        for (final z in [math.max(0, z0 - f.errorM), z1 + f.errorM]) {
          final a = (u - f.cx) / f.fx, b = (v - f.cy) / f.fy;
          for (var j = 0; j < 3; j++) {
            final value =
                f.originM[j] +
                z *
                    (f.rotation[j * 3] * a +
                        f.rotation[j * 3 + 1] * b +
                        f.rotation[j * 3 + 2]);
            lo[j] = math.min(lo[j], value);
            hi[j] = math.max(hi[j], value);
          }
        }
      }
    }
    final error =
        i.positionErrorM +
        2 * (range + f.errorM) * math.sin(i.angularErrorRad / 2);
    for (var j = 0; j < 3; j++) {
      lo[j] -= error;
      hi[j] += error;
    }
    return _Bounds(lo, hi);
  }

  List<List<int>> _features(CameraMetricMotionInput input) {
    final f = input.camera.depth, ranked = <({double score, int x, int y})>[];
    for (var y = 5; y < f.height - 5; y += 6) {
      for (var x = 5; x < f.width - 5; x += 6) {
        final bounds = _bounds(input, x, y);
        if (bounds == null ||
            bounds.lower[2] < .10 ||
            bounds.upper[2] > 1.9 ||
            bounds.lower[1] < .2 ||
            bounds.upper[1] > 5 ||
            bounds.lower[0] < -2 ||
            bounds.upper[0] > 2) {
          continue;
        }
        final patch = _patch(input, x, y),
            mean = patch.reduce((a, b) => a + b) / patch.length;
        final variance =
            patch.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
            patch.length;
        if (variance >= .006) ranked.add((score: variance, x: x, y: y));
      }
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    final selected = <List<int>>[];
    // Round-robin image cells reserve features for smaller visible surfaces.
    // Selection uses only current RGB/depth, never an object mask or label.
    final cells = <int, List<({double score, int x, int y})>>{};
    for (final r in ranked) {
      final cell = (r.y * 6 ~/ f.height) * 8 + r.x * 8 ~/ f.width;
      (cells[cell] ??= []).add(r);
    }
    final distributed = <({double score, int x, int y})>[];
    for (var rank = 0; rank < ranked.length; rank++) {
      var found = false;
      for (final cell in cells.keys.toList()..sort()) {
        if (rank < cells[cell]!.length) {
          distributed.add(cells[cell]![rank]);
          found = true;
        }
      }
      if (!found) break;
    }
    for (final r in distributed) {
      if (selected.any(
        (p) => (p[0] - r.x).abs() < 10 && (p[1] - r.y).abs() < 10,
      )) {
        continue;
      }
      selected.add([r.x, r.y]);
      if (selected.length == maximumFeatures) break;
    }
    return selected;
  }

  List<double> _patch(CameraMetricMotionInput i, int x, int y) => [
    for (var v = y - patchRadius; v <= y + patchRadius; v++)
      for (var u = x - patchRadius; u <= x + patchRadius; u++)
        for (var c = 0; c < 3; c++)
          i.rgb[(v * i.camera.depth.width + u) * 3 + c] / 255,
  ];

  List<int>? _project(CameraMetricMotionInput i, List<double> world) {
    final f = i.camera.depth, p = f.cameraPoint(world);
    if (p[2] <= 0) return null;
    return [
      (f.cx + f.fx * p[0] / p[2] - .5).round(),
      (f.cy + f.fy * p[1] / p[2] - .5).round(),
    ];
  }

  List<int>? _match(
    CameraMetricMotionInput a,
    List<int> xy,
    CameraMetricMotionInput b,
    List<int> around,
  ) {
    if (enableScaleMatching) return _warpedMatch(a, xy, b, around);
    final patch = _patch(a, xy[0], xy[1]), f = b.camera.depth;
    var best = double.infinity;
    final scores = <({double score, int x, int y})>[];
    for (
      var y = math.max(patchRadius, around[1] - searchRadius);
      y <= math.min(f.height - patchRadius - 1, around[1] + searchRadius);
      y++
    ) {
      for (
        var x = math.max(patchRadius, around[0] - searchRadius);
        x <= math.min(f.width - patchRadius - 1, around[0] + searchRadius);
        x++
      ) {
        var sad = 0.0, k = 0;
        for (var v = y - patchRadius; v <= y + patchRadius; v++) {
          for (var u = x - patchRadius; u <= x + patchRadius; u++) {
            for (var c = 0; c < 3; c++) {
              sad += (patch[k++] - b.rgb[(v * f.width + u) * 3 + c] / 255)
                  .abs();
            }
          }
        }
        final score = sad / patch.length;
        best = math.min(best, score);
        scores.add((score: score, x: x, y: y));
      }
    }
    if (scores.isEmpty || best > .065) return null;
    scores.sort((a, b) => a.score.compareTo(b.score));
    final winner = scores.first;
    final second = scores.where(
      (s) => (s.x - winner.x).abs() > 2 || (s.y - winner.y).abs() > 2,
    );
    if (second.isEmpty || second.first.score - best < .015) return null;
    return [winner.x, winner.y];
  }

  double? _axis(CameraMetricMotionInput i, int x, int y) {
    final f = i.camera.depth;
    if (x < 1 || y < 1 || x >= f.width - 1 || y >= f.height - 1) {
      return null;
    }
    final cache = _axes.putIfAbsent(i, () => _AxisCache(f.width * f.height));
    final k = y * f.width + x;
    if (cache.status[k] == 0) {
      final value = _uncachedAxis(i, x, y);
      cache.status[k] = value == null ? 1 : 2;
      if (value != null) cache.values[k] = value;
    }
    return cache.status[k] == 2 ? cache.values[k] : null;
  }

  double? _uncachedAxis(CameraMetricMotionInput i, int x, int y) {
    final f = i.camera.depth;
    if (x < 1 || y < 1 || x >= f.width - 1 || y >= f.height - 1) {
      return null;
    }
    final k = y * f.width + x;
    final lo = f.freeZLowerM[k] - f.errorM;
    final hi = f.surfaceZUpperM[k] + f.errorM;
    final z =
        f.rangeM[k] /
        math.sqrt(
          1 +
              math.pow((x + .5 - f.cx) / f.fx, 2) +
              math.pow((y + .5 - f.cy) / f.fy, 2),
        );
    if (!f.valid[k] ||
        !z.isFinite ||
        !lo.isFinite ||
        !hi.isFinite ||
        lo <= 0 ||
        hi < lo ||
        z < lo - 1e-5 ||
        z > hi + 1e-5 ||
        (hi - lo) / z > .04) {
      return null;
    }
    return z;
  }

  List<int>? _warpedMatch(
    CameraMetricMotionInput a,
    List<int> xy,
    CameraMetricMotionInput b,
    List<int> around,
  ) {
    final p = a.camera.depth, f = b.camera.depth;
    final za = _axis(a, xy[0], xy[1]);
    if (za == null ||
        xy[0] < 4 ||
        xy[1] < 4 ||
        xy[0] >= p.width - 5 ||
        xy[1] >= p.height - 5) {
      return null;
    }
    // Local fronto-parallel translation hypothesis: transform optical basis
    // through calibrated camera rotations, then differentiate the projection.
    final rx = List.generate(
      3,
      (j) =>
          List.generate(
            3,
            (k) => f.rotation[k * 3 + j] * p.rotation[k * 3],
          ).reduce((a, b) => a + b) *
          za /
          p.fx,
    );
    final ry = List.generate(
      3,
      (j) =>
          List.generate(
            3,
            (k) => f.rotation[k * 3 + j] * p.rotation[k * 3 + 1],
          ).reduce((a, b) => a + b) *
          za /
          p.fy,
    );
    final template = [
      for (var dy = -4; dy <= 4; dy += 2)
        for (var dx = -4; dx <= 4; dx += 2)
          for (var c = 0; c < 3; c++)
            a.rgb[((xy[1] + dy) * p.width + xy[0] + dx) * 3 + c] / 255,
    ];
    final scores = <({double score, int x, int y})>[];
    var best = double.infinity;
    for (
      var y = math.max(1, around[1] - searchRadius);
      y <= math.min(f.height - 2, around[1] + searchRadius);
      y++
    ) {
      for (
        var x = math.max(1, around[0] - searchRadius);
        x <= math.min(f.width - 2, around[0] + searchRadius);
        x++
      ) {
        final zb = _axis(b, x, y);
        if (zb == null || za / zb < .6 || za / zb > 1.6) continue;
        final nx = (x + .5 - f.cx) / f.fx;
        final ny = (y + .5 - f.cy) / f.fy;
        final ax = f.fx * (rx[0] - nx * rx[2]) / zb;
        final ay = f.fy * (rx[1] - ny * rx[2]) / zb;
        final bx = f.fx * (ry[0] - nx * ry[2]) / zb;
        final by = f.fy * (ry[1] - ny * ry[2]) / zb;
        if ((ax * by - ay * bx).abs() < .36) continue;
        var error = 0.0, k = 0, good = true;
        for (var dy = -4; dy <= 4 && good; dy += 2) {
          for (var dx = -4; dx <= 4; dx += 2) {
            final u = x + ax * dx + bx * dy, v = y + ay * dx + by * dy;
            if (u < 0 || v < 0 || u >= f.width - 1 || v >= f.height - 1) {
              good = false;
              break;
            }
            final iu = u.floor(), iv = v.floor();
            final du = u - iu, dv = v - iv;
            final i00 = (iv * f.width + iu) * 3;
            final i10 = i00 + 3;
            final i01 = i00 + f.width * 3;
            final i11 = i01 + 3;
            for (var c = 0; c < 3; c++) {
              final sample =
                  b.rgb[i00 + c] / 255 * (1 - du) * (1 - dv) +
                  b.rgb[i10 + c] / 255 * du * (1 - dv) +
                  b.rgb[i01 + c] / 255 * (1 - du) * dv +
                  b.rgb[i11 + c] / 255 * du * dv;
              error += (template[k++] - sample).abs();
            }
            // Scores above the admission threshold plus uniqueness margin
            // cannot beat an admissible winner or undermine its uniqueness.
            if (error > (.065 + .015) * template.length) {
              good = false;
              break;
            }
          }
        }
        if (!good) continue;
        final score = error / template.length;
        scores.add((score: score, x: x, y: y));
        best = math.min(best, score);
      }
    }
    if (scores.isEmpty || best > .065) return null;
    final winner = scores.reduce((a, b) => a.score <= b.score ? a : b);
    var second = double.infinity;
    for (final s in scores) {
      if ((s.x - winner.x).abs() > 2 || (s.y - winner.y).abs() > 2) {
        second = math.min(second, s.score);
      }
    }
    if (second - best < .015) return null;
    return [winner.x, winner.y];
  }

  bool _intersects(_Bounds b, List<double> lo, List<double> hi) {
    // Positive threat only: future position interval of the visible patch at
    // <=1s. This cannot certify the unseen object's extent or clear a corridor.
    final futureLo = List.generate(3, (j) => b.lower[j] + math.min(0, lo[j]));
    final futureHi = List.generate(3, (j) => b.upper[j] + math.max(0, hi[j]));
    return futureHi[0] >= -.45 &&
        futureLo[0] <= .45 &&
        futureHi[1] >= 0 &&
        futureLo[1] <= 3.5 &&
        futureHi[2] >= .05 &&
        futureLo[2] <= 1.85;
  }
}

class _Bounds {
  final List<double> lower, upper;
  _Bounds(this.lower, this.upper);
  List<double> get center => List.generate(3, (j) => (lower[j] + upper[j]) / 2);
}

class _AxisCache {
  final Float64List values;
  final Uint8List status;
  _AxisCache(int length)
    : values = Float64List(length),
      status = Uint8List(length);
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'depth_hazard.dart';



class GroundPlaneAnalyzer {
  static const int kMapSize = 256;
  static const int kZoneStartRow = 128;

  static const int kRansacIters = 40;
  static const double kInlierThresh = 0.15;

  static const double kDropRatio = 0.30;
  static const double kMinCoverage = 0.10;

  static const int _kMaxPoints = 2048;

  final math.Random _rng = math.Random();

  final Float64List _xs = Float64List(_kMaxPoints);
  final Float64List _ys = Float64List(_kMaxPoints);
  final Float64List _zs = Float64List(_kMaxPoints);
  int _pointCount = 0;

  List<DepthHazard> analyze(Float32List depthMap) {
    assert(depthMap.length == kMapSize * kMapSize);

    _pointCount = 0;
    for (int y = kZoneStartRow; y < kMapSize; y += 4) {
      for (int x = 0; x < kMapSize; x += 4) {
        final z = depthMap[y * kMapSize + x];
        if (z > 0.05) {
          _xs[_pointCount] = x.toDouble();
          _ys[_pointCount] = y.toDouble();
          _zs[_pointCount] = z;
          _pointCount++;
          if (_pointCount >= _kMaxPoints) break;
        }
      }
      if (_pointCount >= _kMaxPoints) break;
    }

    if (_pointCount < 10) return const [];

    _Plane? bestPlane;
    int maxInliers = -1;

    for (int i = 0; i < kRansacIters; i++) {
      final i1 = _rng.nextInt(_pointCount);
      final i2 = _rng.nextInt(_pointCount);
      final i3 = _rng.nextInt(_pointCount);

      final plane = _Plane.fromCoords(
        _xs[i1], _ys[i1], _zs[i1],
        _xs[i2], _ys[i2], _zs[i2],
        _xs[i3], _ys[i3], _zs[i3],
      );
      if (plane == null) continue;

      int inliers = 0;
      for (int j = 0; j < _pointCount; j++) {
        final expectedZ = plane.getZ(_xs[j], _ys[j]);
        if (expectedZ <= 0) continue;
        final error = (_zs[j] - expectedZ).abs() / expectedZ;
        if (error < kInlierThresh) inliers++;
      }

      if (inliers > maxInliers) {
        maxInliers = inliers;
        bestPlane = plane;
      }
    }

    if (bestPlane == null || maxInliers < _pointCount * 0.2) {
      return const [];
    }

    final results = <DepthHazard>[];
    const zoneCount = 5;
    const zoneWidth = kMapSize ~/ zoneCount;

    for (int zi = 0; zi < zoneCount; zi++) {
      final colStart = zi * zoneWidth;
      final colEnd   = (zi == zoneCount - 1) ? kMapSize : colStart + zoneWidth;

      int anomalyCount = 0;
      double maxDrop = 0.0;
      int validPixels = 0;

      for (int y = kZoneStartRow; y < kMapSize; y += 2) {
        for (int x = colStart; x < colEnd; x += 2) {
          final z = depthMap[y * kMapSize + x];
          final expectedZ = bestPlane.getZ(x.toDouble(), y.toDouble());

          if (expectedZ > 0.1) {
            validPixels++;
            final threshold = expectedZ * (1.0 - kDropRatio);
            if (z < threshold) {
              anomalyCount++;
              final drop = (expectedZ - z) / expectedZ;
              if (drop > maxDrop) maxDrop = drop;
            }
          }
        }
      }

      if (validPixels == 0) continue;

      final coverage = anomalyCount / validPixels;
      if (coverage < kMinCoverage) continue;

      final score = (coverage * 0.5 + maxDrop.clamp(0.0, 1.0) * 0.5).clamp(0.0, 1.0);
      final zone = HazardZone.values[zi];
      final type = _classifyType(coverage, maxDrop, zone);

      results.add(DepthHazard(
        midasScore: score,
        type:       type,
        zone:       zone,
        coverage:   coverage,
      ));
    }

    results.sort((a, b) => b.midasScore.compareTo(a.midasScore));
    return results;
  }

  DepthHazardType _classifyType(double coverage, double maxDrop, HazardZone zone) {
    if (coverage < 0.35 && maxDrop > 0.50 &&
        (zone == HazardZone.center || zone == HazardZone.centerLeft || zone == HazardZone.centerRight)) {
      return DepthHazardType.pothole;
    }
    if (coverage > 0.40) {
      return DepthHazardType.stepDown;
    }
    return DepthHazardType.unknown;
  }
}

class _Plane {
  final double a, b, c;
  _Plane(this.a, this.b, this.c);

  static _Plane? fromCoords(
    double x1, double y1, double z1,
    double x2, double y2, double z2,
    double x3, double y3, double z3,
  ) {
    final v1x = x2 - x1, v1y = y2 - y1, v1z = z2 - z1;
    final v2x = x3 - x1, v2y = y3 - y1, v2z = z3 - z1;

    final nx = v1y * v2z - v1z * v2y;
    final ny = v1z * v2x - v1x * v2z;
    final nz = v1x * v2y - v1y * v2x;

    if (nz.abs() < 1e-6) return null;

    final a = -nx / nz;
    final b = -ny / nz;
    final d = -(nx * x1 + ny * y1 + nz * z1) / nz;

    return _Plane(a, b, d);
  }

  double getZ(double x, double y) => a * x + b * y + c;
}

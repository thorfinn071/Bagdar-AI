import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'depth_hazard.dart';

class GroundPlaneAnalyzer {
  static const int kMapSize = 256;
  static const int kZoneStartRow = 128;
  static const int kFootZoneStartRow = 218;

  static const int kRansacIters = 40;
  static const double kInlierThresh = 0.15;

  static const double kDropRatio = 0.30;
  static const double kRiseRatio = 0.25;
  static const double kMinCoverage = 0.10;
  static const double kFootZoneDeltaThreshold = 0.22;
  static const double kFootZoneCoverage = 0.18;

  static const double kReflectiveInlierRatioMin = 0.88;
  static const double kReflectiveLumaVarianceMax = 120.0;

  
  
  static const int _kMaxPoints = 2048;

  static double scanZoneLumaVariance(Uint8List lumaMap)
  {
    if (lumaMap.length != kMapSize * kMapSize) return 0.0;
    double sum = 0;
    double sqSum = 0;
    int n = 0;
    for (int y = kZoneStartRow; y < kMapSize; y += 2) {
      for (int x = 0; x < kMapSize; x += 2) {
        final l = lumaMap[y * kMapSize + x].toDouble();
        sum += l;
        sqSum += l * l;
        n++;
      }
    }
    if (n == 0) return 0.0;
    final mean = sum / n;
    final v = (sqSum / n) - mean * mean;
    return v < 0 ? 0.0 : v;
  }

  static bool isSuspiciousReflectiveSurface({
    required double inlierRatio,
    required double? lumaVariance,
  }) {
    if (lumaVariance == null) return false;
    if (!inlierRatio.isFinite || !lumaVariance.isFinite) return false;
    return inlierRatio >= kReflectiveInlierRatioMin &&
        lumaVariance <= kReflectiveLumaVarianceMax;
  }

  final math.Random _rng = math.Random();

  final Float64List _xs = Float64List(_kMaxPoints);
  final Float64List _ys = Float64List(_kMaxPoints);
  final Float64List _zs = Float64List(_kMaxPoints);
  int _pointCount = 0;

  
  
  
  
  
  
  bool _userStationaryHint = false;

  
  
  
  
  
  
  bool _weatherDegradedHint = false;

  List<DepthHazard> analyze(
    Float32List depthMap, {
    Uint8List? lumaMap,
    bool userStationary = false,
    bool weatherDegraded = false,
  }) {
    assert(depthMap.length == kMapSize * kMapSize);
    assert(lumaMap == null || lumaMap.length == kMapSize * kMapSize);

    _userStationaryHint = userStationary;
    
    
    
    
    
    
    _weatherDegradedHint = weatherDegraded;

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
        _xs[i1],
        _ys[i1],
        _zs[i1],
        _xs[i2],
        _ys[i2],
        _zs[i2],
        _xs[i3],
        _ys[i3],
        _zs[i3],
      );
      if (plane == null) continue;

      int inliers=0;
      for(int j=0; j<_pointCount; j++) {
        final expectedZ=plane.getZ(_xs[j],_ys[j]);
        if(expectedZ<=0) continue;
        final error=(_zs[j]-expectedZ).abs()/expectedZ;
        if(error<kInlierThresh) inliers++;
      }

      if (inliers > maxInliers) {
        maxInliers = inliers;
        bestPlane = plane;
      }
    }

    final results = <DepthHazard>[];
    final planeOk = bestPlane != null && maxInliers >= _pointCount * 0.2;

    const zoneCount = 5;
    const zoneWidth = kMapSize ~/ zoneCount;

    if (!planeOk) {
      _appendPlaneIndependentHazards(depthMap, results, lumaMap: lumaMap);
      results.sort((a, b) => b.midasScore.compareTo(a.midasScore));
      return results;
    }

    final inlierRatio = maxInliers / _pointCount;
    final lumaVar = lumaMap != null ? scanZoneLumaVariance(lumaMap) : null;
    
    
    if (isSuspiciousReflectiveSurface(
      inlierRatio: inlierRatio,
      lumaVariance: lumaVar,
    )) {
      results.add(
        const DepthHazard(
          midasScore: 0.60,
          type: DepthHazardType.deadZone,
          zone: HazardZone.center,
          coverage: 0.5,
        ),
      );
      _appendPlaneIndependentHazards(depthMap, results, lumaMap: lumaMap);
      results.sort((a, b) => b.midasScore.compareTo(a.midasScore));
      return results;
    }

    for (int zi = 0; zi < zoneCount; zi++) {
      final colStart = zi * zoneWidth;
      final colEnd = (zi == zoneCount - 1) ? kMapSize : colStart + zoneWidth;

      int dropCount = 0;
      int riseCount = 0;
      double maxDrop = 0.0;
      double maxRise = 0.0;
      int validPixels = 0;
      double dropSum = 0.0;
      double dropSqSum = 0.0;
      double dropLumaSum = 0.0;
      
      
      
      double dropLumaSqSum = 0.0;
      int dropLumaCount = 0;
      double flatLumaSum = 0.0;
      int flatLumaCount = 0;

      for (int y = kZoneStartRow; y < kMapSize; y += 2) {
        for (int x = colStart; x < colEnd; x += 2) {
          final z = depthMap[y * kMapSize + x];
          final expectedZ = bestPlane.getZ(x.toDouble(), y.toDouble());

          if (expectedZ > 0.1) {
            validPixels++;
            final dropThreshold = expectedZ * (1.0 - kDropRatio);
            final riseThreshold = expectedZ * (1.0 + kRiseRatio);

            if (z < dropThreshold) {
              dropCount++;
              final drop = (expectedZ - z) / expectedZ;
              if (drop > maxDrop) maxDrop = drop;
              dropSum += drop;
              dropSqSum += drop * drop;
              if (lumaMap != null) {
                final luma = lumaMap[y * kMapSize + x];
                dropLumaSum += luma;
                
                
                dropLumaSqSum += luma * luma;
                dropLumaCount++;
              }
            } else if (z > riseThreshold) {
              riseCount++;
              final rise = (z - expectedZ) / expectedZ;
              if (rise > maxRise) maxRise = rise;
            } else if (lumaMap != null) {
              flatLumaSum += lumaMap[y * kMapSize + x];
              flatLumaCount++;
            }
          }
        }
      }

      if (validPixels == 0) continue;

      final dropCoverage = dropCount / validPixels;
      final riseCoverage = riseCount / validPixels;

      if (dropCoverage >= kMinCoverage) {
        final suppress = _isLikelyShadowArtifact(
          dropCount: dropCount,
          dropSum: dropSum,
          dropSqSum: dropSqSum,
          dropLumaSum: dropLumaSum,
          dropLumaSqSum: dropLumaSqSum,
          dropLumaCount: dropLumaCount,
          flatLumaSum: flatLumaSum,
          flatLumaCount: flatLumaCount,
          maxDrop: maxDrop,
        );
        if (!suppress) {
          final score = (dropCoverage * 0.5 + maxDrop.clamp(0.0, 1.0) * 0.5)
              .clamp(0.0, 1.0);
          final zone = HazardZone.values[zi];
          final type = _classifyDropType(dropCoverage, maxDrop, zone);
          results.add(
            DepthHazard(
              midasScore: score,
              type: type,
              zone: zone,
              coverage: dropCoverage,
            ),
          );
        }
      }

      if (riseCoverage >= kMinCoverage) {
        final score = (riseCoverage * 0.5 + maxRise.clamp(0.0, 1.0) * 0.5)
            .clamp(0.0, 1.0);
        final zone = HazardZone.values[zi];
        final type = _classifyRiseType(riseCoverage, maxRise, zone);
        results.add(
          DepthHazard(
            midasScore: score,
            type: type,
            zone: zone,
            coverage: riseCoverage,
          ),
        );
      }
    }

    final overheadHazard = _detectOverheadObstacle(
      depthMap, bestPlane, lumaMap: lumaMap,
    );
    if (overheadHazard != null) {
      results.add(overheadHazard);
    }

    
    
    
    

    _appendPlaneIndependentHazards(depthMap, results, lumaMap: lumaMap);

    
    
    
    
    
    
    final emitted = _applyTemporalConfirmation(results);

    emitted.sort((a, b) => b.midasScore.compareTo(a.midasScore));
    return emitted;
  }

  
  
  
  
  
  
  
  
  
  DepthHazard? debugDetectStairsDown(
    Float32List depthMap, {
    bool userStationary = false,
  }) {
    _userStationaryHint = userStationary;
    return _detectStairsDown(depthMap);
  }

  
  
  
  
  void resetTemporalFilter() {
    _recentHazardFrames.clear();
    _lowCurbStreak = 0;
    
    
    
    _lastStairSignal = null;
    _lastStairSignalAt = _kStairSignalEpoch;
    _escalatorStreak = 0;
    
    
    
    _nearFieldBaseline.clear();
    _nearFieldStreak = 0;
  }

  List<DepthHazard> _applyTemporalConfirmation(List<DepthHazard> candidates) {
    _recentHazardFrames.addLast(List<DepthHazard>.unmodifiable(candidates));
    while (_recentHazardFrames.length > _kTemporalWindow) {
      _recentHazardFrames.removeFirst();
    }
    
    
    if (_recentHazardFrames.length < _kTemporalWindow) {
      return List<DepthHazard>.of(candidates);
    }

    final confirmed = <DepthHazard>[];
    for (final h in candidates) {
      int matches = 0;
      for (final frame in _recentHazardFrames) {
        if (frame.any((p) => p.type == h.type && p.zone == h.zone)) {
          matches++;
        }
      }
      if (matches >= _kTemporalMinMatches) confirmed.add(h);
    }
    return confirmed;
  }

  void _appendPlaneIndependentHazards(
    Float32List depthMap,
    List<DepthHazard> results, {
    Uint8List? lumaMap,
  }) {
    final footZoneHazard = _detectFootZoneHazard(depthMap);
    if (footZoneHazard != null) {
      results.add(footZoneHazard);
    }

    
    
    
    
    
    if (!_weatherDegradedHint) {
      final stairsHazard = _detectStairsDown(depthMap);
      if (stairsHazard != null) {
        results.add(stairsHazard);
      }
    } else {
      
      
      
      
      _lastStairSignal = null;
      _lastStairSignalAt = _kStairSignalEpoch;
      _escalatorStreak = 0;
    }

    
    
    
    
    
    
    
    
    
    
    final nearFieldHazard = _detectNearFieldIntrusion(depthMap);
    if (nearFieldHazard != null) {
      results.add(nearFieldHazard);
    }

    final hasCenterDrop = results.any(
      (h) =>
          h.zone == HazardZone.center &&
          (h.type == DepthHazardType.pothole ||
              h.type == DepthHazardType.stepDown),
    );
    
    
    
    
    
    if (!hasCenterDrop && !_weatherDegradedHint) {
      final pitHazard = detectPitGradientFromMap(depthMap);
      if (pitHazard != null) {
        results.add(pitHazard);
      }
    }

    if (lumaMap != null) {
      final glassHazard = detectGlassDoor(
        lumaMap,
        depthMap: depthMap,
      );
      if (glassHazard != null) {
        results.add(glassHazard);
      }

      final slipperyHazard = detectSlipperyFromLuma(lumaMap);
      if (slipperyHazard != null) {
        results.add(slipperyHazard);
      }
    }
  }

  
  
  
  
  
  
  
  static const double _kLowCurbMinDelta = 0.05;
  static const double _kLowCurbMaxDelta = 0.20;
  static const double _kLowCurbCoverage = 0.18;
  
  
  
  
  
  
  
  static const int _kLowCurbConfirmFrames = 2;
  int _lowCurbStreak = 0;

  
  
  
  
  
  
  
  
  
  static const int _kTemporalWindow = 3;
  static const int _kTemporalMinMatches = 2;
  final ListQueue<List<DepthHazard>> _recentHazardFrames =
      ListQueue<List<DepthHazard>>(_kTemporalWindow);

  DepthHazard? _detectFootZoneHazard(Float32List depthMap) {
    int pairCount = 0;
    int strongPairs = 0;
    int lowCurbPairs = 0;
    double maxDelta = 0.0;
    double lowCurbMaxDelta = 0.0;
    double totalDelta = 0.0;

    for (int y = kFootZoneStartRow; y < kMapSize - 1; y += 2) {
      for (int x = 0; x < kMapSize - 1; x += 2) {
        final z = depthMap[y * kMapSize + x];
        if (z <= 0.05) continue;

        final right = depthMap[y * kMapSize + x + 1];
        if (right > 0.05) {
          final delta = (z - right).abs();
          pairCount++;
          totalDelta += delta;
          if (delta > kFootZoneDeltaThreshold) strongPairs++;
          if (delta > maxDelta) maxDelta = delta;
          if (delta >= _kLowCurbMinDelta && delta < _kLowCurbMaxDelta) {
            lowCurbPairs++;
            if (delta > lowCurbMaxDelta) lowCurbMaxDelta = delta;
          }
        }

        final down = depthMap[(y + 1) * kMapSize + x];
        if (down > 0.05) {
          final delta = (z - down).abs();
          pairCount++;
          totalDelta += delta;
          if (delta > kFootZoneDeltaThreshold) strongPairs++;
          if (delta > maxDelta) maxDelta = delta;
          if (delta >= _kLowCurbMinDelta && delta < _kLowCurbMaxDelta) {
            lowCurbPairs++;
            if (delta > lowCurbMaxDelta) lowCurbMaxDelta = delta;
          }
        }
      }
    }

    if (pairCount == 0) {
      _lowCurbStreak = 0;
      return null;
    }

    final coverage = strongPairs / pairCount;
    final avgDelta = totalDelta / pairCount;
    if (coverage >= kFootZoneCoverage && maxDelta >= 0.30 && avgDelta >= 0.12) {
      
      
      _lowCurbStreak = 0;
      final score = (coverage * 0.65 + maxDelta.clamp(0.0, 1.0) * 0.35).clamp(
        0.0,
        1.0,
      );
      return DepthHazard(
        midasScore: score,
        type: DepthHazardType.deadZone,
        zone: HazardZone.center,
        coverage: coverage,
      );
    }

    final lowCurbCoverage = lowCurbPairs / pairCount;
    final lowCurbMatchesThisFrame = lowCurbCoverage >= _kLowCurbCoverage &&
        lowCurbMaxDelta >= _kLowCurbMinDelta + 0.01;
    if (!lowCurbMatchesThisFrame) {
      _lowCurbStreak = 0;
      return null;
    }

    _lowCurbStreak++;
    if (_lowCurbStreak < _kLowCurbConfirmFrames) return null;

    final score =
        (lowCurbCoverage * 0.55 +
                (lowCurbMaxDelta / _kLowCurbMaxDelta).clamp(0.0, 1.0) * 0.45)
            .clamp(0.0, 1.0);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.lowCurb,
      zone: HazardZone.center,
      coverage: lowCurbCoverage,
    );
  }

  DepthHazard? _detectOverheadObstacle(
    Float32List depthMap,
    _Plane plane, {
    Uint8List? lumaMap,
  }) {
    final depthResult = detectOverheadFromMap(
      depthMap,
      planeA: plane.a,
      planeB: plane.b,
      planeC: plane.c,
    );
    if (depthResult != null) return depthResult;
    if (lumaMap == null) return null;
    return _detectOverheadFromEdge(depthMap, lumaMap);
  }

  static const int _kOverheadRowLo = 50;
  static const int _kOverheadRowHi = 120;
  static const double _kOverheadDepthTolerance = 0.25;
  static const double _kOverheadMinCoverage = 0.05;
  static const int _kOverheadMaxVerticalSpread = 25;
  static const double _kOverheadMinHorizontalSpan = 0.30;

  static const double _kEdgeMinSpanFrac = 0.40;
  static const int _kEdgeResponseThreshold = 30;
  static const double _kEdgeDepthDiscontThreshold = 0.15;
  static const int _kEdgeMinRowRun = 3;

  static DepthHazard? detectOverheadFromMap(
    Float32List depthMap, {
    required double planeA,
    required double planeB,
    required double planeC,
  }) {
    if (depthMap.length != kMapSize * kMapSize) return null;

    final nearZ =
        planeA * (kMapSize / 2.0) + planeB * (kMapSize - 1).toDouble() + planeC;
    if (nearZ <= 0.1) return null;

    int totalCount = 0;
    int matchCount = 0;
    int yMatchMin = kMapSize;
    int yMatchMax = -1;
    int xMatchMin = kMapSize;
    int xMatchMax = -1;
    int matchSumX = 0;

    for (int y = _kOverheadRowLo; y < _kOverheadRowHi; y += 2) {
      for (int x = 0; x < kMapSize; x += 2) {
        final z = depthMap[y * kMapSize + x];
        if (z <= 0.05) continue;
        totalCount++;
        if ((z - nearZ).abs() / nearZ < _kOverheadDepthTolerance) {
          matchCount++;
          if (y < yMatchMin) yMatchMin = y;
          if (y > yMatchMax) yMatchMax = y;
          if (x < xMatchMin) xMatchMin = x;
          if (x > xMatchMax) xMatchMax = x;
          matchSumX += x;
        }
      }
    }

    if (totalCount == 0 || matchCount == 0) return null;

    final coverage = matchCount / totalCount;
    if (coverage < _kOverheadMinCoverage) return null;

    final vExtent = yMatchMax - yMatchMin;
    if (vExtent > _kOverheadMaxVerticalSpread) return null;

    final hExtent = xMatchMax - xMatchMin;
    if (hExtent < kMapSize * _kOverheadMinHorizontalSpan) return null;

    final centerX = matchSumX / matchCount;
    final zoneIdx = (centerX * 5 / kMapSize).floor().clamp(0, 4);

    final score = (0.55 + 0.4 * coverage.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.overhead,
      zone: HazardZone.values[zoneIdx],
      coverage: coverage,
    );
  }

  static DepthHazard? _detectOverheadFromEdge(
    Float32List depthMap,
    Uint8List lumaMap,
  ) {
    if (lumaMap.length != kMapSize * kMapSize) return null;
    if (depthMap.length != kMapSize * kMapSize) return null;

    int bestRunRows = 0;
    int bestRowY = -1;
    int bestRowXmin = kMapSize;
    int bestRowXmax = -1;
    int runRows = 0;

    for (int y = _kOverheadRowLo; y < _kOverheadRowHi; y++) {
      int edgePixels = 0;
      int rowXmin = kMapSize;
      int rowXmax = -1;
      final row = y * kMapSize;
      for (int x = 1; x < kMapSize - 1; x++) {
        final left = lumaMap[row + x - 1];
        final right = lumaMap[row + x + 1];
        final resp = (right - left).abs();
        if (resp >= _kEdgeResponseThreshold) {
          edgePixels++;
          if (x < rowXmin) rowXmin = x;
          if (x > rowXmax) rowXmax = x;
        }
      }
      final span = rowXmax > rowXmin
          ? (rowXmax - rowXmin) / kMapSize
          : 0.0;
      if (span >= _kEdgeMinSpanFrac && edgePixels >= 6) {
        runRows++;
        if (runRows > bestRunRows) {
          bestRunRows = runRows;
          bestRowY = y;
          if (rowXmin < bestRowXmin) bestRowXmin = rowXmin;
          if (rowXmax > bestRowXmax) bestRowXmax = rowXmax;
        }
      } else {
        runRows = 0;
      }
    }

    if (bestRunRows < _kEdgeMinRowRun) return null;
    if (bestRowY < 0) return null;

    final aboveY = (bestRowY - bestRunRows - 3).clamp(_kOverheadRowLo, _kOverheadRowHi - 1);
    final belowY = (bestRowY + 3).clamp(_kOverheadRowLo, _kOverheadRowHi - 1);
    final edgeY = (bestRowY - bestRunRows ~/ 2).clamp(_kOverheadRowLo, _kOverheadRowHi - 1);

    double aboveSum = 0, edgeSum = 0, belowSum = 0;
    int aboveN = 0, edgeN = 0, belowN = 0;
    for (int x = bestRowXmin; x <= bestRowXmax; x += 2) {
      final za = depthMap[aboveY * kMapSize + x];
      if (za > 0.05) { aboveSum += za; aboveN++; }
      final ze = depthMap[edgeY * kMapSize + x];
      if (ze > 0.05) { edgeSum += ze; edgeN++; }
      final zb = depthMap[belowY * kMapSize + x];
      if (zb > 0.05) { belowSum += zb; belowN++; }
    }

    if (aboveN < 3 || edgeN < 3 || belowN < 3) return null;
    final aboveMean = aboveSum / aboveN;
    final edgeMean = edgeSum / edgeN;
    final belowMean = belowSum / belowN;

    final bgMean = (aboveMean + belowMean) / 2.0;
    if (bgMean <= 0.05) return null;
    final aboveBelowSimilar =
        (aboveMean - belowMean).abs() / bgMean < _kEdgeDepthDiscontThreshold;
    final edgeDifferent =
        (edgeMean - bgMean).abs() / bgMean >= _kEdgeDepthDiscontThreshold;
    if (!aboveBelowSimilar || !edgeDifferent) return null;

    final cx = (bestRowXmin + bestRowXmax) / 2.0;
    final zoneIdx = (cx * 5 / kMapSize).floor().clamp(0, 4);
    final spanFrac = (bestRowXmax - bestRowXmin) / kMapSize;
    final score = (0.50 + 0.35 * spanFrac.clamp(0.0, 1.0)).clamp(0.0, 0.90);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.overhead,
      zone: HazardZone.values[zoneIdx],
      coverage: spanFrac.clamp(0.0, 1.0),
    );
  }

  static const int _kPitColLo = 96;
  static const int _kPitColHi = 160;
  static const int _kPitBaselineRowLo = 240;
  static const int _kPitBaselineRowHi = 256;
  static const int _kPitRowLo = 90;
  static const int _kPitRowHi = 230;
  static const double _kPitMinDeviation = 0.25;
  static const double _kPitMinAbsoluteGap = 0.04;
  static const int _kPitMinRunRows = 3;

  static DepthHazard? detectPitGradientFromMap(Float32List depthMap) {
    if (depthMap.length != kMapSize * kMapSize) return null;

    double sumY = 0;
    double sumZ = 0;
    double sumYZ = 0;
    double sumY2 = 0;
    int n = 0;
    for (int y = _kPitBaselineRowLo; y < _kPitBaselineRowHi; y++) {
      for (int x = _kPitColLo; x < _kPitColHi; x++) {
        final z = depthMap[y * kMapSize + x];
        if (z > 0.05) {
          sumY += y;
          sumZ += z;
          sumYZ += y * z;
          sumY2 += y * y.toDouble();
          n++;
        }
      }
    }
    if (n < 40) return null;

    final meanY = sumY / n;
    final meanZ = sumZ / n;
    final num = sumYZ - n * meanY * meanZ;
    final den = sumY2 - n * meanY * meanY;
    if (den.abs() < 1e-6) return null;
    final slope = num / den;
    final intercept = meanZ - slope * meanY;

    final pitSign = -slope.sign;

    int runLen = 0;
    int bestRunLen = 0;
    double maxDeviation = 0;

    for (int y = _kPitRowHi; y >= _kPitRowLo; y -= 2) {
      final expectedZ = intercept + slope * y;
      if (expectedZ <= 0.05) {
        if (runLen > bestRunLen) bestRunLen = runLen;
        runLen = 0;
        continue;
      }

      double sumRow = 0;
      int countRow = 0;
      for (int x = _kPitColLo; x < _kPitColHi; x++) {
        final z = depthMap[y * kMapSize + x];
        if (z > 0.05) {
          sumRow += z;
          countRow++;
        }
      }
      if (countRow < 10) {
        if (runLen > bestRunLen) bestRunLen = runLen;
        runLen = 0;
        continue;
      }
      final zRow = sumRow / countRow;
      final delta = zRow - expectedZ;
      final deviation = delta / expectedZ.abs();
      final absGap = delta.abs();

      final aligns = pitSign == 0 || delta.sign == pitSign;
      final strong =
          deviation.abs() >= _kPitMinDeviation && absGap >= _kPitMinAbsoluteGap;

      if (aligns && strong) {
        runLen++;
        if (deviation.abs() > maxDeviation) maxDeviation = deviation.abs();
      } else {
        if (runLen > bestRunLen) bestRunLen = runLen;
        runLen = 0;
      }
    }
    if (runLen > bestRunLen) bestRunLen = runLen;

    if (bestRunLen < _kPitMinRunRows) return null;

    final score = (0.60 + 0.40 * maxDeviation.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.pothole,
      zone: HazardZone.center,
      coverage: maxDeviation.clamp(0.0, 1.0),
    );
  }

  bool _isLikelyShadowArtifact({
    required int dropCount,
    required double dropSum,
    required double dropSqSum,
    required double dropLumaSum,
    required int dropLumaCount,
    required double flatLumaSum,
    required int flatLumaCount,
    required double maxDrop,
    double? dropLumaSqSum,
  }) {
    return isLikelyShadowArtifact(
      dropCount: dropCount,
      dropSum: dropSum,
      dropSqSum: dropSqSum,
      dropLumaSqSum: dropLumaSqSum,
      dropLumaSum: dropLumaSum,
      dropLumaCount: dropLumaCount,
      flatLumaSum: flatLumaSum,
      flatLumaCount: flatLumaCount,
      maxDrop: maxDrop,
    );
  }

  static const double _kShadowMaxDropVariance = 0.0025;
  static const double _kShadowMaxDropMagnitude = 0.55;
  static const double _kShadowMinLumaDelta = 28.0;
  static const int _kShadowMinSamples = 8;
  
  
  
  
  
  static const double _kReflectiveDropLumaVariance = 500.0;

  static bool isLikelyShadowArtifact({
    required int dropCount,
    required double dropSum,
    required double dropSqSum,
    required double dropLumaSum,
    required int dropLumaCount,
    required double flatLumaSum,
    required int flatLumaCount,
    required double maxDrop,
    double? dropLumaSqSum,
  }) {
    if (dropLumaCount < _kShadowMinSamples) return false;
    if (flatLumaCount < _kShadowMinSamples) return false;
    if (dropCount < _kShadowMinSamples) return false;

    final dropMean = dropSum / dropCount;
    final dropVar = (dropSqSum / dropCount) - dropMean * dropMean;
    if (dropVar >= _kShadowMaxDropVariance) return false;

    if (maxDrop > _kShadowMaxDropMagnitude) return false;

    final dropLumaMean = dropLumaSum / dropLumaCount;
    final flatLumaMean = flatLumaSum / flatLumaCount;

    
    
    
    
    
    
    final lumaDelta = (flatLumaMean - dropLumaMean).abs();
    if (lumaDelta >= _kShadowMinLumaDelta) return true;

    
    
    
    
    
    final sqSum = dropLumaSqSum;
    if (sqSum != null && dropLumaCount > 1) {
      final dropLumaVar = (sqSum / dropLumaCount) - dropLumaMean * dropLumaMean;
      if (dropLumaVar >= _kReflectiveDropLumaVariance) return true;
    }

    return false;
  }

  
  
  
  
  
  
  Float64List? _lastStairSignal;
  DateTime _lastStairSignalAt = _kStairSignalEpoch;
  
  
  
  
  
  int _escalatorStreak = 0;
  static const int _kEscalatorConfirmFrames = 2;
  
  
  
  
  static const int _kStairsPhaseSearchPx = 10;
  static const int _kStairsPhaseShiftPx = 4;
  static const Duration _kStairsSignalStale = Duration(milliseconds: 1500);
  static final DateTime _kStairSignalEpoch =
      DateTime.fromMillisecondsSinceEpoch(0);

  DepthHazard? _detectStairsDown(Float32List depthMap) {
    final signal = _computeStairsSignal(depthMap);
    if (signal == null) {
      
      
      
      return null;
    }

    final hazard = _classifyStairsSignal(signal);

    final now = DateTime.now();
    final prev = _lastStairSignal;
    final prevAge = now.difference(_lastStairSignalAt);
    _lastStairSignal = signal;
    _lastStairSignalAt = now;

    if (hazard == null) {
      
      
      _escalatorStreak = 0;
      return null;
    }

    
    
    
    
    
    if (!_userStationaryHint) {
      _escalatorStreak = 0;
      return hazard;
    }

    if (prev == null ||
        prev.length != signal.length ||
        prevAge > _kStairsSignalStale) {
      
      
      _escalatorStreak = 0;
      return hazard;
    }

    final shift = _findStairsPhaseShift(prev, signal);
    if (shift.abs() < _kStairsPhaseShiftPx) {
      _escalatorStreak = 0;
      return hazard;
    }

    
    
    
    
    
    _escalatorStreak++;
    if (_escalatorStreak < _kEscalatorConfirmFrames) {
      return null;
    }

    return DepthHazard(
      
      
      midasScore: (hazard.midasScore * 0.6).clamp(0.0, 1.0),
      type: DepthHazardType.escalatorRiding,
      zone: hazard.zone,
      coverage: hazard.coverage,
    );
  }

  
  
  
  
  
  
  
  
  
  
  
  
  
  static const int _kNearFieldRowStart = kFootZoneStartRow;
  static const double _kNearFieldMinValidZ = 0.05;
  static const int _kNearFieldMinSamples = 512;
  static const double _kNearFieldJumpThreshold = 0.08;
  static const int _kNearFieldBaselineMin = 4;
  static const int _kNearFieldBaselineMax = 8;
  static const int _kNearFieldConfirmFrames = 2;
  final ListQueue<double> _nearFieldBaseline = ListQueue<double>(
    _kNearFieldBaselineMax,
  );
  int _nearFieldStreak = 0;

  DepthHazard? _detectNearFieldIntrusion(Float32List depthMap) {
    
    
    
    if (_userStationaryHint) {
      _nearFieldStreak = 0;
      return null;
    }

    double sum = 0;
    int count = 0;
    for (int y = _kNearFieldRowStart; y < kMapSize; y += 2) {
      final row = y * kMapSize;
      for (int x = 0; x < kMapSize; x += 2) {
        final z = depthMap[row + x];
        if (z > _kNearFieldMinValidZ) {
          sum += z;
          count++;
        }
      }
    }
    
    
    
    if (count < _kNearFieldMinSamples) {
      _nearFieldStreak = 0;
      return null;
    }
    final currentMean = sum / count;

    
    
    
    if (_nearFieldBaseline.length < _kNearFieldBaselineMin) {
      _nearFieldBaseline.addLast(currentMean);
      _nearFieldStreak = 0;
      return null;
    }

    final medianBaseline = _nearFieldMedian();
    final delta = currentMean - medianBaseline;

    if (delta > _kNearFieldJumpThreshold) {
      
      
      
      _nearFieldStreak++;
      if (_nearFieldStreak < _kNearFieldConfirmFrames) {
        return null;
      }
      
      
      
      
      final coverage = (delta / 0.25).clamp(0.0, 1.0);
      final score = (0.45 + 0.30 * coverage).clamp(0.0, 0.85);
      return DepthHazard(
        midasScore: score,
        type: DepthHazardType.nearFieldIntrusion,
        zone: HazardZone.center,
        coverage: coverage,
      );
    }

    
    
    
    _nearFieldBaseline.addLast(currentMean);
    while (_nearFieldBaseline.length > _kNearFieldBaselineMax) {
      _nearFieldBaseline.removeFirst();
    }
    _nearFieldStreak = 0;
    return null;
  }

  double _nearFieldMedian() {
    final sorted = List<double>.of(_nearFieldBaseline)..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
  }

  
  
  
  
  DepthHazard? debugDetectNearFieldIntrusion(
    Float32List depthMap, {
    bool userStationary = false,
  }) {
    _userStationaryHint = userStationary;
    return _detectNearFieldIntrusion(depthMap);
  }

  static int _findStairsPhaseShift(Float64List prev, Float64List curr) {
    
    
    
    
    
    
    const stride = 4;
    final prevDiff = _differencedSignal(prev, stride);
    final currDiff = _differencedSignal(curr, stride);
    if (prevDiff == null || currDiff == null) return 0;

    final n = math.min(prevDiff.length, currDiff.length);
    if (n < 40) return 0;

    double prevMean = 0;
    double currMean = 0;
    for (int i = 0; i < n; i++) {
      prevMean += prevDiff[i];
      currMean += currDiff[i];
    }
    prevMean /= n;
    currMean /= n;

    double bestCorr = -double.infinity;
    int bestLag = 0;
    for (
      int lag = -_kStairsPhaseSearchPx;
      lag <= _kStairsPhaseSearchPx;
      lag++
    ) {
      double corr = 0;
      int count = 0;
      for (int i = 0; i < n; i++) {
        final j = i + lag;
        if (j < 0 || j >= n) continue;
        corr += (prevDiff[i] - prevMean) * (currDiff[j] - currMean);
        count++;
      }
      
      
      if (count < (n * 0.6).floor()) continue;
      final normalized = corr / count;
      if (normalized > bestCorr) {
        bestCorr = normalized;
        bestLag = lag;
      }
    }
    
    
    
    if (bestCorr <= 0) return 0;
    return bestLag;
  }

  static Float64List? _differencedSignal(Float64List signal, int stride) {
    if (signal.length <= stride) return null;
    final diff = Float64List(signal.length - stride);
    for (int i = 0; i < diff.length; i++) {
      diff[i] = signal[i + stride] - signal[i];
    }
    return diff;
  }

  static const int _kStairsColLo = 96;
  static const int _kStairsColHi = 160;
  static const int _kStairsRowLo = 64;
  static const int _kStairsLagMin = 12;
  static const int _kStairsLagMax = 48;
  static const double _kStairsPeakRatio = 3.0;
  static const double _kStairsMinEnergy = 1e-4;
  static const double _kStairsMinDirectionality = 0.58;

  
  
  
  
  static Float64List? _computeStairsSignal(Float32List depthMap) {
    if (depthMap.length != kMapSize * kMapSize) return null;
    const colCount = _kStairsColHi - _kStairsColLo;
    const rowCount = kMapSize - _kStairsRowLo;
    if (rowCount <= _kStairsLagMax + 8) return null;

    final signal = Float64List(rowCount);
    final tmp = Float64List(colCount);
    for (int y = 0; y < rowCount; y++) {
      final rowOffset = (y + _kStairsRowLo) * kMapSize;
      int validCount = 0;
      for (int x = 0; x < colCount; x++) {
        final z = depthMap[rowOffset + x + _kStairsColLo];
        if (z > 0.01) {
          tmp[validCount++] = z;
        }
      }
      if (validCount == 0) {
        signal[y] = y > 0 ? signal[y - 1] : 0.0;
      } else {
        signal[y] = _median(tmp, validCount);
      }
    }
    return signal;
  }

  static DepthHazard? _classifyStairsSignal(Float64List signal) {
    final rowCount = signal.length;
    const stride = 4;
    if (rowCount <= stride + _kStairsLagMax + 4) return null;
    final d = Float64List(rowCount - stride);
    double energy = 0;
    double posSum = 0;
    double negSum = 0;
    for (int i = 0; i < d.length; i++) {
      final v = signal[i + stride] - signal[i];
      d[i] = v;
      energy += v * v;
      if (v > 0) {
        posSum += v;
      } else {
        negSum += -v;
      }
    }
    if (energy < _kStairsMinEnergy) return null;

    final absSum = posSum + negSum;
    if (absSum <= 0) return null;
    final directional = (posSum - negSum).abs() / absSum;
    if (directional < _kStairsMinDirectionality) return null;

    double mean = 0;
    for (final v in d) {
      mean += v;
    }
    mean /= d.length;
    for (int i = 0; i < d.length; i++) {
      d[i] -= mean;
    }

    double var0 = 0;
    for (final v in d) {
      var0 += v * v;
    }
    if (var0 <= 0) return null;

    double peakAc = 0;
    int peakLag = -1;
    double acSum = 0;
    int acCount = 0;
    for (int lag = 6; lag <= _kStairsLagMax + 4; lag++) {
      if (d.length <= lag + 4) break;
      double ac = 0;
      final n = d.length - lag;
      for (int i = 0; i < n; i++) {
        ac += d[i] * d[i + lag];
      }
      final normalized = ac / var0;
      acSum += normalized.abs();
      acCount++;
      if (lag >= _kStairsLagMin &&
          lag <= _kStairsLagMax &&
          normalized > peakAc) {
        peakAc = normalized;
        peakLag = lag;
      }
    }
    if (peakLag < 0 || acCount == 0) return null;

    final acMean = acSum / acCount;
    if (acMean <= 1e-9) return null;
    if (peakAc < _kStairsPeakRatio * acMean) return null;
    if (peakAc < 0.18) return null;

    final score = (0.55 + 0.45 * peakAc.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.stairsDown,
      zone: HazardZone.center,
      coverage: peakAc.clamp(0.0, 1.0),
    );
  }

  
  
  
  static DepthHazard? detectStairsDownFromMap(Float32List depthMap) {
    final signal = _computeStairsSignal(depthMap);
    if (signal == null) return null;
    return _classifyStairsSignal(signal);
  }

  static double _median(Float64List buf, [int? count]) {
    final n = count ?? buf.length;
    if (n <= 0) return 0.0;
    final copy = <double>[for (int i = 0; i < n; i++) buf[i]];
    copy.sort();
    return n.isOdd ? copy[n ~/ 2] : (copy[n ~/ 2 - 1] + copy[n ~/ 2]) / 2.0;
  }

  DepthHazardType _classifyDropType(
    double coverage,
    double maxDrop,
    HazardZone zone,
  ) {
    if (coverage < 0.35 &&
        maxDrop > 0.50 &&
        (zone == HazardZone.center ||
            zone == HazardZone.centerLeft ||
            zone == HazardZone.centerRight)) {
      return DepthHazardType.pothole;
    }
    if (coverage > 0.40) {
      return DepthHazardType.stepDown;
    }
    return DepthHazardType.unknown;
  }

  DepthHazardType _classifyRiseType(
    double coverage,
    double maxRise,
    HazardZone zone,
  ) {
    if (coverage < 0.30 && maxRise > 0.30) {
      return DepthHazardType.curb;
    }
    if (coverage > 0.35) {
      return DepthHazardType.stepUp;
    }
    return DepthHazardType.curb;
  }

  

  

  
  
  static const int _kGlassRowHi = 153;
  static const double _kGlassSymmetryThreshold = 0.70;
  static const double _kGlassMinWidthFrac = 0.20;
  static const double _kGlassMaxContrast = 76.0; 

  static DepthHazard? detectGlassDoor(
    Uint8List lumaMap, {
    Float32List? depthMap,
  }) {
    final sym = detectGlassDoorFromLuma(lumaMap);
    if (sym != null) return sym;
    if (depthMap != null) {
      return _detectGlassDoorFromEdges(depthMap, lumaMap);
    }
    return null;
  }

  static DepthHazard? detectGlassDoorFromLuma(Uint8List lumaMap) {
    if (lumaMap.length != kMapSize * kMapSize) return null;

    const halfW = kMapSize ~/ 2;
    final symmetry = Float64List(halfW);
    const rowCount = _kGlassRowHi;
    if (rowCount <= 0) return null;

    for (int x = 0; x < halfW; x++) {
      double diff = 0;
      for (int y = 0; y < rowCount; y += 2) {
        final left = lumaMap[y * kMapSize + x];
        final right = lumaMap[y * kMapSize + (kMapSize - 1 - x)];
        diff += (left - right).abs();
      }
      final samples = (rowCount + 1) ~/ 2;
      symmetry[x] = 1.0 - diff / (255.0 * samples);
    }

    final xLo = (halfW * 0.10).floor();
    final xHi = (halfW * 0.90).ceil();
    int bestRun = 0, runLen = 0;
    for (int x = xLo; x < xHi; x++) {
      if (symmetry[x] >= _kGlassSymmetryThreshold) {
        runLen++;
        if (runLen > bestRun) bestRun = runLen;
      } else {
        runLen = 0;
      }
    }

    final widthFrac = (bestRun * 2.0) / kMapSize;
    if (widthFrac < _kGlassMinWidthFrac) return null;

    int lumaMin = 255, lumaMax = 0;
    for (int y = 0; y < _kGlassRowHi; y += 4) {
      for (int x = 0; x < kMapSize; x += 4) {
        final v = lumaMap[y * kMapSize + x];
        if (v < lumaMin) lumaMin = v;
        if (v > lumaMax) lumaMax = v;
      }
    }
    final contrast = (lumaMax - lumaMin).toDouble();
    if (contrast > _kGlassMaxContrast) return null;

    final score = (0.45 + 0.35 * widthFrac.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.glassDoor,
      zone: HazardZone.center,
      coverage: widthFrac.clamp(0.0, 1.0),
    );
  }

  static const int _kGlassEdgeThreshold = 25;
  static const int _kGlassEdgeMinRunRows = 20;
  static const double _kGlassEdgeMinGapFrac = 0.20;
  static const double _kGlassEdgeMaxGapFrac = 0.60;
  static const double _kGlassDepthRatio = 1.5;

  static DepthHazard? _detectGlassDoorFromEdges(
    Float32List depthMap,
    Uint8List lumaMap,
  ) {
    if (lumaMap.length != kMapSize * kMapSize) return null;
    if (depthMap.length != kMapSize * kMapSize) return null;

    final colEdgeCount = Int32List(kMapSize);
    for (int y = 10; y < _kGlassRowHi - 1; y += 2) {
      final row = y * kMapSize;
      for (int x = 1; x < kMapSize - 1; x++) {
        final above = lumaMap[(y - 1) * kMapSize + x];
        final below = lumaMap[(y + 1) * kMapSize + x];
        final gy = (below - above).abs();
        if (gy >= _kGlassEdgeThreshold) colEdgeCount[x]++;
      }
    }

    final minRun = _kGlassEdgeMinRunRows ~/ 2;
    int bestLeftX = -1, bestRightX = -1;
    int bestLeftScore = 0, bestRightScore = 0;
    final midX = kMapSize ~/ 2;

    for (int x = 1; x < midX; x++) {
      if (colEdgeCount[x] >= minRun && colEdgeCount[x] > bestLeftScore) {
        bestLeftScore = colEdgeCount[x];
        bestLeftX = x;
      }
    }
    for (int x = midX; x < kMapSize - 1; x++) {
      if (colEdgeCount[x] >= minRun && colEdgeCount[x] > bestRightScore) {
        bestRightScore = colEdgeCount[x];
        bestRightX = x;
      }
    }

    if (bestLeftX < 0 || bestRightX < 0) return null;
    final gapFrac = (bestRightX - bestLeftX) / kMapSize.toDouble();
    if (gapFrac < _kGlassEdgeMinGapFrac ||
        gapFrac > _kGlassEdgeMaxGapFrac) {
      return null;
    }

    double innerSum = 0, outerSum = 0;
    int innerN = 0, outerN = 0;
    for (int y = 30; y < _kGlassRowHi; y += 4) {
      final row = y * kMapSize;
      for (int x = bestLeftX + 2; x < bestRightX - 2; x += 2) {
        final z = depthMap[row + x];
        if (z > 0.05) { innerSum += z; innerN++; }
      }
      for (int x = 0; x < bestLeftX - 2; x += 4) {
        final z = depthMap[row + x];
        if (z > 0.05) { outerSum += z; outerN++; }
      }
      for (int x = bestRightX + 2; x < kMapSize; x += 4) {
        final z = depthMap[row + x];
        if (z > 0.05) { outerSum += z; outerN++; }
      }
    }

    if (innerN < 20 || outerN < 10) return null;
    final innerMean = innerSum / innerN;
    final outerMean = outerSum / outerN;
    if (outerMean <= 0.05) return null;

    final ratio = innerMean / outerMean;
    if (ratio < _kGlassDepthRatio) return null;

    final score = (0.40 + 0.30 * gapFrac.clamp(0.0, 1.0)).clamp(0.0, 0.85);
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.glassDoor,
      zone: HazardZone.center,
      coverage: gapFrac.clamp(0.0, 1.0),
    );
  }

  

  

  static const double _kSlipperyAnisotropyThreshold = 3.0;
  static const double _kSlipperyMinLumaVariance = 500.0;

  static DepthHazard? detectSlipperyFromLuma(Uint8List lumaMap) {
    if (lumaMap.length != kMapSize * kMapSize) return null;

    double hEnergy = 0;
    double vEnergy = 0;

    for (int y = kZoneStartRow + 1; y < kMapSize - 1; y += 2) {
      for (int x = 1; x < kMapSize - 1; x += 2) {
        final gx =
            -lumaMap[(y - 1) * kMapSize + (x - 1)] +
            lumaMap[(y - 1) * kMapSize + (x + 1)] +
            -2 * lumaMap[y * kMapSize + (x - 1)] +
            2 * lumaMap[y * kMapSize + (x + 1)] +
            -lumaMap[(y + 1) * kMapSize + (x - 1)] +
            lumaMap[(y + 1) * kMapSize + (x + 1)];

        final gy =
            -lumaMap[(y - 1) * kMapSize + (x - 1)] +
            -2 * lumaMap[(y - 1) * kMapSize + x] +
            -lumaMap[(y - 1) * kMapSize + (x + 1)] +
            lumaMap[(y + 1) * kMapSize + (x - 1)] +
            2 * lumaMap[(y + 1) * kMapSize + x] +
            lumaMap[(y + 1) * kMapSize + (x + 1)];

        hEnergy += gx * gx;
        vEnergy += gy * gy;
      }
    }

    if (hEnergy < 1e-6) return null;

    final anisotropy = vEnergy / hEnergy;
    if (anisotropy < _kSlipperyAnisotropyThreshold) return null;

    final lumaVar = scanZoneLumaVariance(lumaMap);
    if (lumaVar < _kSlipperyMinLumaVariance) return null;

    final score = (0.40 + 0.20 * (anisotropy / 10.0).clamp(0.0, 1.0)).clamp(
      0.0,
      1.0,
    );
    return DepthHazard(
      midasScore: score,
      type: DepthHazardType.slippery,
      zone: HazardZone.center,
      coverage: (anisotropy / 10.0).clamp(0.0, 1.0),
    );
  }
}

class _Plane {
  final double a, b, c;
  _Plane(this.a, this.b, this.c);

  static _Plane? fromCoords(
    double x1,
    double y1,
    double z1,
    double x2,
    double y2,
    double z2,
    double x3,
    double y3,
    double z3,
  ) {
    final v1x = x2 - x1, v1y = y2 - y1, v1z = z2 - z1;
    final v2x = x3 - x1, v2y = y3 - y1, v2z = z3 - z1;

    final nx = v1y * v2z - v1z * v2y;
    final ny = v1z * v2x - v1x * v2z;
    final nz = v1x * v2y - v1y * v2x;

    if (nz.abs() < 1e-6) return null;

    final a = -nx / nz;
    final b = -ny / nz;
    final c = (nx * x1 + ny * y1 + nz * z1) / nz;

    return _Plane(a, b, c);
  }

  double getZ(double x, double y) => a * x + b * y + c;
}

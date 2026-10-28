import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../models/depth_frame.dart';
import '../models/generic_obstacle.dart';
import '../safety/perception/camera_track_association.dart';
import '../services/fall_detector.dart' show MotionState;
import '../utils/depth_hazard.dart';
import '../utils/depth_map_ops.dart';

/// Pure-Dart geometric obstacle detector. No TTS, widgets, singletons, or
/// platform channels. Geometry is the safety authority; YOLO is not an input.
class GenericObstacleDetector {
  GenericObstacleDetector({
    GenericObstacleConfig? config,
    math.Random? rng,
    this.collectOpeningDiagnostics = false,
    this.collectCameraSupport = false,
  }) : config = config ?? GenericObstacleConfig.engineeringDefaults,
       _rng = rng ?? math.Random(7);

  final GenericObstacleConfig config;
  final bool collectCameraSupport;
  final math.Random _rng;
  final math.Random _forwardGroundRng = math.Random(7);
  math.Random? _openingGroundRng;

  /// Enables an extra bounded fit for offline investigation only. It never
  /// changes segmentation, quality, surface authority or unknown risk.
  final bool collectOpeningDiagnostics;

  /// Image-space ground residual history for relative-depth stability.
  final List<double> _groundResidualEma = <double>[];

  GenericObstacleDetectResult detect({
    required DepthFrame? frame,
    required double pitchDeg,
    required double rollDeg,
    required MotionState motion,
    int? imageTimestampUs,
    Uint8List? lumaMap,
  }) {
    if (frame == null) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.noFrame,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }
    if (!frame.alignedToImage) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.unaligned,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }
    if (imageTimestampUs != null &&
        (imageTimestampUs - frame.timestampUs).abs() >
            config.maxImageDepthDeltaUs) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.stale,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }
    if (frame.frameQuality < config.minHealthyFrameQuality) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.lowConfidence,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }
    if (!rollDeg.isFinite || rollDeg.abs() > config.maxSupportedRollDeg) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.unaligned,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }

    final w = frame.width;
    final h = frame.height;
    final n = w * h;
    if (n != frame.values.length) {
      return const GenericObstacleDetectResult(
        observations: <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.degenerate,
        detectorQuality: 0,
        groundConfidence: 0,
      );
    }

    final proximity = Float32List(n);
    final valid = List<bool>.filled(n, false);
    var validCount = 0;
    if (frame.semantics == DepthValueSemantics.metricMeters) {
      final rel = DepthMapOps.metricToRelativeProximity(
        frame.values,
        minM: config.metricMinM,
        maxM: config.metricMaxM,
      );
      for (int i = 0; i < n; i++) {
        final c = frame.confidence01[i];
        final v = rel[i];
        if (c >= config.minPixelConfidence && DepthMapOps.isValid(v)) {
          proximity[i] = v;
          valid[i] = true;
          validCount++;
        } else {
          proximity[i] = double.nan;
        }
      }
    } else {
      for (int i = 0; i < n; i++) {
        final c = frame.confidence01[i];
        final v = frame.values[i];
        if (c >= config.minPixelConfidence && DepthMapOps.isValid(v)) {
          proximity[i] = v;
          valid[i] = true;
          validCount++;
        } else {
          proximity[i] = double.nan;
        }
      }
    }

    final coverage = validCount / n;
    if (coverage < config.minValidCoverage) {
      return GenericObstacleDetectResult(
        observations: const <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.lowCoverage,
        detectorQuality: coverage,
        groundConfidence: 0,
      );
    }

    final corridor = _corridor(w, h, pitchDeg);
    final corridorCoverage = _corridorDepthCoverage(valid, w, h, corridor);
    // Keep the existing wider reference for obstacle segmentation. A local
    // fit can absorb a box/pole into its plane and must not erase that risk.
    final ground = _fitWideImageGround(proximity, valid, w, h, corridor);
    final forwardGround = _fitImageGround(proximity, valid, w, h, corridor);
    if (ground.inlierRatio < config.minGroundInlierRatio ||
        forwardGround.inlierRatio < config.minGroundInlierRatio) {
      return GenericObstacleDetectResult(
        observations: const <GenericObstacleObservation>[],
        rejectReason: ObstacleRejectReason.planeUnreliable,
        detectorQuality: coverage * 0.5,
        groundConfidence: ground.inlierRatio,
      );
    }
    final surfaceEvidence = _surfaceEvidence(
      proximity,
      valid,
      w,
      h,
      corridor,
      forwardGround,
    );
    final occupancy = List<bool>.filled(n, false);
    var wallProbePixels = 0;
    var wallNearPixels = 0;
    var wallNearSum = 0.0;
    var groundDisagreementPixels = 0;

    final groundBandY = (h * 0.72).floor();
    for (int y = corridor.y0; y < corridor.y1; y++) {
      for (int x = corridor.x0; x < corridor.x1; x++) {
        final i = y * w + x;
        if (!valid[i]) continue;
        final p = proximity[i];
        if (y < groundBandY) {
          wallProbePixels++;
          if (p >= config.warningProximity) {
            wallNearPixels++;
            wallNearSum += p;
          }
        }
        final expected = ground.a * y + ground.b * x + ground.c;
        final forwardExpected =
            forwardGround.a * y + forwardGround.b * x + forwardGround.c;
        final nearerThanWideGround = p > expected + config.occupancyMargin;
        final nearerThanForwardGround =
            p > forwardExpected + config.occupancyMargin;
        final nearerThanGround =
            nearerThanWideGround || nearerThanForwardGround;
        if (nearerThanWideGround &&
            !nearerThanForwardGround &&
            p >= config.monitorProximity) {
          groundDisagreementPixels++;
        }
        // Percentile-normalized ground at the bottom of the frame is ~1.0.
        // Do not treat that as an obstacle; require residual or a hanging
        // near surface above the ground band.
        final hangingNear = y < groundBandY && p >= config.criticalProximity;
        if (nearerThanGround || hangingNear) {
          occupancy[i] = true;
        }
      }
    }

    // Overhead lives above the walking-corridor start row.
    for (int y = 0; y < corridor.y0; y++) {
      for (int x = corridor.x0; x < corridor.x1; x++) {
        final i = y * w + x;
        if (!valid[i]) continue;
        final p = proximity[i];
        if (p >= config.warningProximity) {
          occupancy[i] = true;
        }
      }
    }

    // Broad wall: a coherent near surface can be planar, so residuals vs
    // the ground fit are small. Detect it from corridor-wide near coverage
    // rather than requiring a depth jump.
    final wallNearFrac = wallProbePixels == 0
        ? 0.0
        : wallNearPixels / wallProbePixels;
    final wallMeanNear = wallNearPixels == 0
        ? 0.0
        : wallNearSum / wallNearPixels;
    final centeredAperture = _centeredAperture(
      proximity,
      valid,
      corridor,
      groundBandY,
      w,
      // Preserve aperture classification against the wider obstacle reference.
      // A new local floor fit must not reinterpret a wall's depth dropout.
      _surfaceEvidence(proximity, valid, w, h, corridor, ground),
    );

    final components = _connectedComponents(occupancy, w, h);
    final luma = (lumaMap != null && lumaMap.length == n) ? lumaMap : null;
    final observations = <GenericObstacleObservation>[];

    for (final c in components) {
      final obs = _classifyComponent(
        c,
        proximity,
        frame,
        corridor,
        w,
        h,
        luma,
        centeredAperture,
      );
      if (obs != null) observations.add(obs);
    }

    if (!observations.any((o) => o.geometry == ObstacleGeometry.broadSurface) &&
        centeredAperture == null &&
        wallNearFrac >= config.wallCoverageFrac &&
        wallMeanNear >= config.warningProximity) {
      // A full-height wall also occupies the detector's upper band. Do not
      // emit a duplicate "overhead" observation for the same coherent plane.
      observations.removeWhere(
        (o) =>
            o.geometry == ObstacleGeometry.overhead &&
            o.normalizedBounds.center.dx >= corridor.x0 / w &&
            o.normalizedBounds.center.dx <= corridor.x1 / w,
      );
      final croppedBounds = Rect.fromLTRB(
        corridor.x0 / w,
        corridor.y0 / h,
        corridor.x1 / w,
        groundBandY / h,
      );
      final fullBounds = _toFullFrameBounds(
        croppedBounds,
        frame.cropTopFraction,
      );
      observations.add(
        GenericObstacleObservation(
          geometry: ObstacleGeometry.broadSurface,
          zone: _zone(fullBounds.center.dx),
          normalizedBounds: fullBounds,
          corridorOverlap: wallNearFrac,
          confidence: (wallMeanNear * wallNearFrac).clamp(0.0, 1.0),
          relativeProximity: wallMeanNear,
          nearestDistanceM: _nearestMetric(frame, occupancy, w, h),
          source: frame.provider,
          pixelCount: wallNearPixels,
        ),
      );
    }

    final motionScale = motion == MotionState.stationary ? 0.95 : 1.0;
    final quality =
        ((coverage * 0.5 + forwardGround.inlierRatio * 0.5) * motionScale)
            .clamp(0.0, 1.0);
    _groundResidualEma.add(forwardGround.inlierRatio);
    if (_groundResidualEma.length > 8) _groundResidualEma.removeAt(0);

    return GenericObstacleDetectResult(
      observations: observations,
      rejectReason: observations.isEmpty
          ? ObstacleRejectReason.emptyCorridor
          : ObstacleRejectReason.none,
      detectorQuality: quality,
      groundConfidence: forwardGround.inlierRatio,
      surfaceEvidence: surfaceEvidence,
      corridorCoverage: corridorCoverage,
      unknownReasons: <ObstacleUnknownReason>[
        if (centeredAperture != null) ObstacleUnknownReason.unverifiedAperture,
        if (groundDisagreementPixels >= config.minComponentPixels)
          ObstacleUnknownReason.groundModelDisagreement,
      ],
      groundDisagreementPixels: groundDisagreementPixels,
      openingDiagnostics: collectOpeningDiagnostics && centeredAperture != null
          ? _openingDiagnostics(
              proximity,
              valid,
              frame,
              corridor,
              groundBandY,
              centeredAperture,
              ground,
              forwardGround,
            )
          : null,
      unknownProbabilityFloor: math.max(
        centeredAperture == null ? 0 : config.apertureUnknownProbabilityFloor,
        // A nearer component cannot become free space just because the local
        // floor hypothesis includes it. Keep the disagreement explicit until
        // the scene is confirmed; neither surface evidence nor YOLO clears it.
        groundDisagreementPixels >= config.minComponentPixels ? 0.65 : 0,
      ),
    );
  }

  CorridorOpeningDiagnostics _openingDiagnostics(
    Float32List proximity,
    List<bool> valid,
    DepthFrame frame,
    _Corridor corridor,
    int groundBandY,
    ({int startX, int endX}) aperture,
    _GroundFit wideGround,
    _GroundFit forwardGround,
  ) {
    final w = frame.width;
    final h = frame.height;
    final opening = _Corridor(aperture.startX, aperture.endX, corridor.y0, h);
    final ground = _fitImageGround(
      proximity,
      valid,
      w,
      h,
      opening,
      rng: _openingGroundRng ??= math.Random(7),
    );
    final split = corridor.y0 + (groundBandY - corridor.y0) ~/ 2;
    var disagreementPixels = 0;
    for (var y = corridor.y0; y < h; y++) {
      for (var x = opening.x0; x < opening.x1; x++) {
        final i = y * w + x;
        if (!valid[i]) continue;
        final p = proximity[i];
        final wideExpected = wideGround.a * y + wideGround.b * x + wideGround.c;
        final forwardExpected =
            forwardGround.a * y + forwardGround.b * x + forwardGround.c;
        if (p > wideExpected + config.occupancyMargin &&
            p <= forwardExpected + config.occupancyMargin &&
            p >= config.monitorProximity) {
          disagreementPixels++;
        }
      }
    }
    double? nearFraction(int y0, int y1) {
      var near = 0;
      var observed = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = opening.x0; x < opening.x1; x++) {
          final i = y * w + x;
          if (!valid[i]) continue;
          observed++;
          if (proximity[i] >= config.warningProximity) near++;
        }
      }
      return observed == 0 ? null : near / observed;
    }

    return CorridorOpeningDiagnostics(
      normalizedBounds: _toFullFrameBounds(
        Rect.fromLTRB(opening.x0 / w, 0, opening.x1 / w, 1),
        frame.cropTopFraction,
      ),
      depthCoverage: _corridorDepthCoverage(valid, w, h, opening),
      surface: _surfaceEvidence(proximity, valid, w, h, opening, ground),
      groundDisagreementPixels: disagreementPixels,
      upperNearFraction: nearFraction(corridor.y0, split),
      lowerNearFraction: nearFraction(split, groundBandY),
    );
  }

  CorridorDepthCoverage _corridorDepthCoverage(
    List<bool> valid,
    int w,
    int h,
    _Corridor corridor,
  ) {
    final split = ((corridor.y0 + h) / 2).floor();
    var upper = 0;
    var lower = 0;
    for (var y = 0; y < h; y++) {
      for (var x = corridor.x0; x < corridor.x1; x++) {
        if (!valid[y * w + x]) continue;
        if (y < split) {
          upper++;
        } else {
          lower++;
        }
      }
    }
    final width = corridor.x1 - corridor.x0;
    return CorridorDepthCoverage(
      upperObservedFraction: upper / math.max(1, width * split),
      lowerObservedFraction: lower / math.max(1, width * (h - split)),
    );
  }

  CorridorSurfaceEvidence _surfaceEvidence(
    Float32List proximity,
    List<bool> valid,
    int w,
    int h,
    _Corridor corridor,
    _GroundFit ground,
  ) {
    final y0 = ((corridor.y0 + h) / 2).floor();
    final sampleCount = math.max(1, (corridor.x1 - corridor.x0) * (h - y0));
    var observed = 0;
    var inliers = 0;
    final observedRows = <int>{};
    final observedColumns = <int>{};
    for (var y = y0; y < h; y++) {
      for (var x = corridor.x0; x < corridor.x1; x++) {
        final index = y * w + x;
        if (!valid[index]) continue;
        observed++;
        observedRows.add(y);
        observedColumns.add(x);
        final expected = ground.a * y + ground.b * x + ground.c;
        if ((proximity[index] - expected).abs() < 0.12) inliers++;
      }
    }
    if (observed == 0) return CorridorSurfaceEvidence.unavailable;
    final observedFraction = (observed / sampleCount).clamp(0.0, 1.0);
    final continuity = (inliers / observed).clamp(0.0, 1.0);
    final rowCoverage = observedRows.length / math.max(1, h - y0);
    final columnCoverage =
        observedColumns.length / math.max(1, corridor.x1 - corridor.x0);
    final confidence = math.min(
      ground.inlierRatio,
      math.min(rowCoverage, columnCoverage),
    );
    return CorridorSurfaceEvidence(
      observedFraction: observedFraction,
      continuity: continuity,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  /// Detects a structured centre opening inside a near U-shaped surface.
  ///
  /// Missing or far depth in the aperture remains unknown; this helper only
  /// prevents the side posts and lintel from being collapsed into a synthetic
  /// full-width wall. It does not emit free-space evidence.
  ({int startX, int endX})? _centeredAperture(
    Float32List proximity,
    List<bool> valid,
    _Corridor corridor,
    int groundBandY,
    int w,
    CorridorSurfaceEvidence surface,
  ) {
    if (surface.observedFraction < config.apertureMinSurfaceObservedFraction) {
      return null;
    }
    final rowCount = groundBandY - corridor.y0;
    if (rowCount < 8) return null;
    final lowerStartY = corridor.y0 + rowCount ~/ 2;
    final lowerRowCount = groundBandY - lowerStartY;
    final apertureColumns = <bool>[];
    for (var x = corridor.x0; x < corridor.x1; x++) {
      var near = 0;
      var farLower = 0;
      for (var y = corridor.y0; y < groundBandY; y++) {
        final index = y * w + x;
        if (valid[index] && proximity[index] >= config.warningProximity) {
          near++;
        } else if (y >= lowerStartY &&
            valid[index] &&
            proximity[index] < config.warningProximity) {
          farLower++;
        }
      }
      apertureColumns.add(
        near / rowCount <= config.apertureMaxNearColumnFraction &&
            (farLower / lowerRowCount >=
                    config.apertureMinFarLowerColumnFraction ||
                surface.continuity >= config.apertureMinSurfaceContinuity),
      );
    }

    var bestStart = -1;
    var bestEnd = -1;
    var runStart = -1;
    final imageCenter = w / 2;
    for (var i = 0; i <= apertureColumns.length; i++) {
      final open = i < apertureColumns.length && apertureColumns[i];
      if (open && runStart < 0) runStart = i;
      if ((!open || i == apertureColumns.length) && runStart >= 0) {
        final runEnd = i;
        final runCenter = corridor.x0 + (runStart + runEnd) / 2;
        final centered =
            (runCenter - imageCenter).abs() <=
            w * config.apertureCenterToleranceFraction;
        if (centered && runEnd - runStart > bestEnd - bestStart) {
          bestStart = runStart;
          bestEnd = runEnd;
        }
        runStart = -1;
      }
    }
    if (bestStart < 0) return null;
    final apertureWidth = bestEnd - bestStart;
    if (apertureWidth < w * config.apertureMinWidthFraction) return null;

    double flankNearFraction(int start, int end) {
      if (end <= start) return 0;
      var near = 0;
      var total = 0;
      for (var x = start; x < end; x++) {
        for (var y = corridor.y0; y < groundBandY; y++) {
          total++;
          final index = y * w + x;
          if (valid[index] && proximity[index] >= config.warningProximity) {
            near++;
          }
        }
      }
      return total == 0 ? 0 : near / total;
    }

    final left = flankNearFraction(corridor.x0, corridor.x0 + bestStart);
    final right = flankNearFraction(corridor.x0 + bestEnd, corridor.x1);
    if (left < config.apertureMinFlankNearFraction ||
        right < config.apertureMinFlankNearFraction) {
      return null;
    }
    return (startX: corridor.x0 + bestStart, endX: corridor.x0 + bestEnd);
  }

  _Corridor _corridor(int w, int h, double pitchDeg) {
    final half = (config.corridorWidthFrac * w * 0.5);
    final cx = config.corridorCenterX * w;
    final x0 = (cx - half).floor().clamp(0, w - 1);
    final x1 = (cx + half).ceil().clamp(1, w);
    // Pitch high (looking down) → more of the map is ground; start lower.
    final pitch = pitchDeg.isFinite ? pitchDeg : 45.0;
    final t = ((pitch - 20) / 50).clamp(0.0, 1.0);
    final y0 = (h * (0.18 + 0.20 * t)).floor().clamp(0, h - 2);
    return _Corridor(x0, x1, y0, h);
  }

  _GroundFit _fitImageGround(
    Float32List proximity,
    List<bool> valid,
    int w,
    int h,
    _Corridor corridor, {
    math.Random? rng,
  }) {
    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    final yStart = ((corridor.y0 + h) / 2).floor();
    // Spread the bounded 512-point budget across the whole forward ground
    // band. A raster prefix only covers its first rows, and side walls outside
    // the corridor must not become the reference plane for the walking surface.
    final rows = math.min(32, h - yStart);
    final columns = math.min(16, corridor.x1 - corridor.x0);
    for (var row = 0; row < rows; row++) {
      final y = yStart + row * (h - yStart - 1) ~/ math.max(1, rows - 1);
      for (var column = 0; column < columns; column++) {
        final x =
            corridor.x0 +
            column *
                (corridor.x1 - corridor.x0 - 1) ~/
                math.max(1, columns - 1);
        final i = y * w + x;
        if (!valid[i]) continue;
        xs.add(x.toDouble());
        ys.add(y.toDouble());
        zs.add(proximity[i]);
      }
    }
    if (xs.length < 12) {
      return const _GroundFit(0, 0, 0.35, 0);
    }

    return _fitGroundSamples(xs, ys, zs, rng ?? _forwardGroundRng);
  }

  _GroundFit _fitWideImageGround(
    Float32List proximity,
    List<bool> valid,
    int w,
    int h,
    _Corridor corridor,
  ) {
    final xs = <double>[];
    final ys = <double>[];
    final zs = <double>[];
    final yStart = ((corridor.y0 + h) / 2).floor();
    // Preserve the existing segmentation reference and random sequence.
    // Forward surface support is estimated independently above.
    for (var y = yStart; y < h; y += 4) {
      for (var x = 0; x < w; x += 4) {
        final i = y * w + x;
        if (!valid[i]) continue;
        xs.add(x.toDouble());
        ys.add(y.toDouble());
        zs.add(proximity[i]);
        if (xs.length >= 512) break;
      }
      if (xs.length >= 512) break;
    }
    if (xs.length < 12) return const _GroundFit(0, 0, 0.35, 0);
    return _fitGroundSamples(xs, ys, zs, _rng);
  }

  _GroundFit _fitGroundSamples(
    List<double> xs,
    List<double> ys,
    List<double> zs,
    math.Random rng,
  ) {
    var bestInliers = -1;
    var bestA = 0.0;
    var bestB = 0.0;
    var bestC = 0.35;
    for (int iter = 0; iter < config.ransacIters; iter++) {
      final i1 = rng.nextInt(xs.length);
      final i2 = rng.nextInt(xs.length);
      final i3 = rng.nextInt(xs.length);
      final plane = _planeFrom3(
        xs[i1],
        ys[i1],
        zs[i1],
        xs[i2],
        ys[i2],
        zs[i2],
        xs[i3],
        ys[i3],
        zs[i3],
      );
      if (plane == null) continue;
      var inliers = 0;
      for (int j = 0; j < xs.length; j++) {
        final pred = plane.$1 * ys[j] + plane.$2 * xs[j] + plane.$3;
        if ((zs[j] - pred).abs() < 0.12) inliers++;
      }
      if (inliers > bestInliers) {
        bestInliers = inliers;
        bestA = plane.$1;
        bestB = plane.$2;
        bestC = plane.$3;
      }
    }
    final ratio = bestInliers <= 0 ? 0.0 : bestInliers / xs.length;
    return _GroundFit(bestA, bestB, bestC, ratio);
  }

  (double, double, double)? _planeFrom3(
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
    // z = a*y + b*x + c
    final det = (y1 * (x2 - x3) + y2 * (x3 - x1) + y3 * (x1 - x2));
    if (det.abs() < 1e-6) return null;
    // Solve via differences.
    final dy12 = y2 - y1;
    final dy13 = y3 - y1;
    final dx12 = x2 - x1;
    final dx13 = x3 - x1;
    final dz12 = z2 - z1;
    final dz13 = z3 - z1;
    final denom = dy12 * dx13 - dy13 * dx12;
    if (denom.abs() < 1e-6) return null;
    final a = (dz12 * dx13 - dz13 * dx12) / denom;
    final b = (dy12 * dz13 - dy13 * dz12) / denom;
    final c = z1 - a * y1 - b * x1;
    if (![a, b, c].every((v) => v.isFinite)) return null;
    return (a, b, c);
  }

  List<_Comp> _connectedComponents(List<bool> mask, int w, int h) {
    final seen = List<bool>.filled(w * h, false);
    final out = <_Comp>[];
    final qx = List<int>.filled(w * h, 0);
    final qy = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final s = y * w + x;
        if (!mask[s] || seen[s]) continue;
        var qh = 0;
        var qt = 0;
        qx[qt] = x;
        qy[qt] = y;
        qt++;
        seen[s] = true;
        var minX = x, maxX = x, minY = y, maxY = y, count = 0;
        var sumX = 0, sumY = 0;
        final indices = <int>[];
        while (qh < qt) {
          final cx = qx[qh];
          final cy = qy[qh];
          qh++;
          count++;
          indices.add(cy * w + cx);
          sumX += cx;
          sumY += cy;
          if (cx < minX) minX = cx;
          if (cx > maxX) maxX = cx;
          if (cy < minY) minY = cy;
          if (cy > maxY) maxY = cy;
          void tryPush(int nx, int ny) {
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) return;
            final ni = ny * w + nx;
            if (!mask[ni] || seen[ni]) return;
            seen[ni] = true;
            qx[qt] = nx;
            qy[qt] = ny;
            qt++;
          }

          tryPush(cx - 1, cy);
          tryPush(cx + 1, cy);
          tryPush(cx, cy - 1);
          tryPush(cx, cy + 1);
        }
        if (count >= config.thinMinPixels) {
          out.add(
            _Comp(
              minX,
              minY,
              maxX,
              maxY,
              count,
              sumX / count,
              sumY / count,
              indices,
            ),
          );
        }
      }
    }
    return out;
  }

  GenericObstacleObservation? _classifyComponent(
    _Comp c,
    Float32List proximity,
    DepthFrame frame,
    _Corridor corridor,
    int w,
    int h,
    Uint8List? luma,
    ({int startX, int endX})? centeredAperture,
  ) {
    final bw = (c.maxX - c.minX + 1) / w;
    final bh = (c.maxY - c.minY + 1) / h;
    final overlap = _overlapFrac(c, corridor, w, h);
    final inCorridor = _componentInCorridor(c, corridor);
    if (overlap < 0.002 && inCorridor < 0.15 && c.maxY > corridor.y0) {
      return null;
    }

    var proxSum = 0.0;
    var proxN = 0;
    var maxProx = 0.0;
    for (final i in c.indices) {
      final v = proximity[i];
      if (!DepthMapOps.isValid(v)) continue;
      proxSum += v;
      proxN++;
      if (v > maxProx) maxProx = v;
    }
    if (proxN == 0) return null;
    final meanP = proxSum / proxN;
    final croppedBounds = Rect.fromLTRB(
      c.minX / w,
      c.minY / h,
      (c.maxX + 1) / w,
      (c.maxY + 1) / h,
    );
    final fullBounds = _toFullFrameBounds(croppedBounds, frame.cropTopFraction);
    final zone = _zone(fullBounds.center.dx);

    ObstacleGeometry geometry;
    var conf = (meanP * (0.5 + 0.5 * overlap)).clamp(0.0, 1.0);
    final isThin =
        bw <= config.poleMaxWidthFrac &&
        bh >= config.poleMinHeightFrac &&
        inCorridor >= config.poleMinCorridorOverlap;
    final isOverhead =
        c.maxY <= corridor.y0 ||
        (c.maxY / h <= config.overheadMaxRowFrac &&
            c.minY / h <= 0.20 &&
            bh >= 0.08);
    final isLow =
        c.minY / h >= (1.0 - config.lowObstacleMaxHeightFrac) &&
        bh <= config.lowObstacleMaxHeightFrac &&
        !isThin;
    final isBroad =
        overlap >= config.wallCoverageFrac * 0.5 &&
        bw >= 0.25 &&
        c.count >= config.minComponentPixels;

    // A U-shaped doorway frame is one connected component because the
    // lintel joins both posts. Its bounding rectangle covers the centre even
    // though the depth pixels do not. Do not collapse that shape into a
    // synthetic forward wall; the unobserved opening remains unknown and the
    // spatial runtime therefore still stops while moving.
    final spansAperture =
        centeredAperture != null &&
        c.minX < centeredAperture.startX &&
        c.maxX >= centeredAperture.endX;
    if (isBroad && spansAperture) return null;

    // A thin strip joined to the bottom image edge across an observed
    // aperture has no visible lower boundary. It can be perspective ground
    // residual, so it cannot establish a separate low obstacle. The aperture
    // still carries an unknown floor and the moving planner remains stopped.
    final bottomEdgeStrip =
        c.maxY == h - 1 && c.minY / h >= 0.90 && spansAperture;
    if (isLow && bottomEdgeStrip) return null;

    if (isThin) {
      // Thin-pole branch: do not use the broad coverage threshold.
      // Missing or contradictory luma is not positive edge evidence.
      var edgeSupport = false;
      if (luma != null) {
        edgeSupport = _hasVerticalEdge(luma, c, w, h);
      }
      if (!edgeSupport) {
        geometry = ObstacleGeometry.thinVertical;
        return GenericObstacleObservation(
          geometry: geometry,
          zone: zone,
          normalizedBounds: fullBounds,
          corridorOverlap: overlap,
          confidence: conf * 0.5,
          relativeProximity: meanP,
          nearestDistanceM: _compMetric(frame, c, w),
          source: frame.provider,
          pixelCount: c.count,
          cameraSupport: !collectCameraSupport
              ? null
              : CameraComponentSupport(
                  width: w,
                  height: h,
                  cropTopFraction: frame.cropTopFraction,
                  capturedAtUs: frame.timestampUs,
                  indices: c.indices,
                ),
          edgeOnly: true,
        );
      }
      geometry = ObstacleGeometry.thinVertical;
    } else if (isOverhead) {
      geometry = ObstacleGeometry.overhead;
    } else if (isLow) {
      geometry = ObstacleGeometry.lowObstacle;
    } else if (isBroad) {
      geometry = ObstacleGeometry.broadSurface;
    } else if (c.count >= config.minComponentPixels) {
      geometry = ObstacleGeometry.unknown;
    } else {
      return null;
    }

    return GenericObstacleObservation(
      geometry: geometry,
      zone: zone,
      normalizedBounds: fullBounds,
      corridorOverlap: overlap,
      confidence: conf,
      relativeProximity: maxProx,
      nearestDistanceM: _compMetric(frame, c, w),
      source: frame.provider,
      pixelCount: c.count,
      cameraSupport: !collectCameraSupport
          ? null
          : CameraComponentSupport(
              width: w,
              height: h,
              cropTopFraction: frame.cropTopFraction,
              capturedAtUs: frame.timestampUs,
              indices: c.indices,
            ),
    );
  }

  bool _hasVerticalEdge(Uint8List luma, _Comp c, int w, int h) {
    var strong = 0;
    var tested = 0;
    for (int y = c.minY; y <= c.maxY; y += 2) {
      for (int x = math.max(1, c.minX); x <= math.min(w - 2, c.maxX); x += 2) {
        final i = y * w + x;
        final g = (luma[i + 1] - luma[i - 1]).abs();
        tested++;
        if (g >= 18) strong++;
      }
    }
    if (tested == 0) return false;
    return strong / tested >= 0.12;
  }

  double _componentInCorridor(_Comp c, _Corridor corridor) {
    final ix0 = math.max(c.minX, corridor.x0);
    final ix1 = math.min(c.maxX + 1, corridor.x1);
    final iy0 = math.max(c.minY, 0);
    final iy1 = math.min(c.maxY + 1, corridor.y1);
    if (ix1 <= ix0 || iy1 <= iy0) return 0;
    final inter = (ix1 - ix0) * (iy1 - iy0);
    final area = math.max(1, (c.maxX - c.minX + 1) * (c.maxY - c.minY + 1));
    return inter / area;
  }

  double _overlapFrac(_Comp c, _Corridor corridor, int w, int h) {
    final ix0 = math.max(c.minX, corridor.x0);
    final ix1 = math.min(c.maxX + 1, corridor.x1);
    final iy0 = math.max(c.minY, corridor.y0);
    final iy1 = math.min(c.maxY + 1, corridor.y1);
    if (ix1 <= ix0 || iy1 <= iy0) return 0;
    final inter = (ix1 - ix0) * (iy1 - iy0);
    final corridorArea = math.max(
      1,
      (corridor.x1 - corridor.x0) * (corridor.y1 - corridor.y0),
    );
    return inter / corridorArea;
  }

  HazardZone _zone(double nx) {
    if (nx < 0.22) return HazardZone.left;
    if (nx < 0.40) return HazardZone.centerLeft;
    if (nx < 0.60) return HazardZone.center;
    if (nx < 0.78) return HazardZone.centerRight;
    return HazardZone.right;
  }

  Rect _toFullFrameBounds(Rect cropped, double cropTopFraction) {
    final crop = cropTopFraction.clamp(0.0, 0.9);
    final visible = 1.0 - crop;
    return Rect.fromLTRB(
      cropped.left.clamp(0.0, 1.0),
      (crop + cropped.top * visible).clamp(0.0, 1.0),
      cropped.right.clamp(0.0, 1.0),
      (crop + cropped.bottom * visible).clamp(0.0, 1.0),
    );
  }

  double? _nearestMetric(DepthFrame frame, List<bool> occ, int w, int h) {
    if (frame.semantics != DepthValueSemantics.metricMeters) return null;
    var m = double.infinity;
    for (int i = 0; i < occ.length; i++) {
      if (!occ[i]) continue;
      final z = frame.values[i];
      if (z.isFinite && z >= config.metricMinM && z < m) m = z;
    }
    return m.isFinite ? m : null;
  }

  double? _compMetric(DepthFrame frame, _Comp c, int w) {
    if (frame.semantics != DepthValueSemantics.metricMeters) return null;
    var m = double.infinity;
    for (final i in c.indices) {
      final z = frame.values[i];
      if (z.isFinite && z >= config.metricMinM && z < m) m = z;
    }
    return m.isFinite ? m : null;
  }
}

class _Corridor {
  final int x0, x1, y0, y1;
  const _Corridor(this.x0, this.x1, this.y0, this.y1);
}

class _GroundFit {
  final double a, b, c, inlierRatio;
  const _GroundFit(this.a, this.b, this.c, this.inlierRatio);
}

class _Comp {
  final int minX, minY, maxX, maxY, count;
  final double cx, cy;
  final List<int> indices;
  const _Comp(
    this.minX,
    this.minY,
    this.maxX,
    this.maxY,
    this.count,
    this.cx,
    this.cy,
    this.indices,
  );
}

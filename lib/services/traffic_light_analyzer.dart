import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../models/nav_models.dart';

enum TrafficLightKind { pedestrian, vehicle, unknown }

class TrafficLightAnalyzer {
  static const int _stableFramesRequired = 5;
  static const int _mediumStableFramesRequired = 3;
  static const int _fastStableFramesRequired = 2;
  static const int _uncertainFramesRequired = 2;

  
  
  
  
  
  
  
  static const int _greenFastStableFramesFloor = 3;
  static const double _wideAspectPenaltyStart = 1.2;
  static const double _wideAspectPenaltyScale = 0.08;
  static const double _wideAspectPenaltyMax = 0.12;
  static const double _cropHorizontalFraction = 0.18;
  static const double _cropVerticalFraction = 0.12;
  static const double _dominanceMargin = 0.08;

  TrafficLightColor _lastColor = TrafficLightColor.unknown;
  int _stableCount = 0;
  int _unknownCount = 0;
  TrafficLightColor _confirmedColor = TrafficLightColor.unknown;
  double _lastConfidence = 0.0;
  bool _lastLowVisibility = false;
  TrafficLightKind _lastKind = TrafficLightKind.unknown;
  int? _lastTrackId;

  TrafficLightColor get confirmedColor => _confirmedColor;
  double get lastConfidence => _lastConfidence;
  bool get lastLowVisibility => _lastLowVisibility;
  TrafficLightKind get lastKind => _lastKind;

  static TrafficLightKind classifyKindByAspect(int bboxWidth, int bboxHeight) {
    if (bboxWidth <= 0 || bboxHeight <= 0) return TrafficLightKind.unknown;
    final ratio = bboxHeight / bboxWidth;
    if (ratio >= 1.6 && ratio <= 2.4) return TrafficLightKind.pedestrian;
    if (ratio >= 2.6 && ratio <= 3.8) return TrafficLightKind.vehicle;
    return TrafficLightKind.unknown;
  }

  static double shapePenaltyForAspectRatio(double aspectRatio) {
    if (aspectRatio <= _wideAspectPenaltyStart) {
      return 0.0;
    }
    return min(
      _wideAspectPenaltyMax,
      (aspectRatio - _wideAspectPenaltyStart) * _wideAspectPenaltyScale,
    );
  }

  static TrafficLightColor pickDominantColor({
    required double redScore,
    required double yellowScore,
    required double greenScore,
    double minScore = 0.15,
    double dominanceMargin = _dominanceMargin,
  }) {
    var bestColor = TrafficLightColor.red;
    var bestScore = redScore;
    var secondScore = yellowScore >= greenScore ? yellowScore : greenScore;

    if (yellowScore > bestScore) {
      bestColor = TrafficLightColor.yellow;
      bestScore = yellowScore;
      secondScore = redScore >= greenScore ? redScore : greenScore;
    } else if (greenScore > bestScore) {
      bestColor = TrafficLightColor.green;
      bestScore = greenScore;
      secondScore = redScore >= yellowScore ? redScore : yellowScore;
    }

    if (bestScore < minScore || bestScore - secondScore < dominanceMargin) {
      return TrafficLightColor.unknown;
    }
    return bestColor;
  }

  static int stableFramesRequiredForBox({
    required int bboxWidth,
    required int bboxHeight,
    double? confidence,
    
    
    
    
    
    TrafficLightColor candidateColor = TrafficLightColor.unknown,
  }) {
    if (bboxWidth <= 0 || bboxHeight <= 0) {
      return _stableFramesRequired;
    }

    final area = bboxWidth * bboxHeight;
    final aspectPenalty = shapePenaltyForAspectRatio(bboxWidth / bboxHeight);
    var frames = _stableFramesRequired;

    if (bboxHeight >= 90 && area >= 1800 && aspectPenalty <= 0.02) {
      frames = _fastStableFramesRequired;
    } else if (bboxHeight >= 45 && area >= 700 && aspectPenalty <= 0.06) {
      frames = _mediumStableFramesRequired;
    }

    if (confidence != null) {
      if (confidence >= 0.8) {
        frames = max(_fastStableFramesRequired, frames - 2);
      } else if (confidence >= 0.65) {
        frames = max(_fastStableFramesRequired, frames - 1);
      } else if (confidence <= 0.25) {
        frames = min(_stableFramesRequired + 1, frames + 1);
      }
    }

    
    
    
    
    
    
    
    if (candidateColor == TrafficLightColor.green ||
        candidateColor == TrafficLightColor.yellow) {
      frames = max(frames, _greenFastStableFramesFloor);
    }

    return frames;
  }

  TrafficLightColor analyze(
    CameraImage image,
    int bboxX1,
    int bboxY1,
    int bboxX2,
    int bboxY2, {
    int? trackId,
  }) {
    final bboxW = max(1, (bboxX2 - bboxX1).abs());
    final bboxH = max(1, (bboxY2 - bboxY1).abs());

    if (trackId != null && trackId != _lastTrackId) {
      _lastTrackId = trackId;
      _lastColor = TrafficLightColor.unknown;
      _stableCount = 0;
      _unknownCount = 0;
      _confirmedColor = TrafficLightColor.unknown;
    }
    _lastKind = classifyKindByAspect(bboxW, bboxH);

    final observation = _analyzeRegion(image, bboxX1, bboxY1, bboxX2, bboxY2);
    _lastConfidence = observation.confidence;
    _lastLowVisibility = observation.lowVisibility;
    final raw = observation.color;
    
    
    
    
    
    final requiredFrames = stableFramesRequiredForBox(
      bboxWidth: bboxW,
      bboxHeight: bboxH,
      confidence: observation.confidence,
      candidateColor: raw,
    );

    if (raw == TrafficLightColor.unknown) {
      _unknownCount++;
      _stableCount = 0;
      _lastColor = raw;
      if (observation.lowVisibility ||
          _unknownCount >= _uncertainFramesRequired) {
        _confirmedColor = TrafficLightColor.unknown;
      }
      return _confirmedColor;
    }

    _unknownCount = 0;

    if (raw == _lastColor) {
      _stableCount++;
    } else {
      _lastColor = raw;
      _stableCount = 1;
    }

    if (_stableCount >= requiredFrames) {
      _confirmedColor = _lastColor;
    }

    return _confirmedColor;
  }

  void reset() {
    _lastColor = TrafficLightColor.unknown;
    _stableCount = 0;
    _unknownCount = 0;
    _confirmedColor = TrafficLightColor.unknown;
    _lastConfidence = 0.0;
    _lastLowVisibility = false;
    _lastKind = TrafficLightKind.unknown;
    _lastTrackId = null;
  }

  _TrafficLightObservation _analyzeRegion(
    CameraImage image,
    int x1,
    int y1,
    int x2,
    int y2,
  ) {
    if (image.planes.isEmpty) {
      return const _TrafficLightObservation(
        TrafficLightColor.unknown,
        0.0,
        true,
      );
    }

    final imgW = image.width;
    final imgH = image.height;

    final cx1 = x1.clamp(0, imgW - 1);
    final cy1 = y1.clamp(0, imgH - 1);
    final cx2 = x2.clamp(cx1 + 1, imgW);
    final cy2 = y2.clamp(cy1 + 1, imgH);

    final bboxW = cx2 - cx1;
    final bboxH = cy2 - cy1;
    if (bboxW < 4 || bboxH < 9) {
      return const _TrafficLightObservation(
        TrafficLightColor.unknown,
        0.0,
        true,
      );
    }

    final aspectPenalty = shapePenaltyForAspectRatio(bboxW / bboxH);
    final minScore = 0.15 + aspectPenalty * 0.5;
    final dominanceMargin = _dominanceMargin + aspectPenalty * 0.5;

    final cropX = max(1, (bboxW * _cropHorizontalFraction).round());
    final cropY = max(1, (bboxH * _cropVerticalFraction).round());

    final ix1 = min(max(cx1 + cropX, 0), imgW - 1);
    final ix2 = max(min(cx2 - cropX, imgW), ix1 + 1);
    final iy1 = min(max(cy1 + cropY, 0), imgH - 1);
    final iy2 = max(min(cy2 - cropY, imgH), iy1 + 1);

    final innerH = iy2 - iy1;
    if (innerH < 9) {
      return const _TrafficLightObservation(
        TrafficLightColor.unknown,
        0.0,
        true,
      );
    }

    final thirdH = innerH ~/ 3;
    final topY1 = iy1;
    final topY2 = iy1 + thirdH;
    final midY1 = iy1 + thirdH;
    final midY2 = iy1 + thirdH * 2;
    final botY1 = iy1 + thirdH * 2;
    final botY2 = iy2;

    final yPlane = image.planes[0].bytes;
    final uvPlane = image.planes.length > 1 ? image.planes[1].bytes : null;
    final vPlane = image.planes.length > 2 ? image.planes[2].bytes : null;

    final yRowStride = image.planes[0].bytesPerRow;
    final uvRowStride = image.planes.length > 1
        ? image.planes[1].bytesPerRow
        : 0;
    final uvPixelStride = image.planes.length > 1
        ? image.planes[1].bytesPerPixel ?? 1
        : 1;
    final vRowStride = image.planes.length > 2
        ? image.planes[2].bytesPerRow
        : uvRowStride;

    final topBrightRed = _zoneBrightness(
      yPlane,
      uvPlane,
      vPlane,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      ix1,
      topY1,
      ix2,
      topY2,
      imgW,
      _ColorTarget.red,
      vRowStride,
    );
    final midBrightYellow = _zoneBrightness(
      yPlane,
      uvPlane,
      vPlane,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      ix1,
      midY1,
      ix2,
      midY2,
      imgW,
      _ColorTarget.yellow,
      vRowStride,
    );
    final botBrightGreen = _zoneBrightness(
      yPlane,
      uvPlane,
      vPlane,
      yRowStride,
      uvRowStride,
      uvPixelStride,
      ix1,
      botY1,
      ix2,
      botY2,
      imgW,
      _ColorTarget.green,
      vRowStride,
    );

    var color = pickDominantColor(
      redScore: topBrightRed,
      yellowScore: midBrightYellow,
      greenScore: botBrightGreen,
      minScore: minScore,
      dominanceMargin: dominanceMargin,
    );

    var bestScore = topBrightRed;
    var secondScore = midBrightYellow >= botBrightGreen
        ? midBrightYellow
        : botBrightGreen;
    if (midBrightYellow > bestScore) {
      bestScore = midBrightYellow;
      secondScore = topBrightRed >= botBrightGreen
          ? topBrightRed
          : botBrightGreen;
    } else if (botBrightGreen > bestScore) {
      bestScore = botBrightGreen;
      secondScore = topBrightRed >= midBrightYellow
          ? topBrightRed
          : midBrightYellow;
    }

    
    
    
    
    
    
    
    
    
    if (color == TrafficLightColor.green ||
        color == TrafficLightColor.yellow) {
      final pickedScore = color == TrafficLightColor.green
          ? botBrightGreen
          : midBrightYellow;
      if (pickedScore < _kGoColorMatchFloor) {
        color = TrafficLightColor.unknown;
      }
    }

    
    
    
    
    if (color != TrafficLightColor.unknown) {
      final hasLuminousLed = _hasBrightLedZone(
        yPlane,
        yRowStride,
        ix1,
        iy1,
        ix2,
        iy2,
      );
      if (!hasLuminousLed) {
        color = TrafficLightColor.unknown;
      }
    }

    final confidence = color == TrafficLightColor.unknown
        ? bestScore
        : (bestScore * 0.65 + (bestScore - secondScore).clamp(0.0, 1.0) * 0.35)
              .clamp(0.0, 1.0);
    final lowVisibility = bestScore < (minScore + 0.03) || confidence < 0.25;

    return _TrafficLightObservation(color, confidence, lowVisibility);
  }

  
  
  static const double _kGoColorMatchFloor = 0.30;

  
  
  
  
  
  
  static const double _kMinBrightLedFraction = 0.04;

  bool _hasBrightLedZone(
    Uint8List yPlane,
    int yRowStride,
    int x1,
    int y1,
    int x2,
    int y2,
  ) {
    int brightCount = 0;
    int total = 0;
    final step = max(1, ((x2 - x1) * (y2 - y1)) > 400 ? 2 : 1);
    for (int py = y1; py < y2; py += step) {
      for (int px = x1; px < x2; px += step) {
        final idx = py * yRowStride + px;
        if (idx >= yPlane.length) continue;
        total++;
        if (yPlane[idx] >= 200) brightCount++;
      }
    }
    return total > 0 && brightCount / total >= _kMinBrightLedFraction;
  }

  double _zoneBrightness(
    Uint8List yPlane,
    Uint8List? uvPlane,
    Uint8List? vPlane,
    int yRowStride,
    int uvRowStride,
    int uvPixelStride,
    int x1,
    int y1,
    int x2,
    int y2,
    int imgW,
    _ColorTarget target,
    int vRowStride,
  ) {
    if (uvPlane == null) {
      return _zoneBrightnessYOnly(yPlane, yRowStride, x1, y1, x2, y2);
    }

    int matchCount = 0;
    int totalPixels = 0;
    final step = max(1, ((x2 - x1) * (y2 - y1)) > 400 ? 2 : 1);

    for (int py = y1; py < y2; py += step) {
      for (int px = x1; px < x2; px += step) {
        totalPixels++;
        final yIdx = py * yRowStride + px;
        if (yIdx >= yPlane.length) continue;
        final yVal = yPlane[yIdx];

        final uvY = py >> 1;
        final uvX = px >> 1;
        int u, v;

        if (vPlane != null) {
          final uIdx = uvY * uvRowStride + uvX;
          final vIdx = uvY * vRowStride + uvX;
          if (uIdx >= uvPlane.length || vIdx >= vPlane.length) continue;
          u = uvPlane[uIdx];
          v = vPlane[vIdx];
        } else {
          final idx = uvY * uvRowStride + uvX * uvPixelStride;
          if (idx + 1 >= uvPlane.length) continue;
          u = uvPlane[idx];
          v = uvPlane[idx + 1];
        }

        if (_matchesTarget(yVal, u, v, target)) {
          matchCount++;
        }
      }
    }

    return totalPixels > 0 ? matchCount / totalPixels : 0;
  }

  double _zoneBrightnessYOnly(
    Uint8List yPlane,
    int yRowStride,
    int x1,
    int y1,
    int x2,
    int y2,
  ) {
    int brightCount = 0;
    int total = 0;
    for (int y = y1; y < y2; y++) {
      for (int x = x1; x < x2; x++) {
        final idx = y * yRowStride + x;
        if (idx >= yPlane.length) continue;
        total++;
        if (yPlane[idx] > 180) brightCount++;
      }
    }
    return total > 0 ? brightCount / total : 0;
  }

  bool _matchesTarget(int yVal, int u, int v, _ColorTarget target) {
    switch (target) {
      case _ColorTarget.red:
        return yVal > 80 && v > 160 && u < 120 && (v - u) > 50;
      case _ColorTarget.yellow:
        return yVal > 150 && v > 135 && u < 115 && (v - u) > 30;
      case _ColorTarget.green:
        return yVal > 60 && u > 140 && v < 130 && (u - v) > 20;
    }
  }
}

class _TrafficLightObservation {
  final TrafficLightColor color;
  final double confidence;
  final bool lowVisibility;

  const _TrafficLightObservation(
    this.color,
    this.confidence,
    this.lowVisibility,
  );
}

enum _ColorTarget { red, yellow, green }

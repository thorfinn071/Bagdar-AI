import 'dart:math' as math;

import 'package:camera/camera.dart';

enum MotionIntrusionSide { left, center, right }

class MotionIntrusionEvent {
  final MotionIntrusionSide side;
  final double strength;
  final DateTime at;
  const MotionIntrusionEvent({
    required this.side,
    required this.strength,
    required this.at,
  });
}

class MotionPreAlert {
  static const int _gridW = 32;
  static const int _gridH = 24;
  static const int _sectorCols = 10;

  static const double _stripTopFrac = 0.25;
  static const double _stripBotFrac = 0.60;

  static const double _emaAlpha = 0.05;
  static const double _triggerMultiplier = 4.0;
  static const double _absMin = 2.5;

  static const Duration _cooldown = Duration(milliseconds: 1200);

  final List<int> _prevGrid = List<int>.filled(_gridW * _gridH, 0);
  final List<int> _curGrid = List<int>.filled(_gridW * _gridH, 0);
  bool _hasPrev = false;

  double _baseLeft = 0.0;
  double _baseCenter = 0.0;
  double _baseRight = 0.0;
  double _prevLeft = 0.0;
  double _prevRight = 0.0;

  DateTime _lastTriggerAt = DateTime.fromMillisecondsSinceEpoch(0);

  double get baselineLeft => _baseLeft;
  double get baselineRight => _baseRight;
  double get baselineCenter => _baseCenter;

  MotionIntrusionEvent? feed(CameraImage image, DateTime now) {
    if (image.planes.isEmpty) return null;

    _fillGrid(image, _curGrid);

    if (!_hasPrev) {
      _copyCurToPrev();
      _hasPrev = true;
      return null;
    }

    final yStart = (_gridH * _stripTopFrac).toInt();
    final yEnd = (_gridH * _stripBotFrac).toInt();

    double sumL = 0, sumC = 0, sumR = 0;
    int countL = 0, countC = 0, countR = 0;
    for (int y = yStart; y < yEnd; y++) {
      final rowOffset = y * _gridW;
      for (int x = 0; x < _gridW; x++) {
        final idx = rowOffset + x;
        final d = (_curGrid[idx] - _prevGrid[idx]).abs().toDouble();
        if (x < _sectorCols) {
          sumL += d;
          countL++;
        } else if (x >= _gridW - _sectorCols) {
          sumR += d;
          countR++;
        } else {
          sumC += d;
          countC++;
        }
      }
    }

    final dL = countL > 0 ? sumL / countL : 0.0;
    final dC = countC > 0 ? sumC / countC : 0.0;
    final dR = countR > 0 ? sumR / countR : 0.0;

    _baseLeft = _ema(_baseLeft, dL);
    _baseCenter = _ema(_baseCenter, dC);
    _baseRight = _ema(_baseRight, dR);

    MotionIntrusionEvent? out;
    if (now.difference(_lastTriggerAt) >= _cooldown) {
      final thrL = math.max(_baseLeft * _triggerMultiplier, _absMin);
      final thrR = math.max(_baseRight * _triggerMultiplier, _absMin);
      final triggeredLeft = dL > thrL && dL > _prevLeft;
      final triggeredRight = dR > thrR && dR > _prevRight;

      if (triggeredLeft && triggeredRight) {
        out = MotionIntrusionEvent(
          side: MotionIntrusionSide.center,
          strength: _strength(
            math.max(dL, dR),
            math.max(_baseLeft, _baseRight),
          ),
          at: now,
        );
      } else if (triggeredLeft) {
        out = MotionIntrusionEvent(
          side: MotionIntrusionSide.left,
          strength: _strength(dL, _baseLeft),
          at: now,
        );
      } else if (triggeredRight) {
        out = MotionIntrusionEvent(
          side: MotionIntrusionSide.right,
          strength: _strength(dR, _baseRight),
          at: now,
        );
      }

      if (out != null) _lastTriggerAt = now;
    }

    _prevLeft = dL;
    _prevRight = dR;
    _copyCurToPrev();

    return out;
  }

  void reset() {
    _hasPrev = false;
    _baseLeft = 0;
    _baseCenter = 0;
    _baseRight = 0;
    _prevLeft = 0;
    _prevRight = 0;
    _lastTriggerAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  static double _ema(double prev, double next) =>
      prev == 0 ? next : prev * (1.0 - _emaAlpha) + next * _emaAlpha;

  static double _strength(double delta, double baseline) {
    if (baseline <= 0) return 1.0;
    final ratio = delta / baseline;
    return (ratio / 12.0).clamp(0.0, 1.0);
  }

  void _copyCurToPrev() {
    for (int i = 0; i < _curGrid.length; i++) {
      _prevGrid[i] = _curGrid[i];
    }
  }

  void _fillGrid(CameraImage image, List<int> out) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final w = image.width;
    final h = image.height;
    final binW = w / _gridW;
    final binH = h / _gridH;

    for (int gy = 0; gy < _gridH; gy++) {
      final srcY = (gy * binH + binH / 2).toInt().clamp(0, h - 1);
      final rowStart = srcY * stride;
      for (int gx = 0; gx < _gridW; gx++) {
        final srcX = (gx * binW + binW / 2).toInt().clamp(0, w - 1);
        out[gy * _gridW + gx] = bytes[rowStart + srcX] & 0xFF;
      }
    }
  }

  static MotionIntrusionEvent? analyzeLumaGrids({
    required List<int> prevGrid,
    required List<int> curGrid,
    required int gridW,
    required int gridH,
    required DateTime now,
    int sectorCols = 10,
    double stripTopFrac = 0.25,
    double stripBotFrac = 0.60,
    double prevLeftDelta = 0.0,
    double prevRightDelta = 0.0,
    double baselineLeft = 0.0,
    double baselineRight = 0.0,
    double triggerMultiplier = _triggerMultiplier,
    double absMin = _absMin,
  }) {
    final yStart = (gridH * stripTopFrac).toInt();
    final yEnd = (gridH * stripBotFrac).toInt();

    double sumL = 0, sumR = 0;
    int countL = 0, countR = 0;
    for (int y = yStart; y < yEnd; y++) {
      final rowOffset = y * gridW;
      for (int x = 0; x < gridW; x++) {
        final idx = rowOffset + x;
        final d = (curGrid[idx] - prevGrid[idx]).abs().toDouble();
        if (x < sectorCols) {
          sumL += d;
          countL++;
        } else if (x >= gridW - sectorCols) {
          sumR += d;
          countR++;
        }
      }
    }
    final dL = countL > 0 ? sumL / countL : 0.0;
    final dR = countR > 0 ? sumR / countR : 0.0;

    final thrL = math.max(baselineLeft * triggerMultiplier, absMin);
    final thrR = math.max(baselineRight * triggerMultiplier, absMin);
    final triggeredLeft = dL > thrL && dL > prevLeftDelta;
    final triggeredRight = dR > thrR && dR > prevRightDelta;

    if (!triggeredLeft && !triggeredRight) return null;
    if (triggeredLeft && triggeredRight) {
      return MotionIntrusionEvent(
        side: MotionIntrusionSide.center,
        strength: _strength(
          math.max(dL, dR),
          math.max(baselineLeft, baselineRight),
        ),
        at: now,
      );
    }
    if (triggeredLeft) {
      return MotionIntrusionEvent(
        side: MotionIntrusionSide.left,
        strength: _strength(dL, baselineLeft),
        at: now,
      );
    }
    return MotionIntrusionEvent(
      side: MotionIntrusionSide.right,
      strength: _strength(dR, baselineRight),
      at: now,
    );
  }
}

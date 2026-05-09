import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/constants.dart';

enum MotionIntrusionSide { left, center, right }

enum MotionEventClass { unknown, noise, vehicleLike, personLike }

class MotionIntrusionEvent {
  final MotionIntrusionSide side;
  final double strength;
  final DateTime at;
  final MotionEventClass classGuess;
  final double vxPxS;
  final double vyPxS;
  final bool isCritical;
  const MotionIntrusionEvent({
    required this.side,
    required this.strength,
    required this.at,
    this.classGuess = MotionEventClass.unknown,
    this.vxPxS = 0.0,
    this.vyPxS = 0.0,
    this.isCritical = false,
  });
}

class MotionPreAlert {
  static const double _triggerMultiplier = 6.0;
  static const double _absMin = 3.5;

  
  
  
  
  
  
  
  
  
  static const int _weatherDegradedMinPersistFrames = 5;
  static const int _weatherDegradedPersonMinPersistFrames = 6;

  bool _weatherDegradedHint = false;

  Uint8List _grid = Uint8List(kEventGridW * kEventGridH);
  Uint8List _prev = Uint8List(kEventGridW * kEventGridH);
  late final Float32List _base = Float32List(kEventGridW * kEventGridH);
  late final Uint8List _events = Uint8List(kEventGridW * kEventGridH);
  late final Int32List _labels = Int32List(kEventGridW * kEventGridH);
  late final Int32List _ufParent = Int32List(kEventMaxLabels);
  late final Int32List _accCount = Int32List(kEventMaxLabels);
  late final Int32List _accSumX = Int32List(kEventMaxLabels);
  late final Int32List _accSumY = Int32List(kEventMaxLabels);
  late final Int32List _accMinX = Int32List(kEventMaxLabels);
  late final Int32List _accMinY = Int32List(kEventMaxLabels);
  late final Int32List _accMaxX = Int32List(kEventMaxLabels);
  late final Int32List _accMaxY = Int32List(kEventMaxLabels);

  List<_Blob> _blobsCur =
      List<_Blob>.generate(kEventMaxBlobsPerFrame, (_) => _Blob());
  List<_Blob> _blobsPrev =
      List<_Blob>.generate(kEventMaxBlobsPerFrame, (_) => _Blob());
  int _blobsCurCount = 0;
  int _blobsPrevCount = 0;

  bool _hasPrev = false;
  DateTime _prevFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSoftAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _nextBlobId = 1;

  double get baselineLeft => 0.0;
  double get baselineCenter => 0.0;
  double get baselineRight => 0.0;

  bool _indoorHint = false;

  MotionIntrusionEvent? feed(
    CameraImage image,
    DateTime now, {
    bool weatherDegraded = false,
    bool aeTransitioning = false,
    bool indoor = false,
  }) {
    if (image.planes.isEmpty) return null;
    if (aeTransitioning) return null;
    _weatherDegradedHint = weatherDegraded;
    _indoorHint = indoor;
    _downsampleImage(image);
    return _processFrame(now);
  }

  @visibleForTesting
  MotionIntrusionEvent? feedDownsampledGrid(
    Uint8List grid,
    DateTime now, {
    bool weatherDegraded = false,
    bool aeTransitioning = false,
  }) {
    if (grid.length != kEventGridW * kEventGridH) return null;
    if (aeTransitioning) return null;
    _weatherDegradedHint = weatherDegraded;
    _grid.setAll(0, grid);
    return _processFrame(now);
  }

  void reset() {
    _hasPrev = false;
    _blobsCurCount = 0;
    _blobsPrevCount = 0;
    _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSoftAt = DateTime.fromMillisecondsSinceEpoch(0);
    const n = kEventGridW * kEventGridH;
    for (int i = 0; i < n; i++) {
      _grid[i] = 0;
      _prev[i] = 0;
      _base[i] = 0;
      _events[i] = 0;
      _labels[i] = 0;
    }
  }

  MotionIntrusionEvent? _processFrame(DateTime now) {
    if (!_hasPrev) {
      _hasPrev = true;
      _prevFrameAt = now;
      _swapGrid();
      return null;
    }

    
    
    
    
    
    final indoorScale = _indoorHint ? 1.4 : 1.0;
    final diffThreshold = _weatherDegradedHint
        ? kEventDiffThreshold * 1.6 * indoorScale
        : kEventDiffThreshold.toDouble() * indoorScale;
    final baselineMult = _weatherDegradedHint
        ? kEventBaselineMultiplier * 1.5 * indoorScale
        : kEventBaselineMultiplier * indoorScale;
    const n = kEventGridW * kEventGridH;
    int eventTotal = 0;
    for (int i = 0; i < n; i++) {
      final d = (_grid[i] - _prev[i]).abs();
      final base = _base[i];
      final newBase = base * (1.0 - kEventBaselineEmaAlpha) +
          d * kEventBaselineEmaAlpha;
      _base[i] = newBase;
      final fired =
          (d > diffThreshold && d > newBase * baselineMult) ? 1 : 0;
      _events[i] = fired;
      eventTotal += fired;
    }

    if (eventTotal > n * kEventGlobalPanFrac) {
      _blobsCurCount = 0;
      _swapGrid();
      _swapBlobs();
      _prevFrameAt = now;
      return null;
    }

    final labelCount = _connectedComponents();
    _extractBlobs(labelCount);
    final dtSec = now.difference(_prevFrameAt).inMicroseconds / 1e6;
    if (dtSec > 0) _matchAndComputeVelocity(dtSec);

    final top = _pickTopBlob();
    MotionIntrusionEvent? out;
    if (top != null) out = _classifyAndEmit(top, now);

    _swapGrid();
    _swapBlobs();
    _prevFrameAt = now;
    return out;
  }

  void _swapGrid() {
    final tmp = _grid;
    _grid = _prev;
    _prev = tmp;
  }

  void _swapBlobs() {
    final tmp = _blobsCur;
    _blobsCur = _blobsPrev;
    _blobsPrev = tmp;
    _blobsPrevCount = _blobsCurCount;
    _blobsCurCount = 0;
  }

  void _downsampleImage(CameraImage image) {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    final stride = plane.bytesPerRow;
    final w = image.width;
    final h = image.height;
    final binW = w / kEventGridW;
    final binH = h / kEventGridH;
    for (int gy = 0; gy < kEventGridH; gy++) {
      final srcY = (gy * binH + binH / 2).toInt().clamp(0, h - 1);
      final rowStart = srcY * stride;
      for (int gx = 0; gx < kEventGridW; gx++) {
        final srcX = (gx * binW + binW / 2).toInt().clamp(0, w - 1);
        _grid[gy * kEventGridW + gx] = bytes[rowStart + srcX] & 0xFF;
      }
    }
  }

  int _connectedComponents() {
    const n = kEventGridW * kEventGridH;
    for (int i = 0; i < n; i++) {
      _labels[i] = 0;
    }
    for (int i = 0; i < kEventMaxLabels; i++) {
      _ufParent[i] = i;
    }
    int nextLabel = 1;
    for (int y = 0; y < kEventGridH; y++) {
      final rowOff = y * kEventGridW;
      for (int x = 0; x < kEventGridW; x++) {
        final idx = rowOff + x;
        if (_events[idx] == 0) continue;
        final left = (x > 0) ? _labels[idx - 1] : 0;
        final top = (y > 0) ? _labels[idx - kEventGridW] : 0;
        if (left == 0 && top == 0) {
          if (nextLabel >= kEventMaxLabels) continue;
          _labels[idx] = nextLabel;
          nextLabel++;
        } else if (left != 0 && top == 0) {
          _labels[idx] = _ufFind(left);
        } else if (left == 0 && top != 0) {
          _labels[idx] = _ufFind(top);
        } else {
          final l = _ufFind(left);
          final t = _ufFind(top);
          if (l == t) {
            _labels[idx] = l;
          } else {
            final lo = l < t ? l : t;
            final hi = l < t ? t : l;
            _ufParent[hi] = lo;
            _labels[idx] = lo;
          }
        }
      }
    }
    return nextLabel;
  }

  int _ufFind(int label) {
    int root = label;
    while (_ufParent[root] != root) {
      root = _ufParent[root];
    }
    int cur = label;
    while (_ufParent[cur] != root) {
      final nxt = _ufParent[cur];
      _ufParent[cur] = root;
      cur = nxt;
    }
    return root;
  }

  void _extractBlobs(int labelCount) {
    _blobsCurCount = 0;
    if (labelCount <= 1) return;

    for (int i = 0; i < labelCount; i++) {
      _accCount[i] = 0;
      _accSumX[i] = 0;
      _accSumY[i] = 0;
      _accMinX[i] = kEventGridW;
      _accMinY[i] = kEventGridH;
      _accMaxX[i] = -1;
      _accMaxY[i] = -1;
    }

    for (int y = 0; y < kEventGridH; y++) {
      final rowOff = y * kEventGridW;
      for (int x = 0; x < kEventGridW; x++) {
        final lbl = _labels[rowOff + x];
        if (lbl == 0) continue;
        final root = _ufFind(lbl);
        _accCount[root]++;
        _accSumX[root] += x;
        _accSumY[root] += y;
        if (x < _accMinX[root]) _accMinX[root] = x;
        if (y < _accMinY[root]) _accMinY[root] = y;
        if (x > _accMaxX[root]) _accMaxX[root] = x;
        if (y > _accMaxY[root]) _accMaxY[root] = y;
      }
    }

    final maxAreaPx =
        (kEventMaxBlobAreaFrac * kEventGridW * kEventGridH).toInt();
    for (int r = 1;
        r < labelCount && _blobsCurCount < kEventMaxBlobsPerFrame;
        r++) {
      final c = _accCount[r];
      if (c < kEventMinBlobArea) continue;
      if (c > maxAreaPx) continue;
      final b = _blobsCur[_blobsCurCount];
      b.cx = _accSumX[r] / c;
      b.cy = _accSumY[r] / c;
      b.minX = _accMinX[r];
      b.minY = _accMinY[r];
      b.maxX = _accMaxX[r];
      b.maxY = _accMaxY[r];
      b.area = c;
      b.persistFrames = 1;
      b.vx = 0;
      b.vy = 0;
      b.areaGrowRate = 0;
      b.id = 0;
      _blobsCurCount++;
    }
  }

  void _matchAndComputeVelocity(double dtSec) {
    const r2 = kEventMatchRadiusPx * kEventMatchRadiusPx;
    for (int i = 0; i < _blobsCurCount; i++) {
      final cur = _blobsCur[i];
      double bestD2 = double.infinity;
      int bestJ = -1;
      for (int j = 0; j < _blobsPrevCount; j++) {
        final p = _blobsPrev[j];
        final dx = cur.cx - p.cx;
        final dy = cur.cy - p.cy;
        final d2 = dx * dx + dy * dy;
        if (d2 < bestD2) {
          bestD2 = d2;
          bestJ = j;
        }
      }
      if (bestJ >= 0 && bestD2 <= r2) {
        final p = _blobsPrev[bestJ];
        cur.vx = (cur.cx - p.cx) / dtSec;
        cur.vy = (cur.cy - p.cy) / dtSec;
        cur.persistFrames = p.persistFrames + 1;
        cur.id = p.id != 0 ? p.id : _claimBlobId();
        if (p.area > 0) {
          cur.areaGrowRate = (cur.area - p.area) / p.area / dtSec;
        }
      } else {
        cur.id = _claimBlobId();
      }
    }
  }

  int _claimBlobId() {
    final id = _nextBlobId;
    _nextBlobId++;
    if (_nextBlobId > 1 << 28) _nextBlobId = 1;
    return id;
  }

  _Blob? _pickTopBlob() {
    _Blob? best;
    double bestScore = 0;
    const invSize = 1.0 / (kEventGridW * kEventGridH);
    for (int i = 0; i < _blobsCurCount; i++) {
      final b = _blobsCur[i];
      final v = math.sqrt(b.vx * b.vx + b.vy * b.vy);
      final areaFrac = b.area * invSize;
      final score = b.persistFrames * v * areaFrac;
      if (score > bestScore) {
        bestScore = score;
        best = b;
      }
    }
    return best;
  }

  MotionIntrusionEvent? _classifyAndEmit(_Blob b, DateTime now) {
    final v = math.sqrt(b.vx * b.vx + b.vy * b.vy);
    final boxW = (b.maxX - b.minX + 1).toDouble();
    final boxH = (b.maxY - b.minY + 1).toDouble();
    final aspect = boxH > 0 ? boxW / boxH : 0.0;
    final cyFrac = b.cy / kEventGridH;
    final cxFrac = b.cx / kEventGridW;

    
    
    
    final vehiclePersistThreshold = _weatherDegradedHint
        ? _weatherDegradedMinPersistFrames
        : kEventMinPersistFrames;
    final personPersistThreshold = _weatherDegradedHint
        ? _weatherDegradedPersonMinPersistFrames
        : kEventPersonMinPersistFrames;

    MotionEventClass cls = MotionEventClass.noise;
    if (b.persistFrames >= vehiclePersistThreshold &&
        v >= kEventVehicleVxPxS &&
        aspect >= kEventVehicleAspectMin &&
        cyFrac >= kEventVehicleCyFracLo &&
        cyFrac <= kEventVehicleCyFracHi) {
      cls = MotionEventClass.vehicleLike;
    } else if (b.persistFrames >= personPersistThreshold &&
        aspect < kEventPersonAspectMax &&
        cyFrac >= kEventPersonCyFracLo &&
        cyFrac <= kEventPersonCyFracHi) {
      cls = MotionEventClass.personLike;
    }

    if (cls == MotionEventClass.noise) return null;

    final MotionIntrusionSide side;
    if (cxFrac < 0.33) {
      side = MotionIntrusionSide.left;
    } else if (cxFrac > 0.67) {
      side = MotionIntrusionSide.right;
    } else {
      side = MotionIntrusionSide.center;
    }
    final strength = (v / kEventCriticalVxPxS).clamp(0.0, 1.0);

    final isCritical = cls == MotionEventClass.vehicleLike &&
        v >= kEventCriticalVxPxS &&
        cxFrac >= kEventCriticalCenterFracLo &&
        cxFrac <= kEventCriticalCenterFracHi &&
        b.areaGrowRate > 0 &&
        now.difference(_lastCriticalAt) >= kEventCriticalCooldown;

    if (!isCritical &&
        now.difference(_lastSoftAt) < kEventSoftCooldown) {
      return null;
    }

    if (isCritical) {
      _lastCriticalAt = now;
    } else {
      _lastSoftAt = now;
    }

    return MotionIntrusionEvent(
      side: side,
      strength: strength,
      at: now,
      classGuess: cls,
      vxPxS: b.vx,
      vyPxS: b.vy,
      isCritical: isCritical,
    );
  }

  static double _strength(double delta, double baseline) {
    if (baseline <= 0) return 1.0;
    final ratio = delta / baseline;
    return (ratio / 12.0).clamp(0.0, 1.0);
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

class _Blob {
  int id = 0;
  double cx = 0;
  double cy = 0;
  int minX = 0;
  int minY = 0;
  int maxX = 0;
  int maxY = 0;
  int area = 0;
  int persistFrames = 0;
  double vx = 0;
  double vy = 0;
  double areaGrowRate = 0;
}

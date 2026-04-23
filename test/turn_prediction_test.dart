import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/tracker/raw_det.dart';
import 'package:bagdar/tracker/tracker.dart';

RawDet _box({
  required double cx,
  required double cy,
  required double w,
  required double h,
  required String label,
  double conf = 0.8,
  double distM = 0.0,
  String dist = 'far',
}) {
  final x1 = cx - w / 2;
  final y1 = cy - h / 2;
  final x2 = cx + w / 2;
  final y2 = cy + h / 2;
  return RawDet(
    label: label,
    x1: x1,
    y1: y1,
    x2: x2,
    y2: y2,
    cx: cx,
    cy: cy,
    conf: conf,
    dist: dist,
    distM: distM,
  );
}

RawDet _approachF0(String label, double distM) =>
    _box(cx: 220, cy: 220, w: 40, h: 40, label: label, distM: distM);
RawDet _approachF1(String label, double distM) =>
    _box(cx: 240, cy: 240, w: 160, h: 60, label: label, distM: distM);
RawDet _approachF2Turning(String label, double distM) =>
    _box(cx: 210, cy: 280, w: 400, h: 80, label: label, distM: distM);
RawDet _approachF2Straight(String label, double distM) =>

    _box(cx: 260, cy: 260, w: 400, h: 80, label: label, distM: distM);

void main() {

  group('OPT-17 Turn classification', () {
    test('straight-line motion leaves turning=false and angular velocity ≈ 0',
        () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update(
        [_box(cx: 220, cy: 220, w: 40, h: 40, label: 'car')],
        640,
        480,
        base,
      );
      tr.update(
        [_box(cx: 240, cy: 240, w: 60, h: 60, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_box(cx: 260, cy: 260, w: 80, h: 80, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isFalse);
      expect(
        out.single.lastAngularVelocity.abs(),
        lessThan(kVehTurnAngVelThreshold),
      );
    });

    test('sharp counter-clockwise turn sets turning=true with positive '
        'angular velocity (image coords, y-down)', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update(
        [_box(cx: 220, cy: 220, w: 40, h: 40, label: 'car')],
        640,
        480,
        base,
      );
      tr.update(
        [_box(cx: 240, cy: 240, w: 80, h: 80, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_box(cx: 210, cy: 280, w: 160, h: 160, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isTrue);
      expect(
        out.single.lastAngularVelocity,
        greaterThan(kVehTurnAngVelThreshold),
      );
    });

    test('sharp clockwise turn sets turning=true with negative angular '
        'velocity — sign preserves left/right distinction downstream', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update(
        [_box(cx: 220, cy: 220, w: 40, h: 40, label: 'car')],
        640,
        480,
        base,
      );
      tr.update(
        [_box(cx: 240, cy: 240, w: 80, h: 80, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_box(cx: 280, cy: 210, w: 160, h: 160, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isTrue);
      expect(
        out.single.lastAngularVelocity,
        lessThan(-kVehTurnAngVelThreshold),
      );
    });

    test('two-frame history is not enough — turning stays false until the '
        'third sample is accumulated', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update(
        [_box(cx: 220, cy: 220, w: 40, h: 40, label: 'car')],
        640,
        480,
        base,
      );
      final afterTwo = tr.update(
        [_box(cx: 240, cy: 240, w: 60, h: 60, label: 'car')],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      expect(afterTwo, hasLength(1));
      expect(
        afterTwo.single.turning,
        isFalse,
        reason: 'centerHist has only 2 samples; curvature is undefined',
      );
      expect(afterTwo.single.lastAngularVelocity, 0.0);
    });
  });

  group('OPT-17 approaching boost for turning vehicles', () {
    test('turning car at 4.5 m flips approaching=true even when areaRate '
        'sits under the default vehicle gate (0.22)', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update([_approachF0('car', 4.5)], 640, 480, base);
      tr.update(
        [_approachF1('car', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_approachF2Turning('car', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isTrue);
      expect(
        out.single.approaching,
        isTrue,
        reason: 'turning vehicle at 4.5 m — OPT-17 must drop the gate to '
            'pedestrian thresholds',
      );
    });

    test('straight car with the SAME area growth does NOT fire approaching — '
        'pins OPT-17 as the root cause of the flip', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update([_approachF0('car', 4.5)], 640, 480, base);
      tr.update(
        [_approachF1('car', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_approachF2Straight('car', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isFalse);
      expect(
        out.single.approaching,
        isFalse,
        reason: 'baseline: straight trajectory at 4.5 m keeps the vehicle '
            'gate at the default 0.22',
      );
    });

    test('turning car at 8 m (beyond kVehTurnDistThreshold = 5 m) does NOT '
        'get the approach boost', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update([_approachF0('car', 8.0)], 640, 480, base);
      tr.update(
        [_approachF1('car', 8.0)],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_approachF2Turning('car', 8.0)],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(
        out.single.turning,
        isTrue,
        reason: 'turn geometry is identical to the 4.5 m case',
      );
      expect(
        out.single.approaching,
        isFalse,
        reason: 'distM > kVehTurnDistThreshold — turning must not boost',
      );
    });

    test('turning non-vehicle label (skateboard) never gets the vehicle '
        'approach boost — OPT-17 is vehicle-scoped', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update([_approachF0('skateboard', 4.5)], 640, 480, base);
      tr.update(
        [_approachF1('skateboard', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_approachF2Turning('skateboard', 4.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(
        out.single.turning,
        isTrue,
        reason: 'turn classification is label-agnostic (pure geometry)',
      );
      expect(
        out.single.approaching,
        isFalse,
        reason: 'skateboard is neither vehicle nor pedestrian — neither '
            'branch of the approach gate runs',
      );
    });

    test('turning vehicle at 3.5 m (inside OPT-19 close-range AND OPT-17 '
        'turn-range) still fires approaching — the two optimizations '
        'compose without double-counting', () {
      final tr = Tracker();
      final base = DateTime(2025, 1, 1, 12);
      tr.update([_approachF0('car', 3.5)], 640, 480, base);
      tr.update(
        [_approachF1('car', 3.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 200)),
      );
      final out = tr.update(
        [_approachF2Turning('car', 3.5)],
        640,
        480,
        base.add(const Duration(milliseconds: 700)),
      );

      expect(out, hasLength(1));
      expect(out.single.turning, isTrue);
      expect(out.single.approaching, isTrue);
    });
  });
}

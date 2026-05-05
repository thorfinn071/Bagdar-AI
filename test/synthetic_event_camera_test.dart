import 'dart:typed_data';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/motion_prealert.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _uniformGrid(int value) {
  const n = kEventGridW * kEventGridH;
  final g = Uint8List(n);
  for (int i = 0; i < n; i++) {
    g[i] = value;
  }
  return g;
}

Uint8List _gridWithRect({
  required int baseValue,
  required int rectValue,
  required int x0,
  required int y0,
  required int w,
  required int h,
}) {
  final grid = _uniformGrid(baseValue);
  for (int y = y0; y < y0 + h && y < kEventGridH; y++) {
    for (int x = x0; x < x0 + w && x < kEventGridW; x++) {
      grid[y * kEventGridW + x] = rectValue;
    }
  }
  return grid;
}

void main() {
  group('MotionPreAlert synthetic event camera', () {
    test('first frame returns null (warm-up)', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      final ev = pa.feedDownsampledGrid(_uniformGrid(50), t0);
      expect(ev, isNull);
    });

    test('static frames produce no event', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      pa.feedDownsampledGrid(_uniformGrid(50), t0);
      for (int i = 1; i < 6; i++) {
        final ev = pa.feedDownsampledGrid(
          _uniformGrid(50),
          t0.add(Duration(milliseconds: 20 * i)),
        );
        expect(ev, isNull, reason: 'frame $i');
      }
    });

    test('global luma shift suppressed by panning guard', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      pa.feedDownsampledGrid(_uniformGrid(50), t0);
      final ev = pa.feedDownsampledGrid(
        _uniformGrid(200),
        t0.add(const Duration(milliseconds: 20)),
      );
      expect(ev, isNull);
    });

    test('single-frame flash does not fire critical', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      pa.feedDownsampledGrid(_uniformGrid(50), t0);
      final ev1 = pa.feedDownsampledGrid(
        _gridWithRect(
          baseValue: 50,
          rectValue: 200,
          x0: 30,
          y0: 22,
          w: 10,
          h: 4,
        ),
        t0.add(const Duration(milliseconds: 20)),
      );
      expect(ev1?.isCritical ?? false, isFalse);
      final ev2 = pa.feedDownsampledGrid(
        _uniformGrid(50),
        t0.add(const Duration(milliseconds: 40)),
      );
      expect(ev2?.isCritical ?? false, isFalse);
    });

    test('fast horizontal growing blob fires critical at persist >= 3', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      pa.feedDownsampledGrid(_uniformGrid(50), t0);

      final widths = [8, 18, 30, 42];
      MotionIntrusionEvent? critical;
      for (int i = 0; i < widths.length; i++) {
        final w = widths[i];
        final grid = _gridWithRect(
          baseValue: 50,
          rectValue: 200,
          x0: 20,
          y0: 22,
          w: w,
          h: 4,
        );
        final ev = pa.feedDownsampledGrid(
          grid,
          t0.add(Duration(milliseconds: 20 * (i + 1))),
        );
        if (ev?.isCritical == true) {
          critical = ev;
          break;
        }
      }
      expect(critical, isNotNull);
      expect(critical!.classGuess, MotionEventClass.vehicleLike);
      expect(critical.isCritical, isTrue);
      expect(critical.vxPxS, greaterThanOrEqualTo(kEventCriticalVxPxS));
    });

    test('slow vertical thin blob is personLike, not critical', () {
      final pa = MotionPreAlert();
      final t0 = DateTime(2025, 1, 1, 12);
      pa.feedDownsampledGrid(_uniformGrid(50), t0);

      MotionIntrusionEvent? person;
      for (int i = 0; i < 6; i++) {
        final col = 30 + i;
        final grid = _gridWithRect(
          baseValue: 50,
          rectValue: 200,
          x0: col,
          y0: 30,
          w: 1,
          h: 10,
        );
        final ev = pa.feedDownsampledGrid(
          grid,
          t0.add(Duration(milliseconds: 100 * (i + 1))),
        );
        if (ev?.classGuess == MotionEventClass.personLike) {
          person = ev;
          break;
        }
      }
      expect(person, isNotNull);
      expect(person!.classGuess, MotionEventClass.personLike);
      expect(person.isCritical, isFalse);
    });

    test('extended event fields default safely on legacy constructor', () {
      final ev = MotionIntrusionEvent(
        side: MotionIntrusionSide.left,
        strength: 0.5,
        at: DateTime(2025, 1, 1),
      );
      expect(ev.classGuess, MotionEventClass.unknown);
      expect(ev.vxPxS, 0.0);
      expect(ev.vyPxS, 0.0);
      expect(ev.isCritical, isFalse);
    });
  });
}

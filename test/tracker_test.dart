import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/tracker/kalman_box_tracker.dart';
import 'package:bagdar/tracker/raw_det.dart';
import 'package:bagdar/tracker/tracker.dart';

RawDet makeDet({
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required String label,
  double conf = 0.9,
  String dist = 'far',
  double distM = 0.0,
}) {
  final cx = (x1 + x2) / 2.0;
  final cy = (y1 + y2) / 2.0;
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

void main() {
  group('Tracker matching', () {
    test('matches a near non-overlapping detection to the same track', () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      final first = tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 150,
            y2: 220,
            label: 'person',
          ),
        ],
        640,
        480,
        now,
      );
      expect(first, isEmpty);

      final second = tracker.update(
        [
          makeDet(
            x1: 150,
            y1: 100,
            x2: 200,
            y2: 220,
            label: 'person',
          ),
        ],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );

      expect(second, hasLength(1));
      expect(second.single.id, 1);
      expect(second.single.seenCount, 2);
    });

    test('does not match a distant detection to the existing track', () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 150,
            y2: 220,
            label: 'person',
          ),
        ],
        640,
        480,
        now,
      );

      final second = tracker.update(
        [
          makeDet(
            x1: 320,
            y1: 100,
            x2: 370,
            y2: 220,
            label: 'person',
          ),
        ],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );

      expect(second, isEmpty);
    });
  });

  group('Tracker fast-track', () {
    test('returns a single-frame very-close high-conf detection immediately',
        () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      final first = tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            label: 'person',
            conf: 0.75,
            dist: 'very close',
            distM: 0.9,
          ),
        ],
        640,
        480,
        now,
      );

      expect(first, hasLength(1));
      expect(first.single.fastTrack, isTrue);
      expect(first.single.nearFrameCount, greaterThanOrEqualTo(1));
    });

    test('ignores fast-track when confidence is below the 0.60 gate', () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      final first = tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            label: 'person',
            conf: 0.50,
            dist: 'very close',
            distM: 0.9,
          ),
        ],
        640,
        480,
        now,
      );

      expect(first, isEmpty);
    });

    test('ignores fast-track when dist is not "very close"', () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      final first = tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            label: 'person',
            conf: 0.80,
            dist: 'close',
            distM: 2.5,
          ),
        ],
        640,
        480,
        now,
      );

      expect(first, isEmpty);
    });

    test('ignores fast-track when distM is greater than 1.5 m', () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      final first = tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            label: 'person',
            conf: 0.80,
            dist: 'very close',
            distM: 3.0,
          ),
        ],
        640,
        480,
        now,
      );

      expect(first, isEmpty);
    });

    test('fastTrack flag clears once the track reaches normal confirmation',
        () {
      final tracker = Tracker();
      final now = DateTime(2025, 1, 1, 12);

      tracker.update(
        [
          makeDet(
            x1: 100,
            y1: 100,
            x2: 200,
            y2: 380,
            label: 'person',
            conf: 0.80,
            dist: 'very close',
            distM: 0.9,
          ),
        ],
        640,
        480,
        now,
      );

      final second = tracker.update(
        [
          makeDet(
            x1: 102,
            y1: 102,
            x2: 202,
            y2: 382,
            label: 'person',
            conf: 0.80,
            dist: 'very close',
            distM: 0.9,
          ),
        ],
        640,
        480,
        now.add(const Duration(milliseconds: 120)),
      );

      expect(second, hasLength(1));
      expect(second.single.fastTrack, isFalse);
      expect(second.single.seenCount, 2);
    });
  });

  group('Tracker dynamicThreat (label-agnostic kinematic threat)', () {
    
    
    
    test('sets dynamicThreat on a non-vehicle label growing fast in frame',
        () {
      final tracker = Tracker();
      var now = DateTime(2025, 1, 1, 12);

      tracker.update(
        [
          makeDet(
            x1: 290,
            y1: 320,
            x2: 330,
            y2: 400,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 200));
      tracker.update(
        [
          makeDet(
            x1: 275,
            y1: 305,
            x2: 345,
            y2: 420,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 400));
      final third = tracker.update(
        [
          makeDet(
            x1: 250,
            y1: 275,
            x2: 380,
            y2: 450,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      expect(third, hasLength(1));
      final t = third.single;
      expect(t.dynamicThreat, isTrue);
      
      expect(t.approaching, isFalse);
    });

    test('leaves dynamicThreat off when bbox barely grows', () {
      final tracker = Tracker();
      var now = DateTime(2025, 1, 1, 12);

      tracker.update(
        [
          makeDet(
            x1: 290,
            y1: 320,
            x2: 330,
            y2: 400,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 200));
      tracker.update(
        [
          makeDet(
            x1: 291,
            y1: 321,
            x2: 332,
            y2: 402,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 400));
      final third = tracker.update(
        [
          makeDet(
            x1: 292,
            y1: 322,
            x2: 334,
            y2: 404,
            label: 'skateboard',
            conf: 0.7,
          ),
        ],
        640,
        480,
        now,
      );

      expect(third, hasLength(1));
      expect(third.single.dynamicThreat, isFalse);
      expect(third.single.approaching, isFalse);
    });

    test('fires on vehicle label as well (approaching + dynamicThreat)', () {
      final tracker = Tracker();
      var now = DateTime(2025, 1, 1, 12);

      tracker.update(
        [
          makeDet(
            x1: 200,
            y1: 200,
            x2: 260,
            y2: 260,
            label: 'bicycle',
            conf: 0.75,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 200));
      tracker.update(
        [
          makeDet(
            x1: 190,
            y1: 185,
            x2: 280,
            y2: 290,
            label: 'bicycle',
            conf: 0.75,
          ),
        ],
        640,
        480,
        now,
      );

      now = now.add(const Duration(milliseconds: 400));
      final third = tracker.update(
        [
          makeDet(
            x1: 170,
            y1: 140,
            x2: 320,
            y2: 370,
            label: 'bicycle',
            conf: 0.75,
          ),
        ],
        640,
        480,
        now,
      );

      expect(third, hasLength(1));
      expect(third.single.dynamicThreat, isTrue);
      expect(third.single.approaching, isTrue);
    });
  });

  group('Tracker weatherDegraded (OPT-15)', () {
    test(
      'weatherDegraded=true lifts the pedestrian approach threshold so '
      "borderline area-rate signals don't flip approaching=true",
      () {
        
        
        
        
        
        
        
        
        
        RawDet narrowBox() => makeDet(
              x1: 100,
              y1: 190,
              x2: 140,
              y2: 290,
              label: 'person',
            );
        RawDet wideBox() => makeDet(
              x1: 100,
              y1: 190,
              x2: 270,
              y2: 290,
              label: 'person',
            );

        final base = DateTime(2025, 1, 1, 12);
        final t0 = base;
        final t1 = base.add(const Duration(milliseconds: 200));
        final t2 = base.add(const Duration(milliseconds: 700));

        
        final clear = Tracker();
        clear.update([narrowBox()], 640, 480, t0);
        clear.update([narrowBox()], 640, 480, t1);
        final clearTracks = clear.update([wideBox()], 640, 480, t2);
        expect(clearTracks, hasLength(1));
        expect(clearTracks.single.approaching, isTrue);

        
        final degraded = Tracker()..weatherDegraded = true;
        degraded.update([narrowBox()], 640, 480, t0);
        degraded.update([narrowBox()], 640, 480, t1);
        final degradedTracks = degraded.update([wideBox()], 640, 480, t2);
        expect(degradedTracks, hasLength(1));
        expect(degradedTracks.single.approaching, isFalse);
      },
    );

    test(
      'weatherDegraded does not affect vehicle approach — OPT-19 owns '
      'the vehicle close-range path',
      () {
        
        
        
        
        RawDet f0() => makeDet(
              x1: 200,
              y1: 200,
              x2: 260,
              y2: 260,
              label: 'car',
            );
        RawDet f1() => makeDet(
              x1: 195,
              y1: 193,
              x2: 280,
              y2: 285,
              label: 'car',
            );
        RawDet f2() => makeDet(
              x1: 190,
              y1: 185,
              x2: 330,
              y2: 330,
              label: 'car',
            );

        final base = DateTime(2025, 1, 1, 12);
        for (final wd in const [false, true]) {
          final tr = Tracker()..weatherDegraded = wd;
          tr.update([f0()], 640, 480, base);
          tr.update(
            [f1()],
            640,
            480,
            base.add(const Duration(milliseconds: 200)),
          );
          final out = tr.update(
            [f2()],
            640,
            480,
            base.add(const Duration(milliseconds: 700)),
          );
          expect(out, hasLength(1));
          expect(
            out.single.approaching,
            isTrue,
            reason: 'vehicle approach must fire irrespective of '
                'weatherDegraded=$wd',
          );
        }
      },
    );
  });

  group('KalmanBoxTracker', () {
    test('keeps finite positive predicted boxes', () {
      final kalman = KalmanBoxTracker(
        makeDet(
          x1: 40,
          y1: 50,
          x2: 80,
          y2: 130,
          label: 'person',
        ),
      );

      kalman.predict();
      kalman.update(
        makeDet(
          x1: 140,
          y1: 60,
          x2: 180,
          y2: 140,
          label: 'person',
          conf: 0.6,
        ),
      );

      final box = kalman.getPredictedBox();
      expect(box.every((value) => value.isFinite), isTrue);
      expect(box[2], greaterThan(box[0]));
      expect(box[3], greaterThan(box[1]));
    });
  });
}

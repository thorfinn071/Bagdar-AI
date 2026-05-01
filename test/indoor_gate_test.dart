import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/fall_detector.dart';
import 'package:bagdar/services/indoor_gate.dart';

IndoorTransition _feedStream(
  IndoorGate gate, {
  required int count,
  required double? accuracyM,
  required int? ageSec,
  required MotionState motion,
  required DateTime start,
  Duration step = const Duration(seconds: 2),
}) {
  IndoorTransition last = IndoorTransition.none;
  var now = start;
  for (var i = 0; i < count; i++) {
    last = gate.feed(
      gpsAccuracyM: accuracyM,
      gpsAgeSec: ageSec,
      motion: motion,
      now: now,
    );
    if (i < count - 1) {
      expect(
        last,
        IndoorTransition.none,
        reason: 'intermediate sample #$i must not emit a transition',
      );
    }
    now = now.add(step);
  }
  return last;
}

void main() {

  group('OPT-13 IndoorGate — cold start & street', () {
    test('initial state is unknown with empty streaks', () {
      final gate = IndoorGate();
      expect(gate.state, IndoorState.unknown);
      expect(gate.poorStreak, 0);
      expect(gate.goodStreak, 0);
      expect(gate.walkingStreak, 0);
    });

    test('first good-GPS sample settles into street without a transition',
        () {
      final gate = IndoorGate();
      final base = DateTime(2026, 1, 1, 12);
      final transition = gate.feed(
        gpsAccuracyM: 8.0,
        gpsAgeSec: 2,
        motion: MotionState.walking,
        now: base,
      );
      expect(transition, IndoorTransition.none,
          reason: 'unknown → street does NOT announce indoor state');
      expect(gate.state, IndoorState.street);
    });

    test('sustained good GPS leaves gate in street, no transition spam', () {
      final gate = IndoorGate();
      final last = _feedStream(
        gate,
        count: 20,
        accuracyM: 10.0,
        ageSec: 5,
        motion: MotionState.walking,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(last, IndoorTransition.none);
      expect(gate.state, IndoorState.street);
    });
  });

  group('OPT-13 IndoorGate — enter indoor', () {
    test('15 consecutive poor-GPS + stationary samples flip to indoor', () {
      final gate = IndoorGate();
      final last = _feedStream(
        gate,
        count: 15,
        accuracyM: 50.0,
        ageSec: 90,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(last, IndoorTransition.enteredIndoor);
      expect(gate.state, IndoorState.indoor);
    });

    test('null GPS counts as poor — 15 null-accuracy samples enter indoor',
        () {
      final gate = IndoorGate();
      final last = _feedStream(
        gate,
        count: 15,
        accuracyM: null,
        ageSec: null,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(last, IndoorTransition.enteredIndoor);
    });

    test('stale GPS (age > 60s) treated as poor even with good accuracy', () {
      final gate = IndoorGate();
      final last = _feedStream(
        gate,
        count: 15,
        accuracyM: 5.0,
        ageSec: 120,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(last, IndoorTransition.enteredIndoor);
    });

    test('poor GPS + walking does NOT enter indoor — motion vetoes', () {
      final gate = IndoorGate();
      final last = _feedStream(
        gate,
        count: 30,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.walking,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(last, IndoorTransition.none);
      expect(gate.state, isNot(IndoorState.indoor),
          reason: 'walking pedestrian under weak GPS = tunnel/cold-start, '
              'must never classify as indoor');
    });

    test('enter confirmation resets if motion briefly becomes walking', () {
      final gate = IndoorGate();
      final base = DateTime(2026, 1, 1, 12);
      _feedStream(
        gate,
        count: 10,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: base,
      );
      expect(gate.poorStreak, 10);

      gate.feed(
        gpsAccuracyM: 50.0,
        gpsAgeSec: 5,
        motion: MotionState.walking,
        now: base.add(const Duration(seconds: 22)),
      );
      expect(gate.poorStreak, 0);
      expect(gate.state, IndoorState.unknown);
    });
  });
      
  group('OPT-13 IndoorGate — exit indoor', () {
    IndoorGate enterIndoor() {
      final gate = IndoorGate();
      _feedStream(
        gate,
        count: 15,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 12),
      );
      return gate;
    }

    test('8 consecutive good-GPS samples exit indoor', () {
      final gate = enterIndoor();
      expect(gate.state, IndoorState.indoor);

      final last = _feedStream(
        gate,
        count: 8,
        accuracyM: 8.0,
        ageSec: 2,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 13),
      );
      expect(last, IndoorTransition.exitedIndoor);
      expect(gate.state, IndoorState.street);
    });

    test('5 consecutive walking frames exit indoor even under poor GPS', () {
      final gate = enterIndoor();
      expect(gate.state, IndoorState.indoor);

      final last = _feedStream(
        gate,
        count: 5,
        accuracyM: 45.0,
        ageSec: 5,
        motion: MotionState.walking,
        start: DateTime(2026, 1, 1, 13),
      );
      expect(last, IndoorTransition.exitedIndoor);
      expect(gate.state, IndoorState.street);
    });

    test('exit confirmation resets if motion stops before reaching 5 frames',
        () {
      final gate = enterIndoor();
      final base = DateTime(2026, 1, 1, 13);

      _feedStream(
        gate,
        count: 3,
        accuracyM: 45.0,
        ageSec: 5,
        motion: MotionState.walking,
        start: base,
      );
      expect(gate.walkingStreak, 3);
      expect(gate.state, IndoorState.indoor);

      gate.feed(
        gpsAccuracyM: 45.0,
        gpsAgeSec: 5,
        motion: MotionState.stationary,
        now: base.add(const Duration(seconds: 8)),
      );
      expect(gate.walkingStreak, 0);
      expect(gate.state, IndoorState.indoor);
    });
  });

  group('OPT-13 IndoorGate — hysteresis & reset', () {
    test('accuracy in [15, 30] middle zone freezes streaks and state', () {
      final gate = IndoorGate();
      final base = DateTime(2026, 1, 1, 12);
      _feedStream(
        gate,
        count: 10,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: base,
      );
      expect(gate.poorStreak, 10);

      for (var i = 0; i < 20; i++) {
        final t = gate.feed(
          gpsAccuracyM: 20.0,
          gpsAgeSec: 5,
          motion: MotionState.stationary,
          now: base.add(Duration(seconds: 22 + i * 2)),
        );
        expect(t, IndoorTransition.none);
      }
      expect(gate.poorStreak, 10,
          reason: 'middle zone must not advance the enter streak');
      expect(gate.state, IndoorState.unknown);
    });

    test('reset() clears state and all streaks', () {
      final gate = IndoorGate();
      _feedStream(
        gate,
        count: 15,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: DateTime(2026, 1, 1, 12),
      );
      expect(gate.state, IndoorState.indoor);

      gate.reset();
      expect(gate.state, IndoorState.unknown);
      expect(gate.poorStreak, 0);
      expect(gate.goodStreak, 0);
      expect(gate.walkingStreak, 0);
    });

    test('enter → exit → enter cycle works without residual streaks', () {
      final gate = IndoorGate();
      final base = DateTime(2026, 1, 1, 12);

      var last = _feedStream(
        gate,
        count: 15,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: base,
      );
      expect(last, IndoorTransition.enteredIndoor);

      last = _feedStream(
        gate,
        count: 8,
        accuracyM: 8.0,
        ageSec: 2,
        motion: MotionState.stationary,
        start: base.add(const Duration(seconds: 40)),
      );
      expect(last, IndoorTransition.exitedIndoor);

      last = _feedStream(
        gate,
        count: 15,
        accuracyM: 50.0,
        ageSec: 5,
        motion: MotionState.stationary,
        start: base.add(const Duration(minutes: 2)),
      );
      expect(last, IndoorTransition.enteredIndoor);
    });
  });
}

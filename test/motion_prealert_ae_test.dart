import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';
import 'package:bagdar/services/motion_prealert.dart';

void main() {
  group('Safety audit D-1: MotionPreAlert during an AE transition', () {
    test('feed()/feedDownsampledGrid() short-circuit to null the instant '
        'aeTransitioning is true, regardless of the grid content — this is '
        'the invariant that made the old camera_screen.dart call with '
        'aeTransitioning: true dead code (it could never produce a motion '
        'event to act on), which is why that call was removed in favor of a '
        'direct user notification (earcon + TTS) on every AE start', () {
      final alert = MotionPreAlert();
      const n = kEventGridW * kEventGridH;

      // A grid designed to obviously trigger an intrusion event when NOT
      // AE-transitioning (half the grid flips from 0 to 255 between the
      // two frames fed below).
      final quiet = Uint8List(n);
      final intrusion = Uint8List(n)..fillRange(0, n ~/ 2, 255);

      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      alert.feedDownsampledGrid(quiet, t0, aeTransitioning: true);
      final duringAe = alert.feedDownsampledGrid(
        intrusion,
        t0.add(const Duration(milliseconds: 100)),
        aeTransitioning: true,
      );
      expect(
        duringAe,
        isNull,
        reason:
            'aeTransitioning: true must always short-circuit to '
            'null, even with a large frame-to-frame luma delta',
      );
    });

    test('the same grid transition DOES produce a motion event once '
        'aeTransitioning is false again — proving the detector itself is '
        'healthy and only the AE-transitioning branch is gated off', () {
      final alert = MotionPreAlert();
      const n = kEventGridW * kEventGridH;
      final quiet = Uint8List(n);
      // Sudden appearance in the center corridor only, so the center
      // corridor trigger fires deterministically.
      final intrusion = Uint8List(n);
      for (
        int gy = (kEventGridH * 0.20).toInt();
        gy < (kEventGridH * 0.80).toInt();
        gy++
      ) {
        for (
          int gx = (kEventGridW * 0.35).toInt();
          gx < (kEventGridW * 0.65).toInt();
          gx++
        ) {
          intrusion[gy * kEventGridW + gx] = 255;
        }
      }

      final t0 = DateTime(2025, 1, 1, 12, 0, 0);
      alert.feedDownsampledGrid(quiet, t0, aeTransitioning: false);
      final event = alert.feedDownsampledGrid(
        intrusion,
        t0.add(const Duration(milliseconds: 100)),
        aeTransitioning: false,
      );
      expect(
        event,
        isNotNull,
        reason:
            'a real center-corridor intrusion must still be '
            'detected outside of an AE transition',
      );
    });
  });
}

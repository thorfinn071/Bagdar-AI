import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/fall_detector.dart';

void main() {
  group('FallDetector post-cancel grace window (Safety follow-up H7)', () {
    test(
      'notifyCancelled opens a 60 s grace window where cooldown is bypassed',
      () {
        final fd = FallDetector();
        fd.notifyCancelled();
        final now = DateTime.now();

        expect(fd.isInPostCancelGraceAt(now), isTrue,
            reason: 'grace window should be open immediately after cancel');
        expect(
          fd.isInPostCancelGraceAt(
            now.add(const Duration(seconds: 30)),
          ),
          isTrue,
          reason: 'grace window still open at 30 s post-cancel',
        );
        expect(
          fd.isInPostCancelGraceAt(
            now.add(const Duration(seconds: 61)),
          ),
          isFalse,
          reason: 'grace window must close after 60 s',
        );
      },
    );

    test(
      'notifyCancelled clears any active SOS lockout — a cancel undoes a '
      'previously declared "SOS sent" state',
      () {
        final fd = FallDetector();
        fd.notifyFallSosSent();
        expect(fd.isInSosLockoutAt(DateTime.now()), isTrue);
        fd.notifyCancelled();
        expect(
          fd.isInSosLockoutAt(DateTime.now()),
          isFalse,
          reason:
              'after cancellation, no SOS was actually delivered, so the '
              'follow-up routing must not be armed',
        );
      },
    );
  });

  group('FallDetector SOS lockout (Safety follow-up H7)', () {
    test(
      'notifyFallSosSent opens a 20 s lockout, closes after window',
      () {
        final fd = FallDetector();
        fd.notifyFallSosSent();
        final now = DateTime.now();

        expect(fd.isInSosLockoutAt(now), isTrue);
        expect(
          fd.isInSosLockoutAt(now.add(const Duration(seconds: 19))),
          isTrue,
        );
        expect(
          fd.isInSosLockoutAt(now.add(const Duration(seconds: 21))),
          isFalse,
          reason: 'lockout must close at the configured 20 s boundary',
        );
      },
    );

    test('lockout duration matches the documented 20 s window', () {
      final fd = FallDetector();
      expect(fd.sosLockoutWindow, const Duration(seconds: 20));
      expect(fd.postCancelGraceWindow, const Duration(seconds: 60));
    });
  });
}

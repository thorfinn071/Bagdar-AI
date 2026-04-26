import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/utils/midas_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MidasService stuck-watchdog — Safety A-4', () {
    test('clean state: not busy, not recovering, no trigger', () {
      final svc = MidasService();
      expect(svc.debugIsBusy, isFalse);
      expect(svc.debugIsRecovering, isFalse);
      expect(svc.debugTriggerRecoveryCheck(), isFalse);
      svc.dispose();
    });

    test(
      'busy under timeout does NOT trigger recovery',
      () {
        final svc = MidasService();
        svc.debugMarkStuck(age: const Duration(milliseconds: 1000));
        expect(svc.debugIsBusy, isTrue);
        expect(svc.debugTriggerRecoveryCheck(), isFalse);
        expect(svc.debugIsRecovering, isFalse);
        svc.dispose();
      },
    );

    test(
      'busy past kMidasStuckTimeoutMs triggers recovery exactly once',
      () async {
        final svc = MidasService();
        svc.debugMarkStuck(age: const Duration(milliseconds: 3500));

        expect(svc.debugIsBusy, isTrue);
        expect(svc.debugTriggerRecoveryCheck(), isTrue);
        expect(svc.debugIsRecovering, isTrue);

        
        expect(svc.debugTriggerRecoveryCheck(), isFalse);

        
        
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(svc.debugIsRecovering, isFalse);
        svc.dispose();
      },
    );

    test(
      'recovery clears _busy and _busyStartMs even on init failure',
      () async {
        final svc = MidasService();
        svc.debugMarkStuck(age: const Duration(milliseconds: 4000));
        expect(svc.debugTriggerRecoveryCheck(), isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 800));

        
        expect(svc.debugIsBusy, isFalse);
        expect(svc.debugIsRecovering, isFalse);
        svc.dispose();
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/sos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class RefusingContactStore extends InMemorySharedPreferencesStore {
  RefusingContactStore() : super.empty();
  @override
  Future<bool> setValue(String valueType, String key, Object value) async => false;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStrings.setLanguage(AppLanguage.ru);
  });

  group('SosService helpers', () {
    test('buildMessageText includes coordinates', () {
      final message = SosService.buildMessageText(
        latitude: 51.1234567,
        longitude: 71.7654321,
      );

      expect(
        message,
        contains('https://maps.google.com/?q=51.123457,71.765432'),
      );
    });

    test('buildMessageText falls back without coordinates', () {
      final message = SosService.buildMessageText();

      expect(message, contains(S.get('sos_message')));
      expect(message, contains(S.get('sos_no_gps')));
    });

    test('buildSmsUri keeps the body query parameter', () {
      final uri = SosService.buildSmsUri('+7 (777) 123-45-67', 'help me');

      expect(uri.scheme, 'sms');
      expect(uri.path, '+77771234567');
      expect(uri.queryParameters['body'], 'help me');
    });

    test('setContact trims formatted input', () async {
      final service = SosService();

      final saved = await service.setContact('  +7 (777) 123-45-67  ');

      expect(saved, isTrue);
      expect(service.contactNumber, '+7 (777) 123-45-67');
    });

    test('failed persistence never replaces the active SOS contact', () async {
      final service = SosService();
      expect(await service.setContact('+77771234567'), isTrue);
      SharedPreferencesStorePlatform.instance = RefusingContactStore();
      expect(await service.setContact('+77777654321'), isFalse);
      expect(service.contactNumber, '+77771234567');
    });

    test('buildMessageText flags stale position (>=2 min)', () {
      final stale = DateTime.now().subtract(const Duration(minutes: 5));
      final message = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        positionTimestamp: stale,
      );
      expect(message, contains(S.get('sos_position_stale')));
      expect(message, contains(S.get('sos_position_unit_min')));
    });

    test('buildMessageText does not flag fresh position (<2 min)', () {
      final fresh = DateTime.now().subtract(const Duration(seconds: 30));
      final message = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        positionTimestamp: fresh,
      );
      expect(message.contains(S.get('sos_position_stale')), isFalse);
    });

    test('buildMessageText includes GPS accuracy when provided', () {
      final message = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        accuracyMeters: 12.0,
      );
      expect(message, contains('12m'));
    });

    test('buildMessageText prepends an optional preamble before the main '
        'message body (Safety follow-up H7 follow-up SMS)', () {
      final message = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        preamble: S.get('sos_user_fallen_again'),
      );
      expect(
        message.startsWith(S.get('sos_user_fallen_again')),
        isTrue,
        reason:
            'the follow-up alert text must come first so the recipient '
            'sees "user has fallen again" before the location link',
      );
      expect(message, contains(S.get('sos_message')));
      expect(
        message,
        contains('https://maps.google.com/?q=51.000000,71.000000'),
      );
    });

    test(
      'buildMessageText with empty preamble is identical to no preamble',
      () {
        final a = SosService.buildMessageText(latitude: 51.0, longitude: 71.0);
        final b = SosService.buildMessageText(
          latitude: 51.0,
          longitude: 71.0,
          preamble: '',
        );
        expect(b, equals(a));
      },
    );
  });

  group('SosService follow-up SMS scheduler (Safety follow-up H7)', () {
    test('queueFollowUpFall increments the count and arms the timer', () {
      final service = SosService();
      expect(service.hasQueuedFollowUp, isFalse);
      expect(service.pendingFollowUpCount, 0);

      service.queueFollowUpFall();
      expect(service.hasQueuedFollowUp, isTrue);
      expect(service.pendingFollowUpCount, 1);

      service.queueFollowUpFall();
      expect(
        service.pendingFollowUpCount,
        2,
        reason:
            'a second second-fall during the lockout should accumulate, '
            'not replace, so the eventual SMS reflects the actual count',
      );

      service.cancelQueuedFollowUp();
    });

    test('cancelQueuedFollowUp clears the timer and resets the count', () {
      final service = SosService();
      service.queueFollowUpFall();
      service.queueFollowUpFall();
      service.cancelQueuedFollowUp();
      expect(service.hasQueuedFollowUp, isFalse);
      expect(service.pendingFollowUpCount, 0);
    });
  });

  group('SosResult enum', () {
    test('exposes sentFallback for 112 delivery', () {
      expect(SosResult.values, contains(SosResult.sentFallback));
    });
  });

  group('SosService H9 indoor SOS fallback', () {
    test('buildMessageText appends planned destination when provided', () {
      final message = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        plannedDestination: 'Aviator Park',
      );
      expect(message, contains(S.get('sos_planned_destination')));
      expect(message, contains('Aviator Park'));
    });

    test('buildMessageText appends step delta and cardinal direction '
        'only when GPS is missing', () {
      final indoors = SosService.buildMessageText(
        stepsFromLastFix: 340,
        headingFromLastFix: 315,
      );
      expect(indoors, contains('+340 ${S.get('sos_steps_from_last')}'));
      expect(indoors, contains(S.get('sos_dir_nw')));
      expect(indoors, contains(S.get('sos_of_last_known')));

      final outdoors = SosService.buildMessageText(
        latitude: 51.0,
        longitude: 71.0,
        stepsFromLastFix: 340,
        headingFromLastFix: 315,
      );
      expect(
        outdoors.contains(S.get('sos_steps_from_last')),
        isFalse,
        reason: 'steps/direction line is reserved for the no-GPS path',
      );
    });

    test('buildMessageText maps heading 0/45/90/135/180/225/270/315 '
        'to the correct cardinal key', () {
      const cases = <({double bearing, String key})>[
        (bearing: 0, key: 'sos_dir_n'),
        (bearing: 45, key: 'sos_dir_ne'),
        (bearing: 90, key: 'sos_dir_e'),
        (bearing: 135, key: 'sos_dir_se'),
        (bearing: 180, key: 'sos_dir_s'),
        (bearing: 225, key: 'sos_dir_sw'),
        (bearing: 270, key: 'sos_dir_w'),
        (bearing: 315, key: 'sos_dir_nw'),
      ];
      for (final c in cases) {
        final message = SosService.buildMessageText(
          stepsFromLastFix: 5,
          headingFromLastFix: c.bearing,
        );
        expect(
          message,
          contains(S.get(c.key)),
          reason: 'heading ${c.bearing}° should produce ${c.key}',
        );
      }
    });

    test(
      'buildMessageText includes Wi-Fi SSID + BSSID and cell-tower hint',
      () {
        final message = SosService.buildMessageText(
          networkContext: const {
            'wifiSsid': 'CafeAstana',
            'wifiBssid': 'aa:bb:cc:dd:ee:ff',
            'cellId': 'LTE/401-01/tac=1234/ci=98765',
            'carrier': 'Beeline',
          },
        );
        expect(message, contains(S.get('sos_near_wifi')));
        expect(message, contains('CafeAstana'));
        expect(message, contains('aa:bb:cc:dd:ee:ff'));
        expect(message, contains(S.get('sos_near_cell')));
        expect(message, contains('Beeline'));
        expect(message, contains('LTE/401-01/tac=1234/ci=98765'));
      },
    );

    test(
      'buildMessageText omits network section when context map is empty',
      () {
        final message = SosService.buildMessageText(
          latitude: 51.0,
          longitude: 71.0,
          networkContext: const {},
        );
        expect(message.contains(S.get('sos_near_wifi')), isFalse);
        expect(message.contains(S.get('sos_near_cell')), isFalse);
      },
    );

    test('setPlannedDestination trims and clears (route-stop emits null)', () {
      final service = SosService();
      expect(service.plannedDestination, isNull);

      service.setPlannedDestination('  Almaty Mall  ');
      expect(service.plannedDestination, 'Almaty Mall');

      service.setPlannedDestination('');
      expect(service.plannedDestination, isNull);

      service.setPlannedDestination('  ');
      expect(service.plannedDestination, isNull);

      service.setPlannedDestination('Park');
      service.setPlannedDestination(null);
      expect(service.plannedDestination, isNull);
    });

    test(
      'refreshNetworkContext caches the provider snapshot for SMS use',
      () async {
        final service = SosService(
          networkContextProvider: () async => const {
            'wifiSsid': 'home_wifi',
            'cellId': 'GSM/401-01/lac=1/cid=2',
          },
        );

        await service.refreshNetworkContext();
        final cached = service.cachedNetworkContextForTesting;
        expect(cached, isNotNull);
        expect(cached!['wifiSsid'], 'home_wifi');
        expect(cached['cellId'], 'GSM/401-01/lac=1/cid=2');
      },
    );

    test('refreshNetworkContext silently times out without throwing', () async {
      final service = SosService(
        networkContextProvider: () async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return const {};
        },
      );

      await service.refreshNetworkContext(
        timeout: const Duration(milliseconds: 50),
      );
      expect(service.cachedNetworkContextForTesting, isNull);
    });

    test(
      'refreshNetworkContext is a no-op when the provider is missing',
      () async {
        final service = SosService();
        await service.refreshNetworkContext();
        expect(service.cachedNetworkContextForTesting, isNull);
      },
    );

    test(
      'buildMessageText omits step line when steps delta is zero or negative',
      () {
        final messageZero = SosService.buildMessageText(
          stepsFromLastFix: 0,
          headingFromLastFix: 0,
        );
        expect(messageZero.contains(S.get('sos_steps_from_last')), isFalse);

        final messageNeg = SosService.buildMessageText(
          stepsFromLastFix: -5,
          headingFromLastFix: 0,
        );
        expect(messageNeg.contains(S.get('sos_steps_from_last')), isFalse);
      },
    );

    test(
      'buildMessageText emits step line with no direction when heading is null',
      () {
        final message = SosService.buildMessageText(stepsFromLastFix: 17);
        expect(message, contains('+17 ${S.get('sos_steps_from_last')}'));
        expect(message, contains(S.get('sos_of_last_known')));
        for (final dirKey in const [
          'sos_dir_n',
          'sos_dir_ne',
          'sos_dir_e',
          'sos_dir_se',
          'sos_dir_s',
          'sos_dir_sw',
          'sos_dir_w',
          'sos_dir_nw',
        ]) {
          expect(
            message.contains(S.get(dirKey)),
            isFalse,
            reason: 'no heading → no cardinal label',
          );
        }
      },
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/sos_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test(
      'buildMessageText prepends an optional preamble before the main '
      'message body (Safety follow-up H7 follow-up SMS)',
      () {
        final message = SosService.buildMessageText(
          latitude: 51.0,
          longitude: 71.0,
          preamble: S.get('sos_user_fallen_again'),
        );
        expect(message.startsWith(S.get('sos_user_fallen_again')), isTrue,
            reason:
                'the follow-up alert text must come first so the recipient '
                'sees "user has fallen again" before the location link');
        expect(message, contains(S.get('sos_message')));
        expect(
          message,
          contains('https://maps.google.com/?q=51.000000,71.000000'),
        );
      },
    );

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
      expect(service.pendingFollowUpCount, 2,
          reason:
              'a second second-fall during the lockout should accumulate, '
              'not replace, so the eventual SMS reflects the actual count');

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
}

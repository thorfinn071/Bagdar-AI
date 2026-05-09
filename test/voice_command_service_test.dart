import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/voice_command_service.dart';

typedef _Captured = ({VoiceCommand? cmd, VoiceCommand? navCmd, String? dest});

_Captured _feed(
  VoiceCommandService svc,
  String words, {
  required String locale,
}) {
  VoiceCommand? cmd;
  VoiceCommand? navCmd;
  String? dest;
  svc.onCommand = (c) => cmd = c;
  svc.onNavCommand = (c, d) {
    navCmd = c;
    dest = d;
  };
  svc.processWordsForTesting(words, localeOverride: locale);
  return (cmd: cmd, navCmd: navCmd, dest: dest);
}

void main() {
  group('VoiceCommandService English', () {
    test('SOS exact phrases fire sos command', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'sos',
        'help',
        'emergency',
        'call for help',
        'call 911',
      ]) {
        final r = _feed(svc, phrase, locale: 'en-US');
        expect(r.cmd, VoiceCommand.sos, reason: 'phrase="$phrase"');
      }
    });

    test('multi-word cancel phrases fire cancelFall', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'i am fine',
        "i'm fine",
        'i am okay',
        "i'm ok",
        'false alarm',
        'no problem',
        "i didn't fall",
      ]) {
        final r = _feed(svc, phrase, locale: 'en-US');
        expect(r.cmd, VoiceCommand.cancelFall, reason: 'phrase="$phrase"');
      }
    });

    test('bare single-word triggers must not cancel a fall SOS', () {
      final svc = VoiceCommandService();
      for (final phrase in ['stop', 'cancel', 'abort', 'mistake']) {
        final r = _feed(svc, phrase, locale: 'en-US');
        expect(
          r.cmd,
          isNot(VoiceCommand.cancelFall),
          reason: 'bare word "$phrase" must not cancel a fall SOS',
        );
      }
      for (final phrase in ['стоп', 'отмена', 'отбой', 'прекрати']) {
        final r = _feed(svc, phrase, locale: 'ru-RU');
        expect(
          r.cmd,
          isNot(VoiceCommand.cancelFall),
          reason: 'bare word "$phrase" must not cancel a fall SOS',
        );
      }
      for (final phrase in ['тоқта', 'болдырма', 'қате']) {
        final r = _feed(svc, phrase, locale: 'kk-KZ');
        expect(
          r.cmd,
          isNot(VoiceCommand.cancelFall),
          reason: 'bare word "$phrase" must not cancel a fall SOS',
        );
      }
    });

    test('scan commands recognised', () {
      final svc = VoiceCommandService();
      expect(
        _feed(svc, 'what is around', locale: 'en-US').cmd,
        VoiceCommand.scanAll,
      );
      expect(
        _feed(svc, "what's on the left", locale: 'en-US').cmd,
        VoiceCommand.scanLeft,
      );
      expect(
        _feed(svc, 'what is ahead', locale: 'en-US').cmd,
        VoiceCommand.scanForward,
      );
    });

    test('mode commands recognised', () {
      final svc = VoiceCommandService();
      expect(
        _feed(svc, 'street mode', locale: 'en-US').cmd,
        VoiceCommand.modeStreet,
      );
      expect(
        _feed(svc, 'cane mode', locale: 'en-US').cmd,
        VoiceCommand.modeCane,
      );
      expect(
        _feed(svc, 'scan mode', locale: 'en-US').cmd,
        VoiceCommand.modeScan,
      );
    });

    test('nav prefix extracts destination', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'take me to central park', locale: 'en-US');
      expect(r.navCmd, VoiceCommand.navigateTo);
      expect(r.dest, 'central park');
    });

    test('transit prefix extracts destination', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'bus to airport', locale: 'en-US');
      expect(r.navCmd, VoiceCommand.transitTo);
      expect(r.dest, 'airport');
    });

    test('read text variants recognised', () {
      final svc = VoiceCommandService();
      expect(
        _feed(svc, 'read text', locale: 'en-US').cmd,
        VoiceCommand.readText,
      );
      expect(
        _feed(svc, 'read', locale: 'en-US').cmd,
        VoiceCommand.readText,
      );
    });

    test('unknown phrase returns VoiceCommand.unknown', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'xyzzy blargh', locale: 'en-US');
      expect(r.cmd, VoiceCommand.unknown);
    });

    test('english locale does not leak into russian phrases', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'что вокруг', locale: 'en-US');
      expect(r.cmd, VoiceCommand.unknown,
          reason: 'Russian phrase must not match under en-US');
    });
  });

  group('VoiceCommandService locale isolation', () {
    test('russian phrases still work under ru-RU', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'что вокруг', locale: 'ru-RU');
      expect(r.cmd, VoiceCommand.scanAll);
    });

    test('kazakh phrases still work under kk-KZ', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'айналада не бар', locale: 'kk-KZ');
      expect(r.cmd, VoiceCommand.scanAll);
    });

    test('russian nav prefix still works under ru-RU', () {
      final svc = VoiceCommandService();
      final r = _feed(svc, 'веди в парк', locale: 'ru-RU');
      expect(r.navCmd, VoiceCommand.navigateTo);
      expect(r.dest, 'парк');
    });
  });

  group('VoiceCommandService showHelp', () {
    test('russian help variants', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'справка',
        'помощь',
        'жесты',
        'что умеешь',
        'как пользоваться',
      ]) {
        final r = _feed(svc, phrase, locale: 'ru-RU');
        expect(r.cmd, VoiceCommand.showHelp, reason: 'phrase="$phrase"');
      }
    });

    test('kazakh help variants', () {
      final svc = VoiceCommandService();
      for (final phrase in ['көмек', 'анықтама', 'қимылдар', 'нұсқау']) {
        final r = _feed(svc, phrase, locale: 'kk-KZ');
        expect(r.cmd, VoiceCommand.showHelp, reason: 'phrase="$phrase"');
      }
    });

    test('english help variants do not collide with SOS', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'gestures',
        'show help',
        'commands list',
        'how to use',
        'what can you do',
      ]) {
        final r = _feed(svc, phrase, locale: 'en-US');
        expect(r.cmd, VoiceCommand.showHelp, reason: 'phrase="$phrase"');
      }
      expect(
        _feed(svc, 'help', locale: 'en-US').cmd,
        VoiceCommand.sos,
        reason: '"help" alone must remain SOS',
      );
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/models/language_pack.dart';
import 'package:bagdar/services/language_pack_manager.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/voice_command_service.dart';
import 'package:bagdar/services/vosk_kk_recognizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
    LanguagePackManager.instance.debugReset(packsDir: '/tmp/test_lang_packs');
  });

  group('VoiceCommandService.buildKkClosedGrammar', () {
    test('includes the unknown-token sentinel', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      expect(grammar.contains(VoskKkRecognizer.unknownToken), true);
    });

    test('includes every closed-class kk command phrase', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      
      const samples = <String>[
        'айналада не бар',
        'солда не бар',
        'оңда не бар',
        'алда не бар',
        'оқы',
        'көмек',
        'батарея',
        'сос',
      ];
      for (final phrase in samples) {
        expect(
          grammar.contains(phrase),
          true,
          reason: 'closed-class phrase "$phrase" missing from grammar',
        );
      }
    });

    test('includes kk SOS shouts', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      expect(grammar.contains('жедел көмек'), true);
      expect(grammar.contains('шұғыл көмек'), true);
    });

    test('includes kk cancel-fall acknowledgments', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      
      
      final anyCancel = grammar.any((p) =>
          p.contains('жақсы') ||
          p.contains('дұрыс') ||
          p.contains('жалған'));
      expect(anyCancel, true,
          reason:
              'cancel-fall acknowledgments must appear in the closed grammar '
              'so Vosk can recognize them in safety-critical fall flows');
    });

    test('rejects empty phrases', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      for (final phrase in grammar) {
        expect(phrase.trim().isNotEmpty, true,
            reason: 'grammar contains an empty/whitespace phrase: "$phrase"');
      }
    });

    test('produces no duplicates', () {
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      expect(grammar.length, grammar.toSet().length,
          reason: 'duplicates waste Vosk grammar slots');
    });
  });

  group('VoiceCommandService.useVoskForKk routing flag', () {
    test('default state: feature flag off → Vosk routing inactive', () {
      final svc = VoiceCommandService();
      expect(Settings.instance.enableKazakhStackV2, false);
      expect(svc.useVoskForKk, false);
    });

    test('flag on but pack not installed → Vosk routing still inactive',
        () async {
      await Settings.instance.setEnableKazakhStackV2(true);
      
      final svc = VoiceCommandService();
      
      
      svc.setLocale('kk-KZ');
      expect(svc.useVoskForKk, false);
    });

    test('locale switch back to ru-RU clears Vosk routing intent',
        () async {
      await Settings.instance.setEnableKazakhStackV2(true);
      LanguagePackManager.instance.debugReset(
        packsDir: '/tmp/test_lang_packs',
        installed: const [
          LanguagePack(
            packId: 'vosk-kk',
            name: 'Vosk KK',
            localPath: '/tmp/test_lang_packs/vosk-kk',
            installed: true,
          ),
        ],
      );
      final svc = VoiceCommandService();
      svc.setLocale('kk-KZ');
      svc.setLocale('ru-RU');
      
      
      expect(svc.useVoskForKk, false);
    });
  });

  group('VoiceCommandService parser still works for kk under v2 flag', () {
    
    
    test('kk scan command parses correctly when fed via Vosk path',
        () async {
      await Settings.instance.setEnableKazakhStackV2(true);
      final svc = VoiceCommandService();
      VoiceCommand? captured;
      svc.onCommand = (c) => captured = c;
      svc.processWordsForTesting('айналада не бар', localeOverride: 'kk-KZ');
      expect(captured, VoiceCommand.scanAll);
    });

    test('kk SOS exact phrase still fires sos command', () async {
      await Settings.instance.setEnableKazakhStackV2(true);
      final svc = VoiceCommandService();
      VoiceCommand? captured;
      svc.onCommand = (c) => captured = c;
      svc.processWordsForTesting('жедел көмек', localeOverride: 'kk-KZ');
      expect(captured, VoiceCommand.sos);
    });
  });

  group('Language pack management voice commands', () {
    test('manageLanguagePacks fires for ru/kk/en phrases', () {
      final svc = VoiceCommandService();
      VoiceCommand? captured;
      svc.onCommand = (c) => captured = c;

      svc.processWordsForTesting('языковые пакеты', localeOverride: 'ru-RU');
      expect(captured, VoiceCommand.manageLanguagePacks);

      captured = null;
      svc.processWordsForTesting('тіл пакеттері', localeOverride: 'kk-KZ');
      expect(captured, VoiceCommand.manageLanguagePacks);

      captured = null;
      svc.processWordsForTesting('language packs', localeOverride: 'en-US');
      expect(captured, VoiceCommand.manageLanguagePacks);
    });

    test('enableKkV2 fires for ru/kk/en variants', () {
      final svc = VoiceCommandService();
      VoiceCommand? captured;
      svc.onCommand = (c) => captured = c;

      svc.processWordsForTesting(
        'включи улучшенное распознавание',
        localeOverride: 'ru-RU',
      );
      expect(captured, VoiceCommand.enableKkV2);

      captured = null;
      svc.processWordsForTesting(
        'жетілдірілген тану',
        localeOverride: 'kk-KZ',
      );
      expect(captured, VoiceCommand.enableKkV2);

      captured = null;
      svc.processWordsForTesting(
        'enhanced kazakh',
        localeOverride: 'en-US',
      );
      expect(captured, VoiceCommand.enableKkV2);
    });

    test('disableKkV2 fires for ru/kk/en variants', () {
      final svc = VoiceCommandService();
      VoiceCommand? captured;
      svc.onCommand = (c) => captured = c;

      svc.processWordsForTesting(
        'выключи улучшенное распознавание',
        localeOverride: 'ru-RU',
      );
      expect(captured, VoiceCommand.disableKkV2);

      captured = null;
      svc.processWordsForTesting(
        'қарапайым қазақша тану',
        localeOverride: 'kk-KZ',
      );
      expect(captured, VoiceCommand.disableKkV2);

      captured = null;
      svc.processWordsForTesting(
        'standard kazakh',
        localeOverride: 'en-US',
      );
      expect(captured, VoiceCommand.disableKkV2);
    });

    test('kk closed grammar includes the new manage/enable/disable phrases',
        () {
      
      
      final grammar = VoiceCommandService.buildKkClosedGrammar();
      expect(grammar.contains('тіл пакеттері'), true);
      expect(grammar.contains('жетілдірілген тану'), true);
      expect(grammar.contains('қарапайым қазақша тану'), true);
    });
  });
}

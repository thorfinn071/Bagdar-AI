import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice_command_service.dart';

const List<String> _newKeysFromDesignPlan = [
  'shelf_camera_short',
  'shelf_read_short',
  'shelf_navigate_short',
  'shelf_camera_label',
  'shelf_camera_hint',
  'shelf_read_label',
  'shelf_read_hint',
  'shelf_navigate_label',
  'shelf_navigate_hint',
  'shelf_read_started',
  'shelf_navigate_started',
  'shelf_cane_confirm',
  'ocr_aim_hint',
  'ocr_timeout',
  'ocr_lines_count',
  'processing_heartbeat',
  'pitch_black_heartbeat',
  'offline_banner_no_gps',
  'offline_banner_no_map',
  'settings_save_failed',
  'theme_selected_dark',
  'theme_selected_light',
  'theme_selected_high_contrast',
  'theme_selected_warm',
  'voice_layer_listening',
  'voice_layer_cancel',
  'restart_pipeline',
  'restart_pipeline_done',
];

const Set<String> _allowedEmpty = {
  // pitch_black_heartbeat is intentionally silent — earcon only.
  'pitch_black_heartbeat',
};

VoiceCommand _commandFor(
  VoiceCommandService svc,
  String phrase, {
  required String locale,
}) {
  VoiceCommand? captured;
  svc.onCommand = (c) => captured = c;
  svc.processWordsForTesting(phrase, localeOverride: locale);
  return captured ?? VoiceCommand.unknown;
}

void main() {
  group('Voice script delta — new keys present in all 3 languages', () {
    for (final lang in AppLanguage.values) {
      test('every new key resolves under ${lang.name}', () {
        AppStrings.setLanguage(lang);
        for (final key in _newKeysFromDesignPlan) {
          final value = AppStrings.get(key);
          if (_allowedEmpty.contains(key)) {
            expect(
              value,
              isNot(equals(key)),
              reason:
                  'key="$key" lang=${lang.name} returned the key itself, '
                  'meaning it is missing in all language maps',
            );
            continue;
          }
          expect(
            value.isNotEmpty,
            isTrue,
            reason: 'key="$key" lang=${lang.name} resolved to empty',
          );
          expect(
            value,
            isNot(equals(key)),
            reason:
                'key="$key" lang=${lang.name} fell through to key fallback '
                '— string missing in this language',
          );
        }
      });
    }

    tearDown(() {
      AppStrings.setLanguage(AppLanguage.ru);
    });
  });

  group('VoiceCommand.restartPipeline triggers', () {
    test('Russian phrases', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'перезапусти',
        'перезапусти распознавание',
        'сбрось',
      ]) {
        expect(
          _commandFor(svc, phrase, locale: 'ru-RU'),
          VoiceCommand.restartPipeline,
          reason: 'phrase="$phrase"',
        );
      }
    });

    test('Kazakh phrases', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'қайта қосу',
        'тануды қайта қос',
        'қайта бастау',
      ]) {
        expect(
          _commandFor(svc, phrase, locale: 'kk-KZ'),
          VoiceCommand.restartPipeline,
          reason: 'phrase="$phrase"',
        );
      }
    });

    test('English phrases', () {
      final svc = VoiceCommandService();
      for (final phrase in [
        'restart',
        'restart recognition',
        'reset',
      ]) {
        expect(
          _commandFor(svc, phrase, locale: 'en-US'),
          VoiceCommand.restartPipeline,
          reason: 'phrase="$phrase"',
        );
      }
    });

    test('restart command does not collide with existing commands', () {
      final svc = VoiceCommandService();
      // bare 'reset' / 'restart' must NOT fire SOS / cancelFall
      for (final phrase in ['reset', 'restart']) {
        final cmd = _commandFor(svc, phrase, locale: 'en-US');
        expect(cmd, isNot(VoiceCommand.sos));
        expect(cmd, isNot(VoiceCommand.cancelFall));
      }
    });
  });

  group('Theme voice commands trigger correct VoiceCommand', () {
    final cases = <(String, String, VoiceCommand)>[
      ('тёмная тема', 'ru-RU', VoiceCommand.themeDark),
      ('темная тема', 'ru-RU', VoiceCommand.themeDark),
      ('светлая тема', 'ru-RU', VoiceCommand.themeLight),
      ('высокий контраст', 'ru-RU', VoiceCommand.themeHighContrast),
      ('тёплая тема', 'ru-RU', VoiceCommand.themeWarm),
      ('қара тақырып', 'kk-KZ', VoiceCommand.themeDark),
      ('ашық тақырып', 'kk-KZ', VoiceCommand.themeLight),
      ('жоғары контраст', 'kk-KZ', VoiceCommand.themeHighContrast),
      ('жылы тақырып', 'kk-KZ', VoiceCommand.themeWarm),
      ('dark theme', 'en-US', VoiceCommand.themeDark),
      ('light theme', 'en-US', VoiceCommand.themeLight),
      ('high contrast', 'en-US', VoiceCommand.themeHighContrast),
      ('warm theme', 'en-US', VoiceCommand.themeWarm),
    ];

    for (final (phrase, locale, expected) in cases) {
      test('"$phrase" ($locale) -> ${expected.name}', () {
        final svc = VoiceCommandService();
        expect(
          _commandFor(svc, phrase, locale: locale),
          expected,
        );
      });
    }
  });
}

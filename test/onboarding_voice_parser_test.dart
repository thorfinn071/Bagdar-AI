import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_copy.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_parser.dart';
import 'package:bagdar/models/strings.dart';

void main() {
  for (final language in AppLanguage.values) {
    final i = language.index;
    test(
      '${language.name}: negative answers are distinct from confirmations',
      () {
        final negative = ['не услышал', 'естімедім', 'i did not hear it'][i];
        final positive = ['услышал', 'естідім', 'i heard it'][i];
        expect(
          OnboardingVoiceParser.parse(
            negative,
            language,
            OnboardingVoiceQuestion.stopVoice,
          ),
          OnboardingVoiceIntent.notHeard,
        );
        expect(
          OnboardingVoiceParser.parse(
            positive,
            language,
            OnboardingVoiceQuestion.stopVoice,
          ),
          OnboardingVoiceIntent.heard,
        );
        expect(
          OnboardingVoiceParser.parse(
            positive,
            language,
            OnboardingVoiceQuestion.language,
          ),
          OnboardingVoiceIntent.unknown,
        );
      },
    );
    test(
      '${language.name}: consent is contextual and must match a complete phrase',
      () {
        final consent = [
          'понимаю ограничения',
          'шектеулерді түсінемін',
          'i understand the limits',
        ][i];
        expect(
          OnboardingVoiceParser.parse(
            consent,
            language,
            OnboardingVoiceQuestion.limits,
          ),
          OnboardingVoiceIntent.acceptLimits,
        );
        expect(
          OnboardingVoiceParser.parse(
            consent,
            language,
            OnboardingVoiceQuestion.practice,
          ),
          OnboardingVoiceIntent.unknown,
        );
      },
    );
    test(
      '${language.name}: every question has localized recovery and command hints',
      () {
        final copy = OnboardingVoiceCopy(language);
        for (final question in OnboardingVoiceQuestion.values) {
          expect(copy.question(question).trim(), isNotEmpty);
        }
        for (final key in VoiceCopy.values) {
          expect(copy.t(key).trim(), isNotEmpty);
        }
      },
    );
  }

  for (final text in [
    'да',
    'не понимаю ограничения',
    'не говори стоп',
    'я сказал остановлюсь',
    'услышал но не услышал',
    'отправить sos',
    'пропусти обучение',
    'управление не у меня',
    'не выключай микрофон',
  ]) {
    test('rejects embedded/ambiguous command: $text', () {
      for (final question in OnboardingVoiceQuestion.values) {
        expect(
          OnboardingVoiceParser.parse(text, AppLanguage.ru, question),
          OnboardingVoiceIntent.unknown,
        );
      }
    });
  }

  test('normalizes punctuation and case without dropping negation', () {
    expect(
      OnboardingVoiceParser.parse(
        '  ЕЩЁ   РАЗ! ',
        AppLanguage.ru,
        OnboardingVoiceQuestion.language,
      ),
      OnboardingVoiceIntent.repeat,
    );
    expect(
      OnboardingVoiceParser.parse(
        'НЕ УСЛЫШАЛ.',
        AppLanguage.ru,
        OnboardingVoiceQuestion.ordinaryVoice,
      ),
      OnboardingVoiceIntent.notHeard,
    );
  });

  test(
    'next does not mean consent or permission to accept a feedback sample',
    () {
      for (final question in [
        OnboardingVoiceQuestion.limits,
        OnboardingVoiceQuestion.ordinaryVoice,
        OnboardingVoiceQuestion.stopVoice,
        OnboardingVoiceQuestion.haptic,
        OnboardingVoiceQuestion.handoff,
      ]) {
        expect(
          OnboardingVoiceParser.parse('дальше', AppLanguage.ru, question),
          OnboardingVoiceIntent.unknown,
        );
      }
    },
  );
}

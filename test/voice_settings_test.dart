import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/inspection_voice_coordinator.dart';
import 'package:bagdar/services/voice/voice_input.dart';
import 'package:bagdar/services/voice/voice_settings.dart';
import 'package:bagdar/services/voice/voice_settings_coordinator.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'inspection_voice_test.dart' show GuardedInput, drain;
import 'support/fake_voice_settings_gateway.dart';

void main() {
  late GuardedInput input;
  late FakeVoiceSettingsGateway gateway;
  late VoiceSettingsCoordinator voice;
  var language = AppLanguage.ru;
  var allowed = true;
  var played = true;
  var released = true;
  late List<String> speech;
  VoiceSettingsCoordinator create({
    int maxTurns = 12,
    Duration limit = const Duration(minutes: 2),
  }) => VoiceSettingsCoordinator(
    input: input,
    gateway: gateway,
    language: () => language,
    canInteract: () => allowed,
    speak: (text) async {
      speech.add(text);
      return played;
    },
    prepareInput: () async => released,
    maxTurns: maxTurns,
    sessionLimit: limit,
  );
  setUp(() {
    input = GuardedInput();
    gateway = FakeVoiceSettingsGateway();
    language = AppLanguage.ru;
    allowed = played = released = true;
    speech = [];
    voice = create();
  });
  tearDown(() async {
    voice.dispose();
    await drain();
  });
  Future<void> answer(String text) async {
    input.answer(text);
    await drain();
  }

  Future<void> reviewRate() async {
    await answer('речь');
    await answer('темп');
    await answer('медленнее');
    expect(voice.page, VoiceSettingsPage.review);
  }

  test('opening the coordinator never requests or captures audio', () async {
    await drain();
    expect(input.turns, isEmpty);
    expect(input.permissionRequests, isEmpty);
    expect(gateway.writes, isEmpty);
  });
  final lexicons = {
    AppLanguage.ru: [
      'речь',
      'темп',
      'медленнее',
      'сохранить',
      'громкость',
      'тише',
      'громче',
      'обычная',
      'оформление',
      'светлая',
      'ещё',
      'тёплая',
      'контрастная',
      'тёмная',
      'отменить',
    ],
    AppLanguage.kk: [
      'сөйлеу',
      'қарқын',
      'баяуырақ',
      'сақтау',
      'дыбыс деңгейі',
      'бәсеңірек',
      'қаттырақ',
      'қалыпты',
      'көрініс',
      'жарық',
      'тағы',
      'жылы',
      'контрастты',
      'қараңғы',
      'болдырмау',
    ],
    AppLanguage.en: [
      'speech',
      'rate',
      'slower',
      'save',
      'volume',
      'quieter',
      'louder',
      'normal',
      'appearance',
      'light',
      'more',
      'warm',
      'contrast',
      'dark',
      'cancel',
    ],
  };
  for (final entry in lexicons.entries) {
    test('rate draft and explicit persistence: ${entry.key}', () async {
      language = entry.key;
      gateway.language = language;
      final words = entry.value;
      final running = voice.start(requestPermission: false);
      await drain();
      await answer(words[0]);
      await answer(words[1]);
      await answer(words[2]);
      expect(gateway.writes, isEmpty);
      expect(gateway.rate, 1);
      expect(voice.draft!.number, closeTo(.9, .0001));
      await answer(words[3]);
      await running;
      expect(gateway.writes, hasLength(1));
      expect(gateway.rate, closeTo(.9, .0001));
      expect(input.permissionRequests, [false]);
      expect(input.turns.map((turn) => turn.turn.turnId), [1, 2, 3, 4]);
      expect(voice.active, isFalse);
      expect(voice.draft, isNull);
    });
    for (final mode in ['quieter', 'louder', 'normal']) {
      test('speech volume $mode: ${entry.key}', () async {
        language = entry.key;
        final words = entry.value;
        final running = voice.start(requestPermission: true);
        await drain();
        await answer(words[0]);
        await answer(words[4]);
        await answer(
          words[switch (mode) {
            'quieter' => 5,
            'louder' => 6,
            _ => 7,
          }],
        );
        expect(gateway.writes, isEmpty);
        await answer(words[3]);
        await running;
        expect(gateway.writes.single.kind, VoiceSettingKind.volume);
        expect(
          gateway.volume,
          closeTo(switch (mode) {
            'quieter' => .7,
            'louder' => .9,
            _ => 1.0,
          }, .0001),
        );
      });
    }
    for (final theme in BagdarThemeName.values) {
      test('theme $theme: ${entry.key}', () async {
        language = entry.key;
        gateway.theme = theme == BagdarThemeName.dark
            ? BagdarThemeName.light
            : BagdarThemeName.dark;
        final words = entry.value;
        final running = voice.start(requestPermission: false);
        await drain();
        await answer(words[8]);
        if (theme == BagdarThemeName.highContrast ||
            theme == BagdarThemeName.warm) {
          await answer(words[10]);
        }
        await answer(
          words[switch (theme) {
            BagdarThemeName.dark => 13,
            BagdarThemeName.light => 9,
            BagdarThemeName.highContrast => 12,
            BagdarThemeName.warm => 11,
          }],
        );
        expect(gateway.writes, isEmpty);
        await answer(words[3]);
        await running;
        expect(gateway.writes.single.theme, theme);
        expect(gateway.theme, theme);
      });
    }
  }
  for (final text in [
    'да',
    'нет',
    'не сохранить',
    'не согласен',
    'он сказал сохранить',
    'сохранить настройки и sos',
    'отправить sos',
    'помощь',
    'сохранить громкость',
  ]) {
    test('no implicit consent from $text', () async {
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      await answer(text);
      expect(gateway.writes, isEmpty);
      await answer('отменить');
      await running;
      expect(gateway.writes, isEmpty);
    });
  }
  test('Save at the menu cannot apply a preference', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await answer('сохранить');
    await answer('сохранить');
    await running;
    expect(gateway.writes, isEmpty);
    expect(voice.active, isFalse);
  });
  test('Back discards the proposed value', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await reviewRate();
    await answer('назад');
    expect(voice.page, VoiceSettingsPage.rate);
    expect(voice.draft, isNull);
    await answer('сохранить');
    await answer('отменить');
    await running;
    expect(gateway.writes, isEmpty);
  });
  for (final failure in ['false', 'throw']) {
    test('persistence $failure is not spoken as saved', () async {
      gateway.acknowledgement = false;
      gateway.throwOnSave = failure == 'throw';
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      await answer('сохранить');
      await running;
      expect(gateway.writes, hasLength(1));
      expect(gateway.rate, 1);
      expect(voice.message, contains('не подтверждено'));
      expect(voice.message, isNot(startsWith('Сохранено')));
    });
  }
  test(
    'a value changed by another control cannot be overwritten by an old draft',
    () async {
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      gateway.rate = 1.3;
      await answer('сохранить');
      await running;
      expect(gateway.writes, isEmpty);
      expect(gateway.rate, 1.3);
    },
  );
  for (final confidence in <double?>[
    null,
    .74,
    double.nan,
    double.infinity,
    1.1,
  ]) {
    test('cannot save with confidence $confidence', () async {
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      input.answer('сохранить', confidence: confidence);
      await running;
      expect(gateway.writes, isEmpty);
    });
  }
  for (final kind in ['partial', 'session', 'turn', 'backend', 'not-ready']) {
    test('invalid confirmation identity $kind', () async {
      final running = voice.start(requestPermission: false);
      await drain();
      if (kind == 'not-ready') {
        await answer('речь');
        await answer('темп');
        input.autoReady = false;
        await answer('медленнее');
      } else {
        await reviewRate();
      }
      if (kind == 'backend') {
        final pending = input.pending!;
        input.pending = null;
        pending.result.complete(
          VoiceInputResult(
            sessionId: pending.turn.sessionId,
            turnId: pending.turn.turnId,
            text: 'сохранить',
            confidence: .99,
            backend: 'network',
            outcome: VoiceInputOutcome.recognized,
          ),
        );
      } else {
        input.answer(
          'сохранить',
          isFinal: kind != 'partial',
          sessionId: kind == 'session' ? -1 : null,
          turnId: kind == 'turn' ? -1 : null,
        );
      }
      await running;
      expect(gateway.writes, isEmpty);
    });
  }
  for (final outcome in VoiceInputOutcome.values.where(
    (value) => value != VoiceInputOutcome.recognized,
  )) {
    test('confirmation outcome $outcome cannot save', () async {
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      input.answer('сохранить', outcome: outcome);
      await running;
      expect(gateway.writes, isEmpty);
    });
  }
  for (final event in ['background', 'language', 'critical', 'route']) {
    test('late Save after $event cannot write', () async {
      input.completeOnCancel = false;
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      final pending = input.pending!;
      if (event == 'language') {
        language = AppLanguage.en;
      } else if (event == 'route') {
        allowed = false;
      } else {
        await voice.interrupt();
      }
      input.complete(pending, 'сохранить');
      await running;
      expect(gateway.writes, isEmpty);
    });
  }
  test('native teardown failure blocks Save and restart', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await reviewRate();
    input.failCancel = true;
    input.answer('сохранить');
    await running;
    expect(gateway.writes, isEmpty);
    expect(voice.canStart, isFalse);
    expect(voice.message, contains('не подтверждена'));
    input.failCancel = false;
  });
  test('Save waits for acknowledged microphone teardown', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await reviewRate();
    input.closing = Completer<void>();
    input.answer('сохранить');
    await drain();
    expect(gateway.writes, isEmpty);
    input.closing!.complete();
    await running;
    expect(gateway.writes, hasLength(1));
  });
  test('failed confirmation prompt never opens another input window', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await answer('речь');
    await answer('темп');
    played = false;
    input.answer('медленнее');
    await running;
    expect(input.turns, hasLength(3));
    expect(gateway.writes, isEmpty);
    expect(voice.phase, InspectionVoicePhase.unavailable);
  });
  for (final availability in VoiceInputAvailability.values.where(
    (value) => value != VoiceInputAvailability.ready,
  )) {
    test(
      'unavailable input $availability has no writes or automatic retries',
      () async {
        input.availability = availability;
        await voice.start(requestPermission: false);
        expect(input.turns, isEmpty);
        expect(input.permissionRequests, [false]);
        expect(gateway.writes, isEmpty);
      },
    );
  }
  test('overview reads language and signals without changing either', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await answer('обзор');
    expect(speech.any((text) => text.contains('Язык: русский')), isTrue);
    expect(speech.any((text) => text.contains('Вибрация: обычная')), isTrue);
    await answer('отменить');
    await running;
    expect(gateway.writes, isEmpty);
  });
  test('an unchanged limit value is not written', () async {
    gateway.rate = .6;
    final running = voice.start(requestPermission: false);
    await drain();
    await answer('речь');
    await answer('темп');
    await answer('медленнее');
    expect(voice.page, VoiceSettingsPage.rate);
    expect(voice.draft, isNull);
    await answer('отменить');
    await running;
    expect(gateway.writes, isEmpty);
  });
  test('duplicate start cannot create a competing settings dialogue', () async {
    final running = voice.start(requestPermission: false);
    await drain();
    await voice.start(requestPermission: true);
    expect(input.turns, hasLength(1));
    expect(input.permissionRequests, [false]);
    await answer('отменить');
    await running;
  });
  testWidgets('finite turn budget terminates without a background ASR loop', (
    tester,
  ) async {
    voice.dispose();
    voice = create(maxTurns: 2);
    final running = voice.start(requestPermission: false);
    await tester.pump();
    input.answer('повтори');
    await tester.pump();
    input.answer('повтори');
    await tester.pump();
    await running;
    expect(input.turns, hasLength(2));
    expect(voice.active, isFalse);
    expect(gateway.writes, isEmpty);
  });
  testWidgets('session deadline discards a pending draft', (tester) async {
    voice.dispose();
    voice = create(limit: const Duration(seconds: 2));
    final running = voice.start(requestPermission: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await running;
    expect(voice.draft, isNull);
    expect(voice.active, isFalse);
    expect(gateway.writes, isEmpty);
    expect(input.turns, hasLength(1));
  });
  test(
    'an accepted write already in flight is not falsely described as rolled back',
    () async {
      gateway.pendingSave = Completer<bool>();
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      input.answer('сохранить');
      await drain();
      expect(gateway.writes, hasLength(1));
      await voice.interrupt();
      expect(voice.canStart, isFalse);
      gateway.pendingSave!.complete(true);
      await running;
      expect(gateway.rate, closeTo(.9, .0001));
      expect(voice.message, contains('прерван'));
      expect(voice.message, isNot(contains('не применены')));
    },
  );
  test('a previous dialogue cannot confirm a draft in a new session', () async {
    input.completeOnCancel = false;
    final first = voice.start(requestPermission: false);
    await drain();
    await reviewRate();
    final old = input.pending!;
    await voice.interrupt();
    final next = voice.start(requestPermission: false);
    await drain();
    old.onReady();
    input.complete(old, 'сохранить');
    await first;
    expect(gateway.writes, isEmpty);
    input.answer('отменить');
    await next;
    expect(gateway.writes, isEmpty);
  });
  test(
    'a saved preference remains visible when its spoken confirmation fails',
    () async {
      final running = voice.start(requestPermission: false);
      await drain();
      await reviewRate();
      played = false;
      input.answer('сохранить');
      await running;
      expect(gateway.writes, hasLength(1));
      expect(gateway.rate, closeTo(.9, .0001));
      expect(voice.message, contains('Сохранено'));
      expect(voice.message, contains('Озвучка не подтверждена'));
      expect(voice.phase, InspectionVoicePhase.unavailable);
    },
  );
  testWidgets('confirmation shutdown timeout cannot write a preference', (
    tester,
  ) async {
    final running = voice.start(requestPermission: false);
    await tester.pump();
    for (final text in ['речь', 'темп', 'медленнее']) {
      input.answer(text);
      await tester.pump();
    }
    input.closing = Completer<void>();
    input.answer('сохранить');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await running;
    expect(gateway.writes, isEmpty);
    expect(voice.canStart, isFalse);
    input.closing!.complete();
    await tester.pump();
  });
  test(
    'a delayed OS permission result cannot reopen an interrupted dialogue',
    () async {
      input.preparation = Completer<VoiceInputAvailability>();
      final pending = input.preparation!;
      final running = voice.start(requestPermission: true);
      await drain();
      await voice.interrupt();
      pending.complete(VoiceInputAvailability.ready);
      await running;
      expect(input.turns, isEmpty);
      expect(gateway.writes, isEmpty);
    },
  );
  for (final language in AppLanguage.values) {
    test(
      'context parser excludes bare agreement, unrelated values and negation: $language',
      () {
        for (final page in VoiceSettingsPage.values) {
          for (final phrase in [
            'да',
            'yes',
            'иә',
            'не сохранить',
            'do not save',
            'сақтама',
            'sos',
            'помощь',
            'выключить сигналы',
            'русский',
          ]) {
            expect(parseVoiceSettings(phrase, language, page), isNull);
          }
        }
        final save = lexicons[language]![3];
        expect(
          parseVoiceSettings(save, language, VoiceSettingsPage.review),
          VoiceSettingsIntent.save,
        );
        expect(
          parseVoiceSettings(save, language, VoiceSettingsPage.menu),
          isNull,
        );
      },
    );
  }
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/inspection_voice_commands.dart';
import 'package:bagdar/services/voice/inspection_voice_coordinator.dart';
import 'package:bagdar/services/voice/voice_input.dart';
import 'support/fake_onboarding_voice_input.dart';

class GuardedInput extends FakeOnboardingVoiceInput {
  bool failCancel = false;
  Completer<void>? closing;
  @override
  Future<void> cancel() async {
    if (failCancel) throw StateError('shutdown_unconfirmed');
    await closing?.future;
    await super.cancel();
  }
}

Future<void> drain() async {
  for (var i = 0; i < 25; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late GuardedInput input;
  late InspectionVoiceCoordinator voice;
  late List<InspectionVoiceCommand> actions;
  late List<String> speech;
  var language = AppLanguage.ru;
  var allowed = true;
  var played = true;
  Completer<bool>? speechGate;
  setUp(() {
    input = GuardedInput();
    actions = [];
    speech = [];
    language = AppLanguage.ru;
    allowed = played = true;
    speechGate = null;
    voice = InspectionVoiceCoordinator(
      input: input,
      language: () => language,
      canInteract: () => allowed,
      speak: (text) async {
        speech.add(text);
        return speechGate == null ? played : speechGate!.future;
      },
      execute: (command) async {
        actions.add(command);
        return 'hardware status';
      },
    );
  });
  tearDown(() async {
    voice.dispose();
    await drain();
  });

  test('no recording or permission request on construction', () async {
    await drain();
    expect(input.turns, isEmpty);
    expect(input.permissionRequests, isEmpty);
  });
  for (final entry in {
    AppLanguage.ru: 'статус',
    AppLanguage.kk: 'күйі',
    AppLanguage.en: 'status',
  }.entries) {
    test(
      'one local bounded command and confirmed release: ${entry.key}',
      () async {
        language = entry.key;
        final running = voice.start();
        await drain();
        expect(voice.phase, InspectionVoicePhase.listening);
        expect(input.turns.single.turn.duration, const Duration(seconds: 8));
        input.answer(entry.value);
        await running;
        expect(actions, [InspectionVoiceCommand.status]);
        expect(input.cancels, greaterThanOrEqualTo(2));
        expect(voice.active, isFalse);
        expect(input.turns, hasLength(1)); // No automatic relisten.
      },
    );
  }
  test('waits for prompt playback and native readiness separately', () async {
    speechGate = Completer<bool>();
    input.autoReady = false;
    final running = voice.start();
    await drain();
    expect(input.turns, isEmpty);
    expect(input.permissionRequests, isEmpty);
    speechGate!.complete(true);
    await drain();
    expect(input.turns, hasLength(1));
    expect(voice.phase, InspectionVoicePhase.preparing);
    input.pending!.onReady();
    expect(voice.phase, InspectionVoicePhase.listening);
    input.answer('статус');
    await running;
    expect(actions, [InspectionVoiceCommand.status]);
  });
  test('failed speech cannot request permission or start input', () async {
    played = false;
    await voice.start();
    expect(input.permissionRequests, isEmpty);
    expect(input.turns, isEmpty);
    expect(voice.phase, InspectionVoicePhase.unavailable);
  });
  for (final availability in VoiceInputAvailability.values.where(
    (value) => value != VoiceInputAvailability.ready,
  )) {
    test('no fallback or retry after $availability', () async {
      input.availability = availability;
      await voice.start();
      expect(input.permissionRequests, [true]);
      expect(input.turns, isEmpty);
      expect(actions, isEmpty);
    });
  }
  for (final text in [
    'не статус',
    'не открывай настройки',
    'не закончить осмотр',
    'он сказал настройки',
    'да',
    'нет',
    'sos',
    'сос',
    'помощь',
    'отмени падение',
    'начать осмотр',
    'режим улица',
    'описать сцену',
  ]) {
    test('no action from invalid or unsafe phrase: $text', () async {
      final running = voice.start();
      await drain();
      input.answer(text);
      await running;
      expect(actions, isEmpty);
    });
  }
  for (final confidence in <double?>[
    null,
    .74,
    double.nan,
    double.infinity,
    1.1,
  ]) {
    test('confidence rejection $confidence', () async {
      final running = voice.start();
      await drain();
      input.answer('статус', confidence: confidence);
      await running;
      expect(actions, isEmpty);
    });
  }
  for (final kind in ['partial', 'session', 'turn', 'not-ready', 'backend']) {
    test('identity and readiness rejection $kind', () async {
      input.autoReady = kind != 'not-ready';
      final running = voice.start();
      await drain();
      if (kind == 'backend') {
        final pending = input.pending!;
        input.pending = null;
        pending.result.complete(
          VoiceInputResult(
            sessionId: pending.turn.sessionId,
            turnId: pending.turn.turnId,
            outcome: VoiceInputOutcome.recognized,
            text: 'статус',
            confidence: .99,
            backend: 'network',
          ),
        );
      } else {
        input.answer(
          'статус',
          isFinal: kind != 'partial',
          sessionId: kind == 'session' ? -1 : null,
          turnId: kind == 'turn' ? -1 : null,
        );
      }
      await running;
      expect(actions, isEmpty);
    });
  }
  for (final outcome in VoiceInputOutcome.values.where(
    (value) => value != VoiceInputOutcome.recognized,
  )) {
    test('no action for $outcome', () async {
      final running = voice.start();
      await drain();
      input.answer('статус', outcome: outcome);
      await running;
      expect(actions, isEmpty);
      expect(voice.active, isFalse);
    });
  }
  test('a duplicate start cannot open another window', () async {
    final running = voice.start();
    await drain();
    await voice.start();
    expect(input.turns, hasLength(1));
    input.answer('статус');
    await running;
  });
  for (final event in ['background', 'language', 'critical', 'route']) {
    test('late answer after $event is discarded', () async {
      input.completeOnCancel = false;
      final running = voice.start();
      await drain();
      final pending = input.pending!;
      if (event == 'language') {
        language = AppLanguage.en;
      } else if (event == 'route') {
        allowed = false;
      } else {
        await voice.interrupt();
      }
      input.complete(pending, 'статус');
      await running;
      expect(actions, isEmpty);
    });
  }
  test('old ready and result cannot affect a new session', () async {
    input.completeOnCancel = false;
    final old = voice.start();
    await drain();
    final pending = input.pending!;
    await voice.interrupt();
    final next = voice.start();
    await drain();
    pending.onReady();
    input.complete(pending, 'настройки');
    await old;
    input.answer('статус');
    await next;
    expect(actions, [InspectionVoiceCommand.status]);
  });
  test('action waits for native teardown acknowledgement', () async {
    final running = voice.start();
    await drain();
    input.closing = Completer<void>();
    input.answer('настройки');
    await drain();
    expect(actions, isEmpty);
    input.closing!.complete();
    await running;
    expect(actions, [InspectionVoiceCommand.settings]);
  });
  test('teardown failure blocks action, off claim and new input', () async {
    final running = voice.start();
    await drain();
    input.failCancel = true;
    input.answer('настройки');
    await running;
    expect(actions, isEmpty);
    expect(voice.phase, InspectionVoicePhase.unavailable);
    expect(voice.message, contains('не подтверждена'));
    expect(voice.canStart, isFalse);
    await voice.start();
    expect(input.turns, hasLength(1));
    expect(await voice.interrupt(), isFalse);
    input.failCancel = false;
  });
  test('delayed permission cannot reopen input after interruption', () async {
    input.preparation = Completer<VoiceInputAvailability>();
    final preparation = input.preparation!;
    final running = voice.start();
    await drain();
    await voice.interrupt();
    preparation.complete(VoiceInputAvailability.ready);
    await running;
    expect(input.turns, isEmpty);
  });
  test(
    'microphone-off command stops without executing a product action',
    () async {
      final running = voice.start();
      await drain();
      input.answer('выключить микрофон');
      await running;
      expect(actions, isEmpty);
      expect(voice.message, contains('Микрофон выключен'));
      expect(input.turns, hasLength(1));
    },
  );
  test(
    'route action is cancelled if warning interrupts its announcement',
    () async {
      final running = voice.start();
      await drain();
      speechGate = Completer<bool>();
      input.answer('закончить осмотр');
      await drain();
      await voice.interrupt();
      speechGate!.complete(true);
      await running;
      expect(actions, isEmpty);
    },
  );
  test('repeat refreshes ephemeral service status', () async {
    final first = voice.start();
    await drain();
    input.answer('статус');
    await first;
    final second = voice.start();
    await drain();
    input.answer('повтори');
    await second;
    expect(actions, [
      InspectionVoiceCommand.status,
      InspectionVoiceCommand.status,
    ]);
  });
  testWidgets('an unanswered window times out and never relistens', (
    tester,
  ) async {
    final running = voice.start();
    await tester.pump();
    expect(input.turns, hasLength(1));
    await tester.pump(const Duration(seconds: 11));
    await running;
    expect(actions, isEmpty);
    expect(input.turns, hasLength(1));
    expect(voice.active, isFalse);
  });
  testWidgets('shutdown timeout blocks an otherwise valid command', (
    tester,
  ) async {
    final running = voice.start();
    await tester.pump();
    input.closing = Completer<void>();
    input.answer('настройки');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await running;
    expect(actions, isEmpty);
    expect(voice.phase, InspectionVoicePhase.unavailable);
    input.closing!.complete();
    await tester.pump();
  });
  test('ordinary input refuses unacknowledged emergency release', () async {
    voice.dispose();
    voice = InspectionVoiceCoordinator(
      input: input,
      language: () => language,
      canInteract: () => allowed,
      prepareInput: () async => false,
      speak: (_) async => true,
      execute: (command) async {
        actions.add(command);
        return null;
      },
    );
    await voice.start();
    expect(input.turns, isEmpty);
    expect(input.permissionRequests, isEmpty);
    expect(actions, isEmpty);
    expect(voice.message, contains('не подтверждена'));
  });
  test('unavailable actions are refused before their announcement', () async {
    voice.dispose();
    voice = InspectionVoiceCoordinator(
      input: input,
      language: () => language,
      canInteract: () => allowed,
      isAllowed: (_) => false,
      speak: (text) async {
        speech.add(text);
        return true;
      },
      execute: (command) async {
        actions.add(command);
        return null;
      },
    );
    final running = voice.start();
    await drain();
    input.answer('закончить осмотр');
    await running;
    expect(actions, isEmpty);
    expect(
      speech,
      isNot(
        contains(inspectionVoiceText(InspectionVoiceCopy.finish, language)),
      ),
    );
    expect(voice.message, contains('недоступна'));
  });
  for (final language in AppLanguage.values) {
    test('parser accepts only exact phrases in $language', () {
      final phrases = switch (language) {
        AppLanguage.ru => [
          'статус',
          'справка',
          'повтори',
          'медленнее',
          'быстрее',
          'настройки',
          'закончить осмотр',
          'выключить микрофон',
        ],
        AppLanguage.kk => [
          'күйі',
          'анықтама',
          'қайтала',
          'баяуырақ',
          'жылдамырақ',
          'баптаулар',
          'тексеруді аяқтау',
          'микрофонды өшір',
        ],
        AppLanguage.en => [
          'status',
          'help',
          'repeat',
          'slower',
          'faster',
          'settings',
          'finish inspection',
          'turn off microphone',
        ],
      };
      for (var i = 0; i < phrases.length; i++) {
        expect(
          parseInspectionVoice('  ${phrases[i].toUpperCase()}! ', language),
          InspectionVoiceCommand.values[i],
        );
        expect(parseInspectionVoice('no ${phrases[i]}', language), isNull);
      }
    });
  }
}

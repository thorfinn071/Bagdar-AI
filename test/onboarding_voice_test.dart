import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_coordinator.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_input.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_parser.dart';
import 'package:bagdar/models/strings.dart';
import 'onboarding_v2_test.dart' show TestGateway;
import 'support/fake_onboarding_voice_input.dart';

class VoiceFailingStore extends MemoryOnboardingStore {
  @override
  Future<void> save(OnboardingProgress value) async => throw StateError('save');
}

Future<void> drainVoice() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late OnboardingController c;
  late TestGateway gateway;
  late FakeOnboardingVoiceInput input;
  late OnboardingVoiceCoordinator voice;

  Future<void> setup({
    AppLanguage language = AppLanguage.ru,
    OnboardingStep step = OnboardingStep.language,
    OnboardingStore? store,
  }) async {
    final clock = DateTime(2026, 10, 13, 12);
    gateway = TestGateway(() => clock);
    c = OnboardingController(
      store: store ?? MemoryOnboardingStore(),
      gateway: gateway,
      initialLanguage: language,
      now: () => clock,
    );
    await c.initialize();
    if (step != c.step) await c.goTo(step);
    input = FakeOnboardingVoiceInput();
    voice = OnboardingVoiceCoordinator(controller: c, input: input);
  }

  tearDown(() async {
    voice.dispose();
    c.dispose();
    await drainVoice();
  });

  test(
    'construction and controller updates do not request or capture audio',
    () async {
      await setup();
      await drainVoice();
      await c.selectLanguage(AppLanguage.en);
      expect(input.permissionRequests, isEmpty);
      expect(input.turns, isEmpty);
      expect(gateway.requests, 0);
      expect(gateway.cameraChecks, 0);
    },
  );

  test(
    'microphone waits for successful speech and real ready callback',
    () async {
      await setup();
      final speech = Completer<bool>();
      gateway.pendingSpeech = speech;
      input.autoReady = false;
      await voice.enable();
      await drainVoice();
      expect(c.speaking, isTrue);
      expect(input.turns, isEmpty);
      expect(voice.phase, OnboardingVoicePhase.speaking);
      gateway.pendingSpeech = null;
      speech.complete(true);
      await drainVoice();
      expect(voice.phase, OnboardingVoicePhase.arming);
      input.pending!.onReady();
      expect(voice.phase, OnboardingVoicePhase.listening);
    },
  );

  for (final availability in VoiceInputAvailability.values.where(
    (value) => value != VoiceInputAvailability.ready,
  )) {
    test('$availability never opens a listening window or camera', () async {
      await setup();
      input.availability = availability;
      await voice.enable();
      await drainVoice();
      expect(voice.enabled, isFalse);
      expect(voice.phase, OnboardingVoicePhase.unavailable);
      expect(input.turns, isEmpty);
      expect(gateway.requests, 0);
      expect(gateway.cameraChecks, 0);
    });
  }

  test(
    'failed TTS cannot open the microphone or confirm a feedback sample',
    () async {
      await setup(step: OnboardingStep.feedback);
      gateway.audible = false;
      await voice.enable();
      await drainVoice();
      expect(input.turns, isEmpty);
      expect(c.evidence.voiceSamplePlayed, isFalse);
      expect(c.evidence.criticalChannelVerified, isFalse);
      expect(voice.phase, OnboardingVoicePhase.unavailable);
    },
  );

  for (final language in AppLanguage.values) {
    test(
      '${language.name}: full camera-free dialogue uses the existing gate',
      () async {
        await setup(language: language);
        await voice.enable();
        await drainVoice();
        final i = language.index;
        var count = 0;
        while (c.step != OnboardingStep.camera && count++ < 120) {
          expect(
            input.pending,
            isNotNull,
            reason: '${voice.phase}: ${voice.status}',
          );
          final response = switch (voice.question!) {
            OnboardingVoiceQuestion.language => [
              'русский',
              'қазақша',
              'english',
            ][i],
            OnboardingVoiceQuestion.access => [
              'самостоятельно',
              'өзім',
              'myself',
            ][i],
            OnboardingVoiceQuestion.limits => [
              'понимаю ограничения',
              'шектеулерді түсінемін',
              'i understand the limits',
            ][i],
            OnboardingVoiceQuestion.ordinaryVoice ||
            OnboardingVoiceQuestion.stopVoice => [
              'услышал',
              'естідім',
              'i heard it',
            ][i],
            OnboardingVoiceQuestion.haptic => [
              'почувствовал',
              'сездім',
              'i felt it',
            ][i],
            OnboardingVoiceQuestion.practice =>
              c.practiceAnswered
                  ? ['дальше', 'келесі', 'next'][i]
                  : switch (c.practiceIndex) {
                      0 || 2 => ['остановлюсь', 'тоқтаймын', 'i will stop'][i],
                      1 => ['проверю', 'тексеремін', 'i will check'][i],
                      _ => ['пауза', 'үзіліс', 'pause'][i],
                    },
            OnboardingVoiceQuestion.paused => [
              'продолжить',
              'жалғастыру',
              'continue',
            ][i],
            _ => ['дальше', 'келесі', 'next'][i],
          };
          input.answer(response);
          await drainVoice();
        }
        expect(count, lessThan(120));
        expect(c.step, OnboardingStep.camera);
        expect(c.progress.completedExercises, 4);
        expect(c.trainingComplete, isTrue);
        expect(c.admission, Admission.recheckRequired);
        expect(c.gate.mayStartGenericAssistive, isFalse);
        expect(c.evidence.cameraAccess, CameraAccess.notRequested);
        expect(gateway.requests, 0);
        expect(gateway.cameraChecks, 0);
        expect(gateway.alignmentChecks, 0);
        expect(input.pending, isNotNull);
        expect(voice.question, OnboardingVoiceQuestion.camera);
        expect(voice.enabled, isTrue);
      },
    );
  }

  test('generic yes, next and negated consent cannot accept limits', () async {
    await setup(step: OnboardingStep.limits);
    await voice.enable();
    await drainVoice();
    while (voice.question == OnboardingVoiceQuestion.information) {
      input.answer('дальше');
      await drainVoice();
    }
    expect(voice.question, OnboardingVoiceQuestion.limits);
    input.answer('да');
    await drainVoice();
    expect(c.limitsAccepted, isFalse);
    input.answer('дальше');
    await drainVoice();
    expect(c.limitsAccepted, isFalse);
    input.answer('не согласен');
    await drainVoice();
    expect(c.limitsAccepted, isFalse);
    expect(c.step, OnboardingStep.limits);
    expect(c.progress.complete(OnboardingStep.limits), isFalse);
  });

  test('helper cannot give personal answers until explicit handoff', () async {
    await setup(step: OnboardingStep.access);
    await voice.enable();
    await drainVoice();
    input.answer('с помощником');
    await drainVoice();
    expect(c.userHasControl, isFalse);
    expect(voice.question, OnboardingVoiceQuestion.handoff);
    input.answer('понимаю ограничения');
    await drainVoice();
    expect(c.limitsAccepted, isFalse);
    expect(c.step, OnboardingStep.access);
    input.answer('управление у меня');
    await drainVoice();
    expect(c.userHasControl, isTrue);
    expect(c.step, OnboardingStep.limits);
    expect(c.evidence.criticalChannelVerified, isFalse);
  });

  test(
    'negative hearing and missing vibration never create verification',
    () async {
      await setup(step: OnboardingStep.feedback);
      gateway.haptic = false;
      await voice.enable();
      await drainVoice();
      input.answer('не услышал');
      await drainVoice();
      expect(c.evidence.ordinaryVoiceConfirmed, isFalse);
      expect(c.evidence.voiceConfirmed, isFalse);
      input.answer('услышал');
      await drainVoice();
      expect(voice.question, OnboardingVoiceQuestion.stopVoice);
      input.answer('услышал');
      await drainVoice();
      expect(voice.question, OnboardingVoiceQuestion.haptic);
      input.answer('почувствовал');
      await drainVoice();
      expect(c.evidence.hapticConfirmed, isFalse);
      expect(c.evidence.hapticPlayed, isFalse);
      input.answer('без вибрации');
      await drainVoice();
      expect(voice.question, OnboardingVoiceQuestion.feedbackDone);
      expect(c.evidence.voiceConfirmed, isTrue);
    },
  );

  test('wrong practice answer and next do not complete an exercise', () async {
    await setup(step: OnboardingStep.practice);
    await voice.enable();
    await drainVoice();
    input.answer('пойду');
    await drainVoice();
    expect(c.practiceAnswered, isFalse);
    expect(c.practiceIndex, 0);
    input.answer('дальше');
    await drainVoice();
    expect(c.progress.completedExercises, 0);
    input.answer('остановлюсь');
    await drainVoice();
    expect(c.practiceAnswered, isTrue);
    expect(c.progress.completedExercises, 0);
    input.answer('дальше');
    await drainVoice();
    expect(c.progress.completedExercises, 1);
  });

  for (final invalid in [
    'partial',
    'session',
    'turn',
    'noReady',
    'lowScore',
    'noScore',
    'nanScore',
  ]) {
    test('$invalid cannot advance the language question', () async {
      await setup();
      input.autoReady = invalid != 'noReady';
      await voice.enable();
      await drainVoice();
      input.answer(
        'дальше',
        isFinal: invalid != 'partial',
        sessionId: invalid == 'session' ? -1 : null,
        turnId: invalid == 'turn' ? -1 : null,
        confidence: switch (invalid) {
          'lowScore' => 0.1,
          'noScore' => null,
          'nanScore' => double.nan,
          _ => 0.95,
        },
      );
      await drainVoice();
      expect(c.step, OnboardingStep.language);
      expect(c.progress.complete(OnboardingStep.language), isFalse);
    });
  }

  test(
    'a stale ready/result after screen navigation cannot answer the new question',
    () async {
      await setup();
      input.completeOnCancel = false;
      await voice.enable();
      await drainVoice();
      final old = input.pending!;
      await c.goTo(OnboardingStep.practice);
      old.onReady();
      input.complete(old, 'дальше');
      await drainVoice();
      expect(c.step, OnboardingStep.practice);
      expect(c.practiceIndex, 0);
      expect(c.practiceAnswered, isFalse);
      expect(voice.question, OnboardingVoiceQuestion.practice);
      final current = input.pending!;
      expect(current.turn.turnId, isNot(old.turn.turnId));
      input.answer('остановлюсь', turnId: old.turn.turnId);
      await drainVoice();
      expect(c.practiceAnswered, isFalse);
      input.completeOnCancel = true;
    },
  );

  test(
    'background and resume invalidate pending answer and re-read permission',
    () async {
      await setup(step: OnboardingStep.practice);
      await voice.enable();
      await drainVoice();
      voice.suspend();
      c.suspend(background: true);
      await drainVoice();
      expect(voice.phase, OnboardingVoicePhase.suspended);
      expect(input.pending, isNull);
      expect(c.practiceIndex, 0);
      await c.resume();
      await voice.resume();
      await drainVoice();
      expect(input.permissionRequests, [true, false]);
      expect(voice.question, OnboardingVoiceQuestion.paused);
      input.answer('продолжить');
      await drainVoice();
      expect(voice.question, OnboardingVoiceQuestion.practice);
    },
  );

  test(
    'permission dialog return cannot use its old activation generation',
    () async {
      await setup();
      final prepared = Completer<VoiceInputAvailability>();
      input.preparation = prepared;
      final enabling = voice.enable();
      voice.suspend();
      c.suspend(background: true);
      await c.resume();
      await voice.resume();
      prepared.complete(VoiceInputAvailability.ready);
      await enabling;
      await drainVoice();
      expect(input.permissionRequests, [true, false]);
      expect(voice.phase, OnboardingVoicePhase.listening);
      expect(c.step, OnboardingStep.language);
    },
  );

  test('interrupted turn remains suspended until explicit resume', () async {
    await setup();
    await voice.enable();
    await drainVoice();
    input.answer('', outcome: VoiceInputOutcome.interrupted);
    await drainVoice();
    final turns = input.turns.length;
    expect(voice.phase, OnboardingVoicePhase.suspended);
    c.confirmStationary(false); // unrelated notification
    await drainVoice();
    expect(input.turns.length, turns);
    await voice.resume();
    await drainVoice();
    expect(input.turns.length, turns + 1);
    expect(input.permissionRequests, [true, false]);
  });

  test(
    'bounded silence announces recovery and closes the microphone',
    () async {
      await setup();
      await voice.enable();
      await drainVoice();
      for (var i = 0; i < 3; i++) {
        input.answer('', outcome: VoiceInputOutcome.noSpeech);
        await drainVoice();
      }
      expect(voice.enabled, isFalse);
      expect(voice.phase, OnboardingVoicePhase.suspended);
      expect(input.pending, isNull);
      expect(c.step, OnboardingStep.language);
      expect(gateway.spokenTexts.last, contains('Микрофон выключен'));
    },
  );

  test(
    'language unavailable does not silently choose another engine or language',
    () async {
      await setup(language: AppLanguage.kk);
      await voice.enable();
      await drainVoice();
      input.answer('', outcome: VoiceInputOutcome.languageUnavailable);
      await drainVoice();
      expect(voice.phase, OnboardingVoicePhase.unavailable);
      expect(voice.enabled, isFalse);
      expect(c.progress.language, AppLanguage.kk);
    },
  );

  test(
    'turning off is accepted conservatively without a confidence score',
    () async {
      await setup();
      await voice.enable();
      await drainVoice();
      input.answer('выключить микрофон', confidence: null);
      await drainVoice();
      expect(voice.enabled, isFalse);
      expect(voice.phase, OnboardingVoicePhase.off);
      expect(input.pending, isNull);
      expect(c.step, OnboardingStep.language);
    },
  );

  test(
    'save failure is reported without continuing in the old language',
    () async {
      await setup(store: VoiceFailingStore());
      await voice.enable();
      await drainVoice();
      input.answer('английский');
      await drainVoice();
      expect(c.progress.language, AppLanguage.ru);
      expect(c.step, OnboardingStep.language);
      expect(voice.enabled, isFalse);
      expect(voice.phase, OnboardingVoicePhase.suspended);
    },
  );

  test(
    'stop during pending speech leaves no delayed listening window',
    () async {
      await setup();
      final speech = Completer<bool>();
      gateway.pendingSpeech = speech;
      await voice.enable();
      await drainVoice();
      final disabling = voice.disable();
      gateway.pendingSpeech = null;
      speech.complete(true);
      await disabling;
      await drainVoice();
      expect(voice.phase, OnboardingVoicePhase.off);
      expect(input.turns, isEmpty);
      expect(c.speaking, isFalse);
    },
  );
}

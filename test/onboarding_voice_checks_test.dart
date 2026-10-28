import 'dart:async';

import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_coordinator.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_copy.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_parser.dart';
import 'package:bagdar/models/strings.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onboarding_v2_test.dart' show TestGateway;
import 'onboarding_voice_test.dart' show drainVoice;
import 'support/fake_onboarding_voice_input.dart';

class CheckVoiceInput extends FakeOnboardingVoiceInput {
  bool failClosing = false;
  @override
  Future<void> cancel() async {
    if (failClosing) throw StateError('cancel_unacknowledged');
    await super.cancel();
  }
}

class CheckVoiceGateway extends TestGateway {
  bool settingsAvailable = true;
  int settingsOpened = 0;
  DeviceProbe? deviceResult;
  CheckVoiceGateway(super.clock);
  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return settingsAvailable;
  }

  @override
  Future<DeviceProbe> checkCamera() async {
    if (deviceResult == null) return super.checkCamera();
    cameraChecks++;
    return deviceResult!;
  }
}

/// Fake OS, ASR and hardware only. No named-device readiness evidence.
class CheckVoiceRig {
  DateTime now = DateTime(2026, 10, 13, 12);
  late final CheckVoiceGateway gateway;
  final input = CheckVoiceInput();
  late final OnboardingController c;
  late final OnboardingVoiceCoordinator voice;
  int opened = 0;

  Future<void> init({
    AppLanguage language = AppLanguage.ru,
    bool trained = true,
    OnboardingStep? step,
    AccessMode mode = AccessMode.voice,
    bool inspectionRoute = true,
    CameraAccess access = CameraAccess.granted,
  }) async {
    gateway = CheckVoiceGateway(() => now);
    gateway.access = access;
    final store = MemoryOnboardingStore();
    if (trained) {
      store.progress = OnboardingProgress(
        language: language,
        accessMode: mode,
        checkpoint: OnboardingStep.summary,
        modules: {
          for (final s in OnboardingSessionGate.requiredSetup)
            s: ModuleStatus.completed,
        },
      );
    }
    c = OnboardingController(
      store: store,
      gateway: gateway,
      initialLanguage: language,
      now: () => now,
    );
    await c.initialize();
    if (step != null) await c.goTo(step);
    voice = OnboardingVoiceCoordinator(
      controller: c,
      input: input,
      onInspect: !inspectionRoute
          ? null
          : () async {
              expect(input.pending, isNull);
              expect(voice.enabled, isFalse);
              expect(c.admission, Admission.inspectionOnly);
              expect(c.gate.mayStartGenericAssistive, isFalse);
              opened++;
            },
    );
  }

  Future<void> start() async {
    await voice.enable();
    await drainVoice();
  }

  Future<void> say(String text) async {
    expect(input.pending, isNotNull, reason: '${voice.phase}: ${voice.status}');
    input.answer(text);
    await drainVoice();
  }

  String answer() {
    final i = c.progress.language.index;
    return switch (voice.question!) {
      OnboardingVoiceQuestion.language => ['русский', 'қазақша', 'english'][i],
      OnboardingVoiceQuestion.access => ['самостоятельно', 'өзім', 'myself'][i],
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
      OnboardingVoiceQuestion.camera => [
        'запросить доступ',
        'камераға рұқсат сұрау',
        'request camera access',
      ][i],
      OnboardingVoiceQuestion.standing => [
        'стою на месте',
        'орнымда тұрмын',
        'i am standing still',
      ][i],
      OnboardingVoiceQuestion.device => [
        'проверить устройство',
        'құрылғыны тексеру',
        'check device',
      ][i],
      OnboardingVoiceQuestion.alignment => [
        'проверить положение',
        'қалыпты тексеру',
        'check position',
      ][i],
      OnboardingVoiceQuestion.alignmentConfirm => [
        'положение подтверждаю',
        'қалыпты растаймын',
        'confirm position',
      ][i],
      OnboardingVoiceQuestion.stationaryCheck => [
        'проверить на месте',
        'орнымда тексеру',
        'check while stationary',
      ][i],
      OnboardingVoiceQuestion.sessionCheck => [
        'проверить готовность',
        'дайындықты тексеру',
        'check readiness',
      ][i],
      OnboardingVoiceQuestion.summaryReady => [
        'начать осмотр',
        'шолуды бастау',
        'start inspection',
      ][i],
      _ => ['дальше', 'келесі', 'next'][i],
    };
  }

  Future<void> driveTo(OnboardingVoiceQuestion target) async {
    for (var n = 0; n < 140; n++) {
      if (voice.question == target) return;
      await say(answer());
    }
    fail('Did not reach $target: ${voice.question}');
  }

  Future<void> ready() async {
    await c.playVoice();
    c.confirmOrdinaryVoice(true);
    await c.playVoice(stop: true);
    c.confirmVoice(true);
    await c.requestCamera();
    c.confirmStationary(true);
    await c.deviceCheck(stationary: true);
    await c.alignmentCheck();
    c.confirmAlignment(true);
    await c.goTo(OnboardingStep.summary);
    expect(c.admission, Admission.inspectionOnly);
  }

  Future<void> close() async {
    input.failClosing = false;
    voice.dispose();
    c.dispose();
    await drainVoice();
  }
}

void main() {
  late CheckVoiceRig rig;
  setUp(() => rig = CheckVoiceRig());
  tearDown(() => rig.close());

  test(
    'screen inspection remains available with verified haptics when voice is off and TTS fails',
    () async {
      await rig.init();
      await rig.ready();
      await rig.c.playHaptic();
      rig.c.confirmHaptic(true);
      rig.gateway.audible = false;
      await rig.c.playVoice();
      expect(rig.c.hasSpeechProblem, isTrue);
      expect(rig.c.admission, Admission.inspectionOnly);
      await rig.voice.openInspection();
      expect(rig.opened, 1);
    },
  );

  test(
    'a low-score camera request cannot open a system permission dialog',
    () async {
      await rig.init(access: CameraAccess.denied, step: OnboardingStep.camera);
      await rig.start();
      rig.input.answer('запросить доступ', confidence: 0.1);
      await drainVoice();
      expect(rig.gateway.requests, 0);
      expect(rig.c.evidence.cameraAccess, CameraAccess.denied);
    },
  );

  for (final language in AppLanguage.values) {
    test(
      '${language.name}: all 12 steps require measured hardware and close input before inspection',
      () async {
        await rig.init(language: language, trained: false);
        await rig.start();
        await rig.driveTo(OnboardingVoiceQuestion.camera);
        expect(rig.gateway.requests, 0);
        expect(rig.gateway.cameraChecks, 0);
        await rig.driveTo(OnboardingVoiceQuestion.summaryReady);
        expect(rig.gateway.requests, 1);
        expect(rig.gateway.cameraChecks, 2);
        expect(rig.gateway.alignmentChecks, 1);
        expect(rig.c.progress.completedExercises, 4);
        await rig.say(rig.answer());
        expect(rig.opened, 1);
        expect(rig.input.pending, isNull);
        expect(rig.voice.phase, OnboardingVoicePhase.complete);
      },
    );
    test(
      '${language.name}: saved progress runs the short check with new evidence',
      () async {
        await rig.init(language: language);
        expect(rig.c.isQuickCheck, isTrue);
        expect(rig.c.admission, Admission.recheckRequired);
        await rig.start();
        await rig.driveTo(OnboardingVoiceQuestion.summaryReady);
        expect(rig.gateway.cameraChecks, 1);
        expect(rig.gateway.alignmentChecks, 1);
        expect(rig.c.evidence.alignmentConfirmed, isTrue);
        await rig.say(rig.answer());
        expect(rig.opened, 1);
      },
    );
    test(
      '${language.name}: position negation is distinct and contextual',
      () async {
        await rig.init(language: language, step: OnboardingStep.alignment);
        rig.c.confirmStationary(true);
        await rig.c.alignmentCheck();
        await rig.start();
        expect(rig.voice.question, OnboardingVoiceQuestion.alignmentConfirm);
        await rig.say(
          [
            'положение не подтверждаю',
            'қалыпты растамаймын',
            'do not confirm position',
          ][language.index],
        );
        expect(rig.c.evidence.alignmentConfirmed, isFalse);
        await rig.say(
          [
            'положение подтверждаю',
            'қалыпты растаймын',
            'confirm position',
          ][language.index],
        );
        expect(rig.c.evidence.alignmentConfirmed, isTrue);
        expect(rig.voice.question, OnboardingVoiceQuestion.alignmentDone);
      },
    );
  }

  for (final access in CameraAccess.values.where(
    (a) => a != CameraAccess.granted,
  )) {
    test(
      '$access cannot become permission or hardware readiness through speech',
      () async {
        await rig.init(step: OnboardingStep.camera, access: access);
        await rig.start();
        await rig.say('запросить доступ');
        expect(rig.c.evidence.cameraAccess, access);
        expect(rig.voice.question, OnboardingVoiceQuestion.camera);
        await rig.say('разрешаю');
        await rig.say('дальше');
        expect(rig.c.step, OnboardingStep.camera);
        expect(rig.gateway.requests, 1);
        expect(rig.gateway.cameraChecks, 0);
        await rig.say('отложить');
        expect(rig.c.step, OnboardingStep.summary);
        expect(rig.c.admission, isNot(Admission.inspectionOnly));
        expect(rig.voice.question, OnboardingVoiceQuestion.summaryBlocked);
      },
    );
  }

  test(
    'not standing cannot launch the camera and device work keeps ASR closed',
    () async {
      await rig.init(step: OnboardingStep.device);
      await rig.start();
      expect(rig.voice.question, OnboardingVoiceQuestion.standing);
      await rig.say('не стою на месте');
      await rig.say('проверить устройство');
      expect(rig.gateway.cameraChecks, 0);
      await rig.say('стою на месте');
      expect(rig.voice.question, OnboardingVoiceQuestion.device);
      final pending = Completer<DeviceProbe>();
      rig.gateway.pendingCameraProbe = pending;
      await rig.say('проверить устройство');
      expect(rig.c.busy, isTrue);
      expect(rig.input.pending, isNull);
      expect(rig.voice.phase, OnboardingVoicePhase.checking);
      pending.complete(
        DeviceProbe(
          ProbeResult(ProbeStatus.available, 'freshCheck', rig.now),
          ProbeResult(ProbeStatus.available, 'freshCheck', rig.now),
        ),
      );
      await drainVoice();
      expect(rig.voice.question, OnboardingVoiceQuestion.deviceDone);
      expect(rig.input.pending, isNotNull);
    },
  );

  for (final failure in ['camera', 'thermal', 'stale']) {
    test(
      '$failure device evidence cannot be replaced by next or everything works',
      () async {
        await rig.init(step: OnboardingStep.device);
        rig.c.confirmStationary(true);
        rig.gateway.deviceResult = DeviceProbe(
          ProbeResult(
            failure == 'camera'
                ? ProbeStatus.unavailable
                : ProbeStatus.available,
            'cameraUnavailable',
            failure == 'stale'
                ? rig.now.subtract(const Duration(minutes: 3))
                : rig.now,
          ),
          ProbeResult(
            failure == 'thermal'
                ? ProbeStatus.unavailable
                : ProbeStatus.available,
            'thermalUnavailable',
            rig.now,
          ),
        );
        await rig.start();
        await rig.say('проверить устройство');
        expect(rig.voice.question, OnboardingVoiceQuestion.device);
        await rig.say('всё работает');
        await rig.say('дальше');
        expect(rig.c.step, OnboardingStep.device);
        expect(rig.c.admission, Admission.recheckRequired);
        expect(rig.gateway.cameraChecks, 1);
      },
    );
  }

  test(
    'unknown alignment stays unavailable and coaching uses the existing bounded measurements',
    () async {
      await rig.init(step: OnboardingStep.alignment);
      rig.c.confirmStationary(true);
      rig.gateway.alignmentResult = ProbeResult(
        ProbeStatus.unavailable,
        'alignmentUnavailable',
        rig.now,
      );
      await rig.start();
      await rig.say('проверить положение');
      expect(rig.c.evidence.alignmentConfirmed, isFalse);
      expect(rig.voice.question, OnboardingVoiceQuestion.alignment);
      await rig.say('положение подтверждаю');
      expect(rig.c.evidence.alignmentConfirmed, isFalse);
      rig.gateway.alignmentResult = ProbeResult(
        ProbeStatus.available,
        'alignmentStable',
        rig.now,
      );
      await rig.say('проверить положение');
      expect(rig.voice.question, OnboardingVoiceQuestion.alignmentConfirm);
      expect(rig.c.evidence.alignmentConfirmed, isFalse);
    },
  );

  test(
    'camera system dialog ignores the stale grant and rereads actual OS status',
    () async {
      await rig.init(step: OnboardingStep.camera, access: CameraAccess.denied);
      final pending = Completer<CameraAccess>();
      rig.gateway.pendingCameraRequest = pending;
      await rig.start();
      await rig.say('запросить доступ');
      expect(rig.voice.phase, OnboardingVoicePhase.systemPermission);
      expect(rig.input.pending, isNull);
      rig.voice.suspend();
      rig.c.suspend(background: true);
      rig.gateway.access = CameraAccess.denied;
      await rig.c.resume();
      await rig.voice.resume();
      pending.complete(CameraAccess.granted);
      await drainVoice();
      expect(rig.c.evidence.cameraAccess, CameraAccess.denied);
      expect(rig.voice.question, OnboardingVoiceQuestion.camera);
      expect(rig.input.permissionRequests, [true, false]);
      expect(rig.gateway.requests, 1);
    },
  );

  test('backgrounding discards an in-flight device probe', () async {
    await rig.init(step: OnboardingStep.device);
    rig.c.confirmStationary(true);
    final pending = Completer<DeviceProbe>();
    rig.gateway.pendingCameraProbe = pending;
    await rig.start();
    await rig.say('проверить устройство');
    rig.voice.suspend();
    rig.c.suspend(background: true);
    pending.complete(
      DeviceProbe(
        ProbeResult(ProbeStatus.available, 'freshCheck', rig.now),
        ProbeResult(ProbeStatus.available, 'freshCheck', rig.now),
      ),
    );
    await drainVoice();
    expect(rig.c.evidence.camera.status, ProbeStatus.notChecked);
    expect(rig.c.admission, Admission.recheckRequired);
    expect(rig.input.pending, isNull);
  });

  test(
    'failed settings give spoken recovery and never claim a permission grant',
    () async {
      await rig.init(
        step: OnboardingStep.camera,
        access: CameraAccess.permanentlyDenied,
      );
      rig.gateway.settingsAvailable = false;
      await rig.start();
      await rig.say('настройки приложения');
      expect(rig.gateway.settingsOpened, 1);
      expect(rig.gateway.requests, 0);
      expect(rig.c.evidence.cameraAccess, isNot(CameraAccess.granted));
      expect(
        rig.gateway.spokenTexts.join(' '),
        contains(rig.voice.copy.t(VoiceCopy.settingsUnavailable)),
      );
    },
  );

  test(
    'helper needs a new handoff before stationary and position confirmations',
    () async {
      await rig.init(mode: AccessMode.helper, step: OnboardingStep.alignment);
      await rig.start();
      expect(rig.voice.question, OnboardingVoiceQuestion.handoff);
      await rig.say('стою на месте');
      await rig.say('положение подтверждаю');
      expect(rig.gateway.alignmentChecks, 0);
      expect(rig.c.stationaryAccepted, isFalse);
      await rig.say('управление у меня');
      expect(rig.voice.question, OnboardingVoiceQuestion.standing);
    },
  );

  test(
    'expired evidence rejects the old inspection answer and immediately asks the current question',
    () async {
      await rig.init();
      await rig.ready();
      await rig.start();
      expect(rig.voice.question, OnboardingVoiceQuestion.summaryReady);
      rig.now = rig.now.add(const Duration(minutes: 3));
      await rig.say('начать осмотр');
      expect(rig.opened, 0);
      expect(rig.voice.question, OnboardingVoiceQuestion.summaryBlocked);
      expect(rig.input.pending, isNotNull);
    },
  );

  test('admission is rechecked after handoff speech expires', () async {
    await rig.init();
    await rig.ready();
    await rig.start();
    final speech = Completer<bool>();
    rig.gateway.pendingSpeech = speech;
    await rig.say('начать осмотр');
    expect(rig.input.pending, isNull);
    rig.now = rig.now.add(const Duration(minutes: 3));
    rig.gateway.pendingSpeech = null;
    speech.complete(true);
    await drainVoice();
    expect(rig.opened, 0);
    expect(rig.voice.enabled, isFalse);
  });

  test(
    'unacknowledged input cancellation blocks the screen inspection action',
    () async {
      await rig.init();
      await rig.ready();
      await rig.start();
      rig.input.failClosing = true;
      await rig.voice.openInspection();
      expect(rig.opened, 0);
      expect(rig.voice.phase, OnboardingVoicePhase.unavailable);
      expect(rig.voice.status, rig.voice.copy.t(VoiceCopy.cancelFailed));
    },
  );

  test('a missing inspection route cannot be created by speech', () async {
    await rig.init(inspectionRoute: false);
    await rig.ready();
    await rig.start();
    await rig.say('начать осмотр');
    expect(rig.opened, 0);
    expect(rig.voice.enabled, isTrue);
    expect(
      rig.gateway.spokenTexts.last,
      contains(rig.voice.copy.t(VoiceCopy.inspectionUnavailable)),
    );
  });

  test(
    'requested repeat check actually requires new probes even if previous evidence is fresh',
    () async {
      await rig.init();
      await rig.ready();
      await rig.start();
      final before = rig.gateway.cameraChecks;
      await rig.say('продолжить настройку');
      expect(rig.c.isQuickCheck, isTrue);
      expect(rig.voice.question, OnboardingVoiceQuestion.sessionCheck);
      await rig.say('проверить готовность');
      expect(rig.gateway.cameraChecks, before + 1);
      expect(rig.c.evidence.alignmentConfirmed, isFalse);
    },
  );
}

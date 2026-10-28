import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_copy.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_entry.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_speech.dart';
import 'package:bagdar/models/generic_obstacle_mode.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_screen.dart';
import 'package:bagdar/services/settings_service.dart';

class TestGateway extends UnavailableOnboardingGateway {
  CameraAccess access = CameraAccess.granted;
  bool audible = true;
  OnboardingSpeechResult speechFailure =
      OnboardingSpeechResult.voiceUnavailable;
  bool speechSettingsAvailable = true;
  int speechSettingsOpened = 0;
  bool haptic = true;
  int requests = 0;
  int cameraChecks = 0;
  int speaks = 0;
  int stops = 0;
  int permissionReads = 0;
  final DateTime Function() clock;
  Completer<bool>? pendingSpeech;
  Completer<void>? pendingStop;
  Completer<CameraAccess>? pendingCameraRequest;
  Completer<CameraAccess>? pendingCameraStatus;
  Completer<DeviceProbe>? pendingCameraProbe;
  ProbeResult? alignmentResult;
  Completer<ProbeResult>? pendingAlignment;
  int alignmentChecks = 0;
  final spokenTexts = <String>[];
  TestGateway(this.clock);

  @override
  Future<OnboardingSpeechResult> speak(
    String text,
    AppLanguage language, {
    bool critical = false,
  }) async {
    speaks++;
    spokenTexts.add(text);
    final played = pendingSpeech == null
        ? audible
        : await pendingSpeech!.future;
    return played ? OnboardingSpeechResult.played : speechFailure;
  }

  @override
  Future<bool> openSpeechSettings() async {
    speechSettingsOpened++;
    return speechSettingsAvailable;
  }

  @override
  Future<bool> stopHaptic() async => haptic;
  @override
  Future<CameraAccess> cameraPermission({bool request = false}) async {
    if (request) {
      requests++;
      return pendingCameraRequest == null
          ? access
          : pendingCameraRequest!.future;
    }
    permissionReads++;
    return pendingCameraStatus == null ? access : pendingCameraStatus!.future;
  }

  @override
  Future<DeviceProbe> checkCamera() async {
    cameraChecks++;
    if (pendingCameraProbe != null) return pendingCameraProbe!.future;
    return DeviceProbe(
      ProbeResult(ProbeStatus.available, 'freshCheck', clock()),
      ProbeResult(ProbeStatus.available, 'freshCheck', clock()),
    );
  }

  @override
  Future<ProbeResult> checkAlignment() async {
    alignmentChecks++;
    if (pendingAlignment != null) return pendingAlignment!.future;
    return alignmentResult ??
        ProbeResult(ProbeStatus.available, 'alignmentStable', clock());
  }

  @override
  Future<void> stop() async {
    stops++;
    if (pendingStop != null) await pendingStop!.future;
  }
}

class FailingStore extends MemoryOnboardingStore {
  bool fail = true;
  @override
  Future<void> save(OnboardingProgress value) async {
    if (fail) throw StateError('disk_full');
    await super.save(value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late TestGateway gateway;
  late MemoryOnboardingStore store;
  late OnboardingController controller;

  setUp(() async {
    now = DateTime(2026, 9, 30, 15);
    gateway = TestGateway(() => now);
    store = MemoryOnboardingStore();
    controller = OnboardingController(
      store: store,
      gateway: gateway,
      now: () => now,
    );
    await controller.initialize();
  });
  tearDown(() => controller.dispose());

  test('every typed copy key has non-empty RU, KK and EN content', () {
    expect(OnboardingCopy.catalog.keys.toSet(), OnboardingText.values.toSet());
    for (final entry in OnboardingCopy.catalog.entries) {
      expect(entry.value, hasLength(3), reason: entry.key.name);
      expect(entry.value.every((text) => text.trim().isNotEmpty), isTrue);
    }
  });

  test(
    'exercise checkpoint resumes after restart and revisiting practice',
    () async {
      await controller.goTo(OnboardingStep.practice);
      await controller.practiceAction(PracticeAction.stop);
      await controller.nextExercise();
      await controller.practiceAction(PracticeAction.check);
      await controller.nextExercise();
      final saved = OnboardingProgress.fromJson(
        jsonDecode(jsonEncode(store.progress!.toJson())),
      );
      final resumed = OnboardingController(
        store: MemoryOnboardingStore()..progress = saved,
        gateway: gateway,
      );
      await resumed.initialize();
      expect(resumed.practiceIndex, 2);
      expect(resumed.practiceAnswered, isFalse);
      expect(resumed.evidence.criticalChannelVerified, isFalse);
      expect(resumed.evidence.camera.status, ProbeStatus.notChecked);
      await resumed.later();
      await resumed.goTo(OnboardingStep.practice);
      expect(resumed.practiceIndex, 2);
      resumed.dispose();
    },
  );

  test('an answer without Next is not saved as a completed exercise', () async {
    await controller.goTo(OnboardingStep.practice);
    await controller.practiceAction(PracticeAction.stop);
    expect(store.progress!.completedExercises, 0);
    await controller.later();
    await controller.goTo(OnboardingStep.practice);
    expect(controller.practiceIndex, 0);
    expect(controller.practiceAnswered, isFalse);
  });

  test(
    'failed checkpoint write retains the answered exercise for retry',
    () async {
      final failing = FailingStore()..fail = false;
      final c = OnboardingController(store: failing, gateway: gateway);
      await c.initialize();
      await c.goTo(OnboardingStep.practice);
      await c.practiceAction(PracticeAction.stop);
      failing.fail = true;
      await c.nextExercise();
      expect(c.practiceIndex, 0);
      expect(c.practiceAnswered, isTrue);
      expect(c.message, OnboardingText.saveError);
      failing.fail = false;
      await c.nextExercise();
      expect(c.practiceIndex, 1);
      c.dispose();
    },
  );

  test(
    'language change and explicit practice restart clear saved exercises',
    () async {
      await controller.goTo(OnboardingStep.practice);
      await controller.practiceAction(PracticeAction.stop);
      await controller.nextExercise();
      await controller.selectLanguage(AppLanguage.kk);
      expect(controller.progress.completedExercises, 0);
      await controller.practiceAction(PracticeAction.stop);
      await controller.nextExercise();
      await controller.restartPractice();
      expect(controller.practiceIndex, 0);
      expect(store.progress!.completedExercises, 0);
      expect(controller.progress.complete(OnboardingStep.practice), isFalse);
    },
  );

  test('older v2 progress remains compatible without exercise field', () {
    for (final completed in [false, true]) {
      final json = OnboardingProgress(
        modules: {
          if (completed) OnboardingStep.practice: ModuleStatus.completed,
        },
      ).toJson()..remove('completedExercises');
      final loaded = OnboardingProgress.fromJson(json);
      expect(loaded.completedExercises, completed ? 4 : 0);
    }
  });

  for (final invalid in [-1, 5, 1.5, '2', null]) {
    test('invalid exercise checkpoint $invalid is rejected', () {
      final json = <String, dynamic>{
        ...OnboardingProgress().toJson(),
        'completedExercises': invalid,
      };
      expect(() => OnboardingProgress.fromJson(json), throwsFormatException);
    });
  }

  test(
    'practice explains each wrong action and reads the same explanation',
    () async {
      await controller.goTo(OnboardingStep.practice);
      final correct = [
        PracticeAction.stop,
        PracticeAction.check,
        PracticeAction.stop,
      ];
      final reasons = [
        OnboardingText.wrongStop,
        OnboardingText.wrongSide,
        OnboardingText.wrongLost,
        OnboardingText.wrongPause,
      ];
      for (var index = 0; index < 4; index++) {
        await controller.practiceAction(PracticeAction.move);
        expect(controller.message, reasons[index]);
        expect(controller.practiceAnswered, isFalse);
        await controller.repeatInstruction();
        expect(
          gateway.spokenTexts.last,
          contains(controller.copy.t(reasons[index])),
        );
        if (index < 3) {
          await controller.practiceAction(correct[index]);
          await controller.nextExercise();
        }
      }
      expect(controller.progress.completedExercises, 3);
    },
  );

  for (final entry in {
    OnboardingSpeechResult.voiceUnavailable: OnboardingText.voiceMissing,
    OnboardingSpeechResult.engineUnavailable:
        OnboardingText.speechEngineUnavailable,
    OnboardingSpeechResult.interrupted: OnboardingText.speechInterrupted,
    OnboardingSpeechResult.timedOut: OnboardingText.speechTimedOut,
    OnboardingSpeechResult.failed: OnboardingText.speechFailed,
  }.entries) {
    test(
      '${entry.key.name} is explained and retry verifies the same sample',
      () async {
        gateway.audible = false;
        gateway.speechFailure = entry.key;
        await controller.playVoice(stop: true);
        expect(controller.message, entry.value);
        expect(controller.evidence.stopVoicePlayed, isFalse);
        expect(controller.evidence.voiceConfirmed, isFalse);
        gateway.audible = true;
        await controller.retrySpeech();
        expect(gateway.spokenTexts.last, controller.stopCue);
        expect(controller.evidence.stopVoicePlayed, isTrue);
        expect(controller.evidence.voiceConfirmed, isFalse);
        expect(controller.evidence.voiceSamplePlayed, isFalse);
      },
    );
  }

  test(
    'instruction retry cannot be mistaken for a verification sample',
    () async {
      gateway.audible = false;
      await controller.repeatInstruction();
      final text = gateway.spokenTexts.last;
      gateway.audible = true;
      await controller.retrySpeech();
      expect(gateway.spokenTexts.last, text);
      expect(controller.evidence.voiceSamplePlayed, isFalse);
      expect(controller.evidence.criticalChannelVerified, isFalse);
    },
  );

  test('speech settings failure has a manual recovery instruction', () async {
    gateway.speechSettingsAvailable = false;
    await controller.openSpeechSettings();
    expect(gateway.speechSettingsOpened, 1);
    expect(controller.message, OnboardingText.speechSettingsUnavailable);
    expect(controller.evidence.criticalChannelVerified, isFalse);
  });

  test(
    'returning user starts a short check with fresh unverified evidence',
    () async {
      await finishSetup(controller);
      final c = OnboardingController(
        store: store,
        gateway: gateway,
        now: () => now,
      );
      final checks = gateway.cameraChecks;
      await c.initialize();
      expect(c.isQuickCheck, isTrue);
      expect(c.sessionStage, 1);
      expect(gateway.cameraChecks, checks);
      expect(c.evidence.cameraAccess, CameraAccess.granted);
      expect(c.admission, Admission.recheckRequired);
      expect(c.evidence.criticalChannelVerified, isFalse);
      c.dispose();
    },
  );

  test('short check requires a channel and human confirmations', () async {
    await finishSetup(controller);
    controller.suspend();
    await controller.openSessionCheck();
    final checks = gateway.cameraChecks;
    controller.confirmStationary(true);
    await controller.checkSession();
    expect(gateway.cameraChecks, checks);
    await controller.playHaptic();
    controller.confirmHaptic(true);
    await controller.refreshCameraPermission();
    expect(controller.canCheckSession, isTrue);
    await controller.checkSession();
    expect(controller.evidence.camera.freshAt(now), isTrue);
    expect(controller.evidence.alignment.freshAt(now), isTrue);
    expect(controller.requiredStep, OnboardingStep.alignment);
    expect(controller.admission, Admission.recheckRequired);
    controller.confirmAlignment(true);
    expect(controller.admission, Admission.inspectionOnly);
    now = now.add(const Duration(minutes: 2));
    expect(controller.admission, Admission.recheckRequired);
    controller.suspend();
    expect(controller.sessionStage, 1);
    expect(controller.stationaryAccepted, isFalse);
  });

  test(
    'short check stops on denied permission or unavailable temperature',
    () async {
      await finishSetup(controller);
      await controller.openSessionCheck();
      final alignments = gateway.alignmentChecks;
      gateway.access = CameraAccess.denied;
      final checks = gateway.cameraChecks;
      await controller.checkSession();
      expect(gateway.cameraChecks, checks);
      expect(controller.sessionStage, 2);
      gateway.access = CameraAccess.granted;
      gateway.pendingCameraProbe = Completer<DeviceProbe>()
        ..complete(
          DeviceProbe(
            ProbeResult(ProbeStatus.available, 'freshCheck', now),
            ProbeResult(ProbeStatus.unavailable, 'thermalUnavailable', now),
          ),
        );
      await controller.refreshCameraPermission();
      await controller.checkSession();
      expect(gateway.alignmentChecks, alignments);
      expect(controller.evidence.alignment.status, ProbeStatus.notChecked);
      expect(controller.admission, Admission.recheckRequired);
    },
  );

  test(
    'background cancels short check and ignores the late alignment result',
    () async {
      await finishSetup(controller);
      await controller.openSessionCheck();
      gateway.pendingAlignment = Completer<ProbeResult>();
      final operation = controller.checkSession();
      for (var i = 0; i < 10 && gateway.alignmentChecks < 2; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(gateway.alignmentChecks, 2);
      controller.suspend(background: true);
      gateway.pendingAlignment!.complete(
        ProbeResult(ProbeStatus.available, 'alignmentStable', now),
      );
      await operation;
      expect(controller.evidence.alignment.status, ProbeStatus.notChecked);
      expect(controller.evidence.stationaryConfirmed, isFalse);
      expect(controller.admission, Admission.recheckRequired);
    },
  );

  test(
    'boot and camera-free practice do not request permission or start camera',
    () async {
      expect(gateway.speaks, 0);
      await controller.goTo(OnboardingStep.practice);
      await finishPractice(controller);
      expect(controller.practiceFinished, isTrue);
      expect(gateway.requests, 0);
      expect(gateway.cameraChecks, 0);
      expect(gateway.speaks, 0);
    },
  );

  test(
    'incorrect action cannot complete a practice scene; pause requires resume',
    () async {
      await controller.goTo(OnboardingStep.practice);
      await controller.practiceAction(PracticeAction.move);
      await controller.nextExercise();
      expect(controller.practiceIndex, 0);
      expect(controller.message, OnboardingText.wrongStop);
      await controller.practiceAction(PracticeAction.stop);
      await controller.nextExercise();
      expect(controller.practiceIndex, 1);
      await controller.practiceAction(PracticeAction.check);
      await controller.nextExercise();
      await controller.practiceAction(PracticeAction.stop);
      await controller.nextExercise();
      await controller.practiceAction(PracticeAction.resume);
      expect(controller.practiceAnswered, isFalse);
      await controller.practiceAction(PracticeAction.pause);
      await controller.nextExercise();
      expect(controller.practiceIndex, 3);
      await controller.practiceAction(PracticeAction.resume);
      await controller.nextExercise();
      expect(controller.practiceFinished, isTrue);
    },
  );

  test('limits and practice cannot be completed by pressing Next', () async {
    await controller.goTo(OnboardingStep.limits);
    await controller.next();
    expect(controller.step, OnboardingStep.limits);
    expect(controller.progress.complete(OnboardingStep.limits), isFalse);
    await controller.goTo(OnboardingStep.practice);
    await controller.next();
    expect(controller.step, OnboardingStep.practice);
  });

  test(
    'step reading explains camera denial and unavailable device checks',
    () async {
      gateway.access = CameraAccess.denied;
      await controller.goTo(OnboardingStep.camera);
      await controller.requestCamera();
      await controller.repeatInstruction();
      expect(
        gateway.spokenTexts.last,
        contains(controller.copy.t(OnboardingText.cameraDenied)),
      );
      await controller.goTo(OnboardingStep.device);
      controller.evidence.thermal = ProbeResult(
        ProbeStatus.unavailable,
        'thermalUnavailable',
        now,
      );
      await controller.repeatInstruction();
      expect(
        gateway.spokenTexts.last,
        contains(controller.copy.t(OnboardingText.thermalUnavailable)),
      );
      expect(controller.admission, Admission.trainingRequired);
      expect(gateway.cameraChecks, 0);
    },
  );

  test(
    'repeat reads every limitation without completing or verifying setup',
    () async {
      await controller.goTo(OnboardingStep.limits);
      await controller.repeatInstruction();
      final spoken = gateway.spokenTexts.single;
      for (final key in [
        OnboardingText.limit1,
        OnboardingText.limit2,
        OnboardingText.limit3,
        OnboardingText.limit4,
      ]) {
        expect(spoken, contains(controller.copy.t(key)));
      }
      expect(gateway.requests, 0);
      expect(gateway.cameraChecks, 0);
      expect(controller.limitsAccepted, isFalse);
      expect(controller.evidence.voiceSamplePlayed, isFalse);
      expect(controller.evidence.criticalChannelVerified, isFalse);
    },
  );

  test(
    'stop reading waits for output cancellation and preserves readiness',
    () async {
      await finishSetup(controller);
      gateway.pendingSpeech = Completer<bool>();
      final speech = controller.repeatInstruction();
      expect(controller.speaking, isTrue);
      gateway.pendingStop = Completer<void>();
      final stop = controller.stopSpeech();
      await controller.repeatInstruction();
      expect(controller.busy, isTrue);
      expect(controller.stoppingSpeech, isTrue);
      expect(controller.speaking, isFalse);
      gateway.pendingStop!.complete();
      await stop;
      gateway.pendingSpeech!.complete(true);
      await speech;
      expect(controller.message, OnboardingText.speechStopped);
      expect(controller.busy, isFalse);
      expect(controller.admission, Admission.inspectionOnly);
      expect(controller.evidence.voiceConfirmed, isTrue);
    },
  );

  test('stopping a verification sample cannot mark it played', () async {
    gateway.pendingSpeech = Completer<bool>();
    final speech = controller.playVoice(stop: true);
    await controller.stopSpeech();
    gateway.pendingSpeech!.complete(true);
    await speech;
    controller.confirmVoice(true);
    expect(controller.evidence.stopVoicePlayed, isFalse);
    expect(controller.evidence.voiceConfirmed, isFalse);
  });

  test(
    'background stops reading and blocks queued actions until resume',
    () async {
      gateway.pendingSpeech = Completer<bool>();
      final speech = controller.repeatInstruction();
      controller.suspend(background: true);
      await controller.repeatInstruction();
      expect(gateway.speaks, 1);
      gateway.pendingSpeech!.complete(true);
      await speech;
      expect(controller.speaking, isFalse);
      expect(controller.message, isNull);
      await controller.resume();
      gateway.pendingSpeech = null;
      await controller.repeatInstruction();
      expect(gateway.speaks, 2);
      expect(controller.evidence.criticalChannelVerified, isFalse);
    },
  );

  test('instruction chunks retain the full content in each language', () async {
    for (final language in AppLanguage.values) {
      await controller.selectLanguage(language);
      for (final step in OnboardingStep.values) {
        await controller.goTo(step);
        final text = controller.stepInstruction;
        final chunks = onboardingSpeechSegments(text).toList();
        expect(chunks, isNotEmpty);
        expect(chunks.every((part) => part.length <= 160), isTrue);
        expect(chunks.join(' '), text.trim().split(RegExp(r'\s+')).join(' '));
      }
    }
  });

  test(
    'repeating alignment instructions includes the current correction',
    () async {
      gateway.alignmentResult = ProbeResult(
        ProbeStatus.unavailable,
        'alignmentMoreFlat',
        now,
      );
      await controller.goTo(OnboardingStep.alignment);
      await controller.alignmentCheck();
      await controller.repeatInstruction();
      expect(
        gateway.spokenTexts.single,
        contains(controller.copy.t(OnboardingText.alignmentMoreFlat)),
      );
      controller.confirmAlignment(true);
      expect(controller.evidence.alignmentConfirmed, isFalse);
    },
  );

  test('double Next advances only one answered exercise', () async {
    await controller.goTo(OnboardingStep.practice);
    await controller.practiceAction(PracticeAction.stop);
    gateway.pendingStop = Completer<void>();
    final first = controller.nextExercise();
    final second = controller.nextExercise();
    final wasBusy = controller.busy;
    gateway.pendingStop!.complete();
    await Future.wait([first, second]);
    expect(wasBusy, isTrue);
    expect(controller.practiceIndex, 1);
    expect(controller.practiceAnswered, isFalse);
    expect(controller.practiceFinished, isFalse);
  });

  test(
    'cancelled exercise transition cannot advance after returning',
    () async {
      await controller.goTo(OnboardingStep.practice);
      await controller.practiceAction(PracticeAction.stop);
      gateway.pendingStop = Completer<void>();
      final operation = controller.nextExercise();
      controller.suspend();
      gateway.pendingStop!.complete();
      await operation;
      expect(controller.practiceIndex, 0);
      expect(controller.practicePaused, isTrue);
    },
  );

  test(
    'Continue setup revisits missing human alignment confirmation',
    () async {
      await finishSetup(controller);
      controller.confirmAlignment(false);
      await controller.continueSetup();
      expect(controller.isQuickCheck, isTrue);
      expect(controller.sessionStage, 3);
      expect(controller.requiredStep, OnboardingStep.alignment);
      controller.confirmAlignment(true);
      expect(controller.step, OnboardingStep.summary);
      expect(controller.admission, Admission.inspectionOnly);
    },
  );

  test('technical playback alone never verifies a critical channel', () async {
    controller.confirmVoice(true);
    controller.confirmHaptic(true);
    expect(controller.evidence.criticalChannelVerified, isFalse);
    await controller.playVoice();
    await controller.playVoice(stop: true);
    expect(controller.evidence.criticalChannelVerified, isFalse);
    controller.confirmVoice(true);
    expect(controller.evidence.criticalChannelVerified, isTrue);
    await controller.changeRate(0.75);
    expect(controller.evidence.criticalChannelVerified, isFalse);
    expect(controller.evidence.voiceSamplePlayed, isFalse);
  });

  test(
    'unavailable speech cannot be confirmed; verified haptic is an alternative',
    () async {
      gateway.audible = false;
      await controller.playVoice();
      await controller.playVoice(stop: true);
      controller.confirmVoice(true);
      expect(controller.evidence.criticalChannelVerified, isFalse);
      await controller.playHaptic();
      controller.confirmHaptic(true);
      expect(controller.evidence.criticalChannelVerified, isTrue);
    },
  );

  test(
    'interrupted asynchronous playback does not restore confirmation',
    () async {
      gateway.pendingSpeech = Completer<bool>();
      final operation = controller.playVoice(stop: true);
      controller.suspend();
      gateway.pendingSpeech!.complete(true);
      await operation;
      expect(controller.evidence.stopVoicePlayed, isFalse);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'checkpoint is saved before transition; failed save allows retry',
    () async {
      final failing = FailingStore();
      final c = OnboardingController(store: failing, gateway: gateway);
      await c.initialize();
      await c.next();
      expect(c.step, OnboardingStep.language);
      expect(c.progress.complete(OnboardingStep.language), isFalse);
      expect(c.message, OnboardingText.saveError);
      failing.fail = false;
      await c.next();
      expect(c.step, OnboardingStep.access);
      expect(failing.progress!.checkpoint, OnboardingStep.access);
      c.dispose();
    },
  );

  test(
    'Continue later preserves resume checkpoint and completed modules',
    () async {
      await controller.next();
      await controller.later();
      expect(controller.step, OnboardingStep.summary);
      expect(store.progress!.checkpoint, OnboardingStep.access);
      final resumed = OnboardingController(store: store, gateway: gateway);
      await resumed.initialize();
      expect(resumed.step, OnboardingStep.access);
      expect(resumed.progress.complete(OnboardingStep.language), isTrue);
      expect(resumed.evidence.camera.status, ProbeStatus.notChecked);
      resumed.dispose();
    },
  );

  test(
    'language change invalidates language-dependent evidence, retains unrelated modules',
    () async {
      controller.progress = OnboardingProgress(
        modules: {
          for (final step in OnboardingStep.values)
            step: ModuleStatus.completed,
        },
      );
      await controller.playHaptic();
      controller.confirmHaptic(true);
      await controller.selectLanguage(AppLanguage.kk);
      expect(controller.progress.complete(OnboardingStep.practice), isFalse);
      expect(controller.progress.complete(OnboardingStep.feedback), isFalse);
      expect(controller.progress.complete(OnboardingStep.vocabulary), isFalse);
      expect(controller.progress.complete(OnboardingStep.privacy), isTrue);
      expect(controller.evidence.criticalChannelVerified, isFalse);
    },
  );

  test(
    'denied camera does not open stream and retains access to practice',
    () async {
      gateway.access = CameraAccess.denied;
      await controller.requestCamera();
      await controller.deviceCheck();
      expect(gateway.requests, 1);
      expect(gateway.cameraChecks, 0);
      expect(controller.evidence.camera.status, ProbeStatus.notChecked);
      await controller.goTo(OnboardingStep.practice);
      await finishPractice(controller);
      await controller.next();
      expect(controller.progress.complete(OnboardingStep.practice), isTrue);
      expect(controller.admission, isNot(Admission.inspectionOnly));
    },
  );

  test('resume reads a permission granted during the system dialog', () async {
    await finishSetup(controller);
    gateway.pendingCameraRequest = Completer<CameraAccess>();
    final operation = controller.requestCamera();
    controller.suspend(background: true);
    gateway.access = CameraAccess.granted;
    gateway.pendingCameraRequest!.complete(CameraAccess.granted);
    await operation;
    expect(controller.evidence.cameraAccess, CameraAccess.notRequested);
    final requests = gateway.requests;
    final checks = gateway.cameraChecks;
    await controller.resume();
    expect(controller.evidence.cameraAccess, CameraAccess.granted);
    expect(gateway.requests, requests);
    expect(gateway.cameraChecks, checks);
    expect(controller.evidence.camera.status, ProbeStatus.notChecked);
    expect(controller.evidence.alignment.status, ProbeStatus.notChecked);
    expect(controller.evidence.criticalChannelVerified, isFalse);
    expect(controller.admission, Admission.recheckRequired);
  });

  test(
    'late permission request reconciles even if resume happens first',
    () async {
      gateway.access = CameraAccess.denied;
      gateway.pendingCameraRequest = Completer<CameraAccess>();
      final operation = controller.requestCamera();
      controller.suspend(background: true);
      await controller.resume();
      expect(controller.evidence.cameraAccess, CameraAccess.denied);
      gateway.access = CameraAccess.granted;
      gateway.pendingCameraRequest!.complete(CameraAccess.granted);
      await operation;
      expect(controller.evidence.cameraAccess, CameraAccess.granted);
      expect(gateway.requests, 1);
      expect(gateway.cameraChecks, 0);
    },
  );

  test('older permission read cannot overwrite a later resume', () async {
    final oldStatus = Completer<CameraAccess>();
    gateway.pendingCameraStatus = oldStatus;
    final first = controller.resume();
    controller.suspend(background: true);
    gateway.pendingCameraStatus = null;
    gateway.access = CameraAccess.granted;
    await controller.resume();
    oldStatus.complete(CameraAccess.denied);
    await first;
    expect(controller.evidence.cameraAccess, CameraAccess.granted);
    expect(controller.evidence.camera.status, ProbeStatus.notChecked);
  });

  test(
    'revoked camera permission invalidates previously ready device evidence',
    () async {
      await finishSetup(controller);
      gateway.access = CameraAccess.denied;
      await controller.refreshCameraPermission();
      expect(controller.evidence.cameraAccess, CameraAccess.denied);
      expect(controller.evidence.camera.status, ProbeStatus.notChecked);
      expect(controller.evidence.alignmentConfirmed, isFalse);
      expect(controller.requiredStep, OnboardingStep.camera);
      expect(controller.admission, Admission.recheckRequired);
    },
  );

  test('permission read failure leaves inspection blocked', () async {
    await finishSetup(controller);
    gateway.pendingCameraStatus = Completer<CameraAccess>();
    final operation = controller.refreshCameraPermission();
    gateway.pendingCameraStatus!.completeError(StateError('permission_status'));
    await operation;
    expect(controller.evidence.cameraAccess, CameraAccess.restricted);
    expect(controller.admission, Admission.recheckRequired);
  });

  test(
    'permission revoked during a probe cannot restore ready camera evidence',
    () async {
      await finishSetup(controller);
      gateway.pendingCameraProbe = Completer<DeviceProbe>();
      final probe = controller.deviceCheck(stationary: true);
      await Future<void>.delayed(Duration.zero);
      gateway.access = CameraAccess.denied;
      await controller.refreshCameraPermission();
      gateway.pendingCameraProbe!.complete(
        DeviceProbe(
          ProbeResult(ProbeStatus.available, 'freshCheck', now),
          ProbeResult(ProbeStatus.available, 'freshCheck', now),
        ),
      );
      await probe;
      expect(controller.evidence.cameraAccess, CameraAccess.denied);
      expect(controller.evidence.camera.status, ProbeStatus.notChecked);
      expect(controller.evidence.stationaryConfirmed, isFalse);
      expect(controller.admission, Admission.recheckRequired);
    },
  );

  test('a disposed controller ignores a pending permission read', () async {
    gateway.pendingCameraStatus = Completer<CameraAccess>();
    final c = OnboardingController(
      store: store,
      gateway: gateway,
      now: () => now,
    );
    await c.initialize();
    final operation = c.resume();
    c.dispose();
    gateway.pendingCameraStatus!.complete(CameraAccess.granted);
    await operation;
    expect(c.evidence.cameraAccess, CameraAccess.notRequested);
  });

  for (final missing in [
    OnboardingStep.feedback,
    OnboardingStep.camera,
    OnboardingStep.device,
    OnboardingStep.alignment,
    OnboardingStep.stationary,
  ]) {
    test(
      'Continue setup and admission agree on missing ${missing.name}',
      () async {
        await finishSetup(controller);
        switch (missing) {
          case OnboardingStep.feedback:
            controller.evidence.invalidateFeedback();
          case OnboardingStep.camera:
            controller.evidence.cameraAccess = CameraAccess.denied;
          case OnboardingStep.device:
            controller.evidence.thermal = const ProbeResult.unchecked();
          case OnboardingStep.alignment:
            controller.evidence.alignmentConfirmed = false;
          case OnboardingStep.stationary:
            controller.evidence.stationaryConfirmed = false;
          default:
            fail('unexpected missing check');
        }
        expect(controller.requiredStep, missing);
        expect(controller.admission, Admission.recheckRequired);
        await controller.continueSetup();
        expect(controller.isQuickCheck, isTrue);
        expect(controller.requiredStep, missing);
      },
    );
  }

  test(
    'complete setup admits stationary inspection only; expiration/background fail closed',
    () async {
      await finishSetup(controller);
      expect(controller.step, OnboardingStep.summary);
      expect(controller.admission, Admission.inspectionOnly);
      expect(controller.gate.mayStartGenericAssistive, isFalse);
      expect(kGenericObstacleAssistiveAuthorized, isFalse);
      now = now.add(const Duration(minutes: 2));
      expect(controller.admission, Admission.recheckRequired);
      controller.suspend();
      expect(controller.evidence.camera.status, ProbeStatus.notChecked);
      expect(controller.evidence.criticalChannelVerified, isFalse);
      expect(controller.admission, Admission.recheckRequired);
      final resumed = OnboardingController(store: store, gateway: gateway);
      await resumed.initialize();
      expect(resumed.step, OnboardingStep.summary);
      expect(resumed.admission, Admission.recheckRequired);
      resumed.dispose();
    },
  );

  test(
    'fresh sensor check alone cannot replace human alignment confirmation',
    () async {
      await finishSetup(controller);
      controller.confirmAlignment(false);
      expect(controller.admission, Admission.recheckRequired);
      controller.evidence.alignment = ProbeResult(
        ProbeStatus.available,
        'alignmentStable',
        now,
      );
      expect(controller.admission, Admission.recheckRequired);
    },
  );

  test(
    'helper mode never bypasses missing channels or device checks',
    () async {
      await controller.selectMode(AccessMode.helper);
      controller.progress = controller.progress.copyWith(
        modules: {
          for (final step in OnboardingSessionGate.requiredSetup)
            step: ModuleStatus.completed,
        },
      );
      expect(controller.admission, Admission.recheckRequired);
      expect(controller.gate.mayStartGenericAssistive, isFalse);
    },
  );

  test('negative, unknown and expired probe data are never usable', () {
    expect(const ProbeResult.unchecked().freshAt(now), isFalse);
    expect(
      ProbeResult(ProbeStatus.unavailable, 'cameraDark', now).freshAt(now),
      isFalse,
    );
    expect(
      ProbeResult(
        ProbeStatus.available,
        'freshCheck',
        now.add(const Duration(seconds: 1)),
      ).freshAt(now),
      isFalse,
    );
    expect(
      ProbeResult(
        ProbeStatus.available,
        'freshCheck',
        now.subtract(const Duration(minutes: 2)),
      ).freshAt(now),
      isFalse,
    );
  });

  group('preferences storage', () {
    for (final legacyCompleted in [null, false, true]) {
      test(
        'entry requires v2 setup with legacy completion=$legacyCompleted',
        () async {
          SharedPreferences.setMockInitialValues({
            'num_threads': 3,
            'language': AppLanguage.kk.index,
            if (legacyCompleted != null) 'onboarding_done': legacyCompleted,
            'onboarding_mode': 'cane',
          });
          await Settings.instance.init();
          final screen = await createOnboardingV2Entry();
          expect(screen, isA<OnboardingV2Screen>());
          final c = screen.controller;
          await c.initialize();
          expect(c.step, OnboardingStep.language);
          expect(c.progress.language, AppLanguage.kk);
          expect(c.progress.modules, isEmpty);
          expect(c.admission, Admission.trainingRequired);
          c.dispose();
        },
      );
    }

    test('entry resumes saved v2 language and checkpoint', () async {
      final saved = OnboardingProgress(
        language: AppLanguage.en,
        checkpoint: OnboardingStep.practice,
        modules: {OnboardingStep.limits: ModuleStatus.completed},
      );
      SharedPreferences.setMockInitialValues({
        'num_threads': 3,
        'language': AppLanguage.ru.index,
        'onboarding_done': true,
        PreferencesOnboardingStore.key: jsonEncode(saved.toJson()),
      });
      await Settings.instance.init();
      final screen = await createOnboardingV2Entry();
      final c = screen.controller;
      await c.initialize();
      expect(c.step, OnboardingStep.practice);
      expect(c.progress.language, AppLanguage.en);
      expect(c.progress.complete(OnboardingStep.limits), isTrue);
      expect(c.evidence.camera.status, ProbeStatus.notChecked);
      expect(c.admission, Admission.trainingRequired);
      c.dispose();
    });

    test('inspection rechecks admission and ignores a double start', () async {
      var opened = 0;
      await controller.inspect(() async {
        opened++;
      });
      expect(opened, 0);
      await finishSetup(controller);
      final pending = Completer<void>();
      final first = controller.inspect(() async {
        opened++;
        await pending.future;
      });
      await controller.inspect(() async {
        opened++;
      });
      expect(opened, 1);
      pending.complete();
      await first;
      now = now.add(const Duration(minutes: 3));
      await controller.inspect(() async {
        opened++;
      });
      expect(opened, 1);
    });
    test(
      'future v2 state requires recovery despite legacy completion',
      () async {
        SharedPreferences.setMockInitialValues({
          'onboarding_done': true,
          'num_threads': 3,
          PreferencesOnboardingStore.key: '{"schema":999,"contentVersion":999}',
        });
        await Settings.instance.init();
        final screen = await createOnboardingV2Entry();
        expect(screen, isA<OnboardingV2Screen>());
        await screen.controller.initialize();
        expect(screen.controller.loadStatus, ProgressLoadStatus.unsupported);
        expect(screen.controller.admission, Admission.trainingRequired);
        screen.controller.dispose();
      },
    );
    test(
      'round trip preserves modules, but never persists live evidence or legacy completion',
      () async {
        SharedPreferences.setMockInitialValues({'onboarding_done': true});
        final preferences = await SharedPreferences.getInstance();
        final repository = PreferencesOnboardingStore(preferences);
        expect((await repository.load()).status, ProgressLoadStatus.empty);
        await repository.save(
          OnboardingProgress(
            language: AppLanguage.en,
            checkpoint: OnboardingStep.practice,
            modules: {OnboardingStep.limits: ModuleStatus.completed},
          ),
        );
        final loaded = await repository.load();
        expect(loaded.progress!.checkpoint, OnboardingStep.practice);
        expect(loaded.progress!.language, AppLanguage.en);
        expect(preferences.getBool('onboarding_done'), isTrue);
        expect(
          jsonDecode(preferences.getString(PreferencesOnboardingStore.key)!),
          isNot(contains('camera')),
        );
      },
    );

    for (final raw in [
      '{bad-json',
      '[]',
      '{"schema":1}',
      '{"schema":1,"contentVersion":1,"modules":{"unknown":"completed"}}',
    ]) {
      test('malformed state fails closed: $raw', () async {
        SharedPreferences.setMockInitialValues({
          PreferencesOnboardingStore.key: raw,
        });
        final repository = PreferencesOnboardingStore(
          await SharedPreferences.getInstance(),
        );
        expect((await repository.load()).status, ProgressLoadStatus.corrupt);
      });
    }

    test(
      'future state is preserved; ephemeral training cannot enable inspection',
      () async {
        const future = '{"schema":999,"contentVersion":999}';
        SharedPreferences.setMockInitialValues({
          PreferencesOnboardingStore.key: future,
        });
        final preferences = await SharedPreferences.getInstance();
        final c = OnboardingController(
          store: PreferencesOnboardingStore(preferences),
          gateway: gateway,
        );
        await c.initialize();
        expect(c.loadStatus, ProgressLoadStatus.unsupported);
        await c.later();
        await c.next();
        expect(preferences.getString(PreferencesOnboardingStore.key), future);
        expect(c.step, OnboardingStep.language);
        await c.repeatInstruction();
        expect(
          gateway.spokenTexts.single,
          contains(c.copy.t(OnboardingText.restoreFuture)),
        );
        expect(preferences.getString(PreferencesOnboardingStore.key), future);
        expect(c.loadStatus, ProgressLoadStatus.unsupported);
        expect(c.evidence.voiceSamplePlayed, isFalse);
        await c.recover(withoutSaving: true);
        await c.goTo(OnboardingStep.practice);
        await finishPractice(c);
        await c.next();
        expect(preferences.getString(PreferencesOnboardingStore.key), future);
        expect(c.admission, Admission.trainingRequired);
        await c.requestCamera();
        expect(gateway.requests, 0);
        c.dispose();
      },
    );
  });
}

Future<void> finishPractice(OnboardingController c) async {
  for (final action in [
    PracticeAction.stop,
    PracticeAction.check,
    PracticeAction.stop,
  ]) {
    await c.practiceAction(action);
    await c.nextExercise();
  }
  await c.practiceAction(PracticeAction.pause);
  await c.practiceAction(PracticeAction.resume);
  await c.nextExercise();
}

Future<void> finishSetup(OnboardingController c) async {
  await c.next(); // language
  await c.next(); // access
  c.acceptLimits(true);
  await c.next();
  await c.playVoice();
  await c.playVoice(stop: true);
  c.confirmVoice(true);
  await c.next(); // feedback
  await c.next(); // privacy
  await c.next(); // vocabulary
  await finishPractice(c);
  await c.next(); // practice
  await c.requestCamera();
  await c.next(); // camera
  await c.deviceCheck();
  await c.next(); // device
  await c.alignmentCheck();
  c.confirmAlignment(true);
  await c.next(); // alignment
  c.confirmStationary(true);
  await c.deviceCheck(stationary: true);
  await c.next(); // stationary
}

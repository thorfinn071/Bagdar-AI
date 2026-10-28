import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_copy.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/models/strings.dart';

import 'onboarding_v2_test.dart' show TestGateway, finishSetup;

class SequenceGateway extends TestGateway {
  final results = <ProbeResult>[];
  SequenceGateway(super.clock);

  @override
  Future<ProbeResult> checkAlignment() async {
    if (results.isEmpty) return super.checkAlignment();
    alignmentChecks++;
    return results.removeAt(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late SequenceGateway gateway;
  late MemoryOnboardingStore store;
  late OnboardingController c;

  setUp(() async {
    now = DateTime(2026, 10, 1, 12);
    gateway = SequenceGateway(() => now);
    store = MemoryOnboardingStore();
    c = OnboardingController(store: store, gateway: gateway, now: () => now);
    await c.initialize();
  });
  tearDown(() => c.dispose());

  Future<void> readyToGuide() async {
    await c.goTo(OnboardingStep.alignment);
    c.confirmStationary(true);
  }

  test(
    'guidance requires an explicit request and a stationary confirmation',
    () async {
      await c.goTo(OnboardingStep.alignment);
      expect(gateway.alignmentChecks, 0);
      expect(gateway.speaks, 0);
      await c.guideAlignment();
      expect(gateway.alignmentChecks, 0);
      c.confirmStationary(true);
      await c.guideAlignment();
      expect(gateway.alignmentChecks, 1);
      expect(gateway.cameraChecks, 0);
      expect(gateway.requests, 0);
      expect(gateway.permissionReads, 0);
      expect(c.alignmentAccepted, isFalse);
      expect(c.evidence.alignmentConfirmed, isFalse);
      expect(c.evidence.criticalChannelVerified, isFalse);
      c.confirmAlignment(true);
      expect(c.alignmentAccepted, isTrue);
    },
  );

  test(
    'guidance serializes measured hints and stops on a stable window',
    () async {
      await readyToGuide();
      gateway.results.addAll([
        ProbeResult(ProbeStatus.unavailable, 'alignmentMoreUpright', now),
        ProbeResult(ProbeStatus.unavailable, 'alignmentLevel', now),
        ProbeResult(ProbeStatus.available, 'alignmentStable', now),
      ]);
      await c.guideAlignment();
      expect(gateway.alignmentChecks, 3);
      expect(gateway.spokenTexts, [
        c.copy.t(OnboardingText.coachUpright),
        c.copy.t(OnboardingText.coachLevel),
        c.copy.t(OnboardingText.coachReady),
      ]);
      expect(c.evidence.alignment.freshAt(now), isTrue);
      expect(c.message, OnboardingText.coachReady);
      expect(c.busy, isFalse);
      expect(c.coaching, isFalse);
      expect(c.evidence.alignmentConfirmed, isFalse);
    },
  );

  test(
    'guidance is bounded to four attempts without a readiness shortcut',
    () async {
      await readyToGuide();
      gateway.alignmentResult = ProbeResult(
        ProbeStatus.unavailable,
        'alignmentHoldStill',
        now,
      );
      await c.guideAlignment();
      expect(gateway.alignmentChecks, 4);
      expect(gateway.speaks, 4);
      expect(c.message, OnboardingText.coachRetry);
      c.confirmAlignment(true);
      expect(c.alignmentAccepted, isFalse);
    },
  );

  for (final result in [
    ProbeResult(
      ProbeStatus.unavailable,
      'alignmentUnavailable',
      DateTime(2026, 10, 1, 12),
    ),
    ProbeResult(
      ProbeStatus.available,
      'alignmentStable',
      DateTime(2026, 10, 1, 11, 57),
    ),
    ProbeResult(
      ProbeStatus.available,
      'alignmentStable',
      DateTime(2026, 10, 1, 11, 59, 50),
    ),
    ProbeResult(
      ProbeStatus.available,
      'alignmentStable',
      DateTime(2026, 10, 1, 12, 1),
    ),
  ]) {
    test(
      'missing or invalid sensor evidence ends guidance: ${result.checkedAt}/${result.status}',
      () async {
        await readyToGuide();
        gateway.alignmentResult = result;
        await c.guideAlignment();
        expect(gateway.alignmentChecks, 1);
        expect(
          gateway.spokenTexts.single,
          c.copy.t(OnboardingText.alignmentUnavailable),
        );
        c.confirmAlignment(true);
        expect(c.alignmentAccepted, isFalse);
        expect(c.busy, isFalse);
      },
    );
  }

  test(
    'speech failure ends guidance and retry measures again before giving advice',
    () async {
      await readyToGuide();
      gateway.audible = false;
      gateway.speechFailure = OnboardingSpeechResult.interrupted;
      await c.guideAlignment();
      expect(c.message, OnboardingText.speechInterrupted);
      expect(c.evidence.alignment.status, ProbeStatus.notChecked);
      gateway.audible = true;
      await c.retrySpeech();
      expect(gateway.alignmentChecks, 2);
      expect(gateway.spokenTexts, [
        c.copy.t(OnboardingText.coachReady),
        c.copy.t(OnboardingText.coachReady),
      ]);
      expect(c.evidence.voiceSamplePlayed, isFalse);
      expect(c.evidence.alignment.freshAt(now), isTrue);
      expect(c.evidence.alignmentConfirmed, isFalse);
    },
  );

  test(
    'stopping during a measurement discards its result and all later hints',
    () async {
      await readyToGuide();
      final measurement = Completer<ProbeResult>();
      gateway.pendingAlignment = measurement;
      final running = c.guideAlignment();
      expect(c.coaching, isTrue);
      await c.stopSpeech();
      expect(c.message, OnboardingText.coachStopped);
      expect(c.busy, isFalse);
      gateway.pendingAlignment = null;
      await c.alignmentCheck();
      c.confirmAlignment(true);
      measurement.complete(
        ProbeResult(ProbeStatus.unavailable, 'alignmentMoreFlat', now),
      );
      await running;
      expect(gateway.speaks, 0);
      expect(c.evidence.alignment.freshAt(now), isTrue);
      expect(c.alignmentAccepted, isTrue);
    },
  );

  test(
    'a pending voice hint blocks extra measurements, speech and confirmations',
    () async {
      await readyToGuide();
      gateway.alignmentResult = ProbeResult(
        ProbeStatus.unavailable,
        'alignmentMoreUpright',
        now,
      );
      final speech = Completer<bool>();
      gateway.pendingSpeech = speech;
      final running = c.guideAlignment();
      await Future<void>.delayed(Duration.zero);
      await c.guideAlignment();
      await c.repeatInstruction();
      c.confirmAlignment(true);
      expect(gateway.alignmentChecks, 1);
      expect(gateway.speaks, 1);
      expect(c.alignmentAccepted, isFalse);
      await c.stopSpeech();
      speech.complete(true);
      await running;
    },
  );

  test(
    'stopping during speech cannot restart guidance or invalidate a newer check',
    () async {
      await readyToGuide();
      gateway.alignmentResult = ProbeResult(
        ProbeStatus.unavailable,
        'alignmentMoreFlat',
        now,
      );
      final speech = Completer<bool>();
      gateway.pendingSpeech = speech;
      final running = c.guideAlignment();
      await Future<void>.delayed(Duration.zero);
      expect(gateway.speaks, 1);
      await c.stopSpeech();
      gateway.pendingSpeech = null;
      gateway.alignmentResult = ProbeResult(
        ProbeStatus.available,
        'alignmentStable',
        now,
      );
      await c.alignmentCheck();
      c.confirmAlignment(true);
      speech.complete(true);
      await running;
      expect(gateway.alignmentChecks, 2);
      expect(c.alignmentAccepted, isTrue);
      expect(c.coaching, isFalse);
    },
  );

  test(
    'background cancels guidance and rejects late sensor evidence',
    () async {
      await readyToGuide();
      final measurement = Completer<ProbeResult>();
      gateway.pendingAlignment = measurement;
      final running = c.guideAlignment();
      c.suspend(background: true);
      c.confirmStationary(true);
      measurement.complete(
        ProbeResult(ProbeStatus.available, 'alignmentStable', now),
      );
      await running;
      expect(c.stationaryAccepted, isFalse);
      expect(c.coaching, isFalse);
      expect(c.evidence.alignment.status, ProbeStatus.notChecked);
      expect(gateway.speaks, 0);
      await c.guideAlignment();
      expect(gateway.alignmentChecks, 1);
    },
  );

  testWidgets(
    'measurement timeout releases guidance and ignores late completion',
    (tester) async {
      await readyToGuide();
      final measurement = Completer<ProbeResult>();
      gateway.pendingAlignment = measurement;
      final stoppedBefore = gateway.stops;
      final running = c.guideAlignment();
      await tester.pump(const Duration(seconds: 7));
      await running;
      expect(c.message, OnboardingText.coachRetry);
      expect(c.busy, isFalse);
      expect(gateway.stops, stoppedBefore + 1);
      measurement.complete(
        ProbeResult(ProbeStatus.available, 'alignmentStable', now),
      );
      await tester.pump();
      expect(c.evidence.alignment.status, ProbeStatus.notChecked);
      expect(gateway.speaks, 0);
    },
  );

  testWidgets(
    'voice hint timeout stops playback and requires a new position check',
    (tester) async {
      await readyToGuide();
      final speech = Completer<bool>();
      gateway.pendingSpeech = speech;
      final stoppedBefore = gateway.stops;
      final running = c.guideAlignment();
      await tester.pump();
      expect(gateway.speaks, 1);
      await tester.pump(const Duration(seconds: 21));
      await running;
      expect(c.busy, isFalse);
      expect(c.coaching, isFalse);
      expect(c.message, OnboardingText.coachRetry);
      expect(gateway.stops, stoppedBefore + 1);
      speech.complete(true);
      await tester.pump();
      expect(c.evidence.alignment.status, ProbeStatus.notChecked);
      c.confirmAlignment(true);
      expect(c.alignmentAccepted, isFalse);
    },
  );

  test(
    'helper can configure but cannot confirm or answer on behalf of the user',
    () async {
      await c.selectMode(AccessMode.helper);
      expect(c.userHasControl, isFalse);
      expect(c.requiredStep, OnboardingStep.access);
      await c.goTo(OnboardingStep.limits);
      c.acceptLimits(true);
      await c.next();
      expect(c.step, OnboardingStep.limits);
      expect(c.limitsAccepted, isFalse);
      await c.playVoice();
      await c.playVoice(stop: true);
      await c.playHaptic();
      c.confirmVoice(true);
      c.confirmHaptic(true);
      c.confirmStationary(true);
      await c.alignmentCheck();
      c.confirmAlignment(true);
      expect(c.evidence.criticalChannelVerified, isFalse);
      expect(c.alignmentAccepted, isFalse);
      expect(c.stationaryAccepted, isFalse);
      await c.goTo(OnboardingStep.practice);
      await c.practiceAction(PracticeAction.stop);
      await c.nextExercise();
      expect(c.practiceAnswered, isFalse);
      expect(store.progress!.completedExercises, 0);
      await c.transferControl();
      expect(c.userHasControl, isTrue);
      c.confirmVoice(true);
      c.confirmHaptic(true);
      expect(c.evidence.criticalChannelVerified, isFalse);
      await c.playHaptic();
      c.confirmHaptic(true);
      expect(c.evidence.criticalChannelVerified, isTrue);
      await c.practiceAction(PracticeAction.stop);
      await c.nextExercise();
      expect(store.progress!.completedExercises, 1);
    },
  );

  test(
    'handing back to helper revokes admission and keeps completed training',
    () async {
      await c.selectMode(AccessMode.helper);
      await c.transferControl();
      await finishSetup(c);
      expect(c.admission, Admission.inspectionOnly);
      await c.transferControl(toUser: false);
      expect(c.trainingComplete, isTrue);
      expect(c.admission, Admission.recheckRequired);
      expect(c.requiredStep, OnboardingStep.access);
      var inspections = 0;
      await c.inspect(() async {
        inspections++;
      });
      expect(inspections, 0);
      expect(c.evidence.criticalChannelVerified, isFalse);
      expect(c.alignmentAccepted, isFalse);
      expect(c.stationaryAccepted, isFalse);
      await c.transferControl();
      expect(c.requiredStep, OnboardingStep.feedback);
      final reloaded = OnboardingController(
        store: store,
        gateway: gateway,
        now: () => now,
      );
      await reloaded.initialize();
      expect(reloaded.isQuickCheck, isTrue);
      expect(reloaded.userHasControl, isFalse);
      expect(reloaded.admission, Admission.recheckRequired);
      expect(store.progress!.toJson(), isNot(contains('userHasControl')));
      reloaded.dispose();
    },
  );

  test(
    'session gate rejects helper-owned evidence even when all other checks pass',
    () async {
      await finishSetup(c);
      c.evidence.userHasControl = false;
      expect(
        c.gate.evaluate(c.progress, c.evidence, now),
        Admission.recheckRequired,
      );
      expect(c.requiredStep, OnboardingStep.access);
    },
  );

  test(
    'information blocks preserve mandatory warnings and add only optional explanations',
    () {
      for (final language in AppLanguage.values) {
        final copy = OnboardingCopy(language);
        expect(copy.infoBlocks(OnboardingStep.limits).map((b) => b.body), [
          OnboardingText.limit1,
          OnboardingText.limit2,
          OnboardingText.limit3,
          OnboardingText.limit4,
        ]);
        expect(copy.infoBlocks(OnboardingStep.privacy).map((b) => b.body), [
          OnboardingText.privacyLocal,
          OnboardingText.privacyRecord,
          OnboardingText.privacyOptional,
        ]);
        for (final step in [OnboardingStep.limits, OnboardingStep.privacy]) {
          for (final block in copy.infoBlocks(step)) {
            expect(copy.blockInstruction(block), contains(copy.t(block.body)));
            expect(
              copy.blockInstruction(block),
              isNot(contains(copy.t(block.details))),
            );
            expect(
              copy.blockInstruction(block, details: true),
              contains(copy.t(block.details)),
            );
          }
        }
      }
    },
  );
}

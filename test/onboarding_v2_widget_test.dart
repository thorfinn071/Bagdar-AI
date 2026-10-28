import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_copy.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_screen.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/models/strings.dart';
import 'onboarding_v2_test.dart' show TestGateway, finishSetup;

void main() {
  final captureDirectory = Platform.environment['BAGDAR_CAPTURE_DIR'];
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loader = FontLoader('Inter');
    for (final font in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/Inter-$font.ttf'));
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<OnboardingController> show(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
    AppLanguage language = AppLanguage.ru,
    OnboardingGateway? gateway,
    OnboardingStore? store,
    Future<void> Function(BuildContext, OnboardingController)? onInspect,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OnboardingController(
      store: store ?? MemoryOnboardingStore(),
      gateway: gateway ?? UnavailableOnboardingGateway(),
      initialLanguage: language,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: RepaintBoundary(
            key: const Key('onboarding-capture'),
            child: OnboardingV2Screen(
              controller: controller,
              onInspect: onInspect,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureDirectory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('onboarding-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(captureDirectory);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('first-run screens and practice states render for UX review', (
    tester,
  ) async {
    final c = await show(tester);
    for (final step in OnboardingStep.values) {
      await c.goTo(step);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('heading-${step.name}')), findsOneWidget);
      expect(find.text(c.copy.stepProgress(step)), findsOneWidget);
      expect(tester.takeException(), isNull, reason: step.name);
      await capture(
        tester,
        '${(step.index + 1).toString().padLeft(2, '0')}-${step.name}',
      );
    }
    await c.goTo(OnboardingStep.practice);
    await c.practiceAction(PracticeAction.move);
    await tester.pumpAndSettle();
    await capture(tester, '07-practice-wrong');
    await c.practiceAction(PracticeAction.stop);
    await tester.pumpAndSettle();
    await capture(tester, '07-practice-correct');
    await c.practiceAction(PracticeAction.pause);
    await tester.pumpAndSettle();
    await capture(tester, '07-practice-paused');
    await tester.pumpWidget(const SizedBox());
  });

  for (final language in AppLanguage.values) {
    for (final viewport in [
      (const Size(390, 844), 1.0),
      (const Size(390, 844), 2.0),
      (const Size(844, 390), 2.0),
    ]) {
      testWidgets(
        '${language.name}: practice feedback and next action in $viewport',
        (tester) async {
          final c = await show(
            tester,
            language: language,
            size: viewport.$1,
            scale: viewport.$2,
          );
          final semantics = tester.ensureSemantics();
          await c.goTo(OnboardingStep.practice);
          await tester.pumpAndSettle();
          expect(find.text(c.copy.phase(c.step)), findsOneWidget);
          expect(find.text(c.copy.stepProgress(c.step)), findsOneWidget);
          expect(find.byKey(const Key('onboarding-primary')), findsNothing);

          Future<void> choose(OnboardingText label) async {
            final button = find.widgetWithText(OutlinedButton, c.copy.t(label));
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          void expectVisibleFeedback() {
            final feedback = find.byKey(const Key('practice-feedback'));
            expect(feedback, findsOneWidget);
            expect(
              tester.getRect(feedback).overlaps(Offset.zero & viewport.$1),
              isTrue,
            );
            expect(
              tester
                  .getSemantics(feedback)
                  .getSemanticsData()
                  .flagsCollection
                  .isLiveRegion,
              isTrue,
            );
          }

          await choose(OnboardingText.moveAction);
          expectVisibleFeedback();
          await choose(OnboardingText.moveAction);
          expectVisibleFeedback();
          expect(c.practiceIndex, 0);
          expect(find.text(c.copy.t(OnboardingText.wrongStop)), findsOneWidget);
          expect(find.byKey(const Key('next-exercise')), findsNothing);
          await capture(
            tester,
            'practice-wrong-${language.name}-${viewport.$1.width.toInt()}-${viewport.$2}',
          );

          for (var index = 0; index < 4; index++) {
            if (index == 3) {
              final pause = find.widgetWithText(
                TextButton,
                c.copy.t(OnboardingText.pauseAction),
              );
              await tester.ensureVisible(pause);
              await tester.tap(pause);
              await tester.pumpAndSettle();
              expect(c.practicePaused, isTrue);
              expectVisibleFeedback();
              expect(find.byKey(const Key('next-exercise')), findsNothing);
              await choose(OnboardingText.resumeAction);
            } else {
              await choose(
                index == 1
                    ? OnboardingText.checkAction
                    : OnboardingText.stopAction,
              );
            }
            expectVisibleFeedback();
            expect(
              find.text(c.copy.t(OnboardingText.correctAction)),
              findsOneWidget,
            );
            expect(
              find.text(c.copy.t(OnboardingText.moveAction)),
              findsNothing,
            );
            final next = find.byKey(const Key('next-exercise'));
            expect(
              tester.getRect(next).overlaps(Offset.zero & viewport.$1),
              isTrue,
            );
            expect(
              find.widgetWithText(
                FilledButton,
                c.copy.t(
                  index == 3
                      ? OnboardingText.finishExamples
                      : OnboardingText.nextExample,
                ),
              ),
              findsOneWidget,
            );
            if (index == 0) {
              await capture(
                tester,
                'practice-correct-${language.name}-${viewport.$1.width.toInt()}-${viewport.$2}',
              );
            }
            await tester.ensureVisible(next);
            await tester.tap(next);
            await tester.pumpAndSettle();
            expect(c.practiceIndex, index + 1);
            expect(tester.takeException(), isNull);
          }
          final finish = find.byKey(const Key('onboarding-primary'));
          expect(
            find.text(c.copy.t(OnboardingText.finishPractice)),
            findsOneWidget,
          );
          await tester.ensureVisible(finish);
          await tester.tap(finish);
          await tester.pumpAndSettle();
          expect(c.step, OnboardingStep.camera);
          expect(c.progress.complete(OnboardingStep.practice), isTrue);
          expect(c.evidence.cameraAccess, CameraAccess.notRequested);
          expect(c.admission, Admission.trainingRequired);
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
        },
      );
    }
  }

  testWidgets(
    'selected language screen is native, interactive and captured with Inter',
    (tester) async {
      final c = await show(tester);
      expect(find.text('На каком языке\nвам удобнее?'), findsOneWidget);
      expect(find.byType(Radio<AppLanguage>), findsNWidgets(3));
      await capture(tester, 'language-ru-390x844');
      await tester.ensureVisible(find.text('English'));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(c.progress.language, AppLanguage.en);
      expect(find.text('Continue in English'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('onboarding-primary')));
      await tester.tap(find.byKey(const Key('onboarding-primary')));
      await tester.pumpAndSettle();
      expect(c.step, OnboardingStep.access);
      expect(find.text('With a helper'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  MemoryOnboardingStore trainedStore(AppLanguage language) =>
      MemoryOnboardingStore()
        ..progress = OnboardingProgress(
          language: language,
          checkpoint: OnboardingStep.summary,
          modules: {
            for (final step in OnboardingSessionGate.requiredSetup)
              step: ModuleStatus.completed,
          },
        );

  testWidgets(
    'warning blocks expose headings and explicit reading without automatic speech',
    (tester) async {
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      final semantics = tester.ensureSemantics();
      await c.goTo(OnboardingStep.limits);
      await tester.pumpAndSettle();
      expect(gateway.speaks, 0);
      final blocks = c.copy.infoBlocks(OnboardingStep.limits);
      for (final block in blocks) {
        expect(find.text(c.copy.t(block.body)), findsOneWidget);
        expect(find.text(c.copy.t(block.details)), findsNothing);
        expect(
          tester
              .getSemantics(find.text(c.copy.t(block.title)))
              .getSemanticsData()
              .flagsCollection
              .isHeader,
          isTrue,
        );
      }
      final first = blocks.first;
      final more = find.byKey(ValueKey('details-${first.body.name}'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text(c.copy.t(first.details)), findsOneWidget);
      expect(gateway.speaks, 0);
      final read = find.byKey(ValueKey('read-${first.body.name}'));
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(
        gateway.spokenTexts.single,
        c.copy.blockInstruction(first, details: true),
      );
      expect(c.limitsAccepted, isFalse);
      expect(c.progress.complete(OnboardingStep.limits), isFalse);
      await capture(tester, 'limits-block-expanded');
      await c.goTo(OnboardingStep.privacy);
      await c.goTo(OnboardingStep.limits);
      await tester.pumpAndSettle();
      expect(find.text(c.copy.t(first.details)), findsNothing);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in AppLanguage.values) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets(
        '${language.name}: helper, expanded blocks and active guidance at 200% in $size',
        (tester) async {
          final gateway = TestGateway(DateTime.now);
          final store = MemoryOnboardingStore()
            ..progress = OnboardingProgress(
              language: language,
              accessMode: AccessMode.helper,
              checkpoint: OnboardingStep.alignment,
            );
          final c = await show(
            tester,
            size: size,
            scale: 2,
            language: language,
            gateway: gateway,
            store: store,
          );
          final semantics = tester.ensureSemantics();
          expect(c.userHasControl, isFalse);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('onboarding-position-guide')),
                )
                .onPressed,
            isNull,
          );
          for (final checkbox in tester.widgetList<CheckboxListTile>(
            find.byType(CheckboxListTile),
          )) {
            expect(checkbox.onChanged, isNull);
          }
          expect(gateway.speaks, 0);
          expect(gateway.cameraChecks, 0);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'helper-${language.name}-${size.width.toInt()}-200percent',
          );
          final handoff = find.byKey(const Key('onboarding-handoff'));
          await tester.ensureVisible(handoff);
          expect(
            tester
                .getSemantics(handoff)
                .getSemanticsData()
                .flagsCollection
                .isButton,
            isTrue,
          );
          await tester.tap(handoff);
          await tester.pumpAndSettle();
          expect(c.userHasControl, isTrue);
          expect(c.evidence.criticalChannelVerified, isFalse);
          c.confirmStationary(true);
          await tester.pumpAndSettle();
          final guide = find.byKey(const Key('onboarding-position-guide'));
          await tester.ensureVisible(guide);
          final measurement = Completer<ProbeResult>();
          gateway.pendingAlignment = measurement;
          await tester.tap(guide);
          await tester.pump();
          expect(c.coaching, isTrue);
          expect(c.speaking, isTrue);
          expect(c.evidence.alignmentConfirmed, isFalse);
          final stop = find.byKey(const Key('onboarding-instruction'));
          await tester.ensureVisible(stop);
          await tester.pump();
          expect(find.text(c.copy.t(OnboardingText.coachStop)), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'guide-${language.name}-${size.width.toInt()}-200percent',
          );
          await tester.tap(stop);
          await tester.pumpAndSettle();
          measurement.complete(
            ProbeResult(
              ProbeStatus.available,
              'alignmentStable',
              DateTime.now(),
            ),
          );
          await tester.pumpAndSettle();
          expect(c.coaching, isFalse);
          expect(c.evidence.alignment.status, ProbeStatus.notChecked);
          expect(gateway.speaks, 0);
          gateway.pendingAlignment = null;
          await c.goTo(OnboardingStep.privacy);
          await tester.pumpAndSettle();
          for (final block in c.copy.infoBlocks(OnboardingStep.privacy)) {
            final more = find.byKey(ValueKey('details-${block.body.name}'));
            await tester.ensureVisible(more);
            await tester.tap(more);
            await tester.pumpAndSettle();
            expect(find.text(c.copy.t(block.details)), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.ensureVisible(
            find.byKey(const Key('onboarding-primary')),
          );
          expect(tester.takeException(), isNull);
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'short check advances by human actions and blocks inspection until ready',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now)..access = CameraAccess.denied;
      var inspections = 0;
      final c = await show(
        tester,
        gateway: gateway,
        store: trainedStore(AppLanguage.ru),
        onInspect: (_, _) async {
          inspections++;
        },
      );
      expect(c.isQuickCheck, isTrue);
      expect(gateway.cameraChecks, 0);
      expect(gateway.speaks, 0);
      expect(
        find.bySemanticsLabel('Проверка 1 из 3. Проверка перед запуском'),
        findsOneWidget,
      );
      await capture(tester, 'session-signals');
      await tester.ensureVisible(find.text(c.copy.t(OnboardingText.useHaptic)));
      await tester.tap(find.text(c.copy.t(OnboardingText.useHaptic)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(c.copy.t(OnboardingText.stopHaptic)),
      );
      await tester.tap(find.text(c.copy.t(OnboardingText.stopHaptic)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(c.copy.t(OnboardingText.felt)));
      await tester.tap(find.text(c.copy.t(OnboardingText.felt)));
      await tester.pumpAndSettle();
      expect(c.sessionStage, 2);
      expect(
        find.bySemanticsLabel('Проверка 2 из 3. Проверка перед запуском'),
        findsOneWidget,
      );
      gateway.access = CameraAccess.granted;
      await tester.ensureVisible(
        find.text(c.copy.t(OnboardingText.cameraRequest)),
      );
      await tester.tap(find.text(c.copy.t(OnboardingText.cameraRequest)));
      await tester.pumpAndSettle();
      expect(c.sessionStage, 3);
      final check = find.byKey(const Key('onboarding-check-session'));
      expect(tester.widget<OutlinedButton>(check).onPressed, isNull);
      await tester.ensureVisible(
        find.text(c.copy.t(OnboardingText.stationaryConfirm)),
      );
      await tester.tap(find.text(c.copy.t(OnboardingText.stationaryConfirm)));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(check).onPressed, isNotNull);
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(c.admission, Admission.recheckRequired);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('onboarding-primary')))
            .onPressed,
        isNull,
      );
      await capture(tester, 'session-position-unconfirmed');
      await tester.ensureVisible(
        find.text(c.copy.t(OnboardingText.alignmentConfirm)),
      );
      await tester.tap(find.text(c.copy.t(OnboardingText.alignmentConfirm)));
      await tester.pumpAndSettle();
      expect(c.admission, Admission.inspectionOnly);
      final inspect = find.byKey(const Key('onboarding-primary'));
      await tester.ensureVisible(inspect);
      await tester.tap(inspect);
      await tester.pumpAndSettle();
      expect(inspections, 1);
      expect(gateway.cameraChecks, 1);
      expect(gateway.alignmentChecks, 1);
      await capture(tester, 'session-ready');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(c.sessionStage, 1);
      expect(c.admission, Admission.recheckRequired);
      expect(gateway.cameraChecks, 1);
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets(
    'speech recovery retries the failed sample through accessible controls',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now)
        ..audible = false
        ..speechFailure = OnboardingSpeechResult.interrupted;
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.feedback);
      await c.playVoice(stop: true);
      await tester.pumpAndSettle();
      expect(
        find.text(c.copy.t(OnboardingText.speechInterrupted)),
        findsOneWidget,
      );
      final retry = find.byKey(const Key('onboarding-retry-speech'));
      await tester.ensureVisible(retry);
      gateway.audible = true;
      final action = tester.getSemantics(retry);
      expect(action.getSemanticsData().flagsCollection.isButton, isTrue);
      action.owner!.performAction(action.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(c.evidence.stopVoicePlayed, isTrue);
      expect(c.evidence.voiceConfirmed, isFalse);
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  for (final language in AppLanguage.values) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      testWidgets(
        '${language.name}: short check at 200% in $size has no layout failures',
        (tester) async {
          final gateway = TestGateway(DateTime.now);
          final c = await show(
            tester,
            language: language,
            size: size,
            scale: 2,
            gateway: gateway,
            store: trainedStore(language),
          );
          expect(c.isQuickCheck, isTrue);
          expect(tester.takeException(), isNull);
          await c.playHaptic();
          c.confirmHaptic(true);
          await tester.pumpAndSettle();
          expect(c.sessionStage, 3);
          c.confirmStationary(true);
          await c.checkSession();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'session-${language.name}-${size.width.toInt()}-200percent',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'unavailable voice has explicit status and cannot be user-confirmed',
    (tester) async {
      final c = await show(tester);
      await c.goTo(OnboardingStep.feedback);
      await tester.pumpAndSettle();
      final confirms = tester.widgetList<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(confirms.every((tile) => tile.onChanged == null), isTrue);
      await tester.tap(find.text('Обычная подсказка'));
      await tester.pumpAndSettle();
      expect(c.evidence.voiceSamplePlayed, isFalse);
      expect(c.message, isNotNull);
      await capture(tester, 'feedback-ru-390x844');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'practice buttons require correct action and an explicit pause/resume',
    (tester) async {
      final c = await show(tester);
      await c.goTo(OnboardingStep.practice);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Продолжить движение'));
      await tester.tap(find.text('Продолжить движение'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('next-exercise')), findsNothing);
      await tester.ensureVisible(find.text('Остановиться'));
      await tester.tap(find.text('Остановиться'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('next-exercise')));
      await tester.tap(find.byKey(const Key('next-exercise')));
      await tester.pumpAndSettle();
      expect(c.practiceIndex, 1);
      await tester.ensureVisible(find.text('Поставить на паузу'));
      await tester.tap(find.text('Поставить на паузу'));
      await tester.pumpAndSettle();
      expect(c.practicePaused, isTrue);
      expect(find.text('Возобновить'), findsOneWidget);
      await tester.tap(find.text('Возобновить'));
      await tester.pumpAndSettle();
      expect(c.practicePaused, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'semantic language choices expose selection and tap actions once',
    (tester) async {
      final handle = tester.ensureSemantics();
      await show(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Русский'));
      expect(
        node.getSemanticsData().flagsCollection.isChecked,
        ui.CheckedState.isTrue,
      );
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      expect(
        find.bySemanticsLabel('Шаг 1 из 12. На каком языке\nвам удобнее?'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets(
    'all steps offer explicit repeat without autoplay or camera access',
    (tester) async {
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      for (final step in OnboardingStep.values) {
        final before = gateway.speaks;
        await c.goTo(step);
        await tester.pumpAndSettle();
        expect(gateway.speaks, before);
        final repeat = find.byKey(const Key('onboarding-instruction'));
        await tester.ensureVisible(repeat);
        await tester.tap(repeat);
        await tester.pumpAndSettle();
        expect(gateway.speaks, before + 1);
        expect(gateway.spokenTexts.last, contains(c.copy.stepProgress(step)));
      }
      expect(gateway.requests, 0);
      expect(gateway.cameraChecks, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reading can be stopped through semantics without live announcements',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.limits);
      await tester.pumpAndSettle();
      gateway.pendingSpeech = Completer<bool>();
      final repeat = tester.getSemantics(
        find.byKey(const Key('onboarding-instruction')),
      );
      repeat.owner!.performAction(repeat.id, ui.SemanticsAction.tap);
      await tester.pump();
      expect(c.speaking, isTrue);
      expect(find.text('Остановить озвучку'), findsOneWidget);
      final heading = tester.getSemantics(
        find.byKey(const ValueKey('heading-limits')),
      );
      expect(heading.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      final stop = tester.getSemantics(
        find.byKey(const Key('onboarding-instruction')),
      );
      stop.owner!.performAction(stop.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      gateway.pendingSpeech!.complete(true);
      await tester.pumpAndSettle();
      expect(c.speaking, isFalse);
      expect(c.message, OnboardingText.speechStopped);
      expect(c.limitsAccepted, isFalse);
      await capture(tester, 'limits-with-repeat');
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets('Back stops reading and navigates in one action', (tester) async {
    final gateway = TestGateway(DateTime.now);
    final c = await show(tester, gateway: gateway);
    await c.goTo(OnboardingStep.limits);
    await tester.pumpAndSettle();
    gateway.pendingSpeech = Completer<bool>();
    await tester.tap(find.byKey(const Key('onboarding-instruction')));
    await tester.pump();
    await tester.tap(find.text('Назад'));
    await tester.pumpAndSettle();
    gateway.pendingSpeech!.complete(true);
    await tester.pumpAndSettle();
    expect(c.step, OnboardingStep.access);
    expect(c.progress.complete(OnboardingStep.limits), isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'new exercise exposes its number and keyboard focus without speech',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.practice);
      await c.practiceAction(PracticeAction.stop);
      await tester.pumpAndSettle();
      await c.nextExercise();
      await tester.pumpAndSettle();
      final heading = tester.getSemantics(find.text('Упражнение 2 из 4'));
      expect(heading.getSemanticsData().flagsCollection.isHeader, isTrue);
      expect(heading.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'onboarding-exercise',
      );
      expect(gateway.speaks, 0);
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets('screen and language choices expose their own speech locales', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final c = await show(tester);
    for (final option in [
      ('Қазақша', 'kk'),
      ('Русский', 'ru'),
      ('English', 'en'),
    ]) {
      final choice = tester.getSemantics(find.bySemanticsLabel(option.$1));
      expect(choice.getSemanticsData().locale?.languageCode, option.$2);
    }
    await c.selectLanguage(AppLanguage.kk);
    await c.goTo(OnboardingStep.limits);
    await tester.pumpAndSettle();
    final heading = tester.getSemantics(
      find.byKey(const ValueKey('heading-limits')),
    );
    expect(heading.getSemanticsData().locale?.languageCode, 'kk');
    await tester.pumpWidget(const SizedBox());
    handle.dispose();
  });

  testWidgets(
    'alignment correction is announced and available in step reading',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now)
        ..alignmentResult = ProbeResult(
          ProbeStatus.unavailable,
          'alignmentMoreUpright',
          DateTime.now(),
        );
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.alignment);
      await c.alignmentCheck();
      await tester.pumpAndSettle();
      final correction = c.copy.t(OnboardingText.alignmentMoreUpright);
      final node = tester.getSemantics(find.text(correction));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      await tester.tap(find.byKey(const Key('onboarding-instruction')));
      await tester.pumpAndSettle();
      expect(gateway.spokenTexts.single, contains(correction));
      expect(c.evidence.alignmentConfirmed, isFalse);
      await capture(tester, 'alignment-correction');
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets('rapid exercise taps disable the transition and cannot skip', (
    tester,
  ) async {
    final gateway = TestGateway(DateTime.now);
    final c = await show(tester, gateway: gateway);
    await c.goTo(OnboardingStep.practice);
    await c.practiceAction(PracticeAction.stop);
    await tester.pumpAndSettle();
    final next = find.byKey(const Key('next-exercise'));
    await tester.ensureVisible(next);
    gateway.pendingStop = Completer<void>();
    await tester.tap(next);
    await tester.tap(next);
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    gateway.pendingStop!.complete();
    await tester.pumpAndSettle();
    expect(c.practiceIndex, 1);
    expect(c.practiceAnswered, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'lifecycle resume updates camera status without starting a camera',
    (tester) async {
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.camera);
      await tester.pumpAndSettle();
      gateway.pendingCameraRequest = Completer<CameraAccess>();
      await tester.tap(find.text('Разрешить камеру'));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      gateway.access = CameraAccess.granted;
      gateway.pendingCameraRequest!.complete(CameraAccess.granted);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(c.evidence.cameraAccess, CameraAccess.granted);
      expect(gateway.requests, 1);
      expect(gateway.cameraChecks, 0);
      expect(c.evidence.camera.status, ProbeStatus.notChecked);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'screen reader actions have button roles and invoke their handler',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      await c.goTo(OnboardingStep.feedback);
      await tester.pumpAndSettle();
      final action = tester.getSemantics(
        find.bySemanticsLabel('Обычная подсказка'),
      );
      expect(action.getSemanticsData().flagsCollection.isButton, isTrue);
      expect(
        action.getSemanticsData().hasAction(ui.SemanticsAction.tap),
        isTrue,
      );
      action.owner!.performAction(action.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(gateway.speaks, 1);
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  testWidgets(
    'summary names and opens the missing confirmation for a screen reader',
    (tester) async {
      final handle = tester.ensureSemantics();
      final gateway = TestGateway(DateTime.now);
      final c = await show(tester, gateway: gateway);
      await finishSetup(c);
      c.confirmAlignment(false);
      await tester.pumpAndSettle();
      final expected = c.copy.nextRequiredStep(OnboardingStep.alignment);
      await tester.ensureVisible(find.text(expected));
      await tester.pumpAndSettle();
      final reason = tester.getSemantics(find.text(expected));
      expect(reason.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(
        find.text(c.copy.t(OnboardingText.confirmationRequired)),
        findsOneWidget,
      );
      await capture(tester, 'summary-missing-alignment');
      await tester.ensureVisible(find.text('Продолжить настройку'));
      await tester.tap(find.text('Продолжить настройку'));
      await tester.pumpAndSettle();
      expect(c.isQuickCheck, isTrue);
      expect(c.requiredStep, OnboardingStep.alignment);
      final heading = tester.getSemantics(
        find.bySemanticsLabel('Проверка 3 из 3. Проверка перед запуском'),
      );
      expect(heading.getSemanticsData().flagsCollection.isHeader, isTrue);
      expect(heading.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      await capture(tester, 'alignment-recovery');
      await tester.pumpWidget(const SizedBox());
      handle.dispose();
    },
  );

  for (final language in AppLanguage.values) {
    for (final viewport in [
      (const Size(390, 844), 2.0),
      (const Size(844, 390), 2.0),
    ]) {
      testWidgets('${language.name}: every module at 200% in ${viewport.$1}', (
        tester,
      ) async {
        final c = await show(
          tester,
          size: viewport.$1,
          scale: viewport.$2,
          language: language,
        );
        for (final step in OnboardingStep.values) {
          await c.goTo(step);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: step.name);
          final primary = find.byKey(
            Key(
              step == OnboardingStep.practice
                  ? 'onboarding-later'
                  : 'onboarding-primary',
            ),
          );
          await tester.ensureVisible(primary);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${step.name} bottom');
          if (captureDirectory != null &&
              language == AppLanguage.ru &&
              viewport.$1.width == 390 &&
              step == OnboardingStep.language) {
            await capture(tester, 'language-ru-200percent');
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'readiness screen shows unavailable data and training path, no inspection action',
    (tester) async {
      final c = await show(tester);
      await c.goTo(OnboardingStep.summary);
      await tester.pumpAndSettle();
      expect(find.text('Открыть проверку камеры'), findsNothing);
      expect(find.text('Продолжить настройку'), findsOneWidget);
      await capture(tester, 'summary-ru-390x844');
      await tester.ensureVisible(find.text('Повторить обучение без камеры'));
      await tester.tap(find.text('Повторить обучение без камеры'));
      await tester.pumpAndSettle();
      expect(c.step, OnboardingStep.vocabulary);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

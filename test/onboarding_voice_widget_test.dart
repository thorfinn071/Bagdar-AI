import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_screen.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_copy.dart';
import 'package:bagdar/features/onboarding_v2/voice/onboarding_voice_input.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'onboarding_v2_test.dart' show TestGateway;
import 'support/fake_onboarding_voice_input.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final fonts = FontLoader('Inter');
    for (final font in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$font.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  Future<OnboardingController> show(
    WidgetTester tester,
    FakeOnboardingVoiceInput input, {
    AppLanguage language = AppLanguage.ru,
    Size size = const Size(390, 844),
    double scale = 1,
    OnboardingStep? step,
    bool trained = false,
    BagdarThemeName theme = BagdarThemeName.light,
    Future<void> Function(BuildContext, OnboardingController)? onInspect,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryOnboardingStore();
    if (trained) {
      store.progress = OnboardingProgress(
        language: language,
        checkpoint: OnboardingStep.summary,
        modules: {
          for (final s in OnboardingSessionGate.requiredSetup)
            s: ModuleStatus.completed,
        },
      );
    }
    final c = OnboardingController(
      store: store,
      gateway: TestGateway(DateTime.now),
      initialLanguage: language,
    );
    await c.initialize();
    if (step != null) await c.goTo(step);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: RepaintBoundary(
            key: const Key('voice-capture'),
            child: BagdarThemeScope(
              name: theme,
              child: OnboardingV2Screen(
                controller: c,
                voiceInput: input,
                onInspect: onInspect,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['BAGDAR_VOICE_CAPTURE_DIR'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('voice-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'voice input is opt-in and can be turned off through accessible controls',
    (tester) async {
      final input = FakeOnboardingVoiceInput();
      final c = await show(tester, input);
      final semantics = tester.ensureSemantics();
      expect(input.permissionRequests, isEmpty);
      expect(input.turns, isEmpty);
      final enable = find.byKey(const Key('onboarding-voice-enable'));
      await tester.ensureVisible(enable);
      expect(tester.getSize(enable).height, greaterThanOrEqualTo(48));
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(input.permissionRequests, [true]);
      expect(input.pending, isNotNull);
      final status = find.byKey(const Key('onboarding-voice-status'));
      expect(
        tester
            .getSemantics(status)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
      input.answer('русский');
      await tester.pumpAndSettle();
      expect(c.step, OnboardingStep.access);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('heading-access')))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
      final disable = find.byKey(const Key('onboarding-voice-disable'));
      await tester.ensureVisible(disable);
      await tester.tap(disable);
      await tester.pumpAndSettle();
      expect(input.pending, isNull);
      expect(find.byKey(const Key('onboarding-voice-enable')), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'denied permission keeps the accessible manual flow and explains recovery',
    (tester) async {
      final input = FakeOnboardingVoiceInput()
        ..availability = VoiceInputAvailability.permissionDenied;
      final c = await show(tester, input);
      final enable = find.byKey(const Key('onboarding-voice-enable'));
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(input.turns, isEmpty);
      expect(
        find.text(
          const OnboardingVoiceCopy(
            AppLanguage.ru,
          ).t(VoiceCopy.permissionDenied),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('onboarding-primary')), findsOneWidget);
      expect(c.step, OnboardingStep.language);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'lifecycle cancellation closes input and resumes without requesting permission again',
    (tester) async {
      final input = FakeOnboardingVoiceInput();
      final c = await show(tester, input);
      final enable = find.byKey(const Key('onboarding-voice-enable'));
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(input.pending, isNull);
      expect(c.isForeground, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(input.permissionRequests, [true, false]);
      expect(input.pending, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.light, BagdarThemeName.dark]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets(
          '${language.name}: hardware and short-check voice UI, ${theme.name}, $size, 200%',
          (tester) async {
            for (final step in [
              OnboardingStep.camera,
              OnboardingStep.device,
              OnboardingStep.alignment,
              OnboardingStep.stationary,
              OnboardingStep.summary,
              null,
            ]) {
              final input = FakeOnboardingVoiceInput();
              final c = await show(
                tester,
                input,
                language: language,
                size: size,
                scale: 2,
                step: step,
                trained: true,
                theme: theme,
              );
              expect(c.isQuickCheck, step == null);
              final enable = find.byKey(const Key('onboarding-voice-enable'));
              await tester.ensureVisible(enable);
              await tester.tap(enable);
              await tester.pumpAndSettle();
              expect(input.pending, isNotNull);
              final disable = find.byKey(const Key('onboarding-voice-disable'));
              await tester.ensureVisible(disable);
              await tester.pumpAndSettle();
              expect(tester.getSize(disable).height, greaterThanOrEqualTo(48));
              expect(tester.takeException(), isNull);
              await capture(
                tester,
                '${language.name}-${theme.name}-${step?.name ?? 'quick'}-${size.width.toInt()}-200-listening',
              );
              await tester.tap(disable);
              await tester.pumpAndSettle();
              expect(input.pending, isNull);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
            }
          },
        );
      }
    }
    for (final viewport in [
      (const Size(390, 844), 1.0),
      (const Size(390, 844), 2.0),
      (const Size(844, 390), 2.0),
    ]) {
      testWidgets('${language.name}: voice controls fit $viewport', (
        tester,
      ) async {
        final input = FakeOnboardingVoiceInput();
        await show(
          tester,
          input,
          language: language,
          size: viewport.$1,
          scale: viewport.$2,
        );
        final enable = find.byKey(const Key('onboarding-voice-enable'));
        await tester.ensureVisible(enable);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          '${language.name}-${viewport.$1.width.toInt()}-${viewport.$2}-off',
        );
        await tester.tap(enable);
        await tester.pumpAndSettle();
        expect(input.pending, isNotNull);
        final disable = find.byKey(const Key('onboarding-voice-disable'));
        await tester.ensureVisible(disable);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          '${language.name}-${viewport.$1.width.toInt()}-${viewport.$2}-listening',
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
    'the screen inspection button closes active voice input before the existing callback',
    (tester) async {
      final input = FakeOnboardingVoiceInput();
      var opened = 0;
      final c = await show(
        tester,
        input,
        trained: true,
        step: OnboardingStep.summary,
        onInspect: (_, controller) async {
          expect(input.pending, isNull);
          expect(controller.admission, Admission.inspectionOnly);
          opened++;
        },
      );
      await c.playVoice();
      c.confirmOrdinaryVoice(true);
      await c.playVoice(stop: true);
      c.confirmVoice(true);
      c.confirmStationary(true);
      await c.deviceCheck(stationary: true);
      await c.alignmentCheck();
      c.confirmAlignment(true);
      await tester.pumpAndSettle();
      final enable = find.byKey(const Key('onboarding-voice-enable'));
      await tester.ensureVisible(enable);
      await tester.tap(enable);
      await tester.pumpAndSettle();
      expect(input.pending, isNotNull);
      final inspect = find.byKey(const Key('onboarding-primary'));
      await tester.ensureVisible(inspect);
      await tester.tap(inspect);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(input.pending, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

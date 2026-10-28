import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/services/voice/inspection_voice_coordinator.dart';
import 'package:bagdar/services/voice/voice_settings.dart';
import 'package:bagdar/services/voice/voice_settings_coordinator.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_utility_routes.dart';
import 'package:bagdar/widgets/voice_settings_dialog.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:bagdar/widgets/inspection_voice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'inspection_voice_test.dart' show GuardedInput;
import 'support/fake_voice_settings_gateway.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      font.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  late GuardedInput input;
  late FakeVoiceSettingsGateway gateway;
  late VoiceSettingsCoordinator voice;
  late InspectionUtilityRoutes routes;
  Future<void> show(
    WidgetTester tester, {
    bool autoStart = false,
    AppLanguage language = AppLanguage.ru,
    Size size = const Size(375, 812),
    BagdarThemeName theme = BagdarThemeName.dark,
    Future<bool> Function()? release,
    bool curtain = false,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    bagdarThemeNotifier.value = theme;
    AppStrings.setLanguage(language);
    input = GuardedInput();
    gateway = FakeVoiceSettingsGateway()..language = language;
    routes = InspectionUtilityRoutes(
      canOpen: () => true,
      releaseVoiceInput: release,
    );
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('settings-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BagdarTheme.buildMaterialTheme(theme),
          builder: (_, child) => MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => InspectionSurface(
                background: const ColoredBox(color: Colors.black),
                screenCurtain: curtain,
                sosState: const SosUiState.idle(),
                status: InspectionSystemStatus.fromHealth(
                  CoreHealthCoordinator().snapshot(DateTime(2026, 10, 13)),
                  cameraReady: false,
                  permissionDenied: false,
                ),
                onStatus: () {},
                onSettings: () {},
                onHelp: () {},
                onFinish: () {},
                onSos: () {},
                onCancelSos: () {},
                onDismissSos: () {},
                voiceControls: InspectionVoicePanel(
                  phase: InspectionVoicePhase.off,
                  active: false,
                  message: '',
                  onStart: () {},
                  onStop: () {},
                  onVoiceSettings: () => unawaited(
                    routes.open(
                      context,
                      builder: (_) => VoiceSettingsDialog(
                        autoStart: autoStart,
                        screenCurtain: curtain,
                        createController: (routeCanInteract) {
                          voice = VoiceSettingsCoordinator(
                            input: input,
                            gateway: gateway,
                            language: () => S.current,
                            canInteract: routeCanInteract,
                            speak: (_) async => true,
                            prepareInput: () async => true,
                          );
                          return voice;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final open = find.byKey(const Key('inspection-voice-settings'));
    await tester.ensureVisible(open);
    await tester.pumpAndSettle();
    expect(tester.getSize(open).height, greaterThanOrEqualTo(48));
    await tester.tap(open);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['BAGDAR_VOICE_SETTINGS_CAPTURE_DIR'];
    if (directory == null) return;
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(VoiceSettingsDialog),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scroll.position.jumpTo(0);
    await tester.pump();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('settings-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$directory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> close(WidgetTester tester) async {
    input.failCancel = false;
    final close = find.byKey(const Key('voice-settings-close'));
    await tester.ensureVisible(close);
    await tester.pumpAndSettle();
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSettingsDialog), findsNothing);
    routes.dispose();
  }

  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.light, BagdarThemeName.dark]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets('settings 200%: $language $theme $size', (tester) async {
          await show(tester, language: language, theme: theme, size: size);
          final semantics = tester.ensureSemantics();
          expect(input.turns, isEmpty);
          final name =
              '${language.name}-${theme.name}-${size.width.toInt()}x${size.height.toInt()}';
          await capture(tester, '$name-menu-off');
          final start = find.byKey(const Key('voice-settings-start'));
          await tester.ensureVisible(start);
          await tester.pumpAndSettle();
          expect(tester.getSize(start).height, greaterThanOrEqualTo(48));
          await tester.tap(start);
          await tester.pumpAndSettle();
          expect(input.permissionRequests, [true]);
          expect(voice.phase, InspectionVoicePhase.listening);
          await capture(tester, '$name-menu-listening');
          final answers = switch (language) {
            AppLanguage.ru => ['речь', 'темп', 'медленнее', 'сохранить'],
            AppLanguage.kk => ['сөйлеу', 'қарқын', 'баяуырақ', 'сақтау'],
            AppLanguage.en => ['speech', 'rate', 'slower', 'save'],
          };
          for (final answer in answers.take(3)) {
            input.answer(answer);
            await tester.pumpAndSettle();
          }
          expect(voice.page, VoiceSettingsPage.review);
          expect(gateway.writes, isEmpty);
          expect(find.text(voice.question), findsOneWidget);
          await capture(tester, '$name-review');
          input.failCancel = true;
          input.answer(answers.last);
          await tester.pumpAndSettle();
          expect(gateway.writes, isEmpty);
          expect(voice.canStart, isFalse);
          expect(tester.widget<OutlinedButton>(start).onPressed, isNull);
          await capture(tester, '$name-shutdown-failed');
          expect(tester.takeException(), isNull);
          semantics.dispose();
          await close(tester);
        });
      }
    }
  }
  testWidgets(
    'voice handoff activates only after route release and never requests permission again',
    (tester) async {
      final released = Completer<bool>();
      await show(tester, autoStart: true, release: () => released.future);
      expect(find.byType(VoiceSettingsDialog), findsNothing);
      expect(input.turns, isEmpty);
      expect(input.permissionRequests, isEmpty);
      released.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(VoiceSettingsDialog), findsOneWidget);
      expect(input.permissionRequests, [false]);
      input.answer('отменить');
      await tester.pumpAndSettle();
      await close(tester);
    },
  );
  testWidgets(
    'rejected microphone transfer cannot open settings or capture input',
    (tester) async {
      await show(tester, autoStart: true, release: () async => false);
      expect(find.byType(VoiceSettingsDialog), findsNothing);
      expect(input.turns, isEmpty);
      expect(input.permissionRequests, isEmpty);
      routes.dispose();
    },
  );
  testWidgets(
    'background cancels the confirmation and foreground does not auto-restart',
    (tester) async {
      await show(tester, autoStart: true);
      for (final answer in ['речь', 'темп', 'медленнее']) {
        input.answer(answer);
        await tester.pumpAndSettle();
      }
      input.completeOnCancel = false;
      final old = input.pending!;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      input.complete(old, 'сохранить');
      await tester.pumpAndSettle();
      expect(gateway.writes, isEmpty);
      expect(input.turns, hasLength(4));
      input.completeOnCancel = true;
      await close(tester);
    },
  );
  testWidgets('system back waits for confirmed shutdown', (tester) async {
    await show(tester, autoStart: true);
    input.closing = Completer<void>();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(VoiceSettingsDialog), findsOneWidget);
    input.closing!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSettingsDialog), findsNothing);
    expect(gateway.writes, isEmpty);
    routes.dispose();
  });
  testWidgets('closing during failed shutdown keeps recovery visible', (
    tester,
  ) async {
    await show(tester, autoStart: true);
    input.failCancel = true;
    final button = find.byKey(const Key('voice-settings-close'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(VoiceSettingsDialog), findsOneWidget);
    expect(voice.message, contains('не подтверждена'));
    await close(tester);
  });
  testWidgets('the visible settings dialog follows a published theme change', (
    tester,
  ) async {
    await show(tester, theme: BagdarThemeName.dark);
    expect(
      Theme.of(tester.element(find.byType(Dialog))).brightness,
      Brightness.dark,
    );
    bagdarThemeNotifier.value = BagdarThemeName.light;
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Dialog))).brightness,
      Brightness.light,
    );
    expect(input.turns, isEmpty);
    await close(tester);
  });
  testWidgets(
    'screen curtain preserves accessible controls without starting ASR',
    (tester) async {
      await show(tester, curtain: true);
      final semantics = tester.ensureSemantics();
      final opacity = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(VoiceSettingsDialog),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(opacity.opacity, 0);
      expect(opacity.alwaysIncludeSemantics, isTrue);
      expect(
        tester
            .getSemantics(find.byKey(const Key('voice-settings-start')))
            .label,
        contains(voiceSettingsText('start', S.current)),
      );
      expect(input.turns, isEmpty);
      semantics.dispose();
      await close(tester);
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/fall_countdown_controller.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/camera/voice_command_dispatcher.dart';
import 'package:bagdar/models/constants.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/sos_service.dart';
import 'package:bagdar/services/scene_narrator.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/services/voice_command_service.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/sos_controls.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

class _UnusedCameraViewModel implements CameraViewModel {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected VM access: ${invocation.memberName}');
}

class _FakeSos extends SosService {
  final completer = Completer<SosResult>();
  int requests = 0;

  @override
  String get contactNumber => 'test-contact-never-used';

  @override
  Future<SosResult> sendSos({int retries = kSosRetries}) {
    requests++;
    return completer.future;
  }
}

void main() {
  final captureDir = Platform.environment['BAGDAR_SOS_CAPTURE_DIR'];

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

  setUp(() => AppStrings.setLanguage(AppLanguage.ru));

  FallCountdownController controller(_FakeSos sos) {
    final c = FallCountdownController(
      tts: TtsService.forTesting(),
      sos: sos,
      voice: VoiceCommandService(),
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> show(
    WidgetTester tester, {
    required SosUiState Function() state,
    Listenable? listenable,
    VoidCallback? onSend,
    VoidCallback? onCancel,
    VoidCallback? onDismiss,
    VoidCallback? backgroundTap,
    Size size = const Size(390, 844),
    double scale = 1,
    BagdarThemeName theme = BagdarThemeName.dark,
    bool screenCurtain = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget content() => GestureDetector(
      excludeFromSemantics: state().phase != SosUiPhase.idle,
      onTap: backgroundTap,
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Semantics(
              label: 'Background camera controls',
              child: const SizedBox.expand(),
            ),
            SosSurface(
              state: state(),
              screenCurtain: screenCurtain,
              onSend: onSend ?? () {},
              onCancelCountdown: onCancel ?? () {},
              onDismiss: onDismiss ?? () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('sos-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BagdarTheme.buildMaterialTheme(theme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: BagdarTheme(
            name: theme,
            colors: BagdarColors.of(theme),
            child: listenable == null
                ? content()
                : ListenableBuilder(
                    listenable: listenable,
                    builder: (_, __) => content(),
                  ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> activate(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    final node = tester.getSemantics(finder);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureDir == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('sos-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(captureDir);
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'semantic cancellation needs two actions; background tap is not invoked',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sos = _FakeSos();
      final c = controller(sos)..initForTesting(secondsLeft: 11);
      var backgroundTaps = 0;
      await show(
        tester,
        state: () => c.uiState,
        listenable: c,
        onCancel: c.notifyTouch,
        backgroundTap: () => backgroundTaps++,
      );
      expect(find.text(S.get('sos_fall_cancelled')), findsNothing);
      final cancelId = tester
          .getSemantics(find.byKey(const Key('sos-cancel')))
          .id;
      await capture(tester, 'countdown-ru');
      await activate(tester, find.byKey(const Key('sos-cancel')));
      expect(c.active, isTrue);
      expect(c.uiState.cancelConfirmationPending, isTrue);
      expect(find.text(S.get('sos_confirm_cancel_action')), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(const Key('sos-cancel'))).id,
        cancelId,
        reason: 'The action node must survive the confirmation state change.',
      );
      await capture(tester, 'confirmation-ru');
      await activate(tester, find.byKey(const Key('sos-cancel')));
      expect(c.active, isFalse);
      expect(c.uiState.phase, SosUiPhase.cancelled);
      expect(find.text(S.get('sos_fall_cancelled')), findsOneWidget);
      expect(backgroundTaps, 0);
      expect(sos.requests, 0);
      await capture(tester, 'cancelled-ru');
      semantics.dispose();
    },
  );

  testWidgets('expired confirmation is reflected in UI and needs a new pair', (
    tester,
  ) async {
    final sos = _FakeSos();
    final c = controller(sos)..initForTesting(secondsLeft: 11);
    await show(
      tester,
      state: () => c.uiState,
      listenable: c,
      onCancel: c.notifyTouch,
    );
    await tester.tap(find.byKey(const Key('sos-cancel')));
    await tester.pump();
    expect(c.uiState.cancelConfirmationPending, isTrue);
    await tester.pump(
      FallCountdownController.kCancelConfirmWindow +
          const Duration(milliseconds: 1),
    );
    expect(c.active, isTrue);
    expect(c.uiState.cancelConfirmationPending, isFalse);
    expect(find.text(S.get('sos_cancel_action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('sos-cancel')));
    await tester.pump();
    expect(c.active, isTrue);
    await tester.tap(find.byKey(const Key('sos-cancel')));
    await tester.pump();
    expect(c.uiState.phase, SosUiPhase.cancelled);
    expect(sos.requests, 0);
  });

  testWidgets(
    'expiry sends once; late ticks and touches cannot cancel sending',
    (tester) async {
      final sos = _FakeSos();
      final c = controller(sos)..initForTesting(secondsLeft: 1);
      c.processTickForTesting();
      expect(c.uiState.phase, SosUiPhase.sending);
      c.processTickForTesting();
      c.sendNow();
      c.notifyTouch();
      c.notifyTouch();
      c.dismissStatus();
      expect(c.uiState.phase, SosUiPhase.sending);
      expect(sos.requests, 1);
      sos.completer.complete(SosResult.composerOpened);
      await tester.pump();
      expect(c.uiState.messageKey, 'sos_composer_opened');
      c.dismissStatus();
      expect(c.uiState.phase, SosUiPhase.idle);
    },
  );

  for (final result in SosResult.values) {
    testWidgets(
      'fall result $result retains its delivery meaning and lockout',
      (tester) async {
        final sos = _FakeSos();
        var lockouts = 0;
        final c = FallCountdownController(
          tts: TtsService.forTesting(),
          sos: sos,
          voice: VoiceCommandService(),
          onSosSent: () => lockouts++,
        )..initForTesting(secondsLeft: 1);
        addTearDown(c.dispose);
        c.processTickForTesting();
        sos.completer.complete(result);
        await tester.pump();
        expect(c.uiState.result, result);
        final accepted = {
          SosResult.sent,
          SosResult.sentFallback,
          SosResult.sentWithoutLocation,
        };
        expect(lockouts, accepted.contains(result) ? 1 : 0);
        await show(tester, state: () => c.uiState);
        expect(find.text(S.get(c.uiState.messageKey)), findsOneWidget);
        if (!accepted.contains(result)) {
          expect(find.text(S.get('sos_sent')), findsNothing);
          expect(find.text(S.get('sos_fall_sent')), findsNothing);
        }
      },
    );
  }

  testWidgets('unexpected transport error becomes readable failure', (
    tester,
  ) async {
    final sos = _FakeSos();
    final c = controller(sos)..initForTesting(secondsLeft: 1);
    c.processTickForTesting();
    sos.completer.completeError(StateError('fake failure'));
    await tester.pump();
    expect(c.uiState.phase, SosUiPhase.result);
    expect(c.uiState.result, SosResult.error);
  });

  testWidgets('manual and fall requests share one in-flight attempt', (
    tester,
  ) async {
    final sos = _FakeSos();
    var lockouts = 0;
    final c = FallCountdownController(
      tts: TtsService.forTesting(),
      sos: sos,
      voice: VoiceCommandService(),
      onSosSent: () => lockouts++,
    );
    addTearDown(c.dispose);
    final first = c.sendManually();
    expect(c.uiState.phase, SosUiPhase.sending);
    expect(await c.sendManually(), isNull);
    c.start();
    c.processTickForTesting();
    expect(c.active, isFalse);
    expect(sos.requests, 1);
    sos.completer.complete(SosResult.sent);
    expect(await first, SosResult.sent);
    expect(c.uiState.afterFall, isFalse);
    expect(
      lockouts,
      0,
      reason: 'A standalone manual SOS must not start fall lockout.',
    );
  });

  testWidgets(
    'manual escalation sends once without a cancellation announcement',
    (tester) async {
      final sos = _FakeSos();
      var cancellations = 0;
      var lockouts = 0;
      final tts = TtsService.forTesting();
      final c = FallCountdownController(
        tts: tts,
        sos: sos,
        voice: VoiceCommandService(),
        onCancelled: () => cancellations++,
        onSosSent: () => lockouts++,
      )..initForTesting(secondsLeft: 11);
      addTearDown(c.dispose);
      c.notifyTouch();
      final attempt = c.sendManually();
      c.processTickForTesting();
      expect(sos.requests, 1);
      expect(cancellations, 0);
      expect(
        tts.queueSnapshot.any((j) => j.text == S.get('sos_fall_cancelled')),
        isFalse,
      );
      sos.completer.complete(SosResult.sent);
      await attempt;
      expect(lockouts, 1);
      expect(c.uiState.messageKey, 'sos_fall_sent');
    },
  );

  testWidgets(
    'voice SOS escalates countdown through the same request without cancelling it',
    (tester) async {
      final sos = _FakeSos();
      final c = controller(sos)..initForTesting(secondsLeft: 11);
      var requests = 0;
      final dispatcher = VoiceCommandDispatcher(
        vm: _UnusedCameraViewModel(),
        fallCountdown: c,
        onReadTextRequested: () {},
        onDescribeSceneRequested: ({filter = SceneFilter.all}) {},
        onSosRequested: () {
          requests++;
          unawaited(c.sendManually());
        },
      );
      dispatcher.handleCommand(VoiceCommand.sos);
      expect(requests, 1);
      expect(sos.requests, 1);
      expect(c.uiState.phase, SosUiPhase.sending);
      expect(
        c.tts.queueSnapshot.any((j) => j.text == S.get('sos_fall_cancelled')),
        isFalse,
      );
      sos.completer.complete(SosResult.composerOpened);
      await tester.pump();
      expect(c.uiState.messageKey, 'sos_composer_opened');
    },
  );

  testWidgets(
    'manual SOS requires explicit confirmation and never fires background action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var sends = 0;
      var backgroundTaps = 0;
      await show(
        tester,
        state: () => const SosUiState.idle(),
        onSend: () => sends++,
        backgroundTap: () => backgroundTaps++,
      );
      await activate(tester, find.byKey(const Key('sos-open')));
      await tester.pumpAndSettle();
      expect(sends, 0);
      await capture(tester, 'manual-confirmation-ru');
      await activate(
        tester,
        find.widgetWithText(TextButton, S.get('sos_keep_using')),
      );
      await tester.pumpAndSettle();
      expect(sends, 0);
      await activate(tester, find.byKey(const Key('sos-open')));
      await tester.pumpAndSettle();
      await activate(
        tester,
        find.widgetWithText(FilledButton, S.get('sos_send_action')),
      );
      await tester.pumpAndSettle();
      expect(sends, 1);
      expect(backgroundTaps, 0);
      semantics.dispose();
    },
  );

  for (final waitForDialog in [false, true]) {
    testWidgets(
      'fall countdown preempts manual confirmation, built=$waitForDialog',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final sos = _FakeSos();
        final c = controller(sos);
        await show(
          tester,
          state: () => c.uiState,
          listenable: c,
          onSend: c.sendManually,
          onCancel: c.notifyTouch,
        );
        final open = tester.getSemantics(find.byKey(const Key('sos-open')));
        open.owner!.performAction(open.id, ui.SemanticsAction.tap);
        if (waitForDialog) await tester.pumpAndSettle();
        c.initForTesting(secondsLeft: 11);
        c.processTickForTesting();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.byKey(const Key('sos-cancel')).hitTestable(),
          findsOneWidget,
        );
        expect(sos.requests, 0);
        await activate(tester, find.byKey(const Key('sos-cancel')));
        await activate(tester, find.byKey(const Key('sos-cancel')));
        expect(c.uiState.phase, SosUiPhase.cancelled);
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'sending exposes no send/cancel/dismiss action or live countdown',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await show(tester, state: () => const SosUiState.sending());
      expect(find.text(S.get('sos_sending')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      final node = tester.getSemantics(find.text(S.get('sos_sending')));
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isFalse);
      await capture(tester, 'sending-ru');
      semantics.dispose();
    },
  );

  testWidgets('curtain retains SOS semantic action and touch position', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var sends = 0;
    await show(
      tester,
      state: () => const SosUiState.idle(),
      onSend: () => sends++,
    );
    final normalRect = tester.getRect(find.byKey(const Key('sos-open')));
    await show(
      tester,
      state: () => const SosUiState.idle(),
      screenCurtain: true,
      onSend: () => sends++,
    );
    expect(tester.getRect(find.byKey(const Key('sos-open'))), normalRect);
    expect(normalRect.height, greaterThanOrEqualTo(48));
    await activate(tester, find.byKey(const Key('sos-open')));
    await tester.pumpAndSettle();
    expect(find.text(S.get('sos_manual_title')), findsOneWidget);
    expect(sends, 0);
    semantics.dispose();
  });

  testWidgets(
    'rapid semantic activations open one dialog and request one SOS',
    (tester) async {
      final semantics = tester.ensureSemantics();
      var sends = 0;
      await show(
        tester,
        state: () => const SosUiState.idle(),
        onSend: () => sends++,
      );
      final open = tester.getSemantics(find.byKey(const Key('sos-open')));
      open.owner!.performAction(open.id, ui.SemanticsAction.tap);
      open.owner!.performAction(open.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirm = tester.getSemantics(
        find.widgetWithText(FilledButton, S.get('sos_send_action')),
      );
      confirm.owner!.performAction(confirm.id, ui.SemanticsAction.tap);
      confirm.owner!.performAction(confirm.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(sends, 1);
      expect(find.byType(SosSurface), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      semantics.dispose();
    },
  );

  testWidgets(
    'late delivery after disposal does not publish state or lockout',
    (tester) async {
      final sos = _FakeSos();
      var lockouts = 0;
      final c = FallCountdownController(
        tts: TtsService.forTesting(),
        sos: sos,
        voice: VoiceCommandService(),
        onSosSent: () => lockouts++,
      )..initForTesting(secondsLeft: 1);
      c.processTickForTesting();
      c.dispose();
      sos.completer.complete(SosResult.sent);
      await tester.pump();
      expect(lockouts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'emergency surface hides background semantics without auto-announcing every tick',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final sos = _FakeSos();
      final c = controller(sos)..initForTesting(secondsLeft: 11);
      await show(
        tester,
        state: () => c.uiState,
        listenable: c,
        onCancel: c.notifyTouch,
      );
      expect(find.bySemanticsLabel('Background camera controls'), findsNothing);
      final node = tester.getSemantics(find.byKey(const Key('sos-cancel')));
      c.processTickForTesting();
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(const Key('sos-cancel'))).id,
        node.id,
      );
      final message = find.text(
        '${S.get('sos_fall_countdown')} 10 ${S.get('sos_fall_seconds')}',
      );
      expect(
        tester
            .getSemantics(message)
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isFalse,
      );
      semantics.dispose();
    },
  );

  for (final language in AppLanguage.values) {
    testWidgets(
      'SOS controls and dialog carry ${language.name} semantics locale',
      (tester) async {
        final semantics = tester.ensureSemantics();
        AppStrings.setLanguage(language);
        await show(
          tester,
          state: () =>
              const SosUiState.countdown(10, cancelConfirmationPending: false),
        );
        expect(
          tester
              .getSemantics(find.byKey(const Key('sos-cancel')))
              .getSemanticsData()
              .locale
              ?.languageCode,
          language.name,
        );
        await show(tester, state: () => const SosUiState.idle());
        await activate(tester, find.byKey(const Key('sos-open')));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(
          FilledButton,
          S.get('sos_send_action'),
        );
        expect(
          tester.getSemantics(confirm).getSemanticsData().locale?.languageCode,
          language.name,
        );
        semantics.dispose();
      },
    );
    for (final theme in [BagdarThemeName.dark, BagdarThemeName.light]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets('SOS large text ${language.name} ${theme.name} $size', (
          tester,
        ) async {
          AppStrings.setLanguage(language);
          var current = const SosUiState.countdown(
            10,
            cancelConfirmationPending: true,
          );
          await show(
            tester,
            state: () => current,
            size: size,
            scale: 2,
            theme: theme,
          );
          await tester.ensureVisible(find.byKey(const Key('sos-cancel')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('sos-cancel')).hitTestable(),
            findsOneWidget,
          );
          expect(
            tester.getSize(find.byKey(const Key('sos-cancel'))).height,
            greaterThanOrEqualTo(48),
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            'confirmation-${language.name}-${theme.name}-${size.width.toInt()}-200',
          );
          current = const SosUiState.result(SosResult.composerOpened);
          await show(
            tester,
            state: () => current,
            size: size,
            scale: 2,
            theme: theme,
          );
          await tester.ensureVisible(find.byKey(const Key('sos-dismiss')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(S.get('sos_composer_opened')), findsOneWidget);
          expect(find.text(S.get('sos_sent')), findsNothing);
          current = const SosUiState.idle();
          await show(
            tester,
            state: () => current,
            size: size,
            scale: 2,
            theme: theme,
          );
          await tester.tap(find.byKey(const Key('sos-open')));
          await tester.pumpAndSettle();
          final confirm = find.widgetWithText(
            FilledButton,
            S.get('sos_send_action'),
          );
          await tester.ensureVisible(confirm);
          await tester.pumpAndSettle();
          expect(confirm.hitTestable(), findsOneWidget);
          expect(tester.getSize(confirm).height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}

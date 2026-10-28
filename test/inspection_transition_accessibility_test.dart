import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/main.dart' show BagdarApp;
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/models/language_pack.dart';
import 'package:bagdar/screens/language_packs_screen.dart';
import 'package:bagdar/screens/settings_qr_export_screen.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/language_pack_manager.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:bagdar/widgets/inspection_utility_routes.dart';
import 'package:bagdar/widgets/sos_contact_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecordingTts extends TtsService {
  RecordingTts() : super.forTesting();
  final utterances = <String>[];
  @override
  void say(
    String text,
    SpeechPriority priority, {
    double pan = 0,
    int? trackId,
    String? actionId,
    String? hazardId,
    DateTime? expiresAt,
    bool barge = false,
    bool skipHaptic = false,
  }) => utterances.add(text);
}

void main() {
  final captureDirectory =
      Platform.environment['BAGDAR_TRANSITION_CAPTURE_DIR'];
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
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
  });
  setUp(() => AppStrings.setLanguage(AppLanguage.ru));

  Future<BuildContext> host(
    WidgetTester tester, {
    Widget? body,
    Size size = const Size(390, 844),
    double scale = 1,
    BagdarThemeName theme = BagdarThemeName.dark,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late BuildContext origin;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BagdarTheme.buildMaterialTheme(theme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: BagdarTheme(
            name: theme,
            colors: BagdarColors.of(theme),
            child: RepaintBoundary(
              key: const Key('transition-capture'),
              child: child!,
            ),
          ),
        ),
        home: Builder(
          builder: (context) {
            origin = context;
            return Scaffold(body: body ?? const Text('Inspection origin'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return origin;
  }

  Widget page(Widget child) => Scaffold(body: Center(child: child));

  Future<void> activate(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(finder);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
  }

  testWidgets(
    'sheet can replace itself with a contact dialog in one callback',
    (tester) async {
      final context = await host(tester);
      final owner = InspectionUtilityRoutes(canOpen: () => true);
      Future<InspectionUtilityResult<bool>>? replacement;
      final sheet = owner.open(
        context,
        bottomSheet: true,
        builder: (sheetContext) => TextButton(
          onPressed: () {
            Navigator.pop(sheetContext);
            replacement = owner.openDialog<bool>(
              context,
              builder: (_) =>
                  const AlertDialog(title: Text('Replacement contact')),
            );
          },
          child: const Text('Contact'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contact'));
      await tester.pumpAndSettle();
      await sheet;
      expect(find.text('Replacement contact'), findsOneWidget);
      final duplicate = await owner.openPage<void>(
        context,
        builder: (_) => page(const Text('Duplicate')),
      );
      expect(duplicate.opened, isFalse);
      owner.close();
      await tester.pumpAndSettle();
      expect((await replacement!).interrupted, isTrue);
      expect(find.text('Inspection origin'), findsOneWidget);
      owner.dispose();
    },
  );

  for (final built in [false, true]) {
    testWidgets('SOS removes owned parent and child; child built=$built', (
      tester,
    ) async {
      var allowed = true;
      final owner = InspectionUtilityRoutes(canOpen: () => allowed);
      final context = await host(tester);
      late BuildContext parent;
      final parentResult = owner.openPage<bool>(
        context,
        builder: (context) {
          parent = context;
          return page(const Text('Language packs parent'));
        },
      );
      await tester.pumpAndSettle();
      final childResult = owner.openChildDialog<bool>(
        parent,
        builder: (_) => const AlertDialog(title: Text('Delete pack child')),
      );
      if (built) await tester.pumpAndSettle();
      allowed = false;
      owner.close();
      owner.close();
      allowed = true; // A short emergency still revokes both route generations.
      final duringClose = await owner.openPage<void>(
        context,
        builder: (_) => page(const Text('Late page')),
      );
      expect(duringClose.opened, isFalse);
      await tester.pumpAndSettle();
      for (final result in [await parentResult, await childResult]) {
        expect(result.opened, isTrue);
        expect(result.interrupted, isTrue);
        expect(result.value, isNull);
      }
      expect(find.text('Delete pack child'), findsNothing);
      expect(find.text('Language packs parent'), findsNothing);
      final reopened = owner.openDialog<bool>(
        context,
        builder: (context) => AlertDialog(
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect((await reopened).value, isTrue);
      owner.dispose();
    });
  }

  testWidgets(
    'only a current owned route can open a child; typed normal back result',
    (tester) async {
      final owner = InspectionUtilityRoutes(canOpen: () => true);
      final context = await host(tester);
      expect(
        (await owner.openChildDialog<bool>(
          context,
          builder: (_) => const Text('Denied'),
        )).opened,
        isFalse,
      );
      late BuildContext parent;
      final result = owner.openPage<int>(
        context,
        builder: (context) {
          parent = context;
          return page(const Text('Owned page'));
        },
      );
      await tester.pumpAndSettle();
      late BuildContext child;
      final nested = owner.openChildDialog<bool>(
        parent,
        builder: (context) {
          child = context;
          return const AlertDialog(title: Text('Owned child'));
        },
      );
      await tester.pumpAndSettle();
      expect(
        (await owner.openChildDialog<bool>(
          parent,
          builder: (_) => const Text('Duplicate'),
        )).opened,
        isFalse,
      );
      expect(
        (await owner.openPage<void>(
          context,
          builder: (_) => page(const Text('Duplicate root')),
        )).opened,
        isFalse,
      );
      Navigator.pop(child, false);
      await tester.pumpAndSettle();
      expect((await nested).interrupted, isFalse);
      Navigator.pop(parent, 7);
      await tester.pumpAndSettle();
      final returned = await result;
      expect(returned.opened, isTrue);
      expect(returned.interrupted, isFalse);
      expect(returned.value, 7);
      owner.dispose();
    },
  );

  testWidgets('exact route removal preserves an unrelated external route', (
    tester,
  ) async {
    final context = await host(tester);
    final owner = InspectionUtilityRoutes(canOpen: () => true);
    final owned = owner.openPage<void>(
      context,
      builder: (_) => page(const Text('Owned')),
    );
    await tester.pumpAndSettle();
    final external = Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => page(const Text('External'))),
    );
    await tester.pumpAndSettle();
    owner.close();
    await tester.pumpAndSettle();
    expect((await owned).interrupted, isTrue);
    expect(find.text('External'), findsOneWidget);
    Navigator.pop(context);
    await tester.pumpAndSettle();
    await external;
    expect(find.text('Inspection origin'), findsOneWidget);
    owner.dispose();
  });

  for (final cause in ['SOS', 'dispose', 'unmount']) {
    testWidgets(
      'camera preparation is single flight and cannot push after $cause',
      (tester) async {
        final context = await host(tester);
        var allowed = true;
        var releases = 0;
        var builds = 0;
        final release = Completer<void>();
        final owner = InspectionUtilityRoutes(canOpen: () => allowed);
        Future<InspectionUtilityResult<bool>> open() => owner.openPage<bool>(
          context,
          beforeOpen: () {
            releases++;
            return release.future;
          },
          builder: (_) {
            builds++;
            return page(const Text('Scanner'));
          },
        );
        final pending = open();
        expect((await open()).opened, isFalse);
        expect(releases, 1);
        if (cause == 'SOS') {
          allowed = false;
          owner.close();
          allowed = true;
        } else if (cause == 'dispose') {
          owner.dispose();
        } else {
          await tester.pumpWidget(const SizedBox());
        }
        release.complete();
        final result = await pending;
        await tester.pumpAndSettle();
        expect(result.opened, isFalse);
        expect(result.interrupted, isTrue);
        expect(builds, 0);
        owner.dispose();
      },
    );
  }

  testWidgets(
    'denied open does not release camera; failed preparation releases reservation',
    (tester) async {
      final context = await host(tester);
      var allowed = false;
      var releases = 0;
      final owner = InspectionUtilityRoutes(canOpen: () => allowed);
      final denied = await owner.openPage<void>(
        context,
        beforeOpen: () async {
          releases++;
        },
        builder: (_) => page(const Text('Denied')),
      );
      expect(denied.opened, isFalse);
      expect(releases, 0);
      allowed = true;
      await expectLater(
        owner.openPage<void>(
          context,
          beforeOpen: () async => throw StateError('release failed'),
          builder: (_) => page(const Text('Failed')),
        ),
        throwsStateError,
      );
      final retried = owner.openPage<void>(
        context,
        builder: (_) => page(const Text('Retry')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      owner.dispose();
      await tester.pumpAndSettle();
      expect((await retried).interrupted, isTrue);
    },
  );

  for (final operation in ['picker', 'save']) {
    testWidgets(
      'late contact $operation completion cannot dismiss the SOS successor',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final context = await host(tester);
        var allowed = true;
        final owner = InspectionUtilityRoutes(canOpen: () => allowed);
        final picker = Completer<String?>();
        final save = Completer<bool>();
        var saves = 0;
        final result = owner.openDialog<bool>(
          context,
          builder: (_) => SosContactDialog(
            initialNumber: '+77771234567',
            canInteract: () => allowed,
            pickNumber: () => picker.future,
            saveNumber: (_) {
              saves++;
              return save.future;
            },
          ),
        );
        await tester.pumpAndSettle();
        await activate(
          tester,
          find.text(
            AppStrings.get(operation == 'picker' ? 'sos_contact_pick' : 'save'),
          ),
        );
        allowed = false;
        owner.close();
        // Complete before the removal frame, while the old dialog remains mounted.
        if (operation == 'picker') {
          picker.complete('+77770000000');
        } else {
          save.complete(true);
        }
        await tester.pumpAndSettle();
        expect((await result).interrupted, isTrue);
        expect(find.byType(SosContactDialog), findsNothing);
        expect(find.text('Inspection origin'), findsOneWidget);
        expect(saves, operation == 'picker' ? 0 : 1);
        expect(tester.takeException(), isNull);
        owner.dispose();
        semantics.dispose();
      },
    );
  }

  testWidgets(
    'QR export intro is suppressed when its host revokes the route before first frame',
    (tester) async {
      final tts = RecordingTts();
      await host(
        tester,
        body: SettingsQrExportScreen(tts: tts, canInteract: () => false),
      );
      expect(tts.utterances, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'production app theme reaches pages and dialogs and updates live',
    (tester) async {
      final previous = bagdarThemeNotifier.value;
      bagdarThemeNotifier.value = BagdarThemeName.light;
      late BuildContext origin;
      await tester.pumpWidget(
        BagdarApp(
          home: Builder(
            builder: (context) {
              origin = context;
              return const Scaffold(body: Text('Origin'));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner = InspectionUtilityRoutes(canOpen: () => true);
      late BuildContext parent;
      final opened = owner.openPage<void>(
        origin,
        builder: (context) {
          parent = context;
          return page(Text('page ${BagdarTheme.of(context).name.name}'));
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('page light'), findsOneWidget);
      final child = owner.openChildDialog<void>(
        parent,
        builder: (context) => AlertDialog(
          title: Text('dialog ${BagdarTheme.of(context).name.name}'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('dialog light'), findsOneWidget);
      bagdarThemeNotifier.value = BagdarThemeName.dark;
      await tester.pumpAndSettle();
      expect(find.text('dialog dark'), findsOneWidget);
      owner.close();
      await tester.pumpAndSettle();
      await child;
      await opened;
      owner.dispose();
      await tester.pumpWidget(const SizedBox());
      bagdarThemeNotifier.value = previous;
    },
  );

  testWidgets('page and child return restore keyboard focus at both levels', (
    tester,
  ) async {
    final originFocus = FocusNode();
    final pageFocus = FocusNode();
    final childFocus = FocusNode();
    final context = await host(
      tester,
      body: TextButton(
        focusNode: originFocus,
        onPressed: () {},
        child: const Text('Origin command'),
      ),
    );
    originFocus.requestFocus();
    await tester.pumpAndSettle();
    final owner = InspectionUtilityRoutes(canOpen: () => true);
    late BuildContext parent;
    final opened = owner.openPage<void>(
      context,
      builder: (context) {
        parent = context;
        return page(
          TextButton(
            focusNode: pageFocus,
            autofocus: true,
            onPressed: () {},
            child: const Text('Page command'),
          ),
        );
      },
    );
    await tester.pumpAndSettle();
    expect(pageFocus.hasFocus, isTrue);
    final child = owner.openChildDialog<void>(
      parent,
      builder: (context) => AlertDialog(
        actions: [
          TextButton(
            focusNode: childFocus,
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Return to page'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(childFocus.hasFocus, isTrue);
    await tester.tap(find.text('Return to page'));
    await tester.pumpAndSettle();
    await child;
    expect(pageFocus.hasFocus, isTrue);
    Navigator.pop(parent);
    await tester.pumpAndSettle();
    await opened;
    expect(originFocus.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    originFocus.dispose();
    pageFocus.dispose();
    childFocus.dispose();
  });

  testWidgets(
    'production language pack delete confirmation belongs to the utility stack',
    (tester) async {
      const pack = LanguagePack(
        packId: 'test-pack',
        name: 'Test voice',
        installed: true,
      );
      final manager = LanguagePackManager.instance;
      manager.debugReset(installed: [pack], available: [pack]);
      addTearDown(manager.debugReset);
      final context = await host(tester);
      var canInteract =
          false; // Suppress automatic network refresh in this UI fixture.
      final owner = InspectionUtilityRoutes(canOpen: () => true);
      final opened = owner.openPage<void>(
        context,
        builder: (_) => LanguagePacksScreen(
          tts: RecordingTts(),
          canInteract: () => canInteract,
          showDeleteConfirmation: (context, builder) async =>
              (await owner.openChildDialog<bool>(
                context,
                builder: builder,
              )).value,
        ),
      );
      await tester.pumpAndSettle();
      canInteract = true;
      await tester.tap(find.text(AppStrings.get('lang_packs_delete')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      canInteract = false;
      owner.close();
      await tester.pumpAndSettle();
      expect((await opened).interrupted, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(manager.getInstalled(pack.packId), isNotNull);
      owner.dispose();
    },
  );

  InspectionSurface surface({
    required VoidCallback? onRetry,
    bool curtain = false,
    SosUiState sos = const SosUiState.idle(),
  }) => InspectionSurface(
    background: const ColoredBox(color: Colors.black),
    recovery: InspectionCameraRecovery(onRetry: onRetry),
    screenCurtain: curtain,
    sosState: sos,
    status: InspectionSystemStatus.fromHealth(
      CoreHealthCoordinator().snapshot(DateTime(2026, 10, 12)),
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
  );

  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.light, BagdarThemeName.dark]) {
      for (final landscape in [false, true]) {
        testWidgets(
          'explicit camera recovery ${language.name} ${theme.name} landscape=$landscape at 200%',
          (tester) async {
            AppStrings.setLanguage(language);
            final semantics = tester.ensureSemantics();
            var retries = 0;
            await host(
              tester,
              body: surface(onRetry: () => retries++),
              theme: theme,
              scale: 2,
              size: landscape ? const Size(844, 390) : const Size(390, 844),
            );
            expect(retries, 0);
            final button = find.byKey(const Key('inspection-camera-retry'));
            await activate(tester, button);
            expect(retries, 1);
            final data = tester.getSemantics(button).getSemanticsData();
            expect(data.label, AppStrings.get('inspection_retry_camera'));
            expect(data.locale?.languageCode, language.name);
            expect(data.flagsCollection.isButton, isTrue);
            expect(
              tester.getSize(button).shortestSide,
              greaterThanOrEqualTo(48),
            );
            expect(tester.takeException(), isNull);
            if (captureDirectory != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('transition-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(captureDirectory).create(recursive: true);
                await File(
                  '$captureDirectory/recovery-${language.name}-${theme.name}-$landscape.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'retry disabled while pending, available with curtain, and hidden behind SOS semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final retry = find.byKey(const Key('inspection-camera-retry'));
      await host(tester, body: surface(onRetry: null));
      final data = tester.getSemantics(retry).getSemanticsData();
      expect(data.flagsCollection.isEnabled, ui.Tristate.isFalse);
      expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
      var calls = 0;
      await host(tester, body: surface(onRetry: () => calls++, curtain: true));
      await activate(tester, retry);
      expect(calls, 1);
      await host(
        tester,
        body: surface(
          onRetry: () => calls++,
          curtain: true,
          sos: const SosUiState.sending(),
        ),
      );
      expect(
        tester
            .binding
            .renderViews
            .single
            .owner!
            .semanticsOwner!
            .rootSemanticsNode!
            .toStringDeep(),
        isNot(contains(AppStrings.get('inspection_retry_camera'))),
      );
      expect(calls, 1);
      semantics.dispose();
    },
  );
}

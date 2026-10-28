import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_inspection_route.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_state.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:bagdar/widgets/inspection_utility_routes.dart';
import 'onboarding_v2_test.dart' show TestGateway, finishSetup;

void main() {
  final captureDirectory =
      Platform.environment['BAGDAR_INSPECTION_CAPTURE_DIR'];
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

  InspectionSystemStatus status({bool denied = false}) =>
      InspectionSystemStatus.fromHealth(
        CoreHealthCoordinator().snapshot(DateTime(2026, 10, 11)),
        cameraReady: false,
        permissionDenied: denied,
      );

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
    BagdarThemeName theme = BagdarThemeName.dark,
    bool curtain = false,
    bool denied = false,
    SosUiState Function()? sosState,
    Listenable? changes,
    VoidCallback? onStatus,
    VoidCallback? onSettings,
    VoidCallback? onHelp,
    VoidCallback? onFinish,
    VoidCallback? onSos,
    VoidCallback? onCancel,
    VoidCallback? onRetry,
    VoidCallback? onSystemSettings,
    VoidCallback? onBackgroundTap,
    VoidCallback? onBackgroundDoubleTap,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget surface() => InspectionSurface(
      background: GestureDetector(
        excludeFromSemantics: true,
        behavior: HitTestBehavior.opaque,
        onTap: onBackgroundTap,
        onDoubleTap: onBackgroundDoubleTap,
        child: const ColoredBox(color: Colors.black),
      ),
      recovery: denied
          ? InspectionPermissionRecovery(
              onRetry: onRetry ?? () {},
              onSystemSettings: onSystemSettings ?? () {},
            )
          : null,
      screenCurtain: curtain,
      sosState: sosState?.call() ?? const SosUiState.idle(),
      status: status(denied: denied),
      onStatus: onStatus ?? () {},
      onSettings: onSettings ?? () {},
      onHelp: onHelp ?? () {},
      onFinish: onFinish ?? () {},
      onSos: onSos ?? () {},
      onCancelSos: onCancel ?? () {},
      onDismissSos: () {},
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('inspection-capture'),
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
            child: Scaffold(
              body: changes == null
                  ? surface()
                  : ListenableBuilder(
                      listenable: changes,
                      builder: (_, __) => surface(),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> activate(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    final node = tester.getSemantics(finder);
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pump();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captureDirectory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('inspection-capture')),
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

  for (final curtain in [false, true]) {
    testWidgets(
      'each command has one action outside gesture region; curtain=$curtain',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final calls = <String>[];
        await show(
          tester,
          curtain: curtain,
          onStatus: () => calls.add('status'),
          onSettings: () => calls.add('settings'),
          onHelp: () => calls.add('help'),
          onFinish: () => calls.add('finish'),
          onSos: () => calls.add('sos'),
          onBackgroundTap: () => calls.add('tap'),
          onBackgroundDoubleTap: () => calls.add('double'),
        );
        for (final key in ['status', 'settings', 'help', 'finish']) {
          await activate(tester, 'inspection-$key');
          expect(calls, [
            for (final value in [
              'status',
              'settings',
              'help',
              'finish',
            ].take(calls.length))
              value,
          ]);
        }
        expect(calls, ['status', 'settings', 'help', 'finish']);
        // Physical button taps must also avoid the background tap/double tap.
        await tester.ensureVisible(
          find.byKey(const Key('inspection-settings')),
        );
        await tester.tap(find.byKey(const Key('inspection-settings')));
        await tester.pumpAndSettle();
        expect(calls, ['status', 'settings', 'help', 'finish', 'settings']);
        semantics.dispose();
      },
    );
  }

  testWidgets('curtain preserves command hit rectangles and semantic locale', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester);
    final normal = tester.getRect(find.byKey(const Key('inspection-settings')));
    await show(tester, curtain: true);
    expect(
      tester.getRect(find.byKey(const Key('inspection-settings'))),
      normal,
    );
    expect(
      tester
          .getSemantics(find.byKey(const Key('inspection-settings')))
          .getSemanticsData()
          .locale
          ?.languageCode,
      'ru',
    );
    await capture(tester, 'curtain-ru');
    semantics.dispose();
  });

  testWidgets(
    'permission failure retains commands and explicit recovery actions',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final calls = <String>[];
      await show(
        tester,
        denied: true,
        onRetry: () => calls.add('retry'),
        onSystemSettings: () => calls.add('system-settings'),
        onFinish: () => calls.add('finish'),
      );
      await activate(tester, 'inspection-permission-retry');
      await activate(tester, 'inspection-system-settings');
      await activate(tester, 'inspection-finish');
      expect(calls, ['retry', 'system-settings', 'finish']);
      expect(find.byKey(const Key('sos-open')), findsOneWidget);
      await capture(tester, 'permission-denied-ru');
      semantics.dispose();
    },
  );

  for (final phase in [
    const SosUiState.countdown(10, cancelConfirmationPending: false),
    const SosUiState.sending(),
    const SosUiState.cancelled(),
  ]) {
    testWidgets('SOS ${phase.phase.name} blocks ordinary controls', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await show(tester, sosState: () => phase, curtain: true);
      expect(find.bySemanticsLabel(S.get('settings')), findsNothing);
      expect(find.bySemanticsLabel(S.get('inspection_finish')), findsNothing);
      expect(find.bySemanticsLabel(S.get('inspection_help')), findsNothing);
      await capture(tester, 'sos-${phase.phase.name}-ru');
      semantics.dispose();
    });
  }

  for (final built in [false, true]) {
    for (final sheet in [false, true]) {
      testWidgets('utility preemption: built=$built sheet=$sheet', (
        tester,
      ) async {
        final changes = ValueNotifier(false);
        addTearDown(changes.dispose);
        final utilities = InspectionUtilityRoutes(
          canOpen: () => !changes.value,
        );
        BuildContext? origin;
        await show(
          tester,
          changes: changes,
          sosState: () => changes.value
              ? const SosUiState.sending()
              : const SosUiState.idle(),
          onSettings: () {
            utilities.open(
              origin!,
              bottomSheet: sheet,
              builder: (_) =>
                  const AlertDialog(title: Text('Utility under test')),
            );
          },
        );
        origin = tester.element(find.byType(InspectionControls));
        await tester.ensureVisible(
          find.byKey(const Key('inspection-settings')),
        );
        final node = tester.getSemantics(
          find.byKey(const Key('inspection-settings')),
        );
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        if (built) {
          await tester.pumpAndSettle();
          expect(find.text('Utility under test'), findsOneWidget);
        }
        changes.value = true;
        utilities.close();
        await tester.pumpAndSettle();
        expect(find.text('Utility under test'), findsNothing);
        expect(find.text(S.get('sos_sending')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('status dialog never speaks automatically; repeat is explicit', (
    tester,
  ) async {
    var repeats = 0;
    final utilities = InspectionUtilityRoutes(canOpen: () => true);
    BuildContext? origin;
    await show(
      tester,
      onStatus: () {
        utilities.open(
          origin!,
          builder: (_) => InspectionStatusDialog(
            status: status(),
            onRepeat: () => repeats++,
          ),
        );
      },
    );
    origin = tester.element(find.byType(InspectionControls));
    await activate(tester, 'inspection-status');
    await tester.pumpAndSettle();
    expect(repeats, 0);
    expect(find.text(S.get('inspection_status_limits')), findsOneWidget);
    await activate(tester, 'inspection-repeat-status');
    expect(repeats, 1);
    await capture(tester, 'status-ru');
  });

  testWidgets('native utility return preserves the invoking keyboard focus', (
    tester,
  ) async {
    final utilities = InspectionUtilityRoutes(canOpen: () => true);
    BuildContext? origin;
    await show(
      tester,
      onSettings: () {
        utilities.open(
          origin!,
          builder: (context) => AlertDialog(
            title: const Text('Settings test route'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return'),
              ),
            ],
          ),
        );
      },
    );
    origin = tester.element(find.byType(InspectionControls));
    final settingsText = find.descendant(
      of: find.byKey(const Key('inspection-settings')),
      matching: find.byType(Text),
    );
    final invokingFocus = Focus.of(tester.element(settingsText));
    invokingFocus.requestFocus();
    await tester.pumpAndSettle();
    await activate(tester, 'inspection-settings');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Return'));
    await tester.pumpAndSettle();
    expect(invokingFocus.hasFocus, isTrue);
  });

  testWidgets('production composition preempts the manual SOS dialog', (
    tester,
  ) async {
    final changes = ValueNotifier(false);
    addTearDown(changes.dispose);
    var sends = 0;
    await show(
      tester,
      changes: changes,
      sosState: () => changes.value
          ? const SosUiState.countdown(10, cancelConfirmationPending: false)
          : const SosUiState.idle(),
      onSos: () => sends++,
    );
    await activate(tester, 'sos-open');
    await tester.pumpAndSettle();
    expect(find.text(S.get('sos_manual_title')), findsOneWidget);
    changes.value = true;
    await tester.pumpAndSettle();
    expect(find.text(S.get('sos_manual_title')), findsNothing);
    expect(find.byKey(const Key('sos-cancel')).hitTestable(), findsOneWidget);
    expect(sends, 0);
  });

  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.dark, BagdarThemeName.light]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets(
          'commands, recovery and dialogs 200% ${language.name} ${theme.name} $size',
          (tester) async {
            AppStrings.setLanguage(language);
            final utilities = InspectionUtilityRoutes(canOpen: () => true);
            BuildContext? origin;
            await show(
              tester,
              size: size,
              scale: 2,
              theme: theme,
              denied: true,
              onHelp: () {
                utilities.open(
                  origin!,
                  builder: (_) => const InspectionHelpDialog(),
                );
              },
            );
            origin = tester.element(find.byType(InspectionControls));
            for (final key in [
              'inspection-status',
              'inspection-settings',
              'inspection-help',
              'inspection-finish',
              'inspection-permission-retry',
              'inspection-system-settings',
              'sos-open',
            ]) {
              final finder = find.byKey(Key(key));
              await tester.ensureVisible(finder);
              await tester.pumpAndSettle();
              expect(finder.hitTestable(), findsOneWidget, reason: key);
              expect(tester.getSize(finder).height, greaterThanOrEqualTo(48));
              expect(
                tester
                    .getSemantics(finder)
                    .getSemanticsData()
                    .locale
                    ?.languageCode,
                language.name,
              );
            }
            await tester.ensureVisible(
              find.byKey(const Key('inspection-finish')),
            );
            await tester.pumpAndSettle();
            await capture(
              tester,
              'commands-${language.name}-${theme.name}-${size.width.toInt()}-200',
            );
            await activate(tester, 'inspection-help');
            await tester.pumpAndSettle();
            expect(find.text(S.get('inspection_help_body')), findsOneWidget);
            final close = find.widgetWithText(
              TextButton,
              S.get('inspection_close'),
            );
            expect(close.hitTestable(), findsOneWidget);
            await capture(
              tester,
              'help-${language.name}-${theme.name}-${size.width.toInt()}-200',
            );
            await tester.tap(close);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final allowed in [false, true]) {
    testWidgets(
      'production inspection route respects admission and invalidates return; allowed=$allowed',
      (tester) async {
        var now = DateTime(2026, 10, 11);
        final c = OnboardingController(
          store: MemoryOnboardingStore(),
          gateway: TestGateway(() => now),
          now: () => now,
        );
        await c.initialize();
        if (allowed) await finishSetup(c);
        final savedProgress = c.progress.toJson();
        BuildContext? origin;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                origin = context;
                return const Scaffold(body: Text('Session checks'));
              },
            ),
          ),
        );
        final open = openOnboardingInspection(
          origin!,
          c,
          builder: (context) => Scaffold(
            body: InspectionSurface(
              background: const ColoredBox(color: Colors.black),
              screenCurtain: true,
              sosState: const SosUiState.idle(),
              status: status(),
              onStatus: () {},
              onSettings: () {},
              onHelp: () {},
              onFinish: () => Navigator.pop(context),
              onSos: () {},
              onCancelSos: () {},
              onDismissSos: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (allowed) {
          expect(c.admission, Admission.inspectionOnly);
          await activate(tester, 'inspection-finish');
          await tester.pumpAndSettle();
          await open;
          expect(c.admission, Admission.recheckRequired);
          expect(c.progress.toJson(), savedProgress);
          expect(c.gate.mayStartGenericAssistive, isFalse);
        } else {
          await open;
          expect(find.byType(InspectionSurface), findsNothing);
        }
        expect(find.text('Session checks'), findsOneWidget);
        if (allowed) {
          await openOnboardingInspection(
            origin!,
            c,
            builder: (_) => const Scaffold(body: Text('Unexpected reentry')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Unexpected reentry'), findsNothing);
        }
        now = now.add(const Duration(minutes: 3));
        c.dispose();
      },
    );
  }

  test(
    'health formatter cannot turn missing data or camera loss into readiness',
    () {
      final coordinator = CoreHealthCoordinator();
      final now = DateTime(2026, 10, 11);
      final unknown = InspectionSystemStatus.fromHealth(
        coordinator.snapshot(now),
        cameraReady: true,
        permissionDenied: false,
      );
      expect(
        unknown.details.join(' '),
        contains(S.get('inspection_state_unchecked')),
      );
      for (final component in CoreComponent.values) {
        coordinator.note(
          component: component,
          state: ComponentState.available,
          reasonCode: 'test-available',
          now: now,
          announce: false,
        );
      }
      expect(coordinator.snapshot(now).runState, CoreRunState.operational);
      final lost = InspectionSystemStatus.fromHealth(
        coordinator.snapshot(now),
        cameraReady: false,
        permissionDenied: false,
      );
      expect(lost.summary, S.get('inspection_run_camera_unavailable'));
      final denied = InspectionSystemStatus.fromHealth(
        coordinator.snapshot(now),
        cameraReady: true,
        permissionDenied: true,
      );
      expect(
        denied.details.first,
        contains(S.get('inspection_permission_denied')),
      );
    },
  );

  for (final state in ComponentState.values) {
    test(
      'health formatter preserves ${state.name} without raw reason codes',
      () {
        final coordinator = CoreHealthCoordinator();
        final now = DateTime(2026, 10, 11);
        coordinator.note(
          component: CoreComponent.genericGeometry,
          state: state,
          reasonCode: 'technical-private-reason',
          now: now,
          announce: false,
        );
        final value = InspectionSystemStatus.fromHealth(
          coordinator.snapshot(now),
          cameraReady: true,
          permissionDenied: false,
        );
        expect(
          value.details[2],
          contains(S.get('inspection_state_${state.name}')),
        );
        expect(value.spokenText, isNot(contains('technical-private-reason')));
      },
    );
  }
}

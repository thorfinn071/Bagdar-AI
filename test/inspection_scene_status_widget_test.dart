import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/safety/runtime/confidence_authority_spatial_runtime.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'inspection_scene_status_test.dart'
    show
        inspectionStamp,
        inspectionHeader,
        inspectionDetection,
        admitInspection,
        readInspection;

void main() {
  final captures = Platform.environment['BAGDAR_INSPECTION_SCENE_CAPTURE_DIR'];
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
  tearDown(() => AppStrings.setLanguage(AppLanguage.ru));

  InspectionSystemStatus status({bool stale = false}) {
    final runtime =
        ConfidenceAuthoritySpatialRuntime(
          healthCoordinator: CoreHealthCoordinator(),
        )..beginSession(
          1,
          now: inspectionStamp.subtract(const Duration(milliseconds: 1)),
        );
    final header = inspectionHeader(),
        detection = inspectionDetection(possible: true);
    admitInspection(runtime, header, detection);
    return InspectionSystemStatus.fromHealth(
      runtime.healthCoordinator.snapshot(inspectionStamp),
      cameraReady: true,
      permissionDenied: false,
      scene: readInspection(
        runtime,
        header,
        detection,
        now: stale ? inspectionStamp.add(const Duration(seconds: 2)) : null,
      ),
    );
  }

  Future<void> show(
    WidgetTester tester,
    ValueNotifier<InspectionSystemStatus> changes, {
    required BagdarThemeName theme,
    required bool landscape,
    bool curtain = false,
    required List<String> spoken,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = landscape
        ? const Size(812, 375)
        : const Size(375, 812);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('scene-status-capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: BagdarTheme.buildMaterialTheme(theme),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: BagdarTheme(
            name: theme,
            colors: BagdarColors.of(theme),
            child: Builder(
              builder: (context) => Scaffold(
                body: ValueListenableBuilder<InspectionSystemStatus>(
                  valueListenable: changes,
                  builder: (_, value, __) => InspectionSurface(
                    background: const ColoredBox(color: Colors.black),
                    screenCurtain: curtain,
                    sosState: const SosUiState.idle(),
                    status: value,
                    onStatus: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          ValueListenableBuilder<InspectionSystemStatus>(
                            valueListenable: changes,
                            builder: (_, current, __) => InspectionStatusDialog(
                              status: current,
                              onRepeat: () =>
                                  spoken.add(changes.value.spokenText),
                            ),
                          ),
                    ),
                    onSettings: () {},
                    onHelp: () {},
                    onFinish: () {},
                    onSos: () {},
                    onCancelSos: () {},
                    onDismissSos: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captures == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('scene-status-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(captures)..createSync(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final language in AppLanguage.values) {
    for (final theme in BagdarThemeName.values) {
      for (final landscape in [false, true]) {
        testWidgets(
          '${language.name}/${theme.name}/landscape=$landscape at 200% text',
          (tester) async {
            AppStrings.setLanguage(language);
            final semantics = tester.ensureSemantics();
            final changes = ValueNotifier(status());
            final spoken = <String>[];
            await show(
              tester,
              changes,
              theme: theme,
              landscape: landscape,
              spoken: spoken,
            );
            final button = find.byKey(const Key('inspection-status'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(
              tester.getSemantics(button).label,
              contains(changes.value.observationText),
            );
            expect(
              tester.getSemantics(button).label,
              contains(changes.value.movementText),
            );
            expect(tester.takeException(), isNull);
            final prefix =
                '${language.name}-${theme.name}-${landscape ? 'landscape' : 'portrait'}';
            if (theme == BagdarThemeName.dark ||
                theme == BagdarThemeName.light) {
              await capture(tester, '$prefix-controls');
            }
            await tester.tap(button);
            await tester.pumpAndSettle();
            final dialog = find.byType(InspectionStatusDialog);
            expect(
              find.descendant(
                of: dialog,
                matching: find.text(changes.value.observationText),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: dialog,
                matching: find.text(changes.value.clearanceText),
              ),
              findsOneWidget,
            );
            expect(
              find.descendant(
                of: dialog,
                matching: find.text(changes.value.movementText),
              ),
              findsOneWidget,
            );
            await tester.tap(find.byKey(const Key('inspection-repeat-status')));
            expect(spoken.single, changes.value.spokenText);
            expect(tester.takeException(), isNull);
            if (theme == BagdarThemeName.dark ||
                theme == BagdarThemeName.light) {
              await capture(tester, '$prefix-dialog');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            changes.dispose();
            semantics.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'an open dialog and curtain semantics update when observations expire',
    (tester) async {
      AppStrings.setLanguage(AppLanguage.en);
      final semantics = tester.ensureSemantics();
      final changes = ValueNotifier(status());
      final spoken = <String>[];
      await show(
        tester,
        changes,
        theme: BagdarThemeName.dark,
        landscape: false,
        curtain: true,
        spoken: spoken,
      );
      final button = find.byKey(const Key('inspection-status'));
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(button);
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), true);
      node.owner!.performAction(node.id, ui.SemanticsAction.tap);
      await tester.pumpAndSettle();
      changes.value = status(stale: true);
      await tester.pumpAndSettle();
      final dialog = find.byType(InspectionStatusDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(changes.value.observationText),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('inspection-repeat-status')));
      expect(spoken.single, contains(S.get('inspection_observation_stale')));
      expect(
        spoken.single,
        contains(S.get('inspection_movement_stationary_only')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      changes.dispose();
      semantics.dispose();
    },
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/inspection_voice_commands.dart';
import 'package:bagdar/services/voice/inspection_voice_coordinator.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:bagdar/widgets/inspection_utility_routes.dart';
import 'package:bagdar/widgets/inspection_voice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.light, BagdarThemeName.dark]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets('voice controls: $language $theme $size, text 200%', (
          tester,
        ) async {
          AppStrings.setLanguage(language);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          var starts = 0;
          var stops = 0;
          for (final phase in [
            InspectionVoicePhase.off,
            InspectionVoicePhase.listening,
            InspectionVoicePhase.suspended,
            InspectionVoicePhase.unavailable,
          ]) {
            final active = phase == InspectionVoicePhase.listening;
            final message = inspectionVoiceText(switch (phase) {
              InspectionVoicePhase.listening => InspectionVoiceCopy.listening,
              InspectionVoicePhase.suspended => InspectionVoiceCopy.interrupted,
              InspectionVoicePhase.unavailable =>
                InspectionVoiceCopy.shutdownFailed,
              _ => InspectionVoiceCopy.privacy,
            }, language);
            await tester.pumpWidget(
              MaterialApp(
                theme: BagdarTheme.buildMaterialTheme(theme),
                builder: (_, child) => MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const Key('capture'),
                  child: Scaffold(
                    body: InspectionSurface(
                      background: const ColoredBox(color: Colors.black),
                      screenCurtain: false,
                      sosState: const SosUiState.idle(),
                      status: InspectionSystemStatus.fromHealth(
                        CoreHealthCoordinator().snapshot(
                          DateTime(2026, 10, 13),
                        ),
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
                        phase: phase,
                        active: active,
                        canStart: phase != InspectionVoicePhase.unavailable,
                        message: message,
                        onStart: () => starts++,
                        onStop: () => stops++,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final button = find.byKey(const Key('inspection-voice'));
            await tester.ensureVisible(button);
            await tester.pumpAndSettle();
            expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
            expect(find.text(message), findsOneWidget);
            if (phase != InspectionVoicePhase.unavailable) {
              await tester.tap(button);
            } else {
              expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
            }
            await tester.pump();
            expect(tester.takeException(), isNull);
            final directory =
                Platform.environment['BAGDAR_RUNTIME_VOICE_CAPTURE_DIR'];
            if (directory != null) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage(pixelRatio: 1);
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File(
                  '$directory/${language.name}-${theme.name}-'
                  '${size.width.toInt()}x${size.height.toInt()}-${phase.name}.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(png!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
          semantics.dispose();
          expect(starts, 2);
          expect(stops, 1);
        });
      }
    }
  }
  testWidgets(
    'utility route waits for microphone release and refuses failed release',
    (tester) async {
      final closed = Completer<bool>();
      late BuildContext context;
      final routes = InspectionUtilityRoutes(
        canOpen: () => true,
        releaseVoiceInput: () => closed.future,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final opening = routes.open(
        context,
        builder: (_) => const Text('settings route'),
      );
      await tester.pump();
      expect(find.text('settings route'), findsNothing);
      closed.complete(false);
      await opening;
      await tester.pumpAndSettle();
      expect(find.text('settings route'), findsNothing);
      routes.dispose();
    },
  );
}

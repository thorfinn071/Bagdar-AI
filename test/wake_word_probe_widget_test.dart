import 'dart:io';
import 'dart:ui' as ui;
import 'package:bagdar/camera/inspection_system_status.dart';
import 'package:bagdar/camera/sos_ui_state.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/voice/wake_word_probe.dart';
import 'package:bagdar/services/voice/inspection_voice_coordinator.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/inspection_surface.dart';
import 'package:bagdar/widgets/inspection_voice_panel.dart';
import 'package:bagdar/widgets/wake_word_probe_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wake_word_probe_test.dart' show ProbeInput;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final fonts = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'Bold', 'ExtraBold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final language in AppLanguage.values) {
    for (final theme in [BagdarThemeName.dark, BagdarThemeName.light]) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets(
          'research probe ${language.name} ${theme.name} $size at 200%',
          (tester) async {
            AppStrings.setLanguage(language);
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final input = ProbeInput();
            final probe = WakeWordProbe(
              input: input,
              language: () => language,
              canInteract: () => true,
              releaseOtherInputs: () async => true,
              speak: (_) async => true,
            );
            final semantics = tester.ensureSemantics();
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('wake-capture'),
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
                      onFinish: null,
                      onSos: () {},
                      onCancelSos: () {},
                      onDismissSos: () {},
                      voiceControls: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InspectionVoicePanel(
                            phase: InspectionVoicePhase.off,
                            active: false,
                            message: '',
                            onStart: () {},
                            onStop: () {},
                            onVoiceSettings: () {},
                          ),
                          WakeWordProbePanel(probe: probe),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            final button = find.byKey(const Key('wake-probe-toggle'));
            Future<void> capture(String state) async {
              await tester.ensureVisible(button);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              expect(tester.getSize(button).height, greaterThanOrEqualTo(56));
              final output = Platform.environment['BAGDAR_WAKE_CAPTURE_DIR'];
              if (output != null) {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const Key('wake-capture')),
                );
                await tester.runAsync(() async {
                  final image = await boundary.toImage(pixelRatio: 1);
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final path = File(
                    '$output/${language.name}-${theme.name}-${size.width.toInt()}x${size.height.toInt()}-$state.png',
                  );
                  await path.parent.create(recursive: true);
                  await path.writeAsBytes(data!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }

            expect(input.listens, 0);
            expect(find.text(wakeProbeText('start', language)), findsOneWidget);
            await capture('off');
            final session = probe.start();
            await tester.pump();
            expect(probe.phase, WakeWordProbePhase.waiting);
            expect(find.text(wakeProbeText('stop', language)), findsOneWidget);
            expect(
              find.text(wakeProbeText('waiting', language)),
              findsOneWidget,
            );
            await capture('waiting');
            await tester.tap(button);
            await tester.pump();
            await session;
            expect(probe.phase, WakeWordProbePhase.off);
            expect(input.listens, 1);
            await tester.pumpWidget(const SizedBox.shrink());
            semantics.dispose();
            probe.dispose();
          },
        );
      }
    }
  }
}

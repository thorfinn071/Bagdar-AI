import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bagdar/features/onboarding_v2/onboarding_controller.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_gateway.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_screen.dart';
import 'package:bagdar/features/onboarding_v2/onboarding_store.dart';
import 'package:bagdar/main.dart';
import 'package:bagdar/models/a11y_prefs.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/screens/language_packs_screen.dart';
import 'package:bagdar/screens/settings_qr_export_screen.dart';
import 'package:bagdar/screens/settings_qr_import_screen.dart';
import 'package:bagdar/services/settings_codec.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';
import 'package:bagdar/widgets/camera_controls_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/mobile_scanner_view_attributes.dart';
import 'package:mobile_scanner/src/objects/start_options.dart';

/// Camera test double: layout/preview evidence, never hardware evidence.
class DesignScanner extends MobileScannerPlatform {
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async =>
      const MobileScannerViewAttributes(
        currentTorchMode: TorchState.off,
        size: Size(640, 480),
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {}
}

CameraSettingsSheet settingsSheet() => CameraSettingsSheet(
  currentLanguage: AppStrings.current,
  useGpu: false,
  useNativeDepthBridge: false,
  useHardwareDepthMode: false,
  numThreads: 2,
  showDebugHud: false,
  earconEnabled: true,
  pitchBlackUiEnabled: false,
  classicGestures: false,
  speechRate: 1,
  ttsVolume: 1,
  earconVolume: 0.85,
  verbosity: Verbosity.normal,
  alertFrequency: AlertFrequency.normal,
  hapticStrength: HapticStrength.normal,
  sosTrigger: SosTrigger.twoFingerHold,
  dominantHand: DominantHand.right,
  midasReady: false,
  sosContactNumber: null,
  onLanguageChanged: (_) {},
  onUseGpuChanged: (_) {},
  onNativeDepthBridgeChanged: (_) {},
  onHardwareDepthModeChanged: (_) {},
  onNumThreadsChanged: (_) {},
  onDebugHudChanged: (_) {},
  onEarconEnabledChanged: (_) {},
  onPitchBlackUiChanged: (_) {},
  onClassicGesturesChanged: (_) {},
  onSpeechRateChanged: (_) {},
  onTtsVolumeChanged: (_) {},
  onEarconVolumeChanged: (_) {},
  onVerbosityChanged: (_) {},
  onAlertFrequencyChanged: (_) {},
  onHapticStrengthChanged: (_) {},
  onSosTriggerChanged: (_) {},
  onDominantHandChanged: (_) {},
  onReplayTutorial: () {},
  onReadText: () {},
  onCalibrationTap: () {},
  onEditSosContact: () {},
  onScanLeft: () {},
  onScanCenter: () {},
  onScanRight: () {},
  onVoiceWarningTest: () {},
  onVoiceCriticalTest: () {},
  onPlayEarcon: (_) {},
  patternFn: (_, _) => [],
  intensFn: (_, _) => [],
  vibrateFn: (_, {intensities}) async {},
);

void main() {
  final captures = Platform.environment['BAGDAR_DESIGN_CAPTURE_DIR'];
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
  tearDown(() => bagdarThemeNotifier.value = BagdarThemeName.dark);

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    BagdarThemeName theme = BagdarThemeName.light,
    Size size = const Size(375, 812),
    double scale = 1,
    bool highContrast = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: BagdarTheme.buildMaterialTheme(theme),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
            highContrast: highContrast,
          ),
          child: BagdarThemeScope(
            name: theme,
            child: RepaintBoundary(
              key: const Key('design-capture'),
              child: child!,
            ),
          ),
        ),
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (captures == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('design-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(captures).create(recursive: true);
      await File(
        '$captures/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final theme in BagdarThemeName.values) {
    testWidgets('onboarding uses the app palette: ${theme.name}', (
      tester,
    ) async {
      final c = OnboardingController(
        store: MemoryOnboardingStore(),
        gateway: UnavailableOnboardingGateway(),
      );
      await show(tester, OnboardingV2Screen(controller: c), theme: theme);
      final context = tester.element(find.byType(Scaffold));
      expect(
        Theme.of(context).scaffoldBackgroundColor,
        BagdarColors.of(theme).surfaceBg,
      );
      expect(
        Theme.of(context).colorScheme.primary,
        BagdarColors.of(theme).accentPrimary,
      );
      expect(tester.takeException(), isNull);
      await capture(tester, '${theme.name}-onboarding');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final language in AppLanguage.values) {
    for (final theme in BagdarThemeName.values) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets(
          'settings and QR at 200%: ${language.name} ${theme.name} $size',
          (tester) async {
            AppStrings.setLanguage(language);
            final semantics = tester.ensureSemantics();
            await show(
              tester,
              Scaffold(body: SingleChildScrollView(child: settingsSheet())),
              theme: theme,
              size: size,
              scale: 2,
            );
            expect(find.text(S.get('appearance_title')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(
              find.text(S.get('settings_haptic_test')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              '${theme.name}-${language.name}-settings-large-${size.width.toInt()}',
            );
            await show(
              tester,
              SettingsQrExportScreen(
                tts: TtsService.forTesting(),
                canInteract: () => false,
              ),
              theme: theme,
              size: size,
              scale: 2,
            );
            final close = find.text(S.get('qr_dismiss'));
            await tester.ensureVisible(close);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              tester
                  .getSize(
                    find.ancestor(
                      of: close,
                      matching: find.byType(FilledButton),
                    ),
                  )
                  .height,
              greaterThanOrEqualTo(64),
            );
            await capture(
              tester,
              '${theme.name}-${language.name}-qr-large-${size.width.toInt()}',
            );
            await tester.pumpWidget(const SizedBox());
            semantics.dispose();
          },
        );
      }
    }
  }

  for (final theme in BagdarThemeName.values) {
    for (final size in [const Size(768, 1024), const Size(1024, 768)]) {
      testWidgets('expanded diagnostics on tablet: ${theme.name} $size', (
        tester,
      ) async {
        await show(
          tester,
          Scaffold(body: SingleChildScrollView(child: settingsSheet())),
          theme: theme,
          size: size,
          scale: 2,
        );
        final tile = find.byType(ExpansionTile);
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Debug HUD'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          '${theme.name}-diagnostics-${size.width.toInt()}',
        );
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final language in AppLanguage.values) {
    for (final theme in BagdarThemeName.values) {
      for (final size in [const Size(375, 812), const Size(812, 375)]) {
        testWidgets(
          'QR import preview is scrollable at 200%: ${language.name} ${theme.name} $size',
          (tester) async {
            AppStrings.setLanguage(language);
            final original = MobileScannerPlatform.instance;
            MobileScannerPlatform.instance = DesignScanner();
            addTearDown(() => MobileScannerPlatform.instance = original);
            final tts = TtsService.forTesting();
            await show(
              tester,
              SettingsQrImportScreen(tts: tts),
              theme: theme,
              size: size,
              scale: 2,
            );
            tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
              BarcodeCapture(
                barcodes: [
                  Barcode(rawValue: SettingsCodec.instance.exportToJson()),
                ],
              ),
            );
            await tester.pumpAndSettle();
            final retry = find.text(S.get('qr_import_retry'));
            await tester.ensureVisible(retry);
            await tester.pumpAndSettle();
            expect(find.text(S.get('qr_import_long_press')), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              '${theme.name}-${language.name}-qr-import-${size.width.toInt()}',
            );
            await tester.tap(retry);
            await tester.pumpAndSettle();
            expect(find.text(S.get('qr_import_long_press')), findsNothing);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            tts.dispose();
            await tester.pump(const Duration(seconds: 3));
          },
        );
      }
    }
  }

  testWidgets('settings persists a theme and updates the whole app in place', (
    tester,
  ) async {
    bagdarThemeNotifier.value = BagdarThemeName.dark;
    await tester.pumpWidget(
      BagdarApp(
        home: Scaffold(body: SingleChildScrollView(child: settingsSheet())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<BagdarThemeName>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.get('theme_light')).last);
    await tester.pumpAndSettle();
    expect(Settings.instance.themeMode, BagdarThemeName.light);
    expect(bagdarThemeNotifier.value, BagdarThemeName.light);
    expect(
      Theme.of(
        tester.element(find.byType(CameraSettingsSheet)),
      ).colorScheme.primary,
      BagdarColors.light.accentPrimary,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('system high contrast reaches onboarding and native controls', (
    tester,
  ) async {
    await show(
      tester,
      Scaffold(body: SingleChildScrollView(child: settingsSheet())),
      highContrast: true,
    );
    final context = tester.element(find.byType(CameraSettingsSheet));
    expect(BagdarTheme.of(context).name, BagdarThemeName.highContrast);
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('native screens for visual review', (tester) async {
    for (final theme in BagdarThemeName.values) {
      await show(
        tester,
        Scaffold(body: SingleChildScrollView(child: settingsSheet())),
        theme: theme,
      );
      await capture(tester, '${theme.name}-settings');
      await show(
        tester,
        SettingsQrExportScreen(
          tts: TtsService.forTesting(),
          canInteract: () => false,
        ),
        theme: theme,
      );
      await capture(tester, '${theme.name}-qr');
      await show(
        tester,
        LanguagePacksScreen(
          tts: TtsService.forTesting(),
          canInteract: () => false,
        ),
        theme: theme,
      );
      await capture(tester, '${theme.name}-language-packs');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}

import 'dart:async';

import 'package:flutter/material.dart';

import 'core/core_feature_policy.dart';
import 'onboarding_screen.dart';
import 'services/feature_usage_tracker.dart';
import 'services/field_logger.dart';
import 'services/language_pack_manager.dart';
import 'services/native_tts_bridge.dart';
import 'services/paddle_ocr_bridge.dart';
import 'services/settings_service.dart';
import 'theme/bagdar_theme.dart';
import 'theme/bagdar_tokens.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        FieldLogger.instance.logError(
          'flutter_error',
          details.exceptionAsString(),
        );
      };

      await Settings.instance.init();
      await FeatureUsageTracker.instance.init();

      await LanguagePackManager.instance.init();
      unawaited(LanguagePackManager.instance.fetchManifest());

      unawaited(NativeTtsBridge.instance.init());

      if (CoreFeaturePolicy.current.mayInitialize(CoreFeature.paddleOcr)) {
        unawaited(PaddleOcrBridge.instance.init());
      }

      bagdarThemeNotifier.value = Settings.instance.themeMode;

      final startScreen = await resolveStartScreen();
      runApp(BagdarApp(home: startScreen));
    },
    (error, stack) {
      FieldLogger.instance.logError('uncaught_zone', error.toString());
    },
  );
}

class BagdarApp extends StatelessWidget {
  final Widget home;
  const BagdarApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BagdarThemeName>(
      valueListenable: bagdarThemeNotifier,
      builder: (context, themeName, _) {
        final colors = BagdarColors.of(themeName);
        return MaterialApp(
          title: 'Bagdar AI',
          debugShowCheckedModeBanner: false,
          theme: BagdarTheme.buildMaterialTheme(themeName),
          home: BagdarTheme(name: themeName, colors: colors, child: home),
        );
      },
    );
  }
}

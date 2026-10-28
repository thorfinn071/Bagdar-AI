import 'dart:async';

import 'package:flutter/material.dart';

import 'features/onboarding_v2/onboarding_boot_screen.dart';
import 'services/field_logger.dart';
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

      // Every launch enters v2. Runtime services start only after admission.
      // Paint an accessible shell before awaiting preferences or device probes.
      runApp(const BagdarApp(home: OnboardingBootScreen()));
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
        return MaterialApp(
          title: 'Bagdar AI',
          debugShowCheckedModeBanner: false,
          theme: BagdarTheme.buildMaterialTheme(themeName),
          builder: (context, child) =>
              BagdarThemeScope(name: themeName, child: child!),
          home: home,
        );
      },
    );
  }
}

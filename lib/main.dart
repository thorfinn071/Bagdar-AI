import 'package:flutter/material.dart';

import 'onboarding_screen.dart';
import 'services/feature_usage_tracker.dart';
import 'services/settings_service.dart';
import 'theme/bagdar_theme.dart';
import 'theme/bagdar_tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Settings.instance.init();
  await FeatureUsageTracker.instance.init();

  bagdarThemeNotifier.value = Settings.instance.themeMode;

  final startScreen = await resolveStartScreen();
  runApp(BagdarApp(home: startScreen));
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
          home: BagdarTheme(
            name: themeName,
            colors: colors,
            child: home,
          ),
        );
      },
    );
  }
}

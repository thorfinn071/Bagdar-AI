import 'package:flutter/material.dart';
import 'theme/bagdar_theme.dart';
import 'theme/bagdar_tokens.dart';
import 'features/onboarding_v2/onboarding_controller.dart';
import 'features/onboarding_v2/onboarding_gateway.dart';
import 'features/onboarding_v2/onboarding_screen.dart';
import 'features/onboarding_v2/onboarding_store.dart';

/// Visual review entry point, using the real flow with explicitly unavailable
/// hardware. It cannot request permissions, access camera or send data.
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bagdar onboarding preview',
      theme: BagdarTheme.buildMaterialTheme(BagdarThemeName.light),
      home: OnboardingV2Screen(
        controller: OnboardingController(
          store: MemoryOnboardingStore(),
          gateway: UnavailableOnboardingGateway(),
        ),
      ),
    ),
  );
}

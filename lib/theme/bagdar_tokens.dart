import 'package:flutter/material.dart';

enum BagdarThemeName { dark, light, highContrast, warm }

extension BagdarThemeNameX on BagdarThemeName {
  String get id {
    switch (this) {
      case BagdarThemeName.dark:
        return 'dark';
      case BagdarThemeName.light:
        return 'light';
      case BagdarThemeName.highContrast:
        return 'high_contrast';
      case BagdarThemeName.warm:
        return 'warm';
    }
  }

  static BagdarThemeName fromId(String? id) {
    switch (id) {
      case 'light':
        return BagdarThemeName.light;
      case 'high_contrast':
        return BagdarThemeName.highContrast;
      case 'warm':
        return BagdarThemeName.warm;
      case 'dark':
      default:
        return BagdarThemeName.dark;
    }
  }
}

@immutable
class BagdarColors {
  final Color surfaceBg;
  final Color surfaceElevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color accentPrimary;
  final Color accentOnPrimary;
  final Color stateSuccess;
  final Color stateWarning;
  final Color stateDanger;
  final Color focusRing;
  final Color divider;

  const BagdarColors({
    required this.surfaceBg,
    required this.surfaceElevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.accentPrimary,
    required this.accentOnPrimary,
    required this.stateSuccess,
    required this.stateWarning,
    required this.stateDanger,
    required this.focusRing,
    required this.divider,
  });

  static const dark = BagdarColors(
    surfaceBg: Color(0xFF000000),
    surfaceElevated: Color(0xFF0A0A0A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFE8E8E8),
    accentPrimary: Color(0xFFFFD600),
    accentOnPrimary: Color(0xFF000000),
    stateSuccess: Color(0xFF7CFFB2),
    stateWarning: Color(0xFFFFB300),
    stateDanger: Color(0xFFFF6B6B),
    focusRing: Color(0xFFFFD600),
    divider: Color(0xFF1A1A1A),
  );

  static const light = BagdarColors(
    surfaceBg: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF2F4F7),
    textPrimary: Color(0xFF0A1628),
    textSecondary: Color(0xFF1F2A3D),
    accentPrimary: Color(0xFF0A1628),
    accentOnPrimary: Color(0xFFFFFFFF),
    stateSuccess: Color(0xFF0F5132),
    stateWarning: Color(0xFF7A4F00),
    stateDanger: Color(0xFF7A0E1A),
    focusRing: Color(0xFF0A1628),
    divider: Color(0xFF0A1628),
  );

  static const highContrast = BagdarColors(
    surfaceBg: Color(0xFF000000),
    surfaceElevated: Color(0xFF000000),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFFFFFFF),
    accentPrimary: Color(0xFFFFFFFF),
    accentOnPrimary: Color(0xFF000000),
    stateSuccess: Color(0xFFFFFFFF),
    stateWarning: Color(0xFFFFFFFF),
    stateDanger: Color(0xFFFFFFFF),
    focusRing: Color(0xFFFFFFFF),
    divider: Color(0xFFFFFFFF),
  );

  static const warm = BagdarColors(
    surfaceBg: Color(0xFFF5EFE0),
    surfaceElevated: Color(0xFFEBE2CC),
    textPrimary: Color(0xFF3A2618),
    textSecondary: Color(0xFF5A3A22),
    accentPrimary: Color(0xFF7A3A0E),
    accentOnPrimary: Color(0xFFFFFFFF),
    stateSuccess: Color(0xFF3E5C2A),
    stateWarning: Color(0xFF7A4F00),
    stateDanger: Color(0xFF7A0E1A),
    focusRing: Color(0xFF7A3A0E),
    divider: Color(0xFF3A2618),
  );

  static BagdarColors of(BagdarThemeName name) {
    switch (name) {
      case BagdarThemeName.dark:
        return dark;
      case BagdarThemeName.light:
        return light;
      case BagdarThemeName.highContrast:
        return highContrast;
      case BagdarThemeName.warm:
        return warm;
    }
  }
}

@immutable
class BagdarTypography {
  static const TextStyle display = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    height: 44 / 36,
  );

  static const TextStyle title = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 36 / 28,
  );

  static const TextStyle body = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w500,
    height: 28 / 20,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 24 / 18,
  );
}

@immutable
class BagdarSpacing {
  const BagdarSpacing._();

  static const double xs = 4.0;
  static const double s = 8.0;
  static const double m = 16.0;
  static const double l = 24.0;
  static const double xl = 32.0;

  static const double tapMinimum = 64.0;
  static const double tapPrimary = 88.0;

  static const double focusRingWidth = 4.0;
  static const double focusRingInset = 2.0;

  static const double shelfHeight = 72.0;
  static const double offlineBannerHeight = 32.0;
}

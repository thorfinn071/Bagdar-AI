import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'bagdar_tokens.dart';

/// Process-wide source of truth for the active visual theme. Read
/// at startup from [Settings.themeMode] (see `lib/main.dart`) and
/// updated via [setBagdarTheme] when the user picks a new theme.
/// Wrapping a [ValueListenableBuilder] around this notifier rebuilds
/// the whole app with the new theme without touching any other state.
final ValueNotifier<BagdarThemeName> bagdarThemeNotifier =
    ValueNotifier<BagdarThemeName>(BagdarThemeName.dark);

/// Single entry point for switching the visual theme at runtime.
/// Persists the choice to [SettingsService] so the next cold start
/// reapplies it, then publishes to [bagdarThemeNotifier] so the
/// MaterialApp rebuilds in place.
Future<void> setBagdarTheme(BagdarThemeName name) async {
  if (Settings.instance.isReady) {
    await Settings.instance.setThemeMode(name);
  }
  bagdarThemeNotifier.value = name;
}

class BagdarTheme extends InheritedWidget {
  final BagdarThemeName name;
  final BagdarColors colors;

  const BagdarTheme({
    super.key,
    required this.name,
    required this.colors,
    required super.child,
  });

  static BagdarTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<BagdarTheme>();
    assert(theme != null, 'No BagdarTheme found in context');
    return theme!;
  }

  static BagdarTheme? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<BagdarTheme>();
  }

  static BagdarColors colorsOf(BuildContext context) {
    final theme = maybeOf(context);
    return theme?.colors ?? BagdarColors.dark;
  }

  static ThemeData buildMaterialTheme(BagdarThemeName name) {
    final c = BagdarColors.of(name);
    final isDarkSurface = name == BagdarThemeName.dark ||
        name == BagdarThemeName.highContrast;

    final colorScheme = isDarkSurface
        ? ColorScheme.dark(
            primary: c.accentPrimary,
            onPrimary: c.accentOnPrimary,
            secondary: c.accentPrimary,
            onSecondary: c.accentOnPrimary,
            surface: c.surfaceBg,
            onSurface: c.textPrimary,
            error: c.stateDanger,
            onError: c.accentOnPrimary,
          )
        : ColorScheme.light(
            primary: c.accentPrimary,
            onPrimary: c.accentOnPrimary,
            secondary: c.accentPrimary,
            onSecondary: c.accentOnPrimary,
            surface: c.surfaceBg,
            onSurface: c.textPrimary,
            error: c.stateDanger,
            onError: c.accentOnPrimary,
          );

    final base = ThemeData(
      useMaterial3: true,
      brightness: isDarkSurface ? Brightness.dark : Brightness.light,
      fontFamily: BagdarTypography.fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: c.surfaceBg,
      canvasColor: c.surfaceBg,
      cardColor: c.surfaceElevated,
      dividerColor: c.divider,
      iconTheme: IconThemeData(color: c.textPrimary, size: 28),
      primaryIconTheme: IconThemeData(color: c.accentOnPrimary, size: 28),
      textTheme: TextTheme(
        displayLarge: BagdarTypography.display.copyWith(color: c.textPrimary),
        headlineLarge: BagdarTypography.title.copyWith(color: c.textPrimary),
        titleLarge: BagdarTypography.title.copyWith(color: c.textPrimary),
        bodyLarge: BagdarTypography.body.copyWith(color: c.textPrimary),
        bodyMedium: BagdarTypography.body.copyWith(color: c.textPrimary),
        bodySmall: BagdarTypography.caption.copyWith(color: c.textSecondary),
        labelLarge: BagdarTypography.body.copyWith(color: c.textPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfaceBg,
        foregroundColor: c.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle:
            BagdarTypography.title.copyWith(color: c.textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        modalBackgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        titleTextStyle:
            BagdarTypography.title.copyWith(color: c.textPrimary),
        contentTextStyle:
            BagdarTypography.body.copyWith(color: c.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle:
            BagdarTypography.body.copyWith(color: c.textPrimary),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStatePropertyAll(c.accentPrimary),
        trackColor: WidgetStatePropertyAll(c.surfaceElevated),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accentPrimary,
        inactiveTrackColor: c.surfaceElevated,
        thumbColor: c.accentPrimary,
        overlayColor: c.accentPrimary.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accentPrimary,
        linearTrackColor: c.surfaceElevated,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accentPrimary,
          foregroundColor: c.accentOnPrimary,
          minimumSize: const Size(BagdarSpacing.tapMinimum,
              BagdarSpacing.tapMinimum),
          padding: const EdgeInsets.symmetric(
              horizontal: BagdarSpacing.l, vertical: BagdarSpacing.m),
          textStyle: BagdarTypography.body,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentPrimary,
          minimumSize: const Size(BagdarSpacing.tapMinimum,
              BagdarSpacing.tapMinimum),
          textStyle: BagdarTypography.body,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accentPrimary,
          foregroundColor: c.accentOnPrimary,
          minimumSize: const Size(BagdarSpacing.tapMinimum,
              BagdarSpacing.tapMinimum),
          textStyle: BagdarTypography.body,
        ),
      ),
      focusColor: c.focusRing,
      visualDensity: VisualDensity.standard,
    );

    return base;
  }

  @override
  bool updateShouldNotify(BagdarTheme oldWidget) => name != oldWidget.name;
}

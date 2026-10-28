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
    return theme?.colors ??
        BagdarColors.of(
          Theme.of(context).brightness == Brightness.dark
              ? BagdarThemeName.dark
              : BagdarThemeName.light,
        );
  }

  static ThemeData buildMaterialTheme(BagdarThemeName name) {
    final c = BagdarColors.of(name);
    final dark =
        name == BagdarThemeName.dark || name == BagdarThemeName.highContrast;
    final highContrast = name == BagdarThemeName.highContrast;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BagdarRadius.control),
    );
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BagdarRadius.card),
      side: BorderSide(color: c.divider),
    );
    final scheme =
        ColorScheme.fromSeed(
          seedColor: c.accentPrimary,
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: c.accentPrimary,
          onPrimary: c.accentOnPrimary,
          primaryContainer: c.surfaceSelected,
          onPrimaryContainer: c.textPrimary,
          secondary: c.accentPrimary,
          onSecondary: c.accentOnPrimary,
          secondaryContainer: c.surfaceSelected,
          onSecondaryContainer: c.textPrimary,
          surface: c.surfaceElevated,
          surfaceContainerLowest: c.surfaceBg,
          surfaceContainerLow: c.surfaceElevated,
          surfaceContainer: c.surfaceElevated,
          surfaceContainerHigh: c.surfaceElevated,
          surfaceContainerHighest: c.surfaceSelected,
          onSurface: c.textPrimary,
          onSurfaceVariant: c.textSecondary,
          outline: c.controlBorder,
          outlineVariant: c.divider,
          error: c.stateDanger,
          onError: BagdarColors.readableOn(c.stateDanger),
          surfaceTint: Colors.transparent,
        );
    final primaryStyle =
        FilledButton.styleFrom(
          backgroundColor: c.accentPrimary,
          foregroundColor: c.accentOnPrimary,
          disabledBackgroundColor: highContrast ? c.surfaceBg : c.disabledFill,
          disabledForegroundColor: c.textSecondary,
          minimumSize: const Size(
            BagdarSpacing.tapMinimum,
            BagdarSpacing.tapMinimum,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          textStyle: BagdarTypography.button,
          shape: controlShape,
          elevation: 0,
        ).copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) => highContrast
                ? BorderSide(color: c.controlBorder, width: 2)
                : null,
          ),
        );
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      fontFamily: BagdarTypography.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.surfaceBg,
      canvasColor: c.surfaceBg,
      cardColor: c.surfaceElevated,
      dividerColor: c.divider,
      disabledColor: c.textSecondary,
      iconTheme: IconThemeData(color: c.textPrimary, size: 24),
      primaryIconTheme: IconThemeData(color: c.accentOnPrimary, size: 24),
      textTheme: TextTheme(
        displayLarge: BagdarTypography.display.copyWith(color: c.textPrimary),
        headlineLarge: BagdarTypography.title.copyWith(color: c.textPrimary),
        headlineMedium: BagdarTypography.title.copyWith(color: c.textPrimary),
        headlineSmall: BagdarTypography.section.copyWith(color: c.textPrimary),
        titleLarge: BagdarTypography.section.copyWith(color: c.textPrimary),
        titleMedium: BagdarTypography.section.copyWith(color: c.textPrimary),
        titleSmall: BagdarTypography.button.copyWith(color: c.textPrimary),
        bodyLarge: BagdarTypography.body.copyWith(color: c.textPrimary),
        bodyMedium: BagdarTypography.body.copyWith(color: c.textPrimary),
        bodySmall: BagdarTypography.caption.copyWith(color: c.textSecondary),
        labelLarge: BagdarTypography.button.copyWith(color: c.textPrimary),
        labelMedium: BagdarTypography.caption.copyWith(color: c.textPrimary),
        labelSmall: BagdarTypography.caption.copyWith(color: c.textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfaceBg,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        toolbarHeight: 72,
        titleTextStyle: BagdarTypography.section.copyWith(color: c.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: cardShape,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        textColor: c.textPrimary,
        iconColor: c.accentPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minVerticalPadding: 16,
        titleTextStyle: BagdarTypography.body.copyWith(color: c.textPrimary),
        subtitleTextStyle: BagdarTypography.caption.copyWith(
          color: c.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceElevated,
        modalBackgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(BagdarRadius.panel),
          ),
          side: BorderSide(color: c.divider),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        shape: cardShape,
        titleTextStyle: BagdarTypography.section.copyWith(color: c.textPrimary),
        contentTextStyle: BagdarTypography.body.copyWith(color: c.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceElevated,
        contentTextStyle: BagdarTypography.caption.copyWith(
          color: c.textPrimary,
        ),
        actionTextColor: c.accentPrimary,
        behavior: SnackBarBehavior.floating,
        shape: cardShape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceElevated,
        contentPadding: const EdgeInsets.all(20),
        labelStyle: BagdarTypography.caption.copyWith(color: c.textSecondary),
        hintStyle: BagdarTypography.caption.copyWith(color: c.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BagdarRadius.control),
          borderSide: BorderSide(color: c.controlBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BagdarRadius.control),
          borderSide: BorderSide(color: c.controlBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(BagdarRadius.control),
          borderSide: BorderSide(color: c.focusRing, width: 2),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accentOnPrimary
              : c.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.accentPrimary
              : c.surfaceElevated,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.controlBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: c.controlBorder, width: 2),
        checkColor: WidgetStatePropertyAll(c.accentOnPrimary),
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accentPrimary,
        inactiveTrackColor: c.divider,
        thumbColor: c.accentPrimary,
        overlayColor: c.accentPrimary.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accentPrimary,
        linearTrackColor: c.divider,
        linearMinHeight: 4,
        borderRadius: BorderRadius.circular(BagdarRadius.sharp),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primaryStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primaryStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.accentPrimary,
          disabledForegroundColor: c.textSecondary,
          minimumSize: const Size(
            BagdarSpacing.tapMinimum,
            BagdarSpacing.tapMinimum,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          textStyle: BagdarTypography.button,
          shape: controlShape,
          side: BorderSide(color: c.controlBorder, width: highContrast ? 2 : 1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accentPrimary,
          disabledForegroundColor: c.textSecondary,
          minimumSize: const Size(48, 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          textStyle: BagdarTypography.caption.copyWith(
            fontWeight: FontWeight.w500,
          ),
          shape: controlShape,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      focusColor: c.focusRing.withValues(alpha: 0.24),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  @override
  bool updateShouldNotify(BagdarTheme oldWidget) => name != oldWidget.name;
}

/// Applies the same palette and Material components in the app, standalone
/// onboarding, previews and recovery shells. OS high contrast always wins.
class BagdarThemeScope extends StatelessWidget {
  final BagdarThemeName? name;
  final Widget child;
  const BagdarThemeScope({super.key, this.name, required this.child});

  @override
  Widget build(BuildContext context) {
    final effective = MediaQuery.maybeOf(context)?.highContrast == true
        ? BagdarThemeName.highContrast
        : name ?? BagdarTheme.maybeOf(context)?.name ?? BagdarThemeName.light;
    return BagdarTheme(
      name: effective,
      colors: BagdarColors.of(effective),
      child: Theme(
        data: BagdarTheme.buildMaterialTheme(effective),
        child: child,
      ),
    );
  }
}

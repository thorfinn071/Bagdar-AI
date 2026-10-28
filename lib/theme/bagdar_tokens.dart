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
    surfaceBg: Color(0xFFF6F6F3),
    surfaceElevated: Color(0xFFFFFFFF),
    textPrimary: Color(0xFF25252A),
    textSecondary: Color(0xFF626462),
    accentPrimary: Color(0xFF273C37),
    accentOnPrimary: Color(0xFFFFFFFF),
    stateSuccess: Color(0xFF0F5132),
    stateWarning: Color(0xFF7A4F00),
    stateDanger: Color(0xFF7A0E1A),
    focusRing: Color(0xFF273C37),
    divider: Color(0xFFE0E2DF),
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

  /// Decorative group separators and accessible control outlines have
  /// different contrast requirements. Never use [divider] for an input edge.
  Color get controlBorder => textSecondary;
  bool get _monochrome => accentPrimary == const Color(0xFFFFFFFF);
  Color get surfaceSelected => _monochrome
      ? surfaceElevated
      : Color.alphaBlend(
          accentPrimary.withValues(alpha: 0.08),
          surfaceElevated,
        );
  Color get disabledFill => _monochrome
      ? surfaceElevated
      : Color.alphaBlend(textPrimary.withValues(alpha: 0.12), surfaceElevated);

  /// Returns pure black or pure white — whichever yields the higher WCAG
  /// contrast against [bg]. Used by signage fills (status badges, accent
  /// chips) so foreground glyphs/text stay AAA-legible across all four
  /// themes without hand-tuning an `onColor` per palette.
  static Color readableOn(Color bg) {
    final onBlack = _contrastRatio(bg, const Color(0xFF000000));
    final onWhite = _contrastRatio(bg, const Color(0xFFFFFFFF));
    return onBlack >= onWhite
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
  }

  static double _contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

@immutable
class BagdarTypography {
  const BagdarTypography._();

  /// Primary family — Inter (SIL OFL). Chosen for maximal on-screen
  /// legibility with disambiguated letterforms, while providing full
  /// Cyrillic coverage including the Kazakh-specific glyphs (ә ғ қ ң ө ұ ү
  /// һ і) that Atkinson Hyperlegible lacks entirely. Bundled as static
  /// weights (400/500/700/800) under `assets/fonts/` and declared in
  /// `pubspec.yaml`. When the files are absent Flutter silently falls back
  /// to the platform default, so referencing this name is always safe.
  static const String fontFamily = 'Inter';

  static const FontWeight weightRegular = FontWeight.w400;
  static const FontWeight weightMedium = FontWeight.w500;
  static const FontWeight weightBold = FontWeight.w700;
  static const FontWeight weightHeavy = FontWeight.w800;
  static const FontWeight weightBlack = FontWeight.w900;

  /// Oversized signage headline. Heavy weight + tight leading for the
  /// transit-wayfinding feel. [weightHeavy] (800) is the heaviest bundled
  /// Inter cut; intermediate weights snap to the nearest bundled file.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 40,
    fontWeight: weightHeavy,
    height: 46 / 40,
    letterSpacing: 0.25,
  );

  static const TextStyle title = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: weightBold,
    height: 1.2,
  );

  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: weightRegular,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: weightRegular,
    height: 1.5,
  );

  static const TextStyle section = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: weightBold,
    height: 1.4,
  );

  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: weightBold,
    height: 1.4,
  );

  /// All-caps signage label (mode badges, status words). Wide tracking
  /// echoes pedestrian/transit signage.
  static const TextStyle label = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: weightHeavy,
    height: 20 / 16,
    letterSpacing: 1.5,
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
  static const double contentMaxWidth = 560.0;

  static const double tapMinimum = 64.0;
  static const double tapPrimary = 88.0;

  static const double focusRingWidth = 4.0;
  static const double focusRingInset = 2.0;

  static const double shelfHeight = 72.0;
  static const double offlineBannerHeight = 32.0;
}

/// Shared form, card and sheet geometry across onboarding and inspection.
@immutable
class BagdarRadius {
  const BagdarRadius._();

  static const double sharp = 2.0;
  static const double control = 12.0;
  static const double card = 16.0;
  static const double panel = 20.0;
  static const double pill = 999.0;
}

/// Border / rule weights for the thick-rule signage look.
@immutable
class BagdarBorders {
  const BagdarBorders._();

  static const double hairline = 1.0;
  static const double thin = 2.0;
  static const double rule = 4.0;
  static const double heavy = 6.0;
}

/// Motion durations + curves. Always route durations through
/// [BagdarMotion.duration] so reduce-motion / TalkBack users get instant,
/// non-distracting transitions (honours `MediaQuery.disableAnimations` and
/// `accessibleNavigation`).
@immutable
class BagdarMotion {
  const BagdarMotion._();

  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 140);
  static const Duration medium = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 420);

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve decelerate = Curves.easeOut;

  static bool reduceMotionOf(BuildContext context) {
    final mq = MediaQuery.maybeOf(context);
    if (mq == null) return false;
    return mq.disableAnimations || mq.accessibleNavigation;
  }

  static Duration duration(BuildContext context, Duration d) =>
      reduceMotionOf(context) ? Duration.zero : d;
}

/// Palette for chrome painted directly over the live camera feed (HUD,
/// status panel, nav HUD, debug overlay). The camera is an uncontrolled,
/// mostly-dark backdrop, so these values are always light-on-dark
/// regardless of the active app theme — routing surface/text tokens here
/// would make the `light` and `warm` themes illegible over video.
@immutable
class BagdarOverlay {
  const BagdarOverlay._();

  /// Standard scrim behind HUD text blocks (~80% black).
  static const Color scrim = Color(0xCC000000);

  /// Lighter scrim for subtle chrome.
  static const Color scrimSoft = Color(0x99000000);

  /// Heavier scrim for dense / safety-critical panels.
  static const Color scrimStrong = Color(0xE6000000);

  /// Primary on-camera text.
  static const Color foreground = Color(0xFFFFFFFF);

  /// De-emphasised on-camera text (counts, hints).
  static const Color foregroundMuted = Color(0xFFD6D6D6);

  /// Soft shadow applied to on-camera text so it survives bright frames.
  static const List<Shadow> textShadows = <Shadow>[
    Shadow(color: Color(0xE6000000), blurRadius: 4),
  ];

  /// Returns [color] if it reads on the dark scrim, otherwise [fallback]
  /// (default hi-vis yellow). Dark accents (light/warm navy/brown) would
  /// vanish over video, so they are swapped for a bright equivalent.
  static Color safe(Color color, {Color fallback = const Color(0xFFFFD600)}) {
    return color.computeLuminance() >= 0.4 ? color : fallback;
  }

  /// The dominant on-camera signal colour for [colors]: the theme accent
  /// when bright enough (dark theme yellow, high-contrast white), else the
  /// hi-vis yellow so light/warm themes still signal clearly over video.
  static Color signal(BagdarColors colors) => safe(colors.accentPrimary);

  /// Over-camera fill for a [level], guaranteed bright: keeps the active
  /// theme's state colour when legible, else the dark-theme equivalent.
  static Color statusFill(BagdarStatusLevel level, BagdarColors colors) {
    return safe(
      bagdarStatusStyle(level, colors).fill,
      fallback: bagdarStatusStyle(level, BagdarColors.dark).fill,
    );
  }
}

/// Semantic hazard / state level. Meaning is encoded by **shape + icon +
/// text**, never colour alone — critical for colour-blind and low-vision
/// users and the distinctive signature of the Hi-Vis Wayfinding language.
enum BagdarStatusLevel { danger, caution, clear, info }

/// Geometric shape paired with each [BagdarStatusLevel]. Mirrors road /
/// transit signage: octagon = stop/danger, triangle = caution, circle =
/// clear/permitted, bar = neutral information.
enum BagdarSignalShape { octagon, triangle, circle, bar }

/// Resolved visual treatment for a [BagdarStatusLevel] under a given
/// palette: the shape to draw, the glyph to overlay, the fill colour and a
/// guaranteed-legible foreground.
@immutable
class BagdarStatusStyle {
  final BagdarSignalShape shape;
  final IconData icon;
  final Color fill;
  final Color onFill;

  const BagdarStatusStyle({
    required this.shape,
    required this.icon,
    required this.fill,
    required this.onFill,
  });
}

/// Maps a [BagdarStatusLevel] to its [BagdarStatusStyle] for [colors].
/// Shapes and glyphs are palette-independent; only the fill / foreground
/// adapt per theme.
BagdarStatusStyle bagdarStatusStyle(
  BagdarStatusLevel level,
  BagdarColors colors,
) {
  switch (level) {
    case BagdarStatusLevel.danger:
      return BagdarStatusStyle(
        shape: BagdarSignalShape.octagon,
        icon: Icons.priority_high_rounded,
        fill: colors.stateDanger,
        onFill: BagdarColors.readableOn(colors.stateDanger),
      );
    case BagdarStatusLevel.caution:
      return BagdarStatusStyle(
        shape: BagdarSignalShape.triangle,
        icon: Icons.warning_amber_rounded,
        fill: colors.stateWarning,
        onFill: BagdarColors.readableOn(colors.stateWarning),
      );
    case BagdarStatusLevel.clear:
      return BagdarStatusStyle(
        shape: BagdarSignalShape.circle,
        icon: Icons.check_rounded,
        fill: colors.stateSuccess,
        onFill: BagdarColors.readableOn(colors.stateSuccess),
      );
    case BagdarStatusLevel.info:
      return BagdarStatusStyle(
        shape: BagdarSignalShape.bar,
        icon: Icons.info_outline_rounded,
        fill: colors.accentPrimary,
        onFill: BagdarColors.readableOn(colors.accentPrimary),
      );
  }
}

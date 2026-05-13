import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/theme/bagdar_theme.dart';
import 'package:bagdar/theme/bagdar_tokens.dart';

void main() {
  group('BagdarColors AAA contrast invariants', () {
    test('Dark theme uses pure black surface and electric-yellow accent', () {
      const c = BagdarColors.dark;
      expect(c.surfaceBg, const Color(0xFF000000));
      expect(c.accentPrimary, const Color(0xFFFFD600));
      expect(c.textPrimary, const Color(0xFFFFFFFF));
      expect(_contrast(c.textPrimary, c.surfaceBg), greaterThanOrEqualTo(7.0));
      expect(
        _contrast(c.accentPrimary, c.surfaceBg),
        greaterThanOrEqualTo(7.0),
      );
    });

    test('Light theme uses deep navy on white', () {
      const c = BagdarColors.light;
      expect(c.surfaceBg, const Color(0xFFFFFFFF));
      expect(c.textPrimary, const Color(0xFF0A1628));
      expect(_contrast(c.textPrimary, c.surfaceBg), greaterThanOrEqualTo(7.0));
    });

    test('High-contrast theme contains no grays', () {
      const c = BagdarColors.highContrast;
      expect(c.surfaceBg, const Color(0xFF000000));
      expect(c.textPrimary, const Color(0xFFFFFFFF));
      expect(c.textSecondary, const Color(0xFFFFFFFF));
      expect(c.divider, const Color(0xFFFFFFFF));
      expect(_contrast(c.textPrimary, c.surfaceBg), greaterThanOrEqualTo(20.0));
    });

    test('Warm theme uses cream + dark brown', () {
      const c = BagdarColors.warm;
      expect(c.surfaceBg, const Color(0xFFF5EFE0));
      expect(c.textPrimary, const Color(0xFF3A2618));
      expect(_contrast(c.textPrimary, c.surfaceBg), greaterThanOrEqualTo(7.0));
    });

    test('Every theme satisfies WCAG AAA for primary body text', () {
      for (final name in BagdarThemeName.values) {
        final c = BagdarColors.of(name);
        expect(
          _contrast(c.textPrimary, c.surfaceBg),
          greaterThanOrEqualTo(7.0),
          reason: 'Theme $name fails AAA for textPrimary on surfaceBg',
        );
        expect(
          _contrast(c.accentOnPrimary, c.accentPrimary),
          greaterThanOrEqualTo(7.0),
          reason:
              'Theme $name fails AAA for accentOnPrimary on accentPrimary',
        );
      }
    });
  });

  group('BagdarThemeName id round-trip', () {
    test('every enum value round-trips through its id', () {
      for (final name in BagdarThemeName.values) {
        final id = name.id;
        expect(BagdarThemeNameX.fromId(id), name);
      }
    });

    test('unknown id falls back to dark', () {
      expect(BagdarThemeNameX.fromId(null), BagdarThemeName.dark);
      expect(BagdarThemeNameX.fromId('bogus'), BagdarThemeName.dark);
    });
  });

  group('BagdarTheme.buildMaterialTheme', () {
    test('produces brightness-correct ThemeData for each theme', () {
      expect(
        BagdarTheme.buildMaterialTheme(BagdarThemeName.dark).brightness,
        Brightness.dark,
      );
      expect(
        BagdarTheme.buildMaterialTheme(BagdarThemeName.highContrast).brightness,
        Brightness.dark,
      );
      expect(
        BagdarTheme.buildMaterialTheme(BagdarThemeName.light).brightness,
        Brightness.light,
      );
      expect(
        BagdarTheme.buildMaterialTheme(BagdarThemeName.warm).brightness,
        Brightness.light,
      );
    });

    testWidgets('exposes BagdarColors via BagdarTheme.of(context)',
        (tester) async {
      late BagdarColors captured;
      await tester.pumpWidget(
        MaterialApp(
          home: BagdarTheme(
            name: BagdarThemeName.warm,
            colors: BagdarColors.warm,
            child: Builder(
              builder: (context) {
                captured = BagdarTheme.colorsOf(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(captured.surfaceBg, BagdarColors.warm.surfaceBg);
      expect(captured.accentPrimary, BagdarColors.warm.accentPrimary);
    });
  });
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final brighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (brighter + 0.05) / (darker + 0.05);
}

double _relativeLuminance(Color c) {
  double channel(double v) {
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

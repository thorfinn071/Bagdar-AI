import 'package:flutter/material.dart';

import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';

/// Paints one of the [BagdarSignalShape] geometries filled with [fill].
///
/// Shapes are the load-bearing part of the Hi-Vis Wayfinding semantics:
/// danger = octagon, caution = triangle, clear = circle, info = bar. They
/// let colour-blind, low-vision and high-contrast users (where every state
/// colour collapses to white) still tell states apart by silhouette alone.
class _SignalShapePainter extends CustomPainter {
  final BagdarSignalShape shape;
  final Color fill;

  const _SignalShapePainter({required this.shape, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = fill
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawPath(_pathFor(shape, size), paint);
  }

  static Path _pathFor(BagdarSignalShape shape, Size s) {
    final w = s.width;
    final h = s.height;
    switch (shape) {
      case BagdarSignalShape.octagon:
        final c = 0.293 * w;
        return Path()
          ..moveTo(c, 0)
          ..lineTo(w - c, 0)
          ..lineTo(w, c)
          ..lineTo(w, h - c)
          ..lineTo(w - c, h)
          ..lineTo(c, h)
          ..lineTo(0, h - c)
          ..lineTo(0, c)
          ..close();
      case BagdarSignalShape.triangle:
        // Rounded-corner upward triangle (caution sign silhouette).
        return Path()
          ..moveTo(w / 2, 0)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
      case BagdarSignalShape.circle:
        return Path()..addOval(Rect.fromLTWH(0, 0, w, h));
      case BagdarSignalShape.bar:
        return Path()
          ..addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(0, h * 0.18, w, h * 0.64),
            const Radius.circular(BagdarRadius.sharp),
          ));
    }
  }

  @override
  bool shouldRepaint(_SignalShapePainter old) =>
      old.shape != shape || old.fill != fill;
}

/// A standalone shape+icon "signal mark" (no text). Decorative for
/// accessibility — wrap in a labelled [Semantics] (as [SemanticStatusBadge]
/// does) when it conveys meaning.
class SignalMark extends StatelessWidget {
  final BagdarStatusLevel level;
  final double size;

  /// When true, fills are forced bright for legibility over the camera feed.
  final bool onCamera;

  const SignalMark({
    super.key,
    required this.level,
    this.size = 28,
    this.onCamera = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    final style = bagdarStatusStyle(level, colors);
    final fill =
        onCamera ? BagdarOverlay.statusFill(level, colors) : style.fill;
    final onFill = BagdarColors.readableOn(fill);
    // The triangle's visual mass sits low, so nudge + shrink its glyph.
    final isTriangle = style.shape == BagdarSignalShape.triangle;
    final iconSize = size * (isTriangle ? 0.42 : 0.58);
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _SignalShapePainter(shape: style.shape, fill: fill),
          child: Padding(
            padding: EdgeInsets.only(top: isTriangle ? size * 0.18 : 0),
            child: Center(
              child: Icon(style.icon, size: iconSize, color: onFill),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a hazard / state as **shape + icon + colour + text** — the
/// distinctive, redundantly-encoded status chip of the Hi-Vis Wayfinding
/// language. Replaces ad-hoc colored chips (e.g. in `status_panel.dart` and
/// `nav_hud.dart`).
///
/// Pass [onCamera] when drawn over the live camera preview so fills and
/// text stay legible against the dark scrim in every theme.
class SemanticStatusBadge extends StatelessWidget {
  final BagdarStatusLevel level;

  /// Visible (and, by default, spoken) status text. Caller-localized.
  final String? label;

  /// Overrides the spoken label; defaults to [label].
  final String? semanticLabel;

  /// Icon-only — omits the text but keeps the [Semantics] label.
  final bool dense;

  /// Use the over-camera-safe palette (bright fills, white text + shadow).
  final bool onCamera;

  final double markSize;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;

  const SemanticStatusBadge({
    super.key,
    required this.level,
    this.label,
    this.semanticLabel,
    this.dense = false,
    this.onCamera = false,
    this.markSize = 28,
    this.textStyle,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    final borderColor = onCamera
        ? BagdarOverlay.statusFill(level, colors)
        : bagdarStatusStyle(level, colors).fill;
    final textColor = onCamera ? BagdarOverlay.foreground : colors.textPrimary;
    final bg = onCamera ? BagdarOverlay.scrim : colors.surfaceElevated;

    final resolvedTextStyle = (textStyle ?? BagdarTypography.label).copyWith(
      color: textColor,
      shadows: onCamera ? BagdarOverlay.textShadows : null,
    );

    final mark = SignalMark(level: level, size: markSize, onCamera: onCamera);

    final content = (dense || label == null || label!.isEmpty)
        ? mark
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              const SizedBox(width: BagdarSpacing.s),
              Flexible(
                child: Text(
                  label!,
                  style: resolvedTextStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    return Semantics(
      container: true,
      label: semanticLabel ?? label,
      child: Container(
        padding: padding ??
            const EdgeInsets.symmetric(
              horizontal: BagdarSpacing.s,
              vertical: BagdarSpacing.xs,
            ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          border: Border.all(color: borderColor, width: BagdarBorders.thin),
        ),
        child: content,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import 'focus_ring_decorator.dart';

/// A single tab in the camera-screen quick shelf. Three of these
/// compose [QuickShelf]. Each tab is at least 64×64 dp, label-first
/// (icon is decorative and excluded from semantics), and grows the
/// focus ring via [FocusRingDecorator] when TalkBack lands on it.
///
/// Two label fields are intentionally separate:
/// - [label] — the **short** word painted on screen (e.g. "Read",
///   "Camera"). Constrained to one line so it fits a 72 dp row on a
///   360 dp wide phone.
/// - [semanticLabel] — the **long** action-oriented sentence read by
///   TalkBack (e.g. "Read aloud what the camera sees."). Per the
///   design plan §4.2, screen readers must hear a verb-led sentence
///   so the user can act without seeing the icon.
class BottomShelfTab extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final String? hint;
  final IconData icon;
  final bool active;
  final VoidCallback onActivate;
  final FocusNode? focusNode;

  const BottomShelfTab({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.icon,
    required this.active,
    required this.onActivate,
    this.hint,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    final fg = active ? colors.accentOnPrimary : colors.textPrimary;
    final bg = active ? colors.accentPrimary : colors.surfaceElevated;

    return Semantics(
      button: true,
      selected: active,
      enabled: true,
      label: semanticLabel,
      hint: hint,
      onTap: onActivate,
      child: FocusRingDecorator(
        focusNode: focusNode,
        borderRadius: BorderRadius.zero,
        child: Material(
          color: bg,
          child: InkWell(
            onTap: onActivate,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: BagdarSpacing.tapMinimum,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: BagdarSpacing.s,
                vertical: BagdarSpacing.xs,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ExcludeSemantics(child: Icon(icon, color: fg, size: 24)),
                  const SizedBox(height: 2),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: BagdarTypography.caption.copyWith(
                        color: fg,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        height: 1.1,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

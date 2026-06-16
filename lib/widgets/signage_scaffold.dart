import 'package:flutter/material.dart';

import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';
import 'a11y/focus_ring_decorator.dart';

/// Consistent screen chrome for the Hi-Vis Wayfinding language: an oversized
/// signage title, a bold accent rule, and a generous (64 dp) back
/// affordance. Used by the settings / language-pack / QR screens so they
/// share one signage identity instead of ad-hoc [AppBar]s.
///
/// The accent rule "draws" itself on entrance (left-to-right) — a small,
/// intentional load motion that is suppressed when reduce-motion /
/// TalkBack is active (see [BagdarMotion.reduceMotionOf]).
class SignageScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  /// Trailing header actions (rendered to the right of the title row).
  final List<Widget>? actions;

  final bool showBack;
  final VoidCallback? onBack;
  final String? backSemanticLabel;

  final Widget? bottomBar;
  final Widget? floatingActionButton;

  final EdgeInsetsGeometry bodyPadding;
  final bool scrollable;

  const SignageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.backSemanticLabel,
    this.bottomBar,
    this.floatingActionButton,
    this.bodyPadding = const EdgeInsets.all(BagdarSpacing.l),
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);

    final body =
        scrollable ? SingleChildScrollView(padding: bodyPadding, child: child) : Padding(padding: bodyPadding, child: child);

    return Scaffold(
      backgroundColor: colors.surfaceBg,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomBar,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SignageHeader(
              title: title,
              subtitle: subtitle,
              actions: actions,
              showBack: showBack,
              onBack: onBack,
              backSemanticLabel: backSemanticLabel,
              colors: colors,
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _SignageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final String? backSemanticLabel;
  final BagdarColors colors;

  const _SignageHeader({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.showBack,
    required this.onBack,
    required this.backSemanticLabel,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final backLabel = backSemanticLabel ??
        MaterialLocalizations.of(context).backButtonTooltip;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BagdarSpacing.s,
        BagdarSpacing.s,
        BagdarSpacing.m,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showBack)
                FocusRingDecorator(
                  borderRadius:
                      BorderRadius.circular(BagdarRadius.card),
                  child: Semantics(
                    button: true,
                    label: backLabel,
                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(BagdarRadius.card),
                      onTap: onBack ?? () => Navigator.of(context).maybePop(),
                      child: SizedBox(
                        width: BagdarSpacing.tapMinimum,
                        height: BagdarSpacing.tapMinimum,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: colors.textPrimary,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ),
              if (showBack) const SizedBox(width: BagdarSpacing.s),
              Expanded(
                child: Text(
                  title,
                  style: BagdarTypography.title.copyWith(
                    color: colors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (actions != null) ...[
                const SizedBox(width: BagdarSpacing.s),
                ...actions!,
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                top: BagdarSpacing.xs,
                left: BagdarSpacing.xs,
              ),
              child: Text(
                subtitle!,
                style: BagdarTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          const SizedBox(height: BagdarSpacing.s),
          _AccentRule(color: colors.accentPrimary),
          const SizedBox(height: BagdarSpacing.s),
        ],
      ),
    );
  }
}

/// The bold signage rule under the header. Animates its width from the
/// leading edge on first build (reduce-motion aware).
class _AccentRule extends StatelessWidget {
  final Color color;
  const _AccentRule({required this.color});

  @override
  Widget build(BuildContext context) {
    final duration = BagdarMotion.duration(context, BagdarMotion.slow);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration,
      curve: BagdarMotion.decelerate,
      builder: (context, t, _) {
        return Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: t,
            child: Container(
              height: BagdarBorders.rule,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(BagdarRadius.sharp),
              ),
            ),
          ),
        );
      },
    );
  }
}

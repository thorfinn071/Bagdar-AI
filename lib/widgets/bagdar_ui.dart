import 'package:flutter/material.dart';

import '../models/strings.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';

/// Shared readable column. The heading scrolls with the content so large
/// system text never competes with a fixed-height toolbar.
class BagdarPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  const BagdarPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(BagdarSpacing.l),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: BagdarSpacing.contentMaxWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back_rounded, size: 20),
                          label: Text(S.get('ui_back')),
                        ),
                      ),
                    ),
                    ...actions,
                  ],
                ),
                const SizedBox(height: BagdarSpacing.l),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: BagdarSpacing.s),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: BagdarSpacing.l),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Opaque, bordered surface shared by forms and controls over video.
class BagdarCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const BagdarCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(BagdarSpacing.m),
  });

  @override
  Widget build(BuildContext context) => Material(
    color: BagdarTheme.colorsOf(context).surfaceElevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BagdarRadius.card),
      side: BorderSide(color: BagdarTheme.colorsOf(context).divider),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

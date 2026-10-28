import 'package:flutter/material.dart';

import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';

/// Wraps [child] with a 4 dp solid focus ring (token: `focus.ring`)
/// that appears whenever the child or any of its descendants holds
/// keyboard/input focus. This does not observe TalkBack accessibility focus.
/// The ring is drawn
/// outside the child's painted bounds so it does not consume layout
/// space when invisible.
///
/// Use this directly around any tappable element that does not already
/// receive a Material ink response (which carries its own focus
/// indicator). For elements wrapped in [InkWell] / [InkResponse] the
/// Material indicator is sufficient — do not double-decorate.
class FocusRingDecorator extends StatefulWidget {
  final Widget child;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;
  final double ringWidth;
  final double ringInset;
  final Color? overrideColor;

  const FocusRingDecorator({
    super.key,
    required this.child,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.ringWidth = BagdarSpacing.focusRingWidth,
    this.ringInset = BagdarSpacing.focusRingInset,
    this.overrideColor,
  });

  @override
  State<FocusRingDecorator> createState() => _FocusRingDecoratorState();
}

class _FocusRingDecoratorState extends State<FocusRingDecorator> {
  late FocusNode _node;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    _attachNode();
  }

  void _attachNode() {
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
      _ownsNode = false;
    } else {
      _node = FocusNode(debugLabel: 'FocusRingDecorator');
      _ownsNode = true;
    }
    _node.addListener(_onChange);
  }

  void _detachNode() {
    _node.removeListener(_onChange);
    if (_ownsNode) _node.dispose();
  }

  @override
  void didUpdateWidget(covariant FocusRingDecorator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachNode();
      _attachNode();
    }
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _detachNode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ringColor =
        widget.overrideColor ?? BagdarTheme.colorsOf(context).focusRing;
    final hasFocus = _node.hasFocus;
    return Focus(
      focusNode: _node,
      canRequestFocus: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (hasFocus)
            Positioned(
              left: -widget.ringInset,
              right: -widget.ringInset,
              top: -widget.ringInset,
              bottom: -widget.ringInset,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: Border.all(
                      color: ringColor,
                      width: widget.ringWidth,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

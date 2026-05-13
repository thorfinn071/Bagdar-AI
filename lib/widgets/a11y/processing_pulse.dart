import 'package:flutter/material.dart';

import '../../utils/motion.dart';

/// 3-second sine-eased opacity pulse used to communicate "the app is
/// still working on it". Wrap any child (icon, text, custom paint)
/// to make it gently breathe between [maxOpacity] and [minOpacity].
///
/// Reduced-motion fallback: the pulse is replaced with a static
/// half-step opacity (`(maxOpacity + minOpacity) / 2`) — the widget
/// stays visible without animation. Per the design plan §7.3 the
/// audible feedback (TTS heartbeat / earcon) must be driven by the
/// parent and is not part of this widget's contract.
class ProcessingPulse extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double maxOpacity;
  final double minOpacity;

  const ProcessingPulse({
    super.key,
    required this.child,
    this.period = const Duration(seconds: 3),
    this.maxOpacity = 1.0,
    this.minOpacity = 0.4,
  }) : assert(maxOpacity >= minOpacity),
       assert(maxOpacity <= 1.0),
       assert(minOpacity >= 0.0);

  @override
  State<ProcessingPulse> createState() => _ProcessingPulseState();
}

class _ProcessingPulseState extends State<ProcessingPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.period,
    );
    _opacity = Tween<double>(
      begin: widget.maxOpacity,
      end: widget.minOpacity,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isReducedMotion(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isReducedMotion(context)) {
      return Opacity(
        opacity: (widget.maxOpacity + widget.minOpacity) / 2,
        child: widget.child,
      );
    }
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, child) =>
          Opacity(opacity: _opacity.value, child: child),
      child: widget.child,
    );
  }
}

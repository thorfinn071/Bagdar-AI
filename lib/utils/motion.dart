import 'package:flutter/widgets.dart';

/// Reduced-motion helper. Reads the system "Remove animations" preference
/// (Android: Settings → Accessibility → Remove animations; iOS: Settings →
/// Accessibility → Reduce Motion) and either returns the requested duration
/// unchanged or collapses it to [Duration.zero] so widgets render in their
/// final state immediately.
///
/// Use as: `duration: motion(context, const Duration(milliseconds: 300))`.
///
/// Animations that convey **progress information** (e.g. a long-press hold
/// indicator, an OCR processing pulse driven by audio heartbeats) must
/// continue to animate even when reduced-motion is on, because removing
/// them would strand the user in silence; for those cases, do not call
/// this helper — they are listed in the design plan §7.1 with explicit
/// reduced-motion fallbacks.
Duration motion(BuildContext context, Duration normal) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : normal;
}

bool isReducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

/// Returns [normal] unless reduced-motion is on, in which case it returns
/// [reduced]. Useful for swapping curve / opacity targets, not just durations.
T motionPick<T>(BuildContext context, {required T normal, required T reduced}) {
  return MediaQuery.disableAnimationsOf(context) ? reduced : normal;
}

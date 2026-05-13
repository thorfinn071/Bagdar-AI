import 'package:flutter/material.dart';

import '../../models/speech_job.dart';
import '../../services/haptic_service.dart';
import '../../services/tts_service.dart';
import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import 'focus_ring_decorator.dart';

/// `[label] [−] [value] [+]` row that replaces [Slider] in the
/// settings sheet. Exists because TalkBack's slider semantics work
/// poorly on 64 dp targets — discrete steppers are reliably
/// reachable, announce their new value as plain text, and let the
/// user know they have hit a boundary via haptic + verbal feedback.
///
/// A thin decorative progress strip painted below the stepper gives
/// sighted helpers a visual sense of the current position; it is
/// excluded from semantics so screen readers do not double-announce.
class StepperField extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;
  final String? increaseSemanticLabel;
  final String? decreaseSemanticLabel;
  final TtsService? tts;

  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.onChanged,
    this.increaseSemanticLabel,
    this.decreaseSemanticLabel,
    this.tts,
  });

  double get _step => (max - min) / divisions;
  bool get _atMin => value <= min + _step / 2;
  bool get _atMax => value >= max - _step / 2;
  double get _normalized =>
      ((value - min) / (max - min)).clamp(0.0, 1.0).toDouble();

  void _adjust(double delta) {
    final next = (value + delta).clamp(min, max);
    final snapped = _snap(next);
    if (snapped == value) {
      HapticService.vibrate(const [0, 8, 30, 8]);
      return;
    }
    HapticService.vibrate(const [0, 12]);
    onChanged(snapped);
    final formatted = formatValue(snapped);
    (tts ?? TtsService.instance).say(
      '$label: $formatted',
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  double _snap(double raw) {
    final stepsFromMin = ((raw - min) / _step).round();
    return (min + stepsFromMin * _step).clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    final formatted = formatValue(value);

    return Semantics(
      container: true,
      label: '$label: $formatted',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BagdarSpacing.m,
          vertical: BagdarSpacing.s,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: BagdarTypography.body.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: BagdarSpacing.xs),
            Row(
              children: [
                _StepperButton(
                  icon: Icons.remove,
                  semanticLabel: decreaseSemanticLabel ?? '$label −',
                  enabled: !_atMin,
                  onPressed: () => _adjust(-_step),
                ),
                const SizedBox(width: BagdarSpacing.s),
                Expanded(
                  child: ExcludeSemantics(
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: BagdarSpacing.s,
                        vertical: BagdarSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        formatted,
                        style: BagdarTypography.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: BagdarSpacing.s),
                _StepperButton(
                  icon: Icons.add,
                  semanticLabel: increaseSemanticLabel ?? '$label +',
                  enabled: !_atMax,
                  onPressed: () => _adjust(_step),
                ),
              ],
            ),
            const SizedBox(height: BagdarSpacing.xs),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: _normalized,
                  minHeight: 4,
                  backgroundColor: colors.surfaceElevated,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(colors.accentPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final bool enabled;
  final VoidCallback onPressed;

  const _StepperButton({
    required this.icon,
    required this.semanticLabel,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    final fg = enabled ? colors.accentOnPrimary : colors.textSecondary;
    final bg = enabled ? colors.accentPrimary : colors.surfaceElevated;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? onPressed : null,
      child: FocusRingDecorator(
        borderRadius: BorderRadius.circular(8),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: BagdarSpacing.tapMinimum,
              height: BagdarSpacing.tapMinimum,
              child: ExcludeSemantics(
                child: Icon(icon, color: fg, size: 28),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

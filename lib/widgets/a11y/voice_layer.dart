import 'package:flutter/material.dart';

import '../../models/strings.dart';
import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import 'focus_ring_decorator.dart';

/// Full-screen tinted overlay shown while STT is actively listening.
/// Solves the problem that the existing camera screen only spoke
/// "Слушаю..." with no visual feedback — fine for blind users but
/// invisible to low-vision users with partial sight.
///
/// Mounted/dismissed by the camera screen when
/// `VoiceCommandService.onListeningStateChanged` fires. The Cancel
/// button is 88 dp tall (primary touch target) and wired to
/// `VoiceCommandService.stopListening`.
class VoiceLayer extends StatelessWidget {
  final VoidCallback onCancel;

  const VoiceLayer({super.key, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Positioned.fill(
      child: Material(
        color: colors.accentPrimary.withValues(alpha: 0.92),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(BagdarSpacing.l),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox.shrink(),
                Center(
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: S.get('voice_layer_listening'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.mic,
                          color: colors.accentOnPrimary,
                          size: 96,
                        ),
                        const SizedBox(height: BagdarSpacing.l),
                        Text(
                          S.get('voice_layer_listening'),
                          textAlign: TextAlign.center,
                          style: BagdarTypography.display.copyWith(
                            color: colors.accentOnPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: SizedBox(
                    width: 240,
                    height: BagdarSpacing.tapPrimary,
                    child: FocusRingDecorator(
                      borderRadius: BorderRadius.circular(12),
                      overrideColor: colors.accentOnPrimary,
                      child: Material(
                        color: colors.surfaceBg,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: onCancel,
                          borderRadius: BorderRadius.circular(12),
                          child: Center(
                            child: Semantics(
                              button: true,
                              label: S.get('voice_layer_cancel'),
                              onTap: onCancel,
                              child: Text(
                                S.get('voice_layer_cancel'),
                                style: BagdarTypography.title.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../models/app_mode.dart';
import '../../models/strings.dart';
import '../../theme/bagdar_theme.dart';
import '../../theme/bagdar_tokens.dart';
import '../../tracker/track.dart';
import '../../utils/distance_utils.dart';
import 'a11y/semantic_status_badge.dart';

class StatusPanel extends StatelessWidget {
  final String statusLine;
  final ValueNotifier<List<Track>> tracksNotifier;
  final int imgW, imgH;
  final double? viewportAspect;
  final AppMode mode;

  const StatusPanel({
    super.key,
    required this.statusLine,
    required this.tracksNotifier,
    required this.imgW,
    required this.imgH,
    this.viewportAspect,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = BagdarTheme.colorsOf(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(BagdarSpacing.s),
      padding: const EdgeInsets.all(BagdarSpacing.m),
      decoration: BoxDecoration(
        color: BagdarOverlay.scrim,
        borderRadius: BorderRadius.circular(BagdarRadius.panel),
        border: Border.all(
          color: BagdarOverlay.foregroundMuted.withValues(alpha: 0.25),
          width: BagdarBorders.hairline,
        ),
      ),
      child: ValueListenableBuilder<List<Track>>(
        valueListenable: tracksNotifier,
        builder: (_, tracks, __) {
          final top = tracks.isEmpty
              ? null
              : tracks.reduce((a, b) => _sortKey(a) <= _sortKey(b) ? a : b);

          String label = '—';
          String distText = '—';
          String dirText = '—';
          String distM = '';

          if (top == null) {
            switch (mode) {
              case AppMode.street:
                label = S.get('path_clear_label');
                distText = S.get('dist_safe');
                dirText = S.get('straight');
              case AppMode.cane:
                label = S.get('status_no_obstacle');
                distText = S.get('dist_safe');
                dirText = S.get('straight');
              case AppMode.scan:
                label = S.get('status_scanning');
                distText = S.get('status_waiting');
                dirText = '—';
            }
          }

          if (top != null && imgH > 0 && imgW > 0) {
            label = S.label(top.label);
            distText = _distLabel(top.dist);
            dirText = clockDir(
              top.x1,
              top.x2,
              imgW.toDouble(),
              imgH: imgH.toDouble(),
              viewportAspect: viewportAspect,
            );
            distM = top.distM > 0
                ? ' • ~${top.distM.toStringAsFixed(1)} ${S.get('approx_meters')}'
                : '';
          }

          final approaching = tracks.any((t) => t.approaching);
          final modeStr = mode.label;

          final level = _distLevel(top?.dist);

          final semanticsLabel =
              '${S.get('lbl_object')}: $label$distM. '
              '${S.get('lbl_status')}: $distText, $dirText'
              '${approaching ? ", ${S.get('approaching')}" : ""}';

          return Semantics(
            label: semanticsLabel,
            container: true,
            child: ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusLine,
                          style: BagdarTypography.caption.copyWith(
                            color: BagdarOverlay.foreground,
                            shadows: BagdarOverlay.textShadows,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: BagdarSpacing.s),
                      _ModeChip(label: modeStr, colors: colors),
                    ],
                  ),
                  const SizedBox(height: BagdarSpacing.s),
                  Text(
                    '${S.get('lbl_object')}: $label$distM',
                    style: BagdarTypography.body.copyWith(
                      color: BagdarOverlay.foreground,
                      fontWeight: BagdarTypography.weightBold,
                      shadows: BagdarOverlay.textShadows,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: BagdarSpacing.s),
                  Row(
                    children: [
                      SemanticStatusBadge(
                        level: level,
                        label: distText,
                        onCamera: true,
                        markSize: 26,
                      ),
                      const SizedBox(width: BagdarSpacing.s),
                      Expanded(
                        child: Text(
                          approaching
                              ? '$dirText  ⚠ ${S.get('approaching')}'
                              : dirText,
                          style: BagdarTypography.caption.copyWith(
                            color: approaching
                                ? BagdarOverlay.statusFill(
                                    BagdarStatusLevel.caution, colors)
                                : BagdarOverlay.foreground,
                            fontWeight: approaching
                                ? BagdarTypography.weightBold
                                : BagdarTypography.weightMedium,
                            shadows: BagdarOverlay.textShadows,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (tracks.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: BagdarSpacing.xs),
                      child: Text(
                        '${S.get('lbl_total_objects')}: ${tracks.length}',
                        style: BagdarTypography.caption.copyWith(
                          color: BagdarOverlay.foregroundMuted,
                          shadows: BagdarOverlay.textShadows,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static int _sortKey(Track t) => t.dist == 'very close'
      ? 0
      : t.dist == 'close'
      ? 1
      : 2;

  static String _distLabel(String d) {
    if (d == 'very close') return S.get('dist_stop');
    if (d == 'close') return S.get('dist_attention');
    return S.get('dist_safe');
  }

  static BagdarStatusLevel _distLevel(String? d) {
    if (d == 'very close') return BagdarStatusLevel.danger;
    if (d == 'close') return BagdarStatusLevel.caution;
    return BagdarStatusLevel.clear;
  }
}

/// Compact signage chip showing the active mode in the panel header.
class _ModeChip extends StatelessWidget {
  final String label;
  final BagdarColors colors;

  const _ModeChip({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    final signal = BagdarOverlay.signal(colors);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: BagdarSpacing.s,
        vertical: BagdarSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: BagdarOverlay.scrimStrong,
        borderRadius: BorderRadius.circular(BagdarRadius.sharp),
        border: Border.all(color: signal, width: BagdarBorders.thin),
      ),
      child: Text(
        label.toUpperCase(),
        style: BagdarTypography.label.copyWith(
          color: signal,
          fontSize: 13,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

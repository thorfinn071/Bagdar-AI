import 'package:flutter/material.dart';

import '../../models/app_mode.dart';
import '../../models/strings.dart';
import '../../tracker/track.dart';
import '../../utils/distance_utils.dart';

class StatusPanel extends StatelessWidget {
  final String statusLine;
  final ValueNotifier<List<Track>> tracksNotifier;
  final int imgW, imgH;
  final String Function(String) ruLabel;
  final AppMode mode;

  const StatusPanel({
    super.key,
    required this.statusLine,
    required this.tracksNotifier,
    required this.imgW,
    required this.imgH,
    required this.ruLabel,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      margin:  const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.black.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(14),
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
            label = ruLabel(top.label);
            distText = _distLabel(top.dist);
            dirText = clockDir(top.x1, top.x2, imgW.toDouble());
            distM = top.distM > 0
                ? ' • ~${top.distM.toStringAsFixed(1)} ${S.get('approx_meters')}'
                : '';
          }

          final approaching = tracks.any((t) => t.approaching);
          final modeStr = mode.label;

          return Semantics(
            liveRegion: true,
            label: top == null
                ? S.get('path_clear_label')
                : '$label, $distText, $dirText',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(statusLine,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                  const Spacer(),
                  Text('[$modeStr]',
                      style: const TextStyle(
                          color: Colors.cyanAccent, fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                Text(
                  '${S.get('lbl_object')}: $label$distM',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${S.get('lbl_status')}: $distText • $dirText'
                  '${approaching ? " ⚠ ${S.get('approaching')}" : ""}',
                  style: TextStyle(
                    color: approaching ? Colors.orangeAccent : Colors.white70,
                    fontSize: 13,
                  ),
                ),
                if (tracks.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${S.get('lbl_total_objects')}: ${tracks.length}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static int _sortKey(Track t) =>
      t.dist == 'very close' ? 0 : t.dist == 'close' ? 1 : 2;

  static String _distLabel(String d) {
    if (d == 'very close') return S.get('dist_stop');
    if (d == 'close') return S.get('dist_attention');
    return S.get('dist_safe');
  }
}

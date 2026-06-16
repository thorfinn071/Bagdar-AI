import 'dart:math';

import 'package:flutter/material.dart';

import '../models/nav_models.dart';
import '../models/strings.dart';
import '../services/navigation_service.dart';
import '../theme/bagdar_theme.dart';
import '../theme/bagdar_tokens.dart';

class NavHud extends StatelessWidget {
  final NavState navState;
  final TransitNavPhase transitPhase;
  final RouteStep? currentStep;
  final int remainingMeters;
  final String destinationName;
  final double? compassHeading;
  final double? targetBearing;

  const NavHud({
    super.key,
    required this.navState,
    this.transitPhase = TransitNavPhase.done,
    this.currentStep,
    this.remainingMeters = 0,
    this.destinationName = '',
    this.compassHeading,
    this.targetBearing,
  });

  @override
  Widget build(BuildContext context) {
    if (navState == NavState.idle) return const SizedBox.shrink();

    final colors = BagdarTheme.colorsOf(context);
    final accent = _accentColor(colors);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(
            horizontal: BagdarSpacing.m,
            vertical: BagdarSpacing.s,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: BagdarSpacing.m,
            vertical: BagdarSpacing.m,
          ),
          decoration: BoxDecoration(
            color: BagdarOverlay.scrim,
            borderRadius: BorderRadius.circular(BagdarRadius.panel),
            border: Border.all(color: accent, width: BagdarBorders.thin),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildDirectionArrow(accent),
                  const SizedBox(width: BagdarSpacing.m),
                  Expanded(child: _buildInfo(accent)),
                ],
              ),
              if (destinationName.isNotEmpty) ...[
                const SizedBox(height: BagdarSpacing.s),
                Row(
                  children: [
                    Icon(Icons.place, color: accent, size: 18),
                    const SizedBox(width: BagdarSpacing.xs),
                    Expanded(
                      child: Text(
                        destinationName,
                        style: BagdarTypography.caption.copyWith(
                          color: BagdarOverlay.foreground,
                          shadows: BagdarOverlay.textShadows,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Over-camera-safe accent, distinct per transit phase. Colour is
  /// redundant with the maneuver icon + text, so it only needs to read on
  /// the dark scrim across all themes.
  Color _accentColor(BagdarColors colors) {
    if (transitPhase == TransitNavPhase.riding) {
      return BagdarOverlay.statusFill(BagdarStatusLevel.clear, colors);
    }
    if (transitPhase == TransitNavPhase.waitForBus) {
      return BagdarOverlay.statusFill(BagdarStatusLevel.caution, colors);
    }
    return BagdarOverlay.signal(colors);
  }

  Widget _buildDirectionArrow(Color accent) {
    double rotation = 0;
    IconData icon = Icons.navigation;

    if (currentStep != null) {
      switch (currentStep!.maneuver) {
        case Maneuver.turnLeft:
          icon = Icons.turn_left;
        case Maneuver.turnRight:
          icon = Icons.turn_right;
        case Maneuver.slightLeft:
          icon = Icons.turn_slight_left;
        case Maneuver.slightRight:
          icon = Icons.turn_slight_right;
        case Maneuver.uTurn:
          icon = Icons.u_turn_left;
        case Maneuver.arrive:
          icon = Icons.flag;
        case Maneuver.straight:
          icon = Icons.arrow_upward;
      }
    }

    if (compassHeading != null && targetBearing != null) {
      rotation = ((targetBearing! - compassHeading!) * pi / 180);
    }

    return Container(
      width: BagdarSpacing.tapMinimum,
      height: BagdarSpacing.tapMinimum,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: accent, width: BagdarBorders.thin),
      ),
      child: Transform.rotate(
        angle: rotation,
        child: Icon(icon, color: accent, size: 36),
      ),
    );
  }

  Widget _buildInfo(Color accent) {
    String mainText;
    String subText = '';

    if (navState == NavState.arrivedWalk) {
      mainText = S.get('nav_arrived_short').replaceAll('.', '');
    } else if (transitPhase == TransitNavPhase.waitForBus) {
      mainText = S.get('nav_waiting').replaceAll('.', '');
    } else if (transitPhase == TransitNavPhase.riding) {
      mainText = S.get('hud_riding');
      subText = '$remainingMeters ${S.get('approx_meters')}';
    } else if (currentStep != null) {
      mainText = _maneuverShort(currentStep!.maneuver);
      subText = '${currentStep!.distanceMeters} ${S.get('approx_meters')}';
    } else {
      mainText = '$remainingMeters ${S.get('approx_meters')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          mainText,
          style: BagdarTypography.title.copyWith(
            color: BagdarOverlay.foreground,
            shadows: BagdarOverlay.textShadows,
          ),
        ),
        if (subText.isNotEmpty)
          Text(
            subText,
            style: BagdarTypography.body.copyWith(
              color: accent,
              fontWeight: BagdarTypography.weightBold,
            ),
          ),
      ],
    );
  }

  String _maneuverShort(Maneuver m) {
    switch (m) {
      case Maneuver.straight:
        return '↑ ${S.get('straight')}';
      case Maneuver.turnLeft:
        return '← ${S.get('nav_left')}';
      case Maneuver.turnRight:
        return '→ ${S.get('nav_right')}';
      case Maneuver.slightLeft:
        return '↖ ${S.get('nav_slight_left')}';
      case Maneuver.slightRight:
        return '↗ ${S.get('nav_slight_right')}';
      case Maneuver.uTurn:
        return '↩ ${S.get('hud_uturn')}';
      case Maneuver.arrive:
        return '🏁 ${S.get('nav_arrive')}';
    }
  }
}

import 'dart:math';

import 'package:flutter/material.dart';

import '../models/nav_models.dart';
import '../models/strings.dart';
import '../services/navigation_service.dart';

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

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _accentColor, width: 2.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildDirectionArrow(),
                  const SizedBox(width: 12),
                  Expanded(child: _buildInfo()),
                ],
              ),
              if (destinationName.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place, color: _accentColor, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        destinationName,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
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

  Color get _accentColor {
    if (transitPhase == TransitNavPhase.riding) return Colors.orangeAccent;
    if (transitPhase == TransitNavPhase.waitForBus) return Colors.amberAccent;
    return Colors.cyanAccent;
  }

  Widget _buildDirectionArrow() {
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
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: _accentColor.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Transform.rotate(
        angle: rotation,
        child: Icon(icon, color: _accentColor, size: 36),
      ),
    );
  }

  Widget _buildInfo() {
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
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            shadows: [
              Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 4),
            ],
          ),
        ),
        if (subText.isNotEmpty)
          Text(
            subText,
            style: TextStyle(
              color: _accentColor,
              fontSize: 18,
              fontWeight: FontWeight.w600,
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

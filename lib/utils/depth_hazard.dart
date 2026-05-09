enum DepthHazardType {
  stepDown,
  stepUp,
  pothole,
  curb,
  lowCurb,
  deadZone,
  stairsDown,
  // OPT-14: detected when a periodic "stairs" depth signal drifts across
  // consecutive analyse() calls while the user is confidently stationary —
  // a signature of a moving escalator. Emitted at info level (haptic only)
  // so we avoid the critical spam that the plain stairs detector used to
  // generate every few seconds when the user was simply riding.
  escalatorRiding,
  // OPT-21: detected when the bottom-15% depth-band jumps closer than the
  // rolling baseline by ≥ _kNearFieldJumpThreshold while the user is
  // walking — a signature of a low obstacle (stroller, bollard, luggage)
  // moving into the blind zone below the camera FOV. Info/warning level
  // because the detection is geometric rather than semantic.
  nearFieldIntrusion,
  overhead,
  glassDoor,
  slippery,
  unknown,
}

enum HazardZone { left, centerLeft, center, centerRight, right }

class DepthHazard {
  final double midasScore;
  final DepthHazardType type;
  final HazardZone zone;
  final double coverage;

  const DepthHazard({
    required this.midasScore,
    required this.type,
    required this.zone,
    required this.coverage,
  });

  double get pan {
    switch (zone) {
      case HazardZone.left:
        return -0.9;
      case HazardZone.centerLeft:
        return -0.45;
      case HazardZone.center:
        return 0.0;
      case HazardZone.centerRight:
        return 0.45;
      case HazardZone.right:
        return 0.9;
    }
  }

  @override
  String toString() =>
      'DepthHazard(score=${midasScore.toStringAsFixed(2)}, '
      'type=$type, zone=$zone, cov=${coverage.toStringAsFixed(2)})';
}

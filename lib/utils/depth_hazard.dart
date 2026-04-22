enum DepthHazardType {
  stepDown,
  stepUp,
  pothole,
  curb,
  lowCurb,
  deadZone,
  stairsDown,
  
  
  
  
  
  escalatorRiding,
  
  
  
  
  
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

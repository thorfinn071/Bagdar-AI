enum SurfaceType {
  asphalt,
  concrete,
  pavingStones,
  gravel,
  dirt,
  grass,
  sand,
  unpaved,
  unknown,
}

enum HighwayType {
  footway,
  pedestrian,
  path,
  residential,
  livingStreet,
  service,
  tertiary,
  secondary,
  primary,
  trunk,
  motorway,
  steps,
  cycleway,
  unclassified,
  unknown,
}

class AccessibilityInfo {
  final SurfaceType surface;
  final bool tactilePaving;
  final bool sidewalk;
  final bool lit;
  final bool wheelchair;
  final HighwayType highway;

  const AccessibilityInfo({
    this.surface = SurfaceType.unknown,
    this.tactilePaving = false,
    this.sidewalk = false,
    this.lit = false,
    this.wheelchair = false,
    this.highway = HighwayType.unknown,
  });

  double get weightMultiplier {
    double w = 1.0;

    switch (highway) {
      case HighwayType.footway:
      case HighwayType.pedestrian:
        w *= 0.8;
      case HighwayType.path:
      case HighwayType.livingStreet:
        w *= 0.9;
      case HighwayType.residential:
      case HighwayType.service:
        w *= 1.0;
      case HighwayType.steps:
        w *= 1.4;
      case HighwayType.tertiary:
        w *= 1.1;
      case HighwayType.secondary:
        w *= 1.3;
      case HighwayType.primary:
        w *= 1.5;
      case HighwayType.cycleway:
        w *= 1.2;
      case HighwayType.trunk:
      case HighwayType.motorway:
        w *= 999.0;
      case HighwayType.unclassified:
      case HighwayType.unknown:
        w *= 1.0;
    }

    switch (surface) {
      case SurfaceType.asphalt:
      case SurfaceType.concrete:
      case SurfaceType.pavingStones:
        break;
      case SurfaceType.gravel:
        w *= 1.3;
      case SurfaceType.dirt:
      case SurfaceType.grass:
        w *= 1.5;
      case SurfaceType.sand:
        w *= 1.8;
      case SurfaceType.unpaved:
        w *= 1.4;
      case SurfaceType.unknown:
        w *= 1.05;
    }

    if (tactilePaving) w *= 0.85;
    if (sidewalk) w *= 0.9;
    if (lit) w *= 0.95;

    return w;
  }
}

class CHNode {
  final int id;
  final double lat;
  final double lng;
  final int level;

  const CHNode({
    required this.id,
    required this.lat,
    required this.lng,
    this.level = 0,
  });
}

class CHEdge {
  final int sourceId;
  final int targetId;
  final double weight;
  final double distanceMeters;
  final int streetNameIndex;
  final AccessibilityInfo accessibility;
  final bool isShortcut;
  final int? shortcutMiddleNode;

  const CHEdge({
    required this.sourceId,
    required this.targetId,
    required this.weight,
    required this.distanceMeters,
    this.streetNameIndex = -1,
    this.accessibility = const AccessibilityInfo(),
    this.isShortcut = false,
    this.shortcutMiddleNode,
  });
}

class CHGraph {
  final List<CHNode> nodes;
  final List<CHEdge> forwardEdges;
  final List<CHEdge> backwardEdges;
  final List<int> forwardOffsets;
  final List<int> backwardOffsets;
  final List<String> streetNames;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const CHGraph({
    required this.nodes,
    required this.forwardEdges,
    required this.backwardEdges,
    required this.forwardOffsets,
    required this.backwardOffsets,
    required this.streetNames,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  int get nodeCount => nodes.length;
  int get edgeCount => forwardEdges.length;

  bool containsPoint(double lat, double lng) =>
      lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  int findNearestNode(double lat, double lng) {
    int bestId = 0;
    double bestDist = double.infinity;
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final dLat = n.lat - lat;
      final dLng = n.lng - lng;
      final d = dLat * dLat + dLng * dLng;
      if (d < bestDist) {
        bestDist = d;
        bestId = i;
      }
    }
    return bestId;
  }

  Iterable<CHEdge> outEdges(int nodeId) {
    if (nodeId >= forwardOffsets.length - 1) return const [];
    final start = forwardOffsets[nodeId];
    final end = forwardOffsets[nodeId + 1];
    return forwardEdges.getRange(start, end);
  }

  Iterable<CHEdge> inEdges(int nodeId) {
    if (nodeId >= backwardOffsets.length - 1) return const [];
    final start = backwardOffsets[nodeId];
    final end = backwardOffsets[nodeId + 1];
    return backwardEdges.getRange(start, end);
  }

  String streetName(int index) {
    if (index < 0 || index >= streetNames.length) return '';
    return streetNames[index];
  }
}

const int chGraphMagic = 0x56474348;
const int chGraphVersion = 1;

class CHGraphHeader {
  final int magic;
  final int version;
  final int nodeCount;
  final int forwardEdgeCount;
  final int backwardEdgeCount;
  final int streetNameCount;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  const CHGraphHeader({
    required this.magic,
    required this.version,
    required this.nodeCount,
    required this.forwardEdgeCount,
    required this.backwardEdgeCount,
    required this.streetNameCount,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  bool get isValid => magic == chGraphMagic && version == chGraphVersion;

  static const int byteSize = 72;
}

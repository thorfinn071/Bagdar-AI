import 'local_scene_snapshot.dart';

enum RelativeSectorDirection { left, forward, right }

/// One coarse, non-metric sector in the camera-relative field of view.
///
/// Every numeric value is normalized to 0..1. No value in this contract is a
/// distance or width in metres.
class RelativePolarSector {
  final double observedFraction;
  final double occupancyProbability;
  final double traversabilityProbability;
  final double dropProbability;
  final double movingThreatRisk;
  final double unknownProbability;
  final double confidence;
  final Set<String> sourceMask;
  final List<String> hazardIds;
  final DateTime lastObservedAt;

  RelativePolarSector({
    required this.observedFraction,
    required this.occupancyProbability,
    required this.traversabilityProbability,
    required this.dropProbability,
    required this.movingThreatRisk,
    required this.unknownProbability,
    required this.confidence,
    required Set<String> sourceMask,
    required List<String> hazardIds,
    required this.lastObservedAt,
  }) : assert(_isProbability(observedFraction)),
       assert(_isProbability(occupancyProbability)),
       assert(_isProbability(traversabilityProbability)),
       assert(_isProbability(dropProbability)),
       assert(_isProbability(movingThreatRisk)),
       assert(_isProbability(unknownProbability)),
       assert(_isProbability(confidence)),
       sourceMask = Set.unmodifiable(sourceMask),
       hazardIds = List.unmodifiable(hazardIds);

  static bool _isProbability(double value) => value >= 0 && value <= 1;
}

/// Minimal relative scene representation for the first spatial-safety slice.
class RelativePolarGrid {
  final int revision;
  final DateTime at;
  final DateTime validUntil;
  final bool orientationValid;
  final bool sensingHealthy;
  final bool userMoving;
  final Map<RelativeSectorDirection, RelativePolarSector> sectors;

  RelativePolarGrid({
    required this.revision,
    required this.at,
    required this.validUntil,
    required this.orientationValid,
    required this.sensingHealthy,
    required this.userMoving,
    required Map<RelativeSectorDirection, RelativePolarSector> sectors,
  }) : assert(revision >= 0),
       assert(!validUntil.isBefore(at)),
       sectors = Map.unmodifiable(sectors) {
    assert(
      RelativeSectorDirection.values.every(this.sectors.containsKey),
      'RelativePolarGrid requires left, forward, and right sectors.',
    );
  }

  factory RelativePolarGrid.fromSnapshot(
    LocalSceneSnapshot snapshot, {
    required bool orientationValid,
    required bool userMoving,
  }) {
    if (snapshot.coordinateMode != SceneCoordinateMode.relative) {
      throw ArgumentError.value(
        snapshot.coordinateMode,
        'snapshot',
        'Relative planner input requires a relative scene snapshot.',
      );
    }
    final byId = <String, SceneSpatialElement>{
      for (final element in snapshot.polarSectors) element.id: element,
    };
    RelativePolarSector sector(String id) {
      final element = byId[id];
      if (element == null) {
        return RelativePolarSector(
          observedFraction: 0,
          occupancyProbability: 0,
          traversabilityProbability: 0,
          dropProbability: 0,
          movingThreatRisk: 0,
          unknownProbability: 1,
          confidence: 0,
          sourceMask: const <String>{},
          hazardIds: const <String>[],
          lastObservedAt: snapshot.at,
        );
      }
      final hazardIds = snapshot.hazardTracks
          .where((track) => track.elementId == id)
          .map((track) => track.id)
          .toList(growable: false);
      return RelativePolarSector(
        observedFraction: (1 - element.unknownProbability).clamp(0.0, 1.0),
        occupancyProbability: element.occupancyProbability,
        traversabilityProbability: element.traversabilityProbability,
        dropProbability: element.dropProbability,
        movingThreatRisk: element.movingThreatRisk,
        unknownProbability: element.unknownProbability,
        confidence: element.confidence,
        sourceMask: element.sourceMask,
        hazardIds: hazardIds,
        lastObservedAt: element.lastObservedAt,
      );
    }

    return RelativePolarGrid(
      revision: snapshot.revision,
      at: snapshot.at,
      validUntil: snapshot.validUntil,
      orientationValid: orientationValid,
      sensingHealthy: snapshot.sensorHealth.hasUsableProvider,
      userMoving: userMoving,
      sectors: <RelativeSectorDirection, RelativePolarSector>{
        RelativeSectorDirection.left: sector('left'),
        RelativeSectorDirection.forward: sector('forward'),
        RelativeSectorDirection.right: sector('right'),
      },
    );
  }

  RelativePolarSector sector(RelativeSectorDirection direction) =>
      sectors[direction]!;

  bool isStaleAt(DateTime now) => now.isAfter(validUntil);
}

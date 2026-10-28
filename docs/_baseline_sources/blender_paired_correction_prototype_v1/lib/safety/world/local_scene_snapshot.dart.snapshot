enum SceneCoordinateMode { metric, relative }

enum SceneSensorState { healthy, degraded, unavailable, stale }

class SceneMotionVector {
  final double lateral;
  final double forward;
  final bool metric;

  const SceneMotionVector({
    required this.lateral,
    required this.forward,
    required this.metric,
  }) : assert(lateral >= 0 || lateral < 0 || lateral == 0),
       assert(forward >= 0 || forward < 0 || forward == 0);
}

/// One immutable metric cell or relative polar sector.
class SceneSpatialElement {
  final String id;
  final double occupancyProbability;
  final double traversabilityProbability;
  final double dropProbability;
  final double movingThreatRisk;
  final double unknownProbability;
  final double confidence;
  final Set<String> sourceMask;
  final DateTime lastObservedAt;
  final SceneMotionVector? motionVector;
  final double? closingRate;

  SceneSpatialElement({
    required this.id,
    required this.occupancyProbability,
    required this.traversabilityProbability,
    required this.dropProbability,
    this.movingThreatRisk = 0,
    required this.unknownProbability,
    required this.confidence,
    required Set<String> sourceMask,
    required this.lastObservedAt,
    this.motionVector,
    this.closingRate,
  }) : assert(id != ''),
       assert(_isProbability(occupancyProbability)),
       assert(_isProbability(traversabilityProbability)),
       assert(_isProbability(dropProbability)),
       assert(_isProbability(movingThreatRisk)),
       assert(_isProbability(unknownProbability)),
       assert(_isProbability(confidence)),
       assert(
         closingRate == null ||
             closingRate >= 0 ||
             closingRate < 0 ||
             closingRate == 0,
       ),
       sourceMask = Set.unmodifiable(sourceMask);

  static bool _isProbability(double value) =>
      value.isFinite && value >= 0 && value <= 1;

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'id': id,
    'occupancyProbability': occupancyProbability,
    'traversabilityProbability': traversabilityProbability,
    'dropProbability': dropProbability,
    'movingThreatRisk': movingThreatRisk,
    'unknownProbability': unknownProbability,
    'confidence': confidence,
    'sourceMask': sourceMask.toList(growable: false)..sort(),
    'lastObservedAtUs': lastObservedAt.microsecondsSinceEpoch,
    'hasMotionVector': motionVector != null,
    'hasClosingRate': closingRate != null,
  };
}

class ObservedFieldSnapshot {
  final double observedFraction;
  final double unknownFraction;

  const ObservedFieldSnapshot({
    required this.observedFraction,
    required this.unknownFraction,
  }) : assert(observedFraction >= 0 && observedFraction <= 1),
       assert(unknownFraction >= 0 && unknownFraction <= 1);

  Map<String, double> toDiagnosticMap() => <String, double>{
    'observedFraction': observedFraction,
    'unknownFraction': unknownFraction,
  };
}

class HazardTrackSnapshot {
  final String id;
  final String? elementId;
  final double risk;
  final Set<String> sourceMask;
  final DateTime lastObservedAt;

  HazardTrackSnapshot({
    required this.id,
    this.elementId,
    required this.risk,
    required Set<String> sourceMask,
    required this.lastObservedAt,
  }) : assert(id != ''),
       assert(elementId == null || elementId != ''),
       assert(risk >= 0 && risk <= 1),
       sourceMask = Set.unmodifiable(sourceMask);
}

class MovingThreatSnapshot {
  final String id;
  final String? elementId;
  final double intersectionRisk;
  final double? closingRate;
  final DateTime lastObservedAt;

  const MovingThreatSnapshot({
    required this.id,
    this.elementId,
    required this.intersectionRisk,
    required this.lastObservedAt,
    this.closingRate,
  }) : assert(id != ''),
       assert(elementId == null || elementId != ''),
       assert(intersectionRisk >= 0 && intersectionRisk <= 1),
       assert(
         closingRate == null ||
             closingRate >= 0 ||
             closingRate < 0 ||
             closingRate == 0,
       );
}

class SceneSensorHealth {
  final Map<String, SceneSensorState> providers;

  SceneSensorHealth(Map<String, SceneSensorState> providers)
    : providers = Map.unmodifiable(providers);

  bool get hasUsableProvider =>
      providers.values.any((state) => state == SceneSensorState.healthy);

  Map<String, String> toDiagnosticMap() =>
      providers.map((provider, state) => MapEntry(provider, state.name));
}

/// Immutable scene boundary consumed by the future planner.
///
/// Metric cells and relative polar sectors are deliberately separate lists.
/// Exactly the list matching [coordinateMode] may be populated.
class LocalSceneSnapshot {
  final int revision;
  final DateTime at;
  final DateTime validUntil;
  final SceneCoordinateMode coordinateMode;
  final String spatialReferenceId;
  final double poseQuality;
  final ObservedFieldSnapshot observedField;
  final List<SceneSpatialElement> metricCells;
  final List<SceneSpatialElement> polarSectors;
  final List<HazardTrackSnapshot> hazardTracks;
  final List<MovingThreatSnapshot> movingThreats;
  final SceneSensorHealth sensorHealth;

  LocalSceneSnapshot({
    required this.revision,
    required this.at,
    required this.validUntil,
    required this.coordinateMode,
    required this.spatialReferenceId,
    required this.poseQuality,
    required this.observedField,
    required List<SceneSpatialElement> metricCells,
    required List<SceneSpatialElement> polarSectors,
    required List<HazardTrackSnapshot> hazardTracks,
    required List<MovingThreatSnapshot> movingThreats,
    required this.sensorHealth,
  }) : assert(revision >= 0),
       assert(!validUntil.isBefore(at)),
       assert(spatialReferenceId != ''),
       assert(poseQuality >= 0 && poseQuality <= 1),
       assert(
         coordinateMode == SceneCoordinateMode.metric
             ? polarSectors.isEmpty
             : metricCells.isEmpty,
         'Metric cells and relative polar sectors must never be mixed.',
       ),
       metricCells = List.unmodifiable(metricCells),
       polarSectors = List.unmodifiable(polarSectors),
       hazardTracks = List.unmodifiable(hazardTracks),
       movingThreats = List.unmodifiable(movingThreats);

  bool isStaleAt(DateTime now) => now.isAfter(validUntil);

  /// Privacy-safe summary. It excludes coordinates and track contents.
  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'revision': revision,
    'atUs': at.microsecondsSinceEpoch,
    'validUntilUs': validUntil.microsecondsSinceEpoch,
    'coordinateMode': coordinateMode.name,
    'spatialReferenceId': spatialReferenceId,
    'poseQuality': poseQuality,
    'observedField': observedField.toDiagnosticMap(),
    'spatialElementCount': coordinateMode == SceneCoordinateMode.metric
        ? metricCells.length
        : polarSectors.length,
    'hazardTrackCount': hazardTracks.length,
    'movingThreatCount': movingThreats.length,
    'sensorHealth': sensorHealth.toDiagnosticMap(),
  };
}

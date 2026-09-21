import 'local_scene_snapshot.dart';

enum SpatialEvidenceSource {
  geometry,
  depth,
  semantic,
  traversability,
  motion,
  acoustic,
  replay,
}

/// One bounded source contribution to a local scene element.
///
/// Null probabilities mean "this source has no opinion". They must never be
/// replaced by optimistic zeroes by an adapter.
class SpatialEvidence {
  final String elementId;
  final SceneCoordinateMode coordinateMode;
  final String sourceId;
  final SpatialEvidenceSource source;
  final DateTime observedAt;
  final DateTime validUntil;
  final double observedFraction;
  final double confidence;
  final double? occupancyProbability;
  final double? traversabilityProbability;
  final double? dropProbability;
  final double? movingThreatRisk;
  final double? unknownProbability;
  final List<String> hazardIds;
  final SceneMotionVector? motionVector;
  final double? closingRate;

  SpatialEvidence({
    required this.elementId,
    required this.coordinateMode,
    required this.sourceId,
    required this.source,
    required this.observedAt,
    required this.validUntil,
    required this.observedFraction,
    required this.confidence,
    this.occupancyProbability,
    this.traversabilityProbability,
    this.dropProbability,
    this.movingThreatRisk,
    this.unknownProbability,
    List<String> hazardIds = const <String>[],
    this.motionVector,
    this.closingRate,
  }) : hazardIds = List.unmodifiable(hazardIds) {
    if (elementId.isEmpty || sourceId.isEmpty) {
      throw ArgumentError('Spatial evidence IDs must be non-empty.');
    }
    if (validUntil.isBefore(observedAt)) {
      throw ArgumentError('Spatial evidence expires before observation.');
    }
    _requireProbability(observedFraction, 'observedFraction');
    _requireProbability(confidence, 'confidence');
    _requireOptionalProbability(occupancyProbability, 'occupancyProbability');
    _requireOptionalProbability(
      traversabilityProbability,
      'traversabilityProbability',
    );
    _requireOptionalProbability(dropProbability, 'dropProbability');
    _requireOptionalProbability(movingThreatRisk, 'movingThreatRisk');
    _requireOptionalProbability(unknownProbability, 'unknownProbability');
    if (closingRate != null && !closingRate!.isFinite) {
      throw ArgumentError.value(closingRate, 'closingRate', 'Must be finite.');
    }
  }

  bool isLiveAt(DateTime now) =>
      !observedAt.isAfter(now) && !validUntil.isBefore(now);

  static void _requireProbability(double value, String name) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, name, 'Must be from 0 to 1.');
    }
  }

  static void _requireOptionalProbability(double? value, String name) {
    if (value != null) _requireProbability(value, name);
  }
}

/// Typed boundary for a future segmentation/traversability provider.
///
/// Implementations emit positive surface evidence and explicit unknown/drop
/// evidence through [SpatialEvidence]. They do not mutate the world model and
/// cannot cancel geometry risk.
abstract interface class TraversabilityEvidenceSource {
  String get providerId;

  List<SpatialEvidence> evidenceForScene({
    required SceneCoordinateMode coordinateMode,
    required DateTime observedAt,
    required DateTime validUntil,
  });
}

class FusedSceneElement {
  final SceneSpatialElement element;
  final double observedFraction;
  final DateTime validUntil;
  final List<String> hazardIds;

  FusedSceneElement({
    required this.element,
    required this.observedFraction,
    required this.validUntil,
    required List<String> hazardIds,
  }) : hazardIds = List.unmodifiable(hazardIds);
}

class SceneFusionPolicy {
  final Duration freshFor;
  final Duration stateTtl;
  final double reliableConfidence;
  final double conflictUnknownFloor;
  final double confirmationBoost;

  const SceneFusionPolicy({
    this.freshFor = const Duration(milliseconds: 400),
    this.stateTtl = const Duration(milliseconds: 2400),
    this.reliableConfidence = 0.60,
    this.conflictUnknownFloor = 0.65,
    this.confirmationBoost = 0.08,
  }) : assert(reliableConfidence >= 0 && reliableConfidence <= 1),
       assert(conflictUnknownFloor >= 0 && conflictUnknownFloor <= 1),
       assert(confirmationBoost >= 0 && confirmationBoost <= 1);

  /// Fuses live evidence without allowing any source to subtract risk.
  /// Threats lose authority only through bounded time decay.
  FusedSceneElement? fuse({
    required String elementId,
    required SceneCoordinateMode coordinateMode,
    required FusedSceneElement? previous,
    required List<SpatialEvidence> evidence,
    required DateTime now,
  }) {
    final current = decay(previous, now);
    final live = evidence
        .where(
          (item) =>
              item.elementId == elementId &&
              item.coordinateMode == coordinateMode &&
              item.isLiveAt(now),
        )
        .toList(growable: false);
    if (current == null && live.isEmpty) return null;

    var observedFraction = current?.observedFraction ?? 0.0;
    var occupancy = current?.element.occupancyProbability ?? 0.0;
    var traversability = current?.element.traversabilityProbability ?? 0.0;
    var drop = current?.element.dropProbability ?? 0.0;
    var moving = current?.element.movingThreatRisk ?? 0.0;
    var unknown = current?.element.unknownProbability ?? 0.0;
    var confidence = current?.element.confidence ?? 0.0;
    var lastObservedAt = current?.element.lastObservedAt ?? now;
    var validUntil = current?.validUntil ?? now;
    var motionVector = current?.element.motionVector;
    var closingRate = current?.element.closingRate;
    var bestMotionConfidence = current?.element.confidence ?? 0.0;
    final sources = <String>{...?current?.element.sourceMask};
    final hazards = <String>{...?current?.hazardIds};
    final reliableOccupancy = <double>[];
    final confirmingSources = <String>{};

    for (final item in live) {
      sources.add(item.sourceId);
      hazards.addAll(item.hazardIds);
      if (item.observedFraction > observedFraction) {
        observedFraction = item.observedFraction;
      }
      if (item.occupancyProbability case final value?) {
        if (value > occupancy) occupancy = value;
        if (item.confidence >= reliableConfidence) {
          reliableOccupancy.add(value);
          if (value >= 0.50) confirmingSources.add(item.sourceId);
        }
      }
      if (item.traversabilityProbability case final value?) {
        final weighted = value * item.confidence;
        if (weighted > traversability) traversability = weighted;
      }
      if (item.dropProbability case final value?) {
        if (value > drop) drop = value;
        if (item.confidence >= reliableConfidence && value >= 0.35) {
          confirmingSources.add(item.sourceId);
        }
      }
      if (item.movingThreatRisk case final value?) {
        if (value > moving) moving = value;
      }
      if (item.unknownProbability case final value?) {
        if (value > unknown) unknown = value;
      }
      if (item.confidence > confidence) confidence = item.confidence;
      if (item.observedAt.isAfter(lastObservedAt)) {
        lastObservedAt = item.observedAt;
      }
      if (item.validUntil.isAfter(validUntil)) {
        validUntil = item.validUntil;
      }
      if (item.motionVector != null &&
          item.confidence >= bestMotionConfidence) {
        motionVector = item.motionVector;
        closingRate = item.closingRate;
        bestMotionConfidence = item.confidence;
      }
    }

    final coverageUnknown = 1 - observedFraction;
    if (coverageUnknown > unknown) unknown = coverageUnknown;
    if (_hasOccupancyConflict(reliableOccupancy) ||
        (occupancy >= 0.65 && traversability >= 0.70)) {
      if (conflictUnknownFloor > unknown) unknown = conflictUnknownFloor;
    }
    if (confirmingSources.length >= 2) {
      confidence = (confidence + confirmationBoost).clamp(0.0, 1.0);
    }

    return FusedSceneElement(
      element: SceneSpatialElement(
        id: elementId,
        occupancyProbability: occupancy,
        traversabilityProbability: traversability,
        dropProbability: drop,
        movingThreatRisk: moving,
        unknownProbability: unknown,
        confidence: confidence,
        sourceMask: sources,
        lastObservedAt: lastObservedAt,
        motionVector: motionVector,
        closingRate: closingRate,
      ),
      observedFraction: observedFraction,
      validUntil: validUntil,
      hazardIds: hazards.toList(growable: false)..sort(),
    );
  }

  /// Returns null after the bounded grace period. Before expiry, positive free
  /// evidence decays while unknown grows, so an old cell cannot stay free.
  FusedSceneElement? decay(FusedSceneElement? previous, DateTime now) {
    if (previous == null) return null;
    if (freshFor.isNegative || stateTtl <= freshFor) {
      throw StateError('Scene fusion decay durations are invalid.');
    }
    final age = now.difference(previous.element.lastObservedAt);
    if (age <= freshFor) return previous;
    if (age >= stateTtl) return null;
    final decayWindow = stateTtl - freshFor;
    final elapsed = age - freshFor;
    final authority = (1 - elapsed.inMicroseconds / decayWindow.inMicroseconds)
        .clamp(0.0, 1.0);
    final element = previous.element;
    return FusedSceneElement(
      element: SceneSpatialElement(
        id: element.id,
        occupancyProbability: element.occupancyProbability * authority,
        traversabilityProbability:
            element.traversabilityProbability * authority,
        dropProbability: element.dropProbability * authority,
        movingThreatRisk: element.movingThreatRisk * authority,
        unknownProbability: _max(element.unknownProbability, 1 - authority),
        confidence: element.confidence * authority,
        sourceMask: element.sourceMask,
        lastObservedAt: element.lastObservedAt,
        motionVector: authority >= 0.5 ? element.motionVector : null,
        closingRate: authority >= 0.5 ? element.closingRate : null,
      ),
      observedFraction: previous.observedFraction * authority,
      validUntil: previous.validUntil,
      hazardIds: previous.hazardIds,
    );
  }

  bool _hasOccupancyConflict(List<double> values) {
    if (values.length < 2) return false;
    var minimum = values.first;
    var maximum = values.first;
    for (final value in values.skip(1)) {
      if (value < minimum) minimum = value;
      if (value > maximum) maximum = value;
    }
    return minimum <= 0.20 && maximum >= 0.65;
  }

  double _max(double a, double b) => a > b ? a : b;
}

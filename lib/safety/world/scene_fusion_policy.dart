import '../perception/passage_clearance.dart';
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

  /// Coverage uncertainty in the same provider/session/transform and volume.
  /// Unclassified uncertainty and physical risks cannot be resolved this way.
  final String? unknownScopeId;
  final PassageClearanceResult? coverageResolution;
  final PassageEvaluationContext? passageContext;

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
    this.unknownScopeId,
    this.coverageResolution,
    this.passageContext,
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

  /// Opt-in camera experiment: immutable contributions retain capture clocks.
  final List<SpatialEvidence>? contributions;

  FusedSceneElement({
    required this.element,
    required this.observedFraction,
    required this.validUntil,
    required List<String> hazardIds,
    List<SpatialEvidence>? contributions,
  }) : hazardIds = List.unmodifiable(hazardIds),
       contributions = contributions == null
           ? null
           : List.unmodifiable(contributions);
}

class SceneFusionPolicy {
  final Duration freshFor;
  final Duration stateTtl;
  final double reliableConfidence;
  final double conflictUnknownFloor;
  final double confirmationBoost;
  final int maximumContributions;

  const SceneFusionPolicy({
    this.freshFor = const Duration(milliseconds: 400),
    this.stateTtl = const Duration(milliseconds: 2400),
    this.reliableConfidence = 0.60,
    this.conflictUnknownFloor = 0.65,
    this.confirmationBoost = 0.08,
    this.maximumContributions = 256,
  }) : assert(reliableConfidence >= 0 && reliableConfidence <= 1),
       assert(conflictUnknownFloor >= 0 && conflictUnknownFloor <= 1),
       assert(confirmationBoost >= 0 && confirmationBoost <= 1),
       assert(maximumContributions > 0);

  /// Threats lose authority only through bounded time decay. The opt-in camera
  /// path may resolve classified coverage gaps with a full typed certificate.
  FusedSceneElement? fuse({
    required String elementId,
    required SceneCoordinateMode coordinateMode,
    required FusedSceneElement? previous,
    required List<SpatialEvidence> evidence,
    required DateTime now,
    bool useIndependentEvidenceClocks = false,
  }) {
    if (useIndependentEvidenceClocks || previous?.contributions != null) {
      return _fuseIndependent(
        elementId,
        coordinateMode,
        previous,
        evidence,
        now,
      );
    }
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
    if (previous.contributions != null) {
      return _aggregateIndependent(
        previous.element.id,
        previous.contributions!,
        now,
      );
    }
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

  FusedSceneElement? _fuseIndependent(
    String id,
    SceneCoordinateMode mode,
    FusedSceneElement? previous,
    List<SpatialEvidence> incoming,
    DateTime now,
  ) {
    final records = <SpatialEvidence>[
      ...?previous?.contributions,
      // Switching a populated legacy element into this mode preserves risk.
      if (previous != null && previous.contributions == null)
        SpatialEvidence(
          elementId: id,
          coordinateMode: mode,
          sourceId: 'legacy-history',
          source: SpatialEvidenceSource.replay,
          observedAt: previous.element.lastObservedAt,
          validUntil: previous.validUntil,
          observedFraction: previous.observedFraction,
          confidence: previous.element.confidence,
          occupancyProbability: previous.element.occupancyProbability,
          traversabilityProbability: previous.element.traversabilityProbability,
          dropProbability: previous.element.dropProbability,
          movingThreatRisk: previous.element.movingThreatRisk,
          unknownProbability: previous.element.unknownProbability,
          hazardIds: previous.hazardIds,
        ),
    ].where((e) => now.difference(e.observedAt) < stateTtl).toList();
    final live = incoming
        .where(
          (e) =>
              e.elementId == id && e.coordinateMode == mode && e.isLiveAt(now),
        )
        .toList();
    for (final proof in live.where((e) => _canResolveCoverage(e, now))) {
      // A later full measurement resolves only its own earlier coverage gap.
      // Physical risks, unclassified unknown, and same-frame conflicts survive.
      records.removeWhere(
        (old) =>
            old.unknownScopeId == proof.unknownScopeId &&
            old.observedAt.isBefore(proof.observedAt) &&
            (old.occupancyProbability ?? 0) == 0 &&
            (old.dropProbability ?? 0) == 0 &&
            (old.movingThreatRisk ?? 0) == 0 &&
            old.hazardIds.isEmpty,
      );
    }
    records.addAll(live);
    if (records.length > maximumContributions) {
      // Never evict an obstacle to satisfy the memory bound. Overflow is an
      // explicit, bounded, unresolvable stop rather than optimistic truncation.
      records.clear();
      records.add(
        SpatialEvidence(
          elementId: id,
          coordinateMode: mode,
          sourceId: 'fusion-budget-exceeded',
          source: SpatialEvidenceSource.replay,
          observedAt: now,
          validUntil: now.add(stateTtl),
          observedFraction: 0,
          confidence: 1,
          occupancyProbability: 1,
          dropProbability: 1,
          movingThreatRisk: 1,
          unknownProbability: 1,
        ),
      );
    }
    return _aggregateIndependent(id, records, now);
  }

  bool _canResolveCoverage(SpatialEvidence e, DateTime now) {
    final proof = e.coverageResolution, context = e.passageContext;
    if (proof == null ||
        context == null ||
        e.unknownScopeId == null ||
        e.coordinateMode != SceneCoordinateMode.relative ||
        e.elementId != 'forward' ||
        e.source != SpatialEvidenceSource.depth ||
        e.observedFraction != 1 ||
        e.confidence < .99 ||
        e.traversabilityProbability != 1 ||
        e.unknownProbability != 0 ||
        (e.occupancyProbability ?? 0) != 0 ||
        context.nowUs != now.microsecondsSinceEpoch ||
        context.rgbTimestampUs != e.observedAt.microsecondsSinceEpoch ||
        !proof.appliesTo(request: proof.request, context: context)) {
      return false;
    }
    return proof.coversCameraRecoveryVolume;
  }

  FusedSceneElement? _aggregateIndependent(
    String id,
    List<SpatialEvidence> records,
    DateTime now,
  ) {
    if (freshFor.isNegative || stateTtl <= freshFor) {
      throw StateError('Scene fusion decay durations are invalid.');
    }
    final retained = records
        .where(
          (e) =>
              !e.observedAt.isAfter(now) &&
              now.difference(e.observedAt) < stateTtl,
        )
        .toList();
    if (retained.isEmpty) return null;
    final aged = <SpatialEvidence>[];
    for (final e in retained) {
      final age = now.difference(e.observedAt);
      final authority = age <= freshFor
          ? 1.0
          : (1 -
                    (age - freshFor).inMicroseconds /
                        (stateTtl - freshFor).inMicroseconds)
                .clamp(0.0, 1.0);
      // Expiry removes positive authority even when a different source is fresh.
      final positive = e.isLiveAt(now) ? authority : 0.0;
      aged.add(
        SpatialEvidence(
          elementId: id,
          coordinateMode: e.coordinateMode,
          sourceId: e.sourceId,
          source: e.source,
          observedAt: now,
          validUntil: now,
          observedFraction: e.observedFraction * positive,
          confidence: e.confidence * authority,
          occupancyProbability: e.occupancyProbability == null
              ? null
              : e.occupancyProbability! * authority,
          traversabilityProbability: e.traversabilityProbability == null
              ? null
              : e.traversabilityProbability! * positive,
          dropProbability: e.dropProbability == null
              ? null
              : e.dropProbability! * authority,
          movingThreatRisk: e.movingThreatRisk == null
              ? null
              : e.movingThreatRisk! * authority,
          unknownProbability: e.unknownProbability,
          hazardIds: e.hazardIds,
          motionVector: authority >= .5 ? e.motionVector : null,
          closingRate: authority >= .5 ? e.closingRate : null,
        ),
      );
    }
    // Recompute conflicts from separately aged risks; no shared clock refresh.
    final fused = fuse(
      elementId: id,
      coordinateMode: retained.first.coordinateMode,
      previous: null,
      evidence: aged,
      now: now,
    )!;
    return FusedSceneElement(
      element: SceneSpatialElement(
        id: id,
        occupancyProbability: fused.element.occupancyProbability,
        traversabilityProbability: fused.element.traversabilityProbability,
        dropProbability: fused.element.dropProbability,
        movingThreatRisk: fused.element.movingThreatRisk,
        unknownProbability: fused.element.unknownProbability,
        confidence: fused.element.confidence,
        sourceMask: fused.element.sourceMask,
        lastObservedAt: retained
            .map((e) => e.observedAt)
            .reduce((a, b) => a.isAfter(b) ? a : b),
        motionVector: fused.element.motionVector,
        closingRate: fused.element.closingRate,
      ),
      observedFraction: fused.observedFraction,
      validUntil: retained
          .map((e) => e.validUntil)
          .reduce((a, b) => a.isAfter(b) ? a : b),
      hazardIds: fused.hazardIds,
      contributions: retained,
    );
  }
}

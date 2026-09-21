import 'local_scene_snapshot.dart';
import 'metric_occupancy_grid.dart';
import 'scene_fusion_policy.dart';

enum LocalSceneUpdateStatus {
  accepted,
  rejectedOutOfOrder,
  rejectedCoordinateMode,
  rejectedInvalidEvidence,
  rejectedMetricCalibration,
}

class LocalSceneUpdate {
  final SceneCoordinateMode coordinateMode;
  final DateTime at;
  final DateTime validUntil;
  final double poseQuality;
  final SceneSensorHealth sensorHealth;
  final List<SpatialEvidence> evidence;
  final List<HazardTrackSnapshot> hazardTracks;
  final List<MovingThreatSnapshot> movingThreats;

  LocalSceneUpdate({
    required this.coordinateMode,
    required this.at,
    required this.validUntil,
    required this.poseQuality,
    required this.sensorHealth,
    required List<SpatialEvidence> evidence,
    List<HazardTrackSnapshot> hazardTracks = const <HazardTrackSnapshot>[],
    List<MovingThreatSnapshot> movingThreats = const <MovingThreatSnapshot>[],
  }) : evidence = List.unmodifiable(evidence),
       hazardTracks = List.unmodifiable(hazardTracks),
       movingThreats = List.unmodifiable(movingThreats) {
    if (validUntil.isBefore(at)) {
      throw ArgumentError('Local scene update expires before its timestamp.');
    }
    if (!poseQuality.isFinite || poseQuality < 0 || poseQuality > 1) {
      throw ArgumentError.value(poseQuality, 'poseQuality', 'Must be 0..1.');
    }
  }
}

class LocalSceneUpdateResult {
  final LocalSceneUpdateStatus status;
  final String reason;
  final LocalSceneSnapshot snapshot;

  const LocalSceneUpdateResult({
    required this.status,
    required this.reason,
    required this.snapshot,
  });

  bool get accepted => status == LocalSceneUpdateStatus.accepted;
}

/// Mutable, bounded world-model owner. Consumers only receive immutable
/// [LocalSceneSnapshot] values.
class LocalSceneModel {
  static const _relativeElementIds = <String>{'left', 'forward', 'right'};

  final SceneCoordinateMode coordinateMode;
  final SceneFusionPolicy fusionPolicy;
  final MetricGridCalibration? metricCalibration;

  final Map<String, FusedSceneElement> _elements =
      <String, FusedSceneElement>{};
  List<HazardTrackSnapshot> _hazardTracks = const <HazardTrackSnapshot>[];
  List<MovingThreatSnapshot> _movingThreats = const <MovingThreatSnapshot>[];
  SceneSensorHealth _sensorHealth = SceneSensorHealth(
    const <String, SceneSensorState>{'spatial': SceneSensorState.unavailable},
  );
  DateTime? _lastUpdateAt;
  DateTime? _sceneValidUntil;
  double _poseQuality = 0;
  int _revision = 0;

  LocalSceneModel.relative({this.fusionPolicy = const SceneFusionPolicy()})
    : coordinateMode = SceneCoordinateMode.relative,
      metricCalibration = null;

  LocalSceneModel.metric({
    required MetricGridCalibration calibration,
    this.fusionPolicy = const SceneFusionPolicy(),
  }) : coordinateMode = SceneCoordinateMode.metric,
       metricCalibration = calibration;

  int get revision => _revision;

  void reset() {
    _elements.clear();
    _hazardTracks = const <HazardTrackSnapshot>[];
    _movingThreats = const <MovingThreatSnapshot>[];
    _sensorHealth = SceneSensorHealth(const <String, SceneSensorState>{
      'spatial': SceneSensorState.unavailable,
    });
    _lastUpdateAt = null;
    _sceneValidUntil = null;
    _poseQuality = 0;
    _revision++;
  }

  /// Invalidates all spatial authority without representing the scene as an
  /// empty/free corridor. Used when a provider is lost or the decision-time
  /// TTL expires independently of frame callbacks.
  LocalSceneSnapshot invalidateToUnknown({
    required String providerId,
    required SceneSensorState providerState,
    required DateTime now,
  }) {
    _elements.clear();
    _hazardTracks = const <HazardTrackSnapshot>[];
    _movingThreats = const <MovingThreatSnapshot>[];
    _sensorHealth = SceneSensorHealth(<String, SceneSensorState>{
      providerId: providerState,
    });
    _poseQuality = 0;
    _lastUpdateAt = now;
    _sceneValidUntil = now;
    _revision++;
    return snapshotAt(now);
  }

  LocalSceneUpdateResult update(LocalSceneUpdate update) {
    final lastUpdateAt = _lastUpdateAt;
    if (lastUpdateAt != null && update.at.isBefore(lastUpdateAt)) {
      return _rejected(
        LocalSceneUpdateStatus.rejectedOutOfOrder,
        'update_precedes_current_scene',
        lastUpdateAt,
      );
    }
    if (update.coordinateMode != coordinateMode) {
      return _rejected(
        LocalSceneUpdateStatus.rejectedCoordinateMode,
        'coordinate_mode_mismatch',
        lastUpdateAt ?? update.at,
      );
    }
    final invalidReason = _validateEvidence(update.evidence, update.at);
    if (invalidReason != null) {
      return _rejected(
        invalidReason == 'metric_cell_outside_calibration'
            ? LocalSceneUpdateStatus.rejectedMetricCalibration
            : LocalSceneUpdateStatus.rejectedInvalidEvidence,
        invalidReason,
        lastUpdateAt ?? update.at,
      );
    }

    final evidenceByElement = <String, List<SpatialEvidence>>{};
    for (final item in update.evidence) {
      evidenceByElement.putIfAbsent(item.elementId, () => []).add(item);
    }
    final elementIds = <String>{..._elements.keys, ...evidenceByElement.keys};
    final next = <String, FusedSceneElement>{};
    for (final elementId in elementIds) {
      final fused = fusionPolicy.fuse(
        elementId: elementId,
        coordinateMode: coordinateMode,
        previous: _elements[elementId],
        evidence: evidenceByElement[elementId] ?? const <SpatialEvidence>[],
        now: update.at,
      );
      if (fused != null) next[elementId] = fused;
    }

    _elements
      ..clear()
      ..addAll(next);
    _hazardTracks = List.unmodifiable(update.hazardTracks);
    _movingThreats = List.unmodifiable(update.movingThreats);
    _sensorHealth = update.sensorHealth;
    _poseQuality = update.poseQuality;
    _lastUpdateAt = update.at;
    _sceneValidUntil = update.validUntil;
    _revision++;
    return LocalSceneUpdateResult(
      status: LocalSceneUpdateStatus.accepted,
      reason: 'accepted',
      snapshot: snapshotAt(update.at),
    );
  }

  LocalSceneSnapshot snapshotAt(DateTime now) {
    final snapshotAt = _lastUpdateAt ?? now;
    final validUntil = _sceneValidUntil ?? snapshotAt;
    final decayed = <String, FusedSceneElement>{};
    for (final entry in _elements.entries) {
      final value = fusionPolicy.decay(entry.value, now);
      if (value != null) decayed[entry.key] = value;
    }

    final spatialElements = coordinateMode == SceneCoordinateMode.relative
        ? _relativeElements(decayed, snapshotAt)
        : _metricElements(decayed);
    final observedFraction = coordinateMode == SceneCoordinateMode.relative
        ? _relativeElementIds
                  .map((id) => decayed[id]?.observedFraction ?? 0.0)
                  .reduce((a, b) => a + b) /
              _relativeElementIds.length
        : _metricObservedFraction(decayed);
    final unknownFraction = spatialElements.isEmpty
        ? 1.0
        : spatialElements
                  .map((element) => element.unknownProbability)
                  .reduce((a, b) => a + b) /
              spatialElements.length;

    return LocalSceneSnapshot(
      revision: _revision,
      at: snapshotAt,
      validUntil: validUntil,
      coordinateMode: coordinateMode,
      spatialReferenceId: coordinateMode == SceneCoordinateMode.metric
          ? metricCalibration!.calibrationId
          : 'camera-relative-v1',
      poseQuality: now.isAfter(validUntil) ? 0 : _poseQuality,
      observedField: ObservedFieldSnapshot(
        observedFraction: observedFraction.clamp(0.0, 1.0),
        unknownFraction: unknownFraction.clamp(0.0, 1.0),
      ),
      metricCells: coordinateMode == SceneCoordinateMode.metric
          ? spatialElements
          : const <SceneSpatialElement>[],
      polarSectors: coordinateMode == SceneCoordinateMode.relative
          ? spatialElements
          : const <SceneSpatialElement>[],
      hazardTracks: _liveHazards(now),
      movingThreats: _liveMovingThreats(now),
      sensorHealth: _sensorHealthAt(now, validUntil),
    );
  }

  LocalSceneUpdateResult _rejected(
    LocalSceneUpdateStatus status,
    String reason,
    DateTime snapshotTime,
  ) => LocalSceneUpdateResult(
    status: status,
    reason: reason,
    snapshot: snapshotAt(snapshotTime),
  );

  String? _validateEvidence(List<SpatialEvidence> evidence, DateTime at) {
    for (final item in evidence) {
      if (item.coordinateMode != coordinateMode) {
        return 'evidence_coordinate_mode_mismatch';
      }
      if (item.observedAt.isAfter(at)) return 'future_evidence';
      if (coordinateMode == SceneCoordinateMode.relative &&
          !_relativeElementIds.contains(item.elementId)) {
        return 'unknown_relative_sector';
      }
      if (coordinateMode == SceneCoordinateMode.metric) {
        final index = MetricCellIndex.tryParse(item.elementId);
        final calibration = metricCalibration;
        if (index == null ||
            calibration == null ||
            !calibration.contains(index)) {
          return 'metric_cell_outside_calibration';
        }
      }
    }
    return null;
  }

  List<SceneSpatialElement> _relativeElements(
    Map<String, FusedSceneElement> decayed,
    DateTime snapshotAt,
  ) => <String>['left', 'forward', 'right']
      .map((id) => decayed[id]?.element ?? _unknownElement(id, snapshotAt))
      .toList(growable: false);

  List<SceneSpatialElement> _metricElements(
    Map<String, FusedSceneElement> decayed,
  ) {
    final result =
        decayed.values.map((value) => value.element).toList(growable: false)
          ..sort((a, b) => a.id.compareTo(b.id));
    MetricOccupancyGrid(calibration: metricCalibration!, cells: result);
    return result;
  }

  double _metricObservedFraction(Map<String, FusedSceneElement> decayed) {
    final calibration = metricCalibration!;
    if (decayed.isEmpty) return 0;
    final observed = decayed.values.fold<double>(
      0,
      (sum, value) => sum + value.observedFraction,
    );
    return (observed / calibration.cellCount).clamp(0.0, 1.0);
  }

  SceneSpatialElement _unknownElement(String id, DateTime at) =>
      SceneSpatialElement(
        id: id,
        occupancyProbability: 0,
        traversabilityProbability: 0,
        dropProbability: 0,
        movingThreatRisk: 0,
        unknownProbability: 1,
        confidence: 0,
        sourceMask: const <String>{},
        lastObservedAt: at,
      );

  List<HazardTrackSnapshot> _liveHazards(DateTime now) => _hazardTracks
      .where(
        (track) => now.difference(track.lastObservedAt) < fusionPolicy.stateTtl,
      )
      .toList(growable: false);

  List<MovingThreatSnapshot> _liveMovingThreats(DateTime now) => _movingThreats
      .where(
        (track) => now.difference(track.lastObservedAt) < fusionPolicy.stateTtl,
      )
      .toList(growable: false);

  SceneSensorHealth _sensorHealthAt(DateTime now, DateTime validUntil) {
    if (!now.isAfter(validUntil)) return _sensorHealth;
    return SceneSensorHealth(
      _sensorHealth.providers.map(
        (provider, state) => MapEntry(
          provider,
          state == SceneSensorState.unavailable
              ? SceneSensorState.unavailable
              : SceneSensorState.stale,
        ),
      ),
    );
  }
}

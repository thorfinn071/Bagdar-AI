import 'dart:math' as math;

import 'package:bagdar/safety/perception/passage_clearance.dart';

/// A COMPLETE-SCENE geometry oracle for software experiments only. This input
/// knows surfaces hidden from the camera. It is not a phone depth provider.
/// It reads bounds only, never scene IDs, semantic masks or expected actions.
class SyntheticPassageSource implements PassageClearanceEvidenceSource {
  final PassageCalibration calibration;
  final int frameId;
  final int sessionGeneration;
  final int capturedAtUs;
  final int producedAtUs;
  final List<PassageSection> _sections;

  SyntheticPassageSource({
    required Map<String, dynamic> geometry,
    required this.calibration,
    required this.frameId,
    required this.sessionGeneration,
    required this.capturedAtUs,
    required this.producedAtUs,
    required double lateralCenterM,
  }) : _sections = List.unmodifiable(_measure(geometry, lateralCenterM));

  @override
  String get providerId => calibration.providerId;

  @override
  PassageClearanceObservation observationFor(
    PassageEvaluationContext context,
  ) => PassageClearanceObservation(
    providerId: providerId,
    modelId: calibration.modelId,
    modelHash: calibration.modelHash,
    preprocessId: calibration.preprocessId,
    calibrationId: calibration.id,
    referenceFrameId: calibration.referenceFrameId,
    rgbTransformId: calibration.transformId,
    depthTransformId: calibration.transformId,
    timestampDomain: calibration.timestampDomain,
    units: PassageUnits.metricMeters,
    sessionGeneration: sessionGeneration,
    frameId: frameId,
    rgbTimestampUs: capturedAtUs,
    depthTimestampUs: capturedAtUs,
    producedAtUs: producedAtUs,
    providerHealthy: true,
    sections: _sections,
  );
}

class _Bounds {
  final double left, right, start, end, bottom, top;

  _Bounds(Map<String, dynamic> value, double error, {required bool floor})
    : left = _number(value, 'leftM') + (floor ? error : -error),
      right = _number(value, 'rightM') + (floor ? -error : error),
      start = _number(value, 'startM') + (floor ? error : -error),
      end = _number(value, 'endM') + (floor ? -error : error),
      bottom = _number(value, 'bottomM') - error,
      top = _number(value, 'topM') + error {
    if (left >= right || start >= end || bottom >= top) {
      throw const FormatException('Invalid conservative geometry bounds');
    }
  }

  bool overlaps(double z0, double z1) => start <= z1 && end >= z0;
}

double _number(Map<String, dynamic> value, String key) {
  final raw = value[key];
  if (raw is! num || !raw.isFinite) {
    throw FormatException('Missing or invalid geometry measurement: $key');
  }
  return raw.toDouble();
}

List<_Bounds> _bounds(
  Map<String, dynamic> geometry,
  String key,
  double error, {
  required bool floor,
}) {
  final raw = geometry[key];
  if (raw is! List || raw.length > 4096) {
    throw FormatException('Missing or oversized geometry list: $key');
  }
  return [
    for (final item in raw)
      _Bounds(item as Map<String, dynamic>, error, floor: floor),
  ];
}

List<PassageSection> _measure(Map<String, dynamic> geometry, double center) {
  if (geometry['scope'] != 'complete_scene_geometry_oracle') {
    throw const FormatException('Camera samples cannot certify entire volumes');
  }
  final error = _number(geometry, 'measurementErrorM');
  final domain = geometry['domain'] as Map<String, dynamic>;
  final left = _number(domain, 'leftM') + error;
  final right = _number(domain, 'rightM') - error;
  final start = _number(domain, 'startM') + error;
  final end = _number(domain, 'endM') - error;
  final top = _number(domain, 'topM') - error;
  if (error < 0 ||
      !center.isFinite ||
      center <= left ||
      center >= right ||
      start < 0 ||
      start >= end ||
      top <= 0) {
    throw const FormatException('Invalid oracle coverage domain');
  }
  final occupied = _bounds(geometry, 'occupiedBounds', error, floor: false);
  final floors = _bounds(geometry, 'floorBounds', error, floor: true);
  // Partition at EVERY conservative object/floor boundary; no fixed sparse
  // scan can miss a thin obstacle or an interval between sampled endpoints.
  final edges = <double>{start, end};
  for (final bounds in [...occupied, ...floors]) {
    if (bounds.start > start && bounds.start < end) edges.add(bounds.start);
    if (bounds.end > start && bounds.end < end) edges.add(bounds.end);
  }
  if (edges.length > 129) {
    throw const FormatException('Oracle profile exceeds section budget');
  }
  final sorted = edges.toList()..sort();
  final sections = <PassageSection>[];
  for (var i = 0; i < sorted.length - 1; i++) {
    final z0 = sorted[i], z1 = sorted[i + 1];
    final obstacles = occupied.where((item) => item.overlaps(z0, z1));
    var x0 = left, x1 = right;
    var blocked = false;
    // Ground-connected occupancy cuts the lateral interval. A suspended
    // object instead limits headroom; it cannot disappear above floor rays.
    for (final item in obstacles) {
      if (item.top <= 0 || item.bottom > 0.02) continue;
      if (item.left <= center && item.right >= center) {
        blocked = true;
      } else if (item.right < center) {
        x0 = math.max(x0, item.right);
      } else if (item.left > center) {
        x1 = math.min(x1, item.left);
      }
    }
    var headroom = top;
    for (final item in obstacles) {
      if (item.bottom <= 0.02 || item.right < x0 || item.left > x1) continue;
      headroom = math.min(headroom, math.max(0, item.bottom));
    }
    // A floor certifies a closed interval only if its entire forward span
    // covers it. Merge lateral coverage; don't bridge cracks by interpolation.
    final support =
        floors.where((item) => item.start <= z0 && item.end >= z1).toList()
          ..sort((a, b) => a.left.compareTo(b.left));
    var covered = x0;
    for (final patch in support) {
      if (patch.left > covered) break;
      covered = math.max(covered, patch.right);
    }
    final floorObserved = covered >= x1;
    // Use the FLOOR TOP bounds, including adjacent closed-interval endpoints.
    // Headroom is relative to the highest possible local floor, not world z=0.
    // The full height range conservatively bounds both upward/downward steps.
    double? floorUpper, floorLower;
    for (final patch in floors.where((item) => item.overlaps(z0, z1))) {
      if (patch.right < x0 || patch.left > x1) continue;
      floorUpper = floorUpper == null
          ? patch.top
          : math.max(floorUpper, patch.top);
      final lower = patch.top - 2 * error;
      floorLower = floorLower == null ? lower : math.min(floorLower, lower);
    }
    final floorRange = floorUpper == null || floorLower == null
        ? null
        : floorUpper - floorLower;
    sections.add(
      PassageSection(
        forwardStartM: z0,
        forwardEndM: z1,
        state: blocked
            ? PassageSectionState.blocked
            : floorObserved
            ? PassageSectionState.measured
            : PassageSectionState.unknown,
        bodyObservedFraction: 1,
        floorObservedFraction: floorObserved ? 1 : 0,
        confidence: 1,
        leftBoundaryUpperM: x0,
        rightBoundaryLowerM: x1,
        headroomLowerBoundM: floorObserved && floorUpper != null
            ? math.max(0, headroom - floorUpper)
            : null,
        floorRiseUpperBoundM: floorObserved ? floorRange : null,
        floorDropUpperBoundM: floorObserved ? floorRange : null,
      ),
    );
  }
  return sections;
}

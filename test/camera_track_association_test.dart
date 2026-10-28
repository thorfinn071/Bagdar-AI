import 'dart:ui';
import 'dart:math' as math;

import 'package:bagdar/models/depth_frame.dart';
import 'package:bagdar/core/core_health_coordinator.dart';
import 'package:bagdar/models/generic_obstacle.dart';
import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/camera_track_association.dart';
import 'package:bagdar/safety/perception/observation_header.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/passage_clearance_shadow.dart';
import 'package:bagdar/safety/runtime/spatial_safety_runtime.dart';
import 'package:bagdar/safety/planning/safety_action.dart';
import 'package:bagdar/safety/world/generic_geometry_scene_adapter.dart';
import 'package:bagdar/safety/world/local_scene_model.dart';
import 'package:bagdar/safety/world/local_scene_snapshot.dart';
import 'package:bagdar/tracker/generic_obstacle_tracker.dart';
import 'package:bagdar/utils/depth_hazard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_visible_passage_fixture.dart';

const _stamp = 1000000;
const _rotation = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0];
const _cal = PassageCalibration(
  id: 'c',
  providerId: 'metric',
  modelId: 'visible',
  modelHash: 'metric-hash',
  preprocessId: 'whole-pixel',
  referenceFrameId: 'synthetic-walking-frame-v1',
  transformId: 't',
  timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
  metricScaleValidated: true,
  alignmentValidated: true,
  floorReferenceValidated: true,
);
ObservationHeader _header({
  int frame = 1,
  int stamp = _stamp,
  String preprocess = 'rgb01-chw-256-nearest-stretch-no-crop-v1',
}) => ObservationHeader(
  providerId: 'ncnn',
  modelId: 'midas-small-ncnn',
  modelHash: 'ncnn-hash',
  preprocessId: preprocess,
  sessionGeneration: 1,
  frameId: frame,
  sourceTimestampUs: stamp,
  producedAtUs: stamp + 1000,
  transformId: 't',
  confidence: 1,
  health: ObservationHealth.healthy,
);
CameraVisibleDepthFrame _frame({
  double x = 2,
  double z = 3,
  double height = 1.45,
  double fy = 20,
}) => CameraVisibleDepthFrame(
  width: 4,
  height: 4,
  frameId: 1,
  capturedAtUs: _stamp,
  sessionGeneration: 1,
  fx: 20,
  fy: fy,
  cx: 2,
  cy: 2,
  errorM: 0,
  poseQuality: 1,
  cameraId: 'camera',
  modelHash: 'metric-hash',
  transformId: 't',
  referenceFrameId: visibleRequest.referenceFrameId,
  units: PassageUnits.metricMeters,
  providerHealthy: true,
  rotation: _rotation,
  originM: [x, 0, height],
  rangeM: List.generate(
    16,
    (i) =>
        z *
        math.sqrt(
          1 +
              ((i % 4 + .5 - 2) / 20) * ((i % 4 + .5 - 2) / 20) +
              ((i ~/ 4 + .5 - 2) / fy) * ((i ~/ 4 + .5 - 2) / fy),
        ),
  ),
  freeZLowerM: List.filled(16, z),
  surfaceZUpperM: List.filled(16, z),
  valid: List.filled(16, true),
);

CameraTrackAssociator _source(
  CameraVisibleDepthFrame f, {
  CameraVisibleDepthFrame? rgb,
  ObservationHeader? header,
  int now = _stamp + 2000,
  double? rgbFx,
  String relativeModelHash = 'ncnn-hash',
}) {
  final g = rgb ?? f, h = header ?? _header();
  return CameraTrackAssociator(
    input: CameraTrackAssociationInput(
      rgbHeader: h,
      depth: f,
      imageGeometry: CameraTrackImageGeometry(
        cameraId: g.cameraId,
        width: g.width,
        height: g.height,
        fx: rgbFx ?? g.fx,
        fy: g.fy,
        cx: g.cx,
        cy: g.cy,
        rotation: g.rotation,
        originM: g.originM,
      ),
    ),
    header: h,
    calibration: _cal,
    request: visibleRequest,
    nowUs: now,
    relativeModelHash: relativeModelHash,
  );
}

CameraTrackAssociation _associate(
  CameraTrackAssociator source, {
  bool observed = true,
  bool motion = false,
  int stamp = _stamp,
  CameraComponentSupport? support,
  int? count,
  List<double> bounds = const [0, 0, 1, 1],
}) => source.associate(
  normalizedBounds: bounds,
  trackTimestampUs: stamp,
  currentlyObserved: observed,
  motionOrSemanticRisk: motion,
  support: support,
  expectedPixelCount: count,
);

void main() {
  test('different RGB projection cannot localize', () {
    expect(
      _associate(_source(_frame(), rgbFx: 21)).relation,
      CameraTrackRelation.unknown,
    );
  });
  test('unpinned relative model cannot localize', () {
    expect(
      _associate(_source(_frame(), relativeModelHash: 'wrong')).relation,
      CameraTrackRelation.unknown,
    );
  });
  for (final fault in [
    'none',
    'disabled',
    'missing-depth',
    'partial',
    'conflict',
    'moving-track',
    'bad-pose',
    'stale-depth',
  ]) {
    test(
      'runtime $fault requires full proof and matching stationary track',
      () {
        final runtime =
            SpatialSafetyRuntime(
              healthCoordinator: CoreHealthCoordinator(),
              shadowPassage: PassageClearanceShadowConfiguration(
                calibration: _cal,
                request: visibleRequest,
                policy: visibleSinglePolicy,
                requireCameraEvidence: true,
                associateCameraTracks: fault != 'disabled',
                cameraTrackModelHash: 'ncnn-hash',
              ),
            )..beginSession(
              1,
              now: DateTime.fromMicrosecondsSinceEpoch(_stamp - 1),
            );
        SpatialRuntimeResult? result;
        for (var frame = 1; frame <= 3; frame++) {
          final stamp = _stamp + (frame - 1) * 200000,
              header = _header(frame: frame, stamp: stamp);
          final depth = copyVisibleFrame(
            _frame(),
            frameId: frame,
            timestamp: fault == 'stale-depth' ? stamp - 1 : stamp,
          );
          final input = _source(depth, header: header).input;
          const o = GenericObstacleObservation(
            geometry: ObstacleGeometry.broadSurface,
            zone: HazardZone.center,
            normalizedBounds: Rect.fromLTWH(0, 0, 1, 1),
            corridorOverlap: 1,
            confidence: 1,
            relativeProximity: 1,
            source: DepthProviderKind.ncnnRelative,
          );
          final track = GenericObstacleTrack(
            id: 1,
            last: o,
            hits: 3,
            misses: 0,
            age: 3,
            proximityHist: fault == 'moving-track' ? [.5, 1] : [1],
            metricHist: [null],
            timestampUsHist: [stamp],
            confirmed: true,
          );
          final state = fault == 'conflict'
              ? PassageSectionState.conflicting
              : fault == 'partial'
              ? PassageSectionState.unknown
              : PassageSectionState.measured;
          result = runtime.ingestGenericGeometry(
            header: header,
            detection: const GenericObstacleDetectResult(
              observations: [o],
              rejectReason: ObstacleRejectReason.none,
              detectorQuality: 1,
              groundConfidence: 1,
              unknownProbabilityFloor: .65,
              unknownReasons: [
                ObstacleUnknownReason.groundModelDisagreement,
              ],
            ),
            tracks: [track],
            now: DateTime.fromMicrosecondsSinceEpoch(stamp + 2000),
            orientationValid: true,
            userMoving: frame == 3,
            poseQuality: fault == 'bad-pose' ? .4 : 1,
            cameraTrackInput: fault == 'missing-depth' ? null : input,
            passageObservation: PassageClearanceObservation(
              providerId: _cal.providerId,
              modelId: _cal.modelId,
              modelHash: _cal.modelHash,
              preprocessId: _cal.preprocessId,
              calibrationId: _cal.id,
              referenceFrameId: _cal.referenceFrameId,
              rgbTransformId: _cal.transformId,
              depthTransformId: _cal.transformId,
              timestampDomain: _cal.timestampDomain,
              units: PassageUnits.metricMeters,
              sessionGeneration: 1,
              frameId: frame,
              rgbTimestampUs: stamp,
              depthTimestampUs: stamp,
              producedAtUs: stamp + 1000,
              providerHealthy: true,
              sections: [
                PassageSection(
                  forwardStartM: .2,
                  forwardEndM: 3.5,
                  state: state,
                  bodyObservedFraction: state == PassageSectionState.measured
                      ? 1
                      : 0,
                  floorObservedFraction: 1,
                  confidence: 1,
                  leftBoundaryUpperM: -.45,
                  rightBoundaryLowerM: .45,
                  headroomLowerBoundM: 1.8,
                  floorRiseUpperBoundM: .05,
                  floorDropUpperBoundM: .05,
                ),
              ],
            ),
          );
          expect(result.submittedAction!.delivery, SafetyActionDelivery.shadow);
          expect(runtime.arbiter.active, isNull);
        }
        if (fault == 'none') {
          expect(
            result!.decision!.action.kind,
            SafetyActionKind.continueForward,
          );
          final expired = runtime.tick(
            now: DateTime.fromMicrosecondsSinceEpoch(_stamp + 950000),
            userMoving: true,
            orientationValid: true,
          );
          expect(
            expired.decision!.action.kind,
            isNot(SafetyActionKind.continueForward),
          );
          final lost = runtime.noteMissingObservation(
            providerId: 'ncnn',
            providerState: SceneSensorState.unavailable,
            reason: 'lost',
            now: DateTime.fromMicrosecondsSinceEpoch(_stamp + 1000000),
            userMoving: true,
            orientationValid: true,
          );
          expect(
            lost.decision!.action.kind,
            isNot(SafetyActionKind.continueForward),
          );
        } else {
          expect(
            result!.decision!.action.kind,
            isNot(SafetyActionKind.continueForward),
          );
        }
      },
    );
  }
  test(
    'whole first-surface footprints outside lateral volume are localized',
    () {
      final r = _associate(_source(_frame()));
      expect(r.relation, CameraTrackRelation.outsidePassage);
      expect(r.checkedPixels, 16);
    },
  );
  for (final x in [0.0, .44, .46]) {
    test('inside/boundary surface at x=$x retains risk', () {
      expect(
        _associate(_source(_frame(x: x))).relation,
        CameraTrackRelation.intersectsPassage,
      );
    });
  }
  test('near obstacle before requested .2m cannot be excluded', () {
    expect(
      _associate(_source(_frame(x: 0, z: .1))).relation,
      CameraTrackRelation.intersectsPassage,
    );
  });
  test(
    'bounded ground can localize a residual without certifying headroom',
    () {
      expect(
        _associate(_source(_frame(x: 0, height: .001, fy: 1000))).relation,
        CameraTrackRelation.outsidePassage,
      );
      expect(
        _associate(_source(_frame(x: 0, height: -.3, fy: 1000))).relation,
        CameraTrackRelation.intersectsPassage,
      );
    },
  );
  test('a missing pixel prevents complete exclusion', () {
    final f = _frame(), valid = [...f.valid]..[0] = false;
    expect(
      _associate(_source(copyVisibleFrame(f, valid: valid))).relation,
      CameraTrackRelation.unknown,
    );
  });
  test('subpixel first return and unbounded surface do not disappear', () {
    final f = _frame(x: 0);
    expect(
      _associate(
        _source(
          copyVisibleFrame(
            f,
            lower: List.filled(16, .1),
            upper: List.filled(16, double.nan),
          ),
        ),
      ).relation,
      CameraTrackRelation.unknown,
    );
  });
  test('contradictory lower/upper/centre bounds remain unknown', () {
    final f = _frame();
    expect(
      _associate(
        _source(copyVisibleFrame(f, lower: List.filled(16, 4))),
      ).relation,
      CameraTrackRelation.unknown,
    );
  });
  test(
    'unbounded first return can be excluded only by an entire outward frustum',
    () {
      final outside = _frame();
      final far = _frame(x: 0, z: 4);
      for (final f in [outside, far]) {
        final result = _associate(
          _source(copyVisibleFrame(f, upper: List.filled(16, double.nan))),
          bounds: f == outside ? const [.75, 0, 1, 1] : const [0, 0, 1, 1],
        );
        expect(result.relation, CameraTrackRelation.outsidePassage);
        expect(result.excludedUnboundedPixels, f == outside ? 8 : 16);
      }
      final inward = _frame(x: .6);
      expect(
        _associate(
          _source(copyVisibleFrame(inward, upper: List.filled(16, double.nan))),
        ).relation,
        CameraTrackRelation.unknown,
      );
    },
  );
  final faults =
      <String, CameraVisibleDepthFrame Function(CameraVisibleDepthFrame)>{
        'frame': (f) => copyVisibleFrame(f, frameId: 2),
        'session': (f) => copyVisibleFrame(f, session: 2),
        'capture': (f) => copyVisibleFrame(f, timestamp: _stamp - 1),
        'transform': (f) => copyVisibleFrame(f, transform: 'bad'),
        'model': (f) => copyVisibleFrame(f, modelHash: 'bad'),
        'reference': (f) => copyVisibleFrame(f, referenceFrame: 'bad'),
        'provider': (f) => copyVisibleFrame(f, healthy: false),
        'pose-quality': (f) => copyVisibleFrame(f, pose: .5),
        'nonmetric': (f) =>
            copyVisibleFrame(f, units: PassageUnits.relativeProximity),
        'invalid-rotation': (f) =>
            copyVisibleFrame(f, rotation: List.filled(9, 0)),
        'different-origin': (f) => copyVisibleFrame(f, origin: [3, 0, 1.45]),
        'different-valid-pose': (f) =>
            copyVisibleFrame(f, rotation: [-1, 0, 0, 0, 0, 1, 0, 1, 0]),
      };
  for (final fault in faults.entries) {
    test('${fault.key} mismatch cannot exclude a track', () {
      final rgb = _frame();
      expect(
        _associate(_source(fault.value(rgb), rgb: rgb)).relation,
        CameraTrackRelation.unknown,
      );
    });
  }
  for (final now in [_stamp - 1, _stamp + 100001]) {
    test('future/stale frame at $now remains unknown', () {
      expect(
        _associate(_source(_frame(), now: now)).relation,
        CameraTrackRelation.unknown,
      );
    });
  }
  test('crop/preprocessing mismatch is rejected', () {
    expect(
      _associate(
        _source(_frame(), header: _header(preprocess: 'crop')),
      ).relation,
      CameraTrackRelation.unknown,
    );
  });
  test('missed or older track cannot use current depth', () {
    expect(
      _associate(_source(_frame()), observed: false).relation,
      CameraTrackRelation.unknown,
    );
    expect(
      _associate(_source(_frame()), stamp: _stamp - 1).relation,
      CameraTrackRelation.unknown,
    );
  });
  test('motion/semantic priority preserves the track', () {
    expect(
      _associate(_source(_frame()), motion: true).relation,
      CameraTrackRelation.unknown,
    );
  });
  for (final indices in [
    [0, 0],
    [-1],
    [65536],
    [0],
  ]) {
    test('incomplete/invalid support $indices cannot exclude', () {
      final support = CameraComponentSupport(
        width: 256,
        height: 256,
        cropTopFraction: 0,
        capturedAtUs: _stamp,
        indices: indices,
      );
      expect(
        _associate(_source(_frame()), support: support, count: 2).relation,
        CameraTrackRelation.unknown,
      );
    });
  }
  test(
    'support retains holes while pixel footprints include registration margin',
    () {
      final indices = [0, 255, 65280, 65535];
      final support = CameraComponentSupport(
        width: 256,
        height: 256,
        cropTopFraction: 0,
        capturedAtUs: _stamp,
        indices: indices,
      );
      final r = _associate(_source(_frame()), support: support, count: 4);
      expect(r.relation, CameraTrackRelation.outsidePassage);
      expect(r.checkedPixels, 4);
      expect(() => support.indices.add(2), throwsUnsupportedError);
    },
  );
  test('association does not erase previously ingested physical history', () {
    final model = LocalSceneModel.relative();
    final track = GenericObstacleTrack(
      id: 1,
      last: const GenericObstacleObservation(
        geometry: ObstacleGeometry.broadSurface,
        zone: HazardZone.center,
        normalizedBounds: Rect.fromLTWH(0, 0, 1, 1),
        corridorOverlap: 1,
        confidence: 1,
        relativeProximity: 1,
        source: DepthProviderKind.ncnnRelative,
      ),
      hits: 3,
      misses: 0,
      age: 3,
      proximityHist: [1],
      metricHist: [null],
      timestampUsHist: [_stamp],
      confirmed: true,
    );
    final detection = GenericObstacleDetectResult(
      observations: [track.last],
      rejectReason: ObstacleRejectReason.none,
      detectorQuality: 1,
      groundConfidence: 1,
      surfaceEvidence: CorridorSurfaceEvidence.unavailable,
      unknownProbabilityFloor: 0,
      unknownReasons: const [],
    );
    LocalSceneUpdateResult ingest({CameraTrackAssociator? source}) =>
        model.ingestGenericGeometry(
          header: _header(),
          detection: detection,
          tracks: [track],
          at: DateTime.fromMicrosecondsSinceEpoch(_stamp + 2000),
          validUntil: DateTime.fromMicrosecondsSinceEpoch(_stamp + 300000),
          poseQuality: 1,
          enablePassageRecovery: true,
          cameraTrackAssociator: source,
        );
    expect(
      ingest().snapshot.polarSectors
          .firstWhere((e) => e.id == 'forward')
          .occupancyProbability,
      1,
    );
    expect(
      ingest(source: _source(_frame())).snapshot.polarSectors
          .firstWhere((e) => e.id == 'forward')
          .occupancyProbability,
      1,
    );
    final fresh = LocalSceneModel.relative().ingestGenericGeometry(
      header: _header(),
      detection: detection,
      tracks: [track],
      at: DateTime.fromMicrosecondsSinceEpoch(_stamp + 2000),
      validUntil: DateTime.fromMicrosecondsSinceEpoch(_stamp + 300000),
      poseQuality: 1,
      enablePassageRecovery: true,
      cameraTrackAssociator: _source(_frame()),
    );
    expect(
      fresh.snapshot.polarSectors
          .firstWhere((e) => e.id == 'forward')
          .occupancyProbability,
      0,
    );
  });
}

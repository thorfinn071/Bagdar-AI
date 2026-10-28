import 'dart:convert';
import 'dart:math' as math;

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'harness/unknown_volume_diagnostics.dart';

const _request = PassageClearanceRequest(
  referenceFrameId: 'unit-walking',
  lateralCenterM: 0,
  widthM: .6,
  headroomM: 1.2,
  forwardStartM: 2,
  forwardEndM: 2.2,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);
const _calibration = PassageCalibration(
  id: 'unit',
  providerId: 'unit',
  modelId: 'unit',
  modelHash: 'unit',
  preprocessId: 'unit',
  referenceFrameId: 'unit-walking',
  transformId: 'unit',
  timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
  metricScaleValidated: true,
  alignmentValidated: true,
  floorReferenceValidated: true,
);

CameraVisibleDepthFrame _frame({double depthZ = 5, double fx = 4}) =>
    CameraVisibleDepthFrame(
      width: 8,
      height: 8,
      frameId: 1,
      capturedAtUs: 1000000,
      sessionGeneration: 1,
      fx: fx,
      fy: fx,
      cx: 4,
      cy: 4,
      errorM: 0,
      poseQuality: 1,
      cameraId: 'unit',
      modelHash: 'unit',
      transformId: 'unit',
      referenceFrameId: 'unit-walking',
      units: PassageUnits.metricMeters,
      providerHealthy: true,
      rotation: [1, 0, 0, 0, 0, 1, 0, -1, 0],
      originM: [0, 0, 1],
      rangeM: [
        for (var y = 0; y < 8; y++)
          for (var x = 0; x < 8; x++)
            depthZ *
                math.sqrt(
                  1 +
                      math.pow((x + .5 - 4) / fx, 2) +
                      math.pow((y + .5 - 4) / fx, 2),
                ),
      ],
      freeZLowerM: List.filled(64, depthZ),
      surfaceZUpperM: List.filled(64, depthZ),
      valid: List.filled(64, true),
    );

PassageEvaluationContext _context({int ageUs = 2000}) =>
    PassageEvaluationContext(
      nowUs: 1000000 + ageUs,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      sessionGeneration: 1,
      frameId: 1,
      rgbTimestampUs: 1000000,
      transformId: 'unit',
    );

Map<String, Object?> _inspect(
  CameraVisibleDepthFrame frame, {
  int ageUs = 2000,
}) {
  final source = CameraPassageClearanceSource(
    calibration: _calibration,
    request: _request,
    frames: [frame],
    producedAtUs: 1001000,
  );
  final observation = source.observationFor(_context(ageUs: ageUs))!;
  final before = [
    source.certifiedBodyBoxes,
    source.unknownBodyBoxes,
    jsonEncode(
      observation.sections
          .map(
            (s) => [
              s.state.name,
              s.bodyObservedFraction,
              s.floorObservedFraction,
            ],
          )
          .toList(),
    ),
    jsonEncode(frame.valid),
    jsonEncode(frame.rangeM),
  ];
  final result = UnknownVolumeDiagnostics(frame: frame, request: _request)
      .inspect(
        source: source,
        observation: observation,
        context: _context(ageUs: ageUs),
      );
  expect([
    source.certifiedBodyBoxes,
    source.unknownBodyBoxes,
    jsonEncode(
      observation.sections
          .map(
            (s) => [
              s.state.name,
              s.bodyObservedFraction,
              s.floorObservedFraction,
            ],
          )
          .toList(),
    ),
    jsonEncode(frame.valid),
    jsonEncode(frame.rangeM),
  ], before);
  return result;
}

void main() {
  test('complete cell map matches the producer and never grants authority', () {
    final result = _inspect(_frame());
    expect(result['replicaMatchesSource'], true);
    expect(result['canAuthorizeMovement'], false);
    expect(result['canCertifyFreeSpace'], false);
    final body = (result['counts'] as Map)['body'] as Map;
    expect(
      body['observed'],
      (result['nx'] as int) * (result['ny'] as int) * (result['nz'] as int),
    );
    expect(body['outsideFrustum'], 0);
    expect(result['unknownBodyBoxes'], 0);
    // Good body coverage does not stand in for a measured floor.
    expect(
      ((result['counts'] as Map)['floor'] as Map)['floorHeightUncertain'],
      greaterThan(0),
    );
  });

  test('frustum gaps remain geometric gaps even with dense valid depth', () {
    final result = _inspect(_frame(fx: 100));
    expect(
      ((result['counts'] as Map)['body'] as Map)['outsideFrustum'],
      greaterThan(0),
    );
    expect((result['occlusionWitnessCells'] as Map)['body'], 0);
    expect(((result['outsideSides'] as Map)['body'] as Map).isNotEmpty, true);
  });

  for (final fault in [
    'invalidPixel',
    'missingPixelBounds',
    'incompatiblePixelBounds',
  ]) {
    test('independent return failure remains visible: $fault', () {
      final frame = _frame();
      final bad = copyVisibleFrame(
        frame,
        valid: fault == 'invalidPixel' ? List.filled(64, false) : null,
        lower: fault == 'missingPixelBounds'
            ? List.filled(64, double.nan)
            : fault == 'incompatiblePixelBounds'
            ? List.filled(64, 8)
            : null,
      );
      final result = _inspect(bad);
      expect(((result['counts'] as Map)['body'] as Map)[fault], greaterThan(0));
      expect((result['occlusionWitnessCells'] as Map)['body'], 0);
    });
  }

  test('positive occlusion witness requires a ray intersecting the cell', () {
    final frame = _frame(depthZ: 1);
    final diagnostic = UnknownVolumeDiagnostics(
      frame: frame,
      request: _request,
    );
    final witness = diagnostic.occlusionWitness([-.3, .3, 2, 2.2, .7, 1.3]);
    expect(witness, isNotNull);
    expect(
      (witness!['firstReturnUpperZ'] as double) + (witness['errorM'] as double),
      lessThan(witness['rayEntryZ'] as double),
    );
    expect(witness['clearanceAuthority'], false);
    expect(diagnostic.rayInterval([-.3, .3, 2, 2.2, .7, 1.3], 0, 0), isNull);
    final result = _inspect(frame);
    expect((result['occlusionWitnessCells'] as Map)['body'], greaterThan(0));
    expect(result['unknownBodyBoxes'], greaterThan(0));
  });

  test(
    'insufficient lower bound and wide intervals do not prove occlusion',
    () {
      final frame = copyVisibleFrame(
        _frame(depthZ: 1),
        upper: List.filled(64, 3),
      );
      final diagnostic = UnknownVolumeDiagnostics(
        frame: frame,
        request: _request,
      );
      expect(diagnostic.occlusionWitness([-.3, .3, 2, 2.2, .7, 1.3]), isNull);
      final result = _inspect(frame);
      expect(
        ((result['counts'] as Map)['body']
            as Map)['firstReturnIntersectsVolume'],
        greaterThan(0),
      );
      expect((result['occlusionWitnessCells'] as Map)['body'], 0);
    },
  );

  test('missing upper bounds cannot create a positive occlusion witness', () {
    final frame = copyVisibleFrame(
      _frame(depthZ: 1),
      upper: List.filled(64, double.nan),
    );
    expect(
      UnknownVolumeDiagnostics(
        frame: frame,
        request: _request,
      ).occlusionWitness([-.3, .3, 2, 2.2, .7, 1.3]),
      isNull,
    );
  });

  test('error bounds that cross the cell prevent an occlusion conclusion', () {
    final frame = copyVisibleFrame(_frame(depthZ: 1), error: 2);
    expect(
      UnknownVolumeDiagnostics(
        frame: frame,
        request: _request,
      ).occlusionWitness([-.3, .3, 2, 2.2, .7, 1.3]),
      isNull,
    );
  });

  test(
    'zero-height floor intersection is tested without thickening the floor',
    () {
      final f = _frame(depthZ: 1);
      final frame = copyVisibleFrame(
        f,
        rotation: [1, 0, 0, 0, -1, 0, 0, 0, -1],
        origin: [0, 2.1, 1],
      );
      final diagnostic = UnknownVolumeDiagnostics(
        frame: frame,
        request: _request,
      );
      expect(diagnostic.rayInterval([-.3, .3, 2, 2.2, 0, 0], 4, 4), isNull);
      expect(diagnostic.rayInterval([-1, 1, 1, 3, 0, 0], 4, 4), [1, 1]);
    },
  );

  for (final fault in ['stale', 'relative', 'model', 'provider']) {
    test(
      'unavailable context cannot publish an empty or apparently clear map: $fault',
      () {
        final frame = copyVisibleFrame(
          _frame(),
          units: fault == 'relative' ? PassageUnits.relativeProximity : null,
          modelHash: fault == 'model' ? 'foreign' : null,
          healthy: fault == 'provider' ? false : null,
        );
        expect(
          () => _inspect(frame, ageUs: fault == 'stale' ? 100001 : 2000),
          throwsStateError,
        );
      },
    );
  }
}

import 'package:bagdar/safety/perception/camera_passage_clearance_source.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/perception/single_camera_observability.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;

CameraVisibleDepthFrame opticalFrame({double focal = 2}) =>
    CameraVisibleDepthFrame(
      width: 4,
      height: 4,
      frameId: 1,
      capturedAtUs: 1000000,
      sessionGeneration: 1,
      fx: focal,
      fy: focal,
      cx: 2,
      cy: 2,
      errorM: 0,
      poseQuality: 1,
      cameraId: 'camera',
      modelHash: 'metric',
      transformId: 'transform',
      referenceFrameId: 'walking',
      units: PassageUnits.metricMeters,
      providerHealthy: true,
      rotation: [1, 0, 0, 0, 0, 1, 0, -1, 0],
      originM: [0, 0, 1],
      rangeM: List.filled(16, double.nan),
      freeZLowerM: List.filled(16, double.nan),
      surfaceZUpperM: List.filled(16, double.nan),
      valid: List.filled(16, false),
    );

PassageClearanceRequest opticalRequest({
  double start = .2,
  double end = 3.5,
  double centre = 0,
}) => PassageClearanceRequest(
  referenceFrameId: 'walking',
  lateralCenterM: centre,
  widthM: 1,
  headroomM: 1.95,
  forwardStartM: start,
  forwardEndM: end,
  maximumFloorRiseM: .05,
  maximumFloorDropM: .05,
);

PassageCalibration opticalCalibration({
  bool metric = true,
  bool aligned = true,
  bool floor = true,
}) => PassageCalibration(
  id: 'calibration',
  providerId: 'provider',
  modelId: 'model',
  modelHash: 'metric',
  preprocessId: 'whole-pixel',
  referenceFrameId: 'walking',
  transformId: 'transform',
  timestampDomain: PassageTimestampDomain.elapsedRealtimeMicroseconds,
  metricScaleValidated: metric,
  alignmentValidated: aligned,
  floorReferenceValidated: floor,
);

PassageEvaluationContext opticalContext({
  int age = 2000,
  PassageTimestampDomain clock =
      PassageTimestampDomain.elapsedRealtimeMicroseconds,
}) => PassageEvaluationContext(
  nowUs: 1000000 + age,
  timestampDomain: clock,
  sessionGeneration: 1,
  frameId: 1,
  rgbTimestampUs: 1000000,
  transformId: 'transform',
);

void main() {
  const preflight = SingleCameraObservabilityPreflight();
  SingleCameraObservability assess({
    CameraVisibleDepthFrame? frame,
    PassageCalibration? calibration,
    PassageClearanceRequest? request,
    PassageEvaluationContext? context,
  }) => preflight.assess(
    frame: frame ?? opticalFrame(),
    calibration: calibration ?? opticalCalibration(),
    request: request ?? opticalRequest(),
    context: context ?? opticalContext(),
  );

  test('closed-form 90-degree frustum retains one metre near gap', () {
    final result = assess();
    expect(result.visibleStartM, closeTo(1, 1e-6));
    expect(result.visibleEndM, 3.5);
    expect(result.entireRequestInView, false);
    expect(result.canAuthorizeMovement, false);
  });
  test(
    'ideal wide frustum with every depth missing cannot certify free space',
    () {
      final result = assess(frame: opticalFrame(focal: .2));
      expect(result.entireRequestInView, true);
      expect(result.canCertifyFreeSpace, false);
      expect(result.canAuthorizeMovement, false);
    },
  );
  test('shortening distance cannot remove near blind volume', () {
    final result = assess(request: opticalRequest(end: .8));
    expect(result.visibleStartM, isNull);
    expect(result.entireRequestInView, false);
  });
  test(
    'far-only frustum fit remains a different request without authority',
    () {
      final result = assess(request: opticalRequest(start: 1.1));
      expect(result.entireRequestInView, true);
      expect(result.canAuthorizeMovement, false);
    },
  );
  test('off-centre corridor includes complete lateral edges', () {
    final result = assess(request: opticalRequest(centre: 1.5));
    expect(result.visibleStartM, closeTo(2, 1e-6));
  });
  test('backwards camera has no forward visibility interval', () {
    final result = assess(
      frame: copyVisibleFrame(
        opticalFrame(),
        rotation: [-1, 0, 0, 0, 0, -1, 0, -1, 0],
      ),
    );
    expect(result.inputsAdmitted, true);
    expect(result.visibleStartM, isNull);
  });
  test('100 ms accepted but 100001 us and future captures unavailable', () {
    expect(assess(context: opticalContext(age: 100000)).inputsAdmitted, true);
    for (final age in [-1, 100001]) {
      expect(assess(context: opticalContext(age: age)).inputsAdmitted, false);
    }
  });
  for (final failure in {
    'relative': copyVisibleFrame(
      opticalFrame(),
      units: PassageUnits.relativeProximity,
    ),
    'pose': copyVisibleFrame(opticalFrame(), pose: .89),
    'provider': copyVisibleFrame(opticalFrame(), healthy: false),
    'reflection': copyVisibleFrame(
      opticalFrame(),
      rotation: [-1, 0, 0, 0, 0, 1, 0, -1, 0],
    ),
    'session': copyVisibleFrame(opticalFrame(), session: 2),
    'frame': copyVisibleFrame(opticalFrame(), frameId: 2),
    'transform': copyVisibleFrame(opticalFrame(), transform: 'foreign'),
    'model': copyVisibleFrame(opticalFrame(), modelHash: 'foreign'),
    'reference': copyVisibleFrame(opticalFrame(), referenceFrame: 'foreign'),
  }.entries) {
    test('unavailable inputs: ${failure.key}', () {
      final result = assess(frame: failure.value);
      expect(result.inputsAdmitted, false);
      expect(result.visibleStartM, isNull);
      expect(result.canAuthorizeMovement, false);
    });
  }
  test('all metric calibration declarations and clock binding required', () {
    for (final calibration in [
      opticalCalibration(metric: false),
      opticalCalibration(aligned: false),
      opticalCalibration(floor: false),
    ]) {
      expect(assess(calibration: calibration).inputsAdmitted, false);
    }
    expect(
      assess(
        context: opticalContext(
          clock: PassageTimestampDomain.utcEpochMicroseconds,
        ),
      ).inputsAdmitted,
      false,
    );
  });
  test('invalid and nonfinite requests do not expose metric distances', () {
    for (final request in [
      opticalRequest(start: -1),
      opticalRequest(end: .2),
      opticalRequest(centre: double.nan),
      opticalRequest(end: double.infinity),
    ]) {
      final result = assess(request: request);
      expect(result.inputsAdmitted, false);
      expect(result.visibleStartM, isNull);
    }
  });
}

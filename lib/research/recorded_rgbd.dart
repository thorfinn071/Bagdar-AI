import 'dart:math' as math;
import 'dart:typed_data';

import '../safety/perception/camera_passage_clearance_source.dart';
import '../safety/perception/passage_clearance.dart';
import '../safety/perception/single_camera_observability.dart';

/// Research data only. Native source times remain separate from replay clocks.
/// Immutable copies prevent a later buffer reuse from changing this frame.
class RecordedRgbdFrame {
  final String recordingId, sourceIdentity, deviceModel, trackingState;
  final int frameId, sourceTimestampUs, width, height;
  final Float32List axisDepthM;
  final Uint8List confidence, validity;
  final List<double> rgbIntrinsics, cameraTransform;
  final int rgbWidth, rgbHeight;

  RecordedRgbdFrame({
    required this.recordingId,
    required this.sourceIdentity,
    required this.deviceModel,
    required this.trackingState,
    required this.frameId,
    required this.sourceTimestampUs,
    required this.width,
    required this.height,
    required this.rgbWidth,
    required this.rgbHeight,
    required Float32List axisDepthM,
    required Uint8List confidence,
    required Uint8List validity,
    required List<double> rgbIntrinsics,
    required List<double> cameraTransform,
  }) : axisDepthM = Float32List.fromList(axisDepthM).asUnmodifiableView(),
       confidence = Uint8List.fromList(confidence).asUnmodifiableView(),
       validity = Uint8List.fromList(validity).asUnmodifiableView(),
       rgbIntrinsics = List.unmodifiable(rgbIntrinsics),
       cameraTransform = List.unmodifiable(cameraTransform) {
    if (recordingId.isEmpty ||
        sourceIdentity.isEmpty ||
        deviceModel.isEmpty ||
        frameId <= 0 ||
        sourceTimestampUs < 0 ||
        width <= 0 ||
        height <= 0 ||
        width * height > 1048576 ||
        rgbWidth <= 0 ||
        rgbHeight <= 0 ||
        axisDepthM.length != width * height ||
        validity.length != width * height ||
        (confidence.isNotEmpty && confidence.length != width * height) ||
        confidence.any((v) => v > 2) ||
        validity.any((v) => v > 1) ||
        rgbIntrinsics.length != 9 ||
        cameraTransform.length != 16 ||
        rgbIntrinsics.any((v) => !v.isFinite) ||
        cameraTransform.any((v) => !v.isFinite) ||
        rgbIntrinsics[0] <= 0 ||
        rgbIntrinsics[4] <= 0 ||
        rgbWidth * height != rgbHeight * width ||
        !['normal', 'limited', 'notAvailable'].contains(trackingState)) {
      throw const FormatException('Invalid recorded RGB-D frame.');
    }
    for (var i = 0; i < axisDepthM.length; i++) {
      if ((validity[i] == 1) != (axisDepthM[i].isFinite && axisDepthM[i] > 0)) {
        throw const FormatException(
          'Validity does not preserve invalid depth.',
        );
      }
    }
    _requireRigid(_columnToRow(cameraTransform));
  }

  bool get hasSamples => trackingState == 'normal' && confidence.isNotEmpty;
  bool isHighConfidence(int index) =>
      hasSamples && validity[index] == 1 && confidence[index] == 2;
  bool get hasWholePixelBounds => false;
}

/// Deliberately artificial epoch for the existing offline runtime interfaces.
/// It preserves source intervals; it never measures native capture-to-feedback.
class RecordedReplayClock {
  final String recordingId;
  final int firstSourceUs;
  static const anchorUs = 1000000;
  static const mode = 'artificial_replay_epoch_preserving_source_intervals';
  const RecordedReplayClock(this.recordingId, this.firstSourceUs);

  int timestamp(RecordedRgbdFrame frame) {
    if (frame.recordingId != recordingId ||
        frame.sourceTimestampUs < firstSourceUs) {
      throw const FormatException('Foreign session or source clock rollback.');
    }
    return anchorUs + frame.sourceTimestampUs - firstSourceUs;
  }
}

/// Empirical geometry can be described for diagnostics, but sceneDepth centre
/// samples cannot establish the whole-pixel bounds required by the producer.
/// This version has no constructor that silently promotes empirical fit to
/// physical sensor/clock/whole-volume certification.
class PhysicalEvidenceProfile {
  final String id, recordingId;
  final List<double>? diagnosticWorldToWalking;
  final double? empiricalSampleErrorM;
  PhysicalEvidenceProfile({
    required this.id,
    required this.recordingId,
    List<double>? diagnosticWorldToWalking,
    this.empiricalSampleErrorM,
  }) : diagnosticWorldToWalking = diagnosticWorldToWalking == null
           ? null
           : List.unmodifiable(diagnosticWorldToWalking) {
    if (id.isEmpty ||
        recordingId.isEmpty ||
        (empiricalSampleErrorM != null &&
            (!empiricalSampleErrorM!.isFinite || empiricalSampleErrorM! < 0))) {
      throw const FormatException('Invalid physical evidence profile.');
    }
    if (diagnosticWorldToWalking != null) {
      _requireRigid(diagnosticWorldToWalking);
    }
  }

  bool get metricErrorBoundsValidated => false;
  bool get physicalAlignmentValidated => false;
  bool get floorReferenceValidated => false;
  bool get clockBindingValidated => false;
  bool get wholePixelBoundsValidated => false;
  bool get canAuthorizeMovement => false;
}

/// Single current frame. No previous-frame cache, labels, fitted geometry or
/// confidence values can become a clearance certificate in this adapter.
class RecordedPassageEvidenceSource implements PassageClearanceEvidenceSource {
  final RecordedRgbdFrame frame;
  final RecordedReplayClock clock;
  final PhysicalEvidenceProfile profile;
  final PassageClearanceRequest request;
  final int producedAtUs;
  static const maximumAgeUs = 100000;

  RecordedPassageEvidenceSource({
    required this.frame,
    required this.clock,
    required this.profile,
    required this.request,
    required this.producedAtUs,
  }) {
    if (profile.recordingId != frame.recordingId ||
        clock.recordingId != frame.recordingId) {
      throw const FormatException('Calibration/frame session mismatch.');
    }
    clock.timestamp(frame);
  }

  @override
  String get providerId => 'recorded-arkit-scene-depth';
  String get transformId => '${frame.recordingId}:native:${frame.frameId}';

  PassageCalibration get calibration => PassageCalibration(
    id: profile.id,
    providerId: providerId,
    modelId: 'arkit-scene-depth-sdk-estimate',
    modelHash: frame.sourceIdentity,
    preprocessId: 'native-axis-metre-samples-no-fill-v1',
    referenceFrameId: request.referenceFrameId,
    transformId: transformId,
    timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
    metricScaleValidated: false,
    alignmentValidated: false,
    floorReferenceValidated: false,
  );

  List<String> reasonsAt(int nowUs) => [
    if (!frame.hasSamples) 'depth_confidence_or_tracking_unavailable',
    if (nowUs < clock.timestamp(frame)) 'future_frame',
    if (nowUs - clock.timestamp(frame) > maximumAgeUs) 'stale_frame',
    if (producedAtUs < clock.timestamp(frame) || producedAtUs > nowUs)
      'invalid_production_time',
    'metric_error_bounds_not_established',
    'physical_alignment_not_established',
    'floor_reference_not_established',
    'native_clock_binding_not_established',
    'whole_pixel_first_return_bounds_unavailable',
  ];

  @override
  PassageClearanceObservation observationFor(PassageEvaluationContext context) {
    final stamp = clock.timestamp(frame);
    final identityMatches =
        context.sessionGeneration == 1 &&
        context.frameId == frame.frameId &&
        context.rgbTimestampUs == stamp &&
        context.transformId == transformId &&
        context.timestampDomain == PassageTimestampDomain.utcEpochMicroseconds;
    // Even good SDK samples are not a free-volume observation.
    return PassageClearanceObservation(
      providerId: providerId,
      modelId: calibration.modelId,
      modelHash: frame.sourceIdentity,
      preprocessId: calibration.preprocessId,
      calibrationId: profile.id,
      referenceFrameId: request.referenceFrameId,
      rgbTransformId: transformId,
      depthTransformId: transformId,
      timestampDomain: PassageTimestampDomain.utcEpochMicroseconds,
      units: PassageUnits.metricMeters,
      sessionGeneration: 1,
      frameId: frame.frameId,
      rgbTimestampUs: stamp,
      depthTimestampUs: stamp,
      oldestEvidenceTimestampUs: stamp,
      producedAtUs: producedAtUs,
      providerHealthy: identityMatches && reasonsAt(context.nowUs).isEmpty,
      sections: [
        PassageSection(
          forwardStartM: request.forwardStartM,
          forwardEndM: request.forwardEndM,
          state: PassageSectionState.unknown,
          bodyObservedFraction: 0,
          floorObservedFraction: 0,
          confidence: 0,
        ),
      ],
    );
  }

  /// Geometric illustration conditional on independently supplied placement.
  /// This uses a separate preflight and cannot feed observationFor.
  Map<String, Object?> geometryDiagnostics(int nowUs) {
    final placement = profile.diagnosticWorldToWalking;
    if (placement == null) {
      return {
        'status': 'not_run',
        'reason': 'measured_placement_not_supplied',
        'canCertifyFreeSpace': false,
        'canAuthorizeMovement': false,
      };
    }
    final m = _multiply(placement, _columnToRow(frame.cameraTransform));
    // ARKit camera right/up/back -> image camera right/down/forward.
    final rotation = [
      for (var r = 0; r < 3; r++) ...[m[r * 4], -m[r * 4 + 1], -m[r * 4 + 2]],
    ];
    final fx = frame.rgbIntrinsics[0] * frame.width / frame.rgbWidth;
    final fy = frame.rgbIntrinsics[4] * frame.height / frame.rgbHeight;
    final cx = frame.rgbIntrinsics[6] * frame.width / frame.rgbWidth;
    final cy = frame.rgbIntrinsics[7] * frame.height / frame.rgbHeight;
    final n = frame.width * frame.height;
    final diagnostic = CameraVisibleDepthFrame(
      width: frame.width,
      height: frame.height,
      frameId: frame.frameId,
      capturedAtUs: clock.timestamp(frame),
      sessionGeneration: 1,
      fx: fx,
      fy: fy,
      cx: cx,
      cy: cy,
      errorM: profile.empiricalSampleErrorM ?? 0,
      poseQuality: 1,
      cameraId: frame.deviceModel,
      modelHash: frame.sourceIdentity,
      transformId: transformId,
      referenceFrameId: request.referenceFrameId,
      units: PassageUnits.metricMeters,
      providerHealthy: frame.trackingState == 'normal',
      rotation: rotation,
      originM: [m[3], m[7], m[11]],
      rangeM: [
        for (var i = 0; i < n; i++)
          frame.axisDepthM[i] *
              math.sqrt(
                1 +
                    math.pow((i % frame.width + .5 - cx) / fx, 2) +
                    math.pow((i ~/ frame.width + .5 - cy) / fy, 2),
              ),
      ],
      freeZLowerM: List.filled(n, double.nan),
      surfaceZUpperM: List.filled(n, double.nan),
      valid: [for (var i = 0; i < n; i++) frame.isHighConfidence(i)],
    );
    final c = calibration;
    final geometryOnly = PassageCalibration(
      id: c.id,
      providerId: c.providerId,
      modelId: c.modelId,
      modelHash: c.modelHash,
      preprocessId: c.preprocessId,
      referenceFrameId: c.referenceFrameId,
      transformId: c.transformId,
      timestampDomain: c.timestampDomain,
      // Hypothetical geometric placement only, never used in the producer.
      metricScaleValidated: true,
      alignmentValidated: true,
      floorReferenceValidated: true,
    );
    return {
      'status': 'conditional_geometry_only',
      'placementPhysicallyValidated': false,
      ...const SingleCameraObservabilityPreflight()
          .assess(
            frame: diagnostic,
            calibration: geometryOnly,
            request: request,
            context: PassageEvaluationContext(
              nowUs: nowUs,
              timestampDomain: c.timestampDomain,
              sessionGeneration: 1,
              frameId: frame.frameId,
              rgbTimestampUs: clock.timestamp(frame),
              transformId: transformId,
            ),
          )
          .toDiagnosticMap(),
    };
  }
}

List<double> _columnToRow(List<double> matrix) => [
  for (var row = 0; row < 4; row++)
    for (var col = 0; col < 4; col++) matrix[col * 4 + row],
];

List<double> _multiply(List<double> a, List<double> b) => [
  for (var r = 0; r < 4; r++)
    for (var c = 0; c < 4; c++)
      List.generate(
        4,
        (k) => a[r * 4 + k] * b[k * 4 + c],
      ).reduce((x, y) => x + y),
];

void _requireRigid(List<double> matrix) {
  if (matrix.length != 16 ||
      matrix.any((v) => !v.isFinite) ||
      [
        matrix[12],
        matrix[13],
        matrix[14],
        matrix[15] - 1,
      ].any((v) => v.abs() > 1e-5)) {
    throw const FormatException('Invalid affine transform.');
  }
  for (var a = 0; a < 3; a++) {
    for (var b = 0; b < 3; b++) {
      var dot = 0.0;
      for (var k = 0; k < 3; k++) {
        dot += matrix[k * 4 + a] * matrix[k * 4 + b];
      }
      if ((dot - (a == b ? 1 : 0)).abs() > 1e-4) {
        throw const FormatException('Nonrigid transform.');
      }
    }
  }
  final determinant =
      matrix[0] * (matrix[5] * matrix[10] - matrix[6] * matrix[9]) -
      matrix[1] * (matrix[4] * matrix[10] - matrix[6] * matrix[8]) +
      matrix[2] * (matrix[4] * matrix[9] - matrix[5] * matrix[8]);
  if ((determinant - 1).abs() > 1e-4) {
    throw const FormatException('Reflected transform.');
  }
}

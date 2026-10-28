import 'camera_passage_clearance_source.dart';
import 'dart:typed_data';
import 'dart:collection';
import 'dart:isolate';

/// Identity belongs to the RGB capture provider, never an NN result.
class FastRgbContract {
  final String providerId, revision, preprocessId;
  const FastRgbContract({
    required this.providerId,
    required this.revision,
    required this.preprocessId,
  });
  bool get valid =>
      providerId.isNotEmpty && revision.isNotEmpty && preprocessId.isNotEmpty;
}

class FastRgbHeader {
  final String providerId, revision, preprocessId, transformId;
  final int sessionGeneration, frameId, sourceTimestampUs, producedAtUs;
  final bool healthy;
  final double confidence;
  const FastRgbHeader({
    required this.providerId,
    required this.revision,
    required this.preprocessId,
    required this.transformId,
    required this.sessionGeneration,
    required this.frameId,
    required this.sourceTimestampUs,
    required this.producedAtUs,
    required this.healthy,
    required this.confidence,
  });
}

class FastRgbGeometry {
  final String cameraId;
  final int width, height;
  final double fx, fy, cx, cy;
  final List<double> rotation, originM;

  FastRgbGeometry({
    required this.cameraId,
    required this.width,
    required this.height,
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
    required List<double> rotation,
    required List<double> originM,
  }) : rotation = List.unmodifiable(rotation),
       originM = List.unmodifiable(originM);
}

class FastCameraInput {
  final FastRgbHeader rgbHeader;
  final FastRgbGeometry imageGeometry;
  final CameraVisibleDepthFrame depth;

  const FastCameraInput({
    required this.rgbHeader,
    required this.imageGeometry,
    required this.depth,
  });
}

/// RGB and first-return depth registered at one capture. No object/scene labels.
class FastMetricMotionInput {
  final FastCameraInput camera;
  final List<int> rgb;
  final double positionErrorM, angularErrorRad;

  FastMetricMotionInput({
    required this.camera,
    required List<int> rgb,
    required this.positionErrorM,
    required this.angularErrorRad,
  }) : rgb = rgb.every((v) => v >= 0 && v <= 255)
           ? Uint8List.fromList(rgb).asUnmodifiableView()
           : List.unmodifiable(rgb);

  /// The uniquely owned transferred storage is exposed only as read-only
  /// typed views. Uint8 storage cannot contain invalid byte values.
  FastMetricMotionInput._transferred({
    required this.camera,
    required Uint8List pixels,
    required this.positionErrorM,
    required this.angularErrorRad,
  }) : rgb = pixels.asUnmodifiableView();

  factory FastMetricMotionInput.fromTransferable({
    required TransferableTypedData storage,
    required CameraVisibleDepthFrame metadata,
    required FastRgbHeader header,
    required FastRgbGeometry geometry,
    required double positionErrorM,
    required double angularErrorRad,
  }) {
    final buffer = storage.materialize(),
        n = metadata.width * metadata.height,
        rgbLength = n * 3;
    final start = (rgbLength + 7) & ~7;
    final depth = _TransferredDepthFrame(
      metadata,
      buffer.asFloat64List(start, n),
      buffer.asFloat64List(start + n * 8, n),
      buffer.asFloat64List(start + n * 16, n),
      buffer.asUint8List(start + n * 24, n),
    );
    return FastMetricMotionInput._transferred(
      camera: FastCameraInput(
        depth: depth,
        rgbHeader: header,
        imageGeometry: geometry,
      ),
      pixels: buffer.asUint8List(0, rgbLength),
      positionErrorM: positionErrorM,
      angularErrorRad: angularErrorRad,
    );
  }
}

class _ReadOnlyMask extends ListBase<bool> {
  final Uint8List _data;
  _ReadOnlyMask(Uint8List data) : _data = data.asUnmodifiableView();
  @override
  int get length => _data.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable validity mask');
  @override
  bool operator [](int index) => _data[index] == 1;
  @override
  void operator []=(int index, bool value) =>
      throw UnsupportedError('Immutable validity mask');
}

/// Registered depth with zero-copy, read-only transferred payload views.
/// The inherited geometry/structural admission contract is unchanged.
class _TransferredDepthFrame extends CameraVisibleDepthFrame {
  final Float64List _range, _lower, _upper;
  final List<bool> _valid;
  _TransferredDepthFrame(
    CameraVisibleDepthFrame f,
    Float64List range,
    Float64List lower,
    Float64List upper,
    Uint8List validity,
  ) : _range = range.asUnmodifiableView(),
      _lower = lower.asUnmodifiableView(),
      _upper = upper.asUnmodifiableView(),
      _valid = _ReadOnlyMask(validity),
      super(
        width: f.width,
        height: f.height,
        frameId: f.frameId,
        capturedAtUs: f.capturedAtUs,
        sessionGeneration: f.sessionGeneration,
        fx: f.fx,
        fy: f.fy,
        cx: f.cx,
        cy: f.cy,
        errorM: f.errorM,
        poseQuality: f.poseQuality,
        cameraId: f.cameraId,
        modelHash: f.modelHash,
        transformId: f.transformId,
        referenceFrameId: f.referenceFrameId,
        units: f.units,
        providerHealthy: f.providerHealthy,
        rotation: f.rotation,
        originM: f.originM,
        rangeM: const [],
        freeZLowerM: const [],
        surfaceZUpperM: const [],
        valid: const [],
      );
  @override
  List<double> get rangeM => _range;
  @override
  List<double> get freeZLowerM => _lower;
  @override
  List<double> get surfaceZUpperM => _upper;
  @override
  List<bool> get valid => _valid;
}

enum FastPatchClassification {
  consistentWithStationary,
  approaching,
  receding,
  lateral,
  uncertain,
}

class FastPatchMotion {
  final List<int> previousPixel, currentPixel;
  final List<double> positionLowerM, positionUpperM;
  final List<double> velocityLowerMps, velocityUpperMps;
  final FastPatchClassification classification;
  final bool possibleBodyIntersection;

  FastPatchMotion({
    required List<int> previousPixel,
    required List<int> currentPixel,
    required List<double> positionLowerM,
    required List<double> positionUpperM,
    required List<double> velocityLowerMps,
    required List<double> velocityUpperMps,
    required this.classification,
    required this.possibleBodyIntersection,
  }) : previousPixel = List.unmodifiable(previousPixel),
       currentPixel = List.unmodifiable(currentPixel),
       positionLowerM = List.unmodifiable(positionLowerM),
       positionUpperM = List.unmodifiable(positionUpperM),
       velocityLowerMps = List.unmodifiable(velocityLowerMps),
       velocityUpperMps = List.unmodifiable(velocityUpperMps);

  bool get establishesMotion =>
      classification == FastPatchClassification.approaching ||
      classification == FastPatchClassification.receding ||
      classification == FastPatchClassification.lateral;

  Map<String, Object?> toDiagnosticMap() => {
    'previousPixel': previousPixel,
    'currentPixel': currentPixel,
    'positionLowerM': positionLowerM,
    'positionUpperM': positionUpperM,
    'velocityLowerMps': velocityLowerMps,
    'velocityUpperMps': velocityUpperMps,
    'classification': classification.name,
    'possibleBodyIntersection': possibleBodyIntersection,
  };
}

class FastMetricMotionResult {
  final String reason;
  final int sessionGeneration,
      frameId,
      capturedAtUs,
      oldestEvidenceTimestampUs,
      validUntilUs;
  final int candidates, unknownPatches;
  final String transformId;
  final List<FastPatchMotion> patches;

  FastMetricMotionResult({
    required this.reason,
    required this.sessionGeneration,
    required this.frameId,
    required this.capturedAtUs,
    required this.oldestEvidenceTimestampUs,
    required this.validUntilUs,
    required this.transformId,
    required this.candidates,
    required this.unknownPatches,
    required List<FastPatchMotion> patches,
  }) : patches = List.unmodifiable(patches);

  bool get available => patches.isNotEmpty;
  // A single local match never authorizes a global motion/absence conclusion.
  int get threateningPatches => patches
      .where((p) => p.establishesMotion && p.possibleBodyIntersection)
      .length;
  bool get addsMotionRisk => threateningPatches >= 3;
  bool isLiveAt(int nowUs) => nowUs >= capturedAtUs && nowUs <= validUntilUs;

  Map<String, Object?> toDiagnosticMap() => {
    'reason': reason,
    'available': available,
    'frameId': frameId,
    'oldestEvidenceTimestampUs': oldestEvidenceTimestampUs,
    'validUntilUs': validUntilUs,
    'candidates': candidates,
    'unknownPatches': unknownPatches,
    'threateningPatches': threateningPatches,
    'addsMotionRisk': addsMotionRisk,
    'absenceOfMotionCertified': false,
    'freeSpaceCertified': false,
    'patches': patches.map((p) => p.toDiagnosticMap()).toList(),
  };
}

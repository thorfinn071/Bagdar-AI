import 'dart:math' as math;
import 'dart:ui';

import 'depth_frame.dart' show CameraIntrinsics;

/// Timestamp domain used by the current camera callback.
///
/// The camera plugin does not expose a sensor timestamp on every supported
/// Android device, so Core stamps capture and receipt from the same UTC epoch
/// clock. A future sensor-clock integration must add an explicit conversion
/// instead of mixing domains in this field.
enum FrameTimestampDomain { utcEpochMicroseconds }

enum FrameExposureState { unknown, stable, transitioning, clipped }

enum FrameMotionState { unknown, stationary, walking, running, unstable }

class FrameSize {
  final int width;
  final int height;

  const FrameSize(this.width, this.height)
    : assert(width > 0),
      assert(height > 0);

  int get area => width * height;

  Map<String, int> toDiagnosticMap() => <String, int>{
    'width': width,
    'height': height,
  };
}

class CropTransform {
  final double leftFraction;
  final double topFraction;
  final double rightFraction;
  final double bottomFraction;

  const CropTransform({
    this.leftFraction = 0,
    this.topFraction = 0,
    this.rightFraction = 0,
    this.bottomFraction = 0,
  }) : assert(leftFraction >= 0 && leftFraction < 1),
       assert(topFraction >= 0 && topFraction < 1),
       assert(rightFraction >= 0 && rightFraction < 1),
       assert(bottomFraction >= 0 && bottomFraction < 1),
       assert(leftFraction + rightFraction < 1),
       assert(topFraction + bottomFraction < 1);

  static const none = CropTransform();

  Map<String, double> toDiagnosticMap() => <String, double>{
    'left': leftFraction,
    'top': topFraction,
    'right': rightFraction,
    'bottom': bottomFraction,
  };
}

class AngularVelocity {
  final double xRadPerSec;
  final double yRadPerSec;
  final double zRadPerSec;
  final bool available;

  const AngularVelocity({
    required this.xRadPerSec,
    required this.yRadPerSec,
    required this.zRadPerSec,
    this.available = true,
  }) : assert(xRadPerSec >= 0 || xRadPerSec < 0 || xRadPerSec == 0),
       assert(yRadPerSec >= 0 || yRadPerSec < 0 || yRadPerSec == 0),
       assert(zRadPerSec >= 0 || zRadPerSec < 0 || zRadPerSec == 0);

  static const unknown = AngularVelocity(
    xRadPerSec: 0,
    yRadPerSec: 0,
    zRadPerSec: 0,
    available: false,
  );

  double get magnitude => math.sqrt(
    xRadPerSec * xRadPerSec + yRadPerSec * yRadPerSec + zRadPerSec * zRadPerSec,
  );
}

/// The one spatial transform shared by RGB, luma, depth, masks, and boxes.
///
/// Order is fixed: source sensor -> upright rotation -> horizontal mirror ->
/// crop. [mapSourceRectToUpright] intentionally stops before crop for payloads
/// already expanded back to the full upright frame.
class FrameTransform {
  final int sensorRotationDeg;
  final bool mirrored;
  final FrameSize sourceSize;
  final FrameSize uprightSize;
  final CropTransform crop;

  FrameTransform({
    required this.sensorRotationDeg,
    required this.mirrored,
    required this.sourceSize,
    required this.uprightSize,
    this.crop = CropTransform.none,
  }) : assert(
         sensorRotationDeg == 0 ||
             sensorRotationDeg == 90 ||
             sensorRotationDeg == 180 ||
             sensorRotationDeg == 270,
       ),
       assert(
         (sensorRotationDeg == 90 || sensorRotationDeg == 270)
             ? uprightSize.width == sourceSize.height &&
                   uprightSize.height == sourceSize.width
             : uprightSize.width == sourceSize.width &&
                   uprightSize.height == sourceSize.height,
       );

  factory FrameTransform.forSensor({
    required int sensorRotationDeg,
    required bool mirrored,
    required FrameSize sourceSize,
    CropTransform crop = CropTransform.none,
  }) {
    final rotation = normalizeRotation(sensorRotationDeg);
    final swapAxes = rotation == 90 || rotation == 270;
    return FrameTransform(
      sensorRotationDeg: rotation,
      mirrored: mirrored,
      sourceSize: sourceSize,
      uprightSize: FrameSize(
        swapAxes ? sourceSize.height : sourceSize.width,
        swapAxes ? sourceSize.width : sourceSize.height,
      ),
      crop: crop,
    );
  }

  static int normalizeRotation(int degrees) {
    final normalized = ((degrees % 360) + 360) % 360;
    return switch (normalized) {
      90 || 180 || 270 => normalized,
      _ => 0,
    };
  }

  /// Stable across processes; never uses Dart's runtime [hashCode].
  String get id =>
      'frame-transform-v1:'
      '${sourceSize.width}x${sourceSize.height}:'
      '${uprightSize.width}x${uprightSize.height}:'
      'r$sensorRotationDeg:m${mirrored ? 1 : 0}:'
      'c${crop.leftFraction.toStringAsFixed(6)},'
      '${crop.topFraction.toStringAsFixed(6)},'
      '${crop.rightFraction.toStringAsFixed(6)},'
      '${crop.bottomFraction.toStringAsFixed(6)}';

  Offset mapSourcePointToUpright(Offset point) {
    var upright = switch (sensorRotationDeg) {
      90 => Offset(1.0 - point.dy, point.dx),
      180 => Offset(1.0 - point.dx, 1.0 - point.dy),
      270 => Offset(point.dy, 1.0 - point.dx),
      _ => point,
    };
    if (mirrored) {
      upright = Offset(1.0 - upright.dx, upright.dy);
    }
    return upright;
  }

  Offset mapUprightPointToCrop(Offset point) {
    final visibleWidth = 1.0 - crop.leftFraction - crop.rightFraction;
    final visibleHeight = 1.0 - crop.topFraction - crop.bottomFraction;
    return Offset(
      (point.dx - crop.leftFraction) / visibleWidth,
      (point.dy - crop.topFraction) / visibleHeight,
    );
  }

  Offset mapSourcePointToCroppedUpright(Offset point) =>
      mapUprightPointToCrop(mapSourcePointToUpright(point));

  Rect mapSourceRectToUpright(Rect sourceRect) =>
      _mapRect(sourceRect, mapSourcePointToUpright);

  Rect mapSourceRectToCroppedUpright(Rect sourceRect) =>
      _mapRect(sourceRect, mapSourcePointToCroppedUpright);

  Rect _mapRect(Rect rect, Offset Function(Offset) mapPoint) {
    final points = <Offset>[
      mapPoint(rect.topLeft),
      mapPoint(rect.topRight),
      mapPoint(rect.bottomLeft),
      mapPoint(rect.bottomRight),
    ];
    final xs = points.map((p) => p.dx);
    final ys = points.map((p) => p.dy);
    return Rect.fromLTRB(
      xs.reduce(math.min).clamp(0.0, 1.0),
      ys.reduce(math.min).clamp(0.0, 1.0),
      xs.reduce(math.max).clamp(0.0, 1.0),
      ys.reduce(math.max).clamp(0.0, 1.0),
    );
  }

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'id': id,
    'rotationDeg': sensorRotationDeg,
    'mirrored': mirrored,
    'sourceSize': sourceSize.toDiagnosticMap(),
    'uprightSize': uprightSize.toDiagnosticMap(),
    'crop': crop.toDiagnosticMap(),
  };
}

/// One immutable camera frame and all metadata needed to interpret it.
class FramePacket {
  final int sessionGeneration;
  final int frameId;
  final int cameraTimestampUs;
  final int receivedAtUs;
  final FrameTimestampDomain timestampDomain;
  final FrameTransform transform;
  final CameraIntrinsics? cameraIntrinsics;
  final FrameExposureState exposureState;
  final double? blurScore;
  final double? illuminationScore;
  final double pitchDeg;
  final double rollDeg;
  final AngularVelocity angularVelocity;
  final FrameMotionState motionState;

  const FramePacket({
    required this.sessionGeneration,
    required this.frameId,
    required this.cameraTimestampUs,
    required this.receivedAtUs,
    required this.transform,
    required this.pitchDeg,
    required this.rollDeg,
    required this.angularVelocity,
    required this.motionState,
    this.timestampDomain = FrameTimestampDomain.utcEpochMicroseconds,
    this.cameraIntrinsics,
    this.exposureState = FrameExposureState.unknown,
    this.blurScore,
    this.illuminationScore,
  }) : assert(sessionGeneration >= 0),
       assert(frameId > 0),
       assert(cameraTimestampUs >= 0),
       assert(receivedAtUs >= cameraTimestampUs),
       assert(pitchDeg >= 0 || pitchDeg < 0 || pitchDeg == 0),
       assert(rollDeg >= 0 || rollDeg < 0 || rollDeg == 0),
       assert(blurScore == null || (blurScore >= 0 && blurScore <= 1)),
       assert(
         illuminationScore == null ||
             (illuminationScore >= 0 && illuminationScore <= 1),
       );

  int get timestampUs => cameraTimestampUs;
  int get sensorRotationDeg => transform.sensorRotationDeg;
  bool get mirrored => transform.mirrored;
  FrameSize get sourceSize => transform.sourceSize;
  FrameSize get uprightSize => transform.uprightSize;
  CropTransform get cropTransform => transform.crop;
  int get sourceWidth => sourceSize.width;
  int get sourceHeight => sourceSize.height;
  int get uprightWidth => uprightSize.width;
  int get uprightHeight => uprightSize.height;
  double get cropTopFraction => cropTransform.topFraction;
  String get transformId => transform.id;

  /// Metadata only. No pixels, depth values, boxes, speech, or location data.
  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'sessionGeneration': sessionGeneration,
    'frameId': frameId,
    'cameraTimestampUs': cameraTimestampUs,
    'receivedAtUs': receivedAtUs,
    'timestampDomain': timestampDomain.name,
    'transform': transform.toDiagnosticMap(),
    'hasCameraIntrinsics': cameraIntrinsics != null,
    'exposureState': exposureState.name,
    'blurScore': blurScore,
    'illuminationScore': illuminationScore,
    'pitchDeg': pitchDeg,
    'rollDeg': rollDeg,
    'angularVelocityAvailable': angularVelocity.available,
    'motionState': motionState.name,
  };
}

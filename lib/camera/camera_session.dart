import '../models/frame_packet.dart';
import '../safety/perception/observation_header.dart';

/// One camera session owns one generation of frames.
///
/// A new physical camera open increments [generation]. Depth, YOLO, and
/// trackers must drop packets stamped with an older generation.
class CameraSession {
  static const Duration maxImageDepthDelta = Duration(milliseconds: 150);

  int generation = 0;
  int _lastIssuedFrameId = 0;

  int get lastIssuedFrameId => _lastIssuedFrameId;

  int beginNewSession() {
    generation += 1;
    _lastIssuedFrameId = 0;
    return generation;
  }

  /// Invalidates every packet owned by the stopped physical camera stream.
  void endSession() {
    generation += 1;
    _lastIssuedFrameId = 0;
  }

  bool accepts(int packetGeneration) => packetGeneration == generation;

  int nextFrameId() {
    _lastIssuedFrameId += 1;
    return _lastIssuedFrameId;
  }

  bool acceptsPacket(FramePacket packet) =>
      packet.sessionGeneration == generation &&
      packet.frameId > 0 &&
      packet.frameId <= _lastIssuedFrameId;

  /// Latest-frame-wins gate used before an asynchronous result reaches
  /// trackers, fusion, status, or user feedback.
  bool acceptsObservation(ObservationHeader header, {int? latestFrameId}) =>
      header.sessionGeneration == generation &&
      header.frameId == (latestFrameId ?? _lastIssuedFrameId);

  static bool timestampsAligned({
    required int imageTimestampUs,
    required int depthTimestampUs,
    Duration maxDelta = maxImageDepthDelta,
  }) {
    return (imageTimestampUs - depthTimestampUs).abs() <=
        maxDelta.inMicroseconds;
  }
}

import '../../models/frame_packet.dart';

enum ObservationHealth { healthy, degraded, unavailable, rejected }

/// Shared immutable identity and freshness contract for perception results.
class ObservationHeader {
  final String providerId;
  final String modelId;
  final String modelHash;
  final String preprocessId;
  final int sessionGeneration;
  final int frameId;
  final int sourceTimestampUs;
  final int producedAtUs;
  final String transformId;
  final double confidence;
  final ObservationHealth health;

  const ObservationHeader({
    required this.providerId,
    required this.modelId,
    required this.modelHash,
    required this.preprocessId,
    required this.sessionGeneration,
    required this.frameId,
    required this.sourceTimestampUs,
    required this.producedAtUs,
    required this.transformId,
    required this.confidence,
    required this.health,
  }) : assert(providerId != ''),
       assert(modelId != ''),
       assert(modelHash != ''),
       assert(preprocessId != ''),
       assert(sessionGeneration >= 0),
       assert(frameId > 0),
       assert(sourceTimestampUs >= 0),
       assert(producedAtUs >= sourceTimestampUs),
       assert(transformId != ''),
       assert(confidence >= 0 && confidence <= 1);

  factory ObservationHeader.fromPacket({
    required FramePacket packet,
    required String providerId,
    required String modelId,
    required String modelHash,
    required String preprocessId,
    required int producedAtUs,
    required double confidence,
    required ObservationHealth health,
  }) => ObservationHeader(
    providerId: providerId,
    modelId: modelId,
    modelHash: modelHash,
    preprocessId: preprocessId,
    sessionGeneration: packet.sessionGeneration,
    frameId: packet.frameId,
    sourceTimestampUs: packet.cameraTimestampUs,
    producedAtUs: producedAtUs,
    transformId: packet.transformId,
    confidence: confidence.clamp(0.0, 1.0),
    health: health,
  );

  bool matchesPacket(FramePacket packet) =>
      sessionGeneration == packet.sessionGeneration &&
      frameId == packet.frameId &&
      sourceTimestampUs == packet.cameraTimestampUs &&
      transformId == packet.transformId;

  bool exceedsLatency(Duration maximum) =>
      producedAtUs - sourceTimestampUs > maximum.inMicroseconds;

  /// Header-only replay metadata; payloads remain outside diagnostics.
  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'providerId': providerId,
    'modelId': modelId,
    'modelHash': modelHash,
    'preprocessId': preprocessId,
    'sessionGeneration': sessionGeneration,
    'frameId': frameId,
    'sourceTimestampUs': sourceTimestampUs,
    'producedAtUs': producedAtUs,
    'transformId': transformId,
    'confidence': confidence,
    'health': health.name,
  };
}

class PerceptionObservation<T> {
  final ObservationHeader header;
  final T payload;

  const PerceptionObservation({required this.header, required this.payload});

  Map<String, Object?> toDiagnosticMap() => header.toDiagnosticMap();
}

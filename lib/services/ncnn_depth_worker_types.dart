import 'dart:isolate';
import 'dart:typed_data';

import '../models/depth_frame.dart';

class NcnnDepthWorkerConfig {
  final String paramPath;
  final String binPath;
  final int threads;
  final bool useVulkan;

  const NcnnDepthWorkerConfig({
    required this.paramPath,
    required this.binPath,
    this.threads = 2,
    this.useVulkan = true,
  });
}

/// Only numeric, privately owned buffers reach the inference isolate.
class NcnnDepthInput {
  final List<Uint8List> planes;
  final List<int> rowStrides;
  final List<int> pixelStrides;
  final int width;
  final int height;
  final double cropTopFrac;
  final int rotationDegrees;
  final bool mirrored;
  final int sourceTimestampUs;
  final bool userStationary;
  final bool weatherDegraded;
  final bool winterMode;
  final String? debugDumpDirectory;

  const NcnnDepthInput({
    required this.planes,
    required this.rowStrides,
    required this.pixelStrides,
    required this.width,
    required this.height,
    this.cropTopFrac = 0.40,
    this.rotationDegrees = 0,
    this.mirrored = false,
    this.sourceTimestampUs = 0,
    this.userStationary = false,
    this.weatherDegraded = false,
    this.winterMode = false,
    this.debugDumpDirectory,
  });

  void validate() {
    if (width <= 0 ||
        height <= 0 ||
        width > 8192 ||
        height > 8192 ||
        planes.length != 3 ||
        rowStrides.length != 3 ||
        pixelStrides.length != 3 ||
        !cropTopFrac.isFinite ||
        sourceTimestampUs < 0) {
      throw ArgumentError('invalid NCNN input metadata');
    }
    var total = 0;
    for (var i = 0; i < 3; i++) {
      final w = i == 0 ? width : (width + 1) ~/ 2;
      final h = i == 0 ? height : (height + 1) ~/ 2;
      final row = rowStrides[i];
      final pixel = pixelStrides[i];
      if (row <= 0 ||
          row > 16 * 1024 * 1024 ||
          pixel > 16 * 1024 * 1024 ||
          pixel <= 0 ||
          row < (w - 1) * pixel + 1 ||
          planes[i].length < (h - 1) * row + (w - 1) * pixel + 1) {
        throw ArgumentError('invalid NCNN plane $i');
      }
      total += planes[i].length;
    }
    if (total > 16 * 1024 * 1024) {
      throw ArgumentError('NCNN input exceeds bounded transport');
    }
  }

  NcnnDepthTransfer freeze() {
    validate();
    return NcnnDepthTransfer(this, [
      for (final plane in planes) TransferableTypedData.fromList([plane]),
    ]);
  }
}

class NcnnDepthTransfer {
  // Metadata must not retain the CameraImage's original byte arrays.
  final NcnnDepthInput metadata;
  final List<TransferableTypedData> buffers;

  NcnnDepthTransfer(NcnnDepthInput input, this.buffers)
    : metadata = NcnnDepthInput(
        planes: const [],
        rowStrides: List<int>.of(input.rowStrides),
        pixelStrides: List<int>.of(input.pixelStrides),
        width: input.width,
        height: input.height,
        cropTopFrac: input.cropTopFrac,
        rotationDegrees: input.rotationDegrees,
        mirrored: input.mirrored,
        sourceTimestampUs: input.sourceTimestampUs,
        userStationary: input.userStationary,
        weatherDegraded: input.weatherDegraded,
        winterMode: input.winterMode,
        debugDumpDirectory: input.debugDumpDirectory,
      );

  NcnnDepthInput materialize() => NcnnDepthInput(
    planes: [for (final buffer in buffers) buffer.materialize().asUint8List()],
    rowStrides: metadata.rowStrides,
    pixelStrides: metadata.pixelStrides,
    width: metadata.width,
    height: metadata.height,
    cropTopFrac: metadata.cropTopFrac,
    rotationDegrees: metadata.rotationDegrees,
    mirrored: metadata.mirrored,
    sourceTimestampUs: metadata.sourceTimestampUs,
    userStationary: metadata.userStationary,
    weatherDegraded: metadata.weatherDegraded,
    winterMode: metadata.winterMode,
    debugDumpDirectory: metadata.debugDumpDirectory,
  );
}

abstract interface class NcnnDepthBackend {
  bool init(NcnnDepthWorkerConfig config);
  bool get isVulkan;
  int get outputWidth;
  int get outputHeight;
  Float32List? infer(NcnnDepthInput input);
  void dispose();
}

typedef NcnnDepthBackendFactory = NcnnDepthBackend Function();

class NcnnDepthReply {
  final DepthAnalysisResult result;
  final double preprocessMs;
  final double inferenceMs;
  final double totalMs;
  final bool planeFitOk;

  const NcnnDepthReply({
    required this.result,
    this.preprocessMs = 0,
    this.inferenceMs = 0,
    this.totalMs = 0,
    this.planeFitOk = false,
  });

  factory NcnnDepthReply.unavailable(String reason) => NcnnDepthReply(
    result: DepthAnalysisResult(
      legacyHazards: const [],
      health: DepthHealth.unavailable(
        provider: DepthProviderKind.ncnnRelative,
        reason: reason,
      ),
    ),
  );
}

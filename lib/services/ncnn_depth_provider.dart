import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../utils/depth_hazard.dart';
import '../core/simulation_build.dart';
import '../utils/ncnn_depth_debug_dump.dart';
import 'depth_provider.dart';
import 'device_capability.dart';
import 'ncnn_depth_worker.dart';
import 'settings_service.dart';

/// Camera-facing facade; all native lifecycle and depth computation belong
/// to the persistent worker, never the Flutter UI isolate.
class NcnnDepthProvider implements DepthProvider {
  static const String _paramAsset = 'assets/midas_small.ncnn.param';
  static const String _binAsset = 'assets/midas_small.ncnn.bin';
  static const int _kMaxFailuresInWindow = 3;
  static const Duration _kFailureWindow = Duration(minutes: 5);
  NcnnDepthWorker? _worker;
  Future<bool>? _initializing;
  Future<void>? _shutdown;
  bool _ready = false;
  bool _disposed = false;
  bool _permanentlyDisabled = false;
  int _generation = 0;
  int _requestId = 0;
  final List<DateTime> _recentFailures = [];
  double _lastOutputConfidence = 0;
  double _lastPreprocessMs = 0;
  double _lastInferenceMs = 0;
  double _lastAnalyzeMs = 0;
  double lastRoundTripMs = 0;
  int? lastCompletedSourceTimestampUs;
  bool _lastPlaneFitOk = false;
  bool _isVulkan = false;
  void Function()? onSessionDisabled;

  NcnnDepthProvider._();

  @visibleForTesting
  NcnnDepthProvider.withWorker(NcnnDepthWorker worker)
    : _worker = worker,
      _ready = true,
      _isVulkan = worker.isVulkan;

  static Future<NcnnDepthProvider?> tryCreate() async =>
      Platform.isAndroid ? NcnnDepthProvider._() : null;

  @override
  DepthTier get tier => _isVulkan ? DepthTier.ncnnVulkan : DepthTier.ncnnCpu;
  @override
  bool get isReady => _ready && !_disposed && !_permanentlyDisabled;
  @override
  bool get nativeBridgeEnabled => true;
  @override
  bool get nativeBridgeAvailable => true;
  @override
  bool get lowConfidenceFallbackActive => false;
  @override
  double get lastConfidenceScore => _lastOutputConfidence;
  @override
  double get lastPreprocessMs => _lastPreprocessMs;
  @override
  double get lastInferenceMs => _lastInferenceMs;
  @override
  double get lastAnalyzeMs => _lastAnalyzeMs;
  @override
  bool get lastUsedNativeBridge => true;
  @override
  bool get lastPlaneFitOk => _lastPlaneFitOk;
  int get queuedInputs => _worker?.queuedInputs ?? 0;
  @override
  void setNativeBridgeEnabled(bool enabled) {}

  @override
  Future<bool> init({int threads = 2}) {
    if (_disposed || _permanentlyDisabled) return Future.value(false);
    if (_ready) return Future.value(true);
    return _initializing ??= _initialize(threads);
  }

  Future<bool> _initialize(int threads) async {
    final generation = _generation;
    if (Settings.instance.isReady && Settings.instance.ncnnDisabled) {
      Settings.instance.setNcnnDisabled(false).ignore();
    }
    final paths = await _extractAssets();
    if (paths == null || _disposed || generation != _generation) return false;
    try {
      final worker = await NcnnDepthWorker.start(
        NcnnDepthWorkerConfig(
          paramPath: paths.$1,
          binPath: paths.$2,
          threads: threads.clamp(1, 4),
          // Software Vulkan on an emulator can spend seconds compiling shaders.
          // This opt-in uses the same native NCNN CPU path available on phones.
          useVulkan:
              !(simulationBuild &&
                  const bool.fromEnvironment('BAGDAR_SIMULATION_CPU')),
        ),
      );
      if (_disposed || generation != _generation) {
        await worker.close();
        return false;
      }
      _worker = worker;
      _isVulkan = worker.isVulkan;
      _ready = true;
      return true;
    } catch (error) {
      debugPrint('NcnnDepthProvider: worker init failed ($error)');
      return false;
    }
  }

  static Future<(String, String)?> _extractAssets() async {
    try {
      final docs = await getApplicationSupportDirectory();
      final paramPath = '${docs.path}/midas_small.ncnn.param';
      final binPath = '${docs.path}/midas_small.ncnn.bin';

      final paramData = await rootBundle.load(_paramAsset);
      final binData = await rootBundle.load(_binAsset);

      final paramFile = File(paramPath);
      final binFile = File(binPath);

      if (!await paramFile.exists() ||
          (await paramFile.length()) != paramData.lengthInBytes) {
        await paramFile.writeAsBytes(
          paramData.buffer.asUint8List(
            paramData.offsetInBytes,
            paramData.lengthInBytes,
          ),
          flush: true,
        );
      }
      if (!await binFile.exists() ||
          (await binFile.length()) != binData.lengthInBytes) {
        await binFile.writeAsBytes(
          binData.buffer.asUint8List(
            binData.offsetInBytes,
            binData.lengthInBytes,
          ),
          flush: true,
        );
      }
      return (paramPath, binPath);
    } catch (e) {
      debugPrint('NcnnDepthProvider: asset extraction failed ($e)');
      return null;
    }
  }

  @override
  Future<List<DepthHazard>> analyze(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
  }) async => (await analyzeDetailed(
    image,
    cropTopFrac: cropTopFrac,
    userStationary: userStationary,
    weatherDegraded: weatherDegraded,
    winterMode: winterMode,
  )).legacyHazards;

  @override
  Future<DepthAnalysisResult> analyzeDetailed(
    CameraImage image, {
    double cropTopFrac = 0.40,
    bool userStationary = false,
    bool weatherDegraded = false,
    bool winterMode = false,
    int sourceTimestampUs = 0,
    int rotationDegrees = 0,
    bool mirrored = false,
  }) async {
    final worker = _worker;
    if (!isReady || worker == null) {
      return NcnnDepthReply.unavailable(
        _permanentlyDisabled ? 'session_disabled' : 'not_ready',
      ).result;
    }
    final generation = _generation;
    final requestId = ++_requestId;
    final roundTrip = Stopwatch()..start();
    NcnnDepthReply reply;
    try {
      final planes = image.planes;
      if (planes.length < 3) throw ArgumentError('YUV420 needs three planes');
      final input = NcnnDepthInput(
        planes: [for (final p in planes.take(3)) p.bytes],
        rowStrides: [for (final p in planes.take(3)) p.bytesPerRow],
        pixelStrides: [for (final p in planes.take(3)) p.bytesPerPixel ?? 1],
        width: image.width,
        height: image.height,
        cropTopFrac: cropTopFrac,
        userStationary: userStationary,
        weatherDegraded: weatherDegraded,
        winterMode: winterMode,
        sourceTimestampUs: sourceTimestampUs,
        rotationDegrees: rotationDegrees,
        mirrored: mirrored,
        debugDumpDirectory: NcnnDepthDebugDump.enabled
            ? NcnnDepthDebugDump.outputDir
            : null,
      );
      reply = await worker.analyze(input.freeze());
    } catch (_) {
      reply = NcnnDepthReply.unavailable('exception');
    }
    if (_disposed || generation != _generation) {
      return NcnnDepthReply.unavailable('worker_closed').result;
    }
    final reason = reply.result.health.rejectionReason;
    if (reply.result.health.capability == DepthCapability.providerUnavailable &&
        reason != 'worker_superseded' &&
        reason != 'worker_closed') {
      _recordFailure();
    }
    if (requestId == _requestId) {
      lastCompletedSourceTimestampUs = sourceTimestampUs;
      _lastPreprocessMs = reply.preprocessMs;
      _lastInferenceMs = reply.inferenceMs;
      _lastAnalyzeMs = reply.totalMs;
      lastRoundTripMs = roundTrip.elapsedMicroseconds / 1000;
      _lastOutputConfidence = reply.result.frame?.frameQuality ?? 0;
      _lastPlaneFitOk = reply.result.frame != null && reply.planeFitOk;
    }
    return reply.result;
  }

  void _recordFailure() {
    final now = DateTime.now();
    _recentFailures.removeWhere((t) => now.difference(t) > _kFailureWindow);
    _recentFailures.add(now);
    if (_recentFailures.length >= _kMaxFailuresInWindow) {
      _markSessionDisabled();
    }
  }

  void _markSessionDisabled() {
    if (_permanentlyDisabled) return;
    _permanentlyDisabled = true;
    debugPrint(
      'NcnnDepthProvider: $_kMaxFailuresInWindow invalid-output failures in '
      '${_kFailureWindow.inMinutes}m — disabling for THIS session only. '
      'A restart will re-enable NCNN depth.',
    );

    onSessionDisabled?.call();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    _generation++;
    unawaited(shutdown());
  }

  /// Allows lifecycle owners to await acknowledged native cleanup.
  Future<void> shutdown() => _shutdown ??= _closeWorker();

  Future<void> _closeWorker() async {
    if (!_disposed) {
      _disposed = true;
      _ready = false;
      _generation++;
    }
    final worker = _worker;
    _worker = null;
    if (worker != null) await worker.close();
    final initializing = _initializing;
    if (initializing != null) await initializing;
  }

  @visibleForTesting
  bool get debugIsPermanentlyDisabled => _permanentlyDisabled;
}

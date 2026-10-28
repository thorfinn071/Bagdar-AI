import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/simulation_build.dart';
import 'simulation_bundle.dart';

/// Preloaded inputs, real elapsed-time delivery and no synthetic model outputs.
class SimulationSession extends ChangeNotifier {
  final SimulationBundle bundle;
  final SimulationSequence sequence;
  final String outputPath;
  final String runId;
  final _accelerometer = StreamController<AccelerometerEvent>.broadcast(
    sync: true,
  );
  final _gyroscope = StreamController<GyroscopeEvent>.broadcast(sync: true);
  final List<Uint8List> _pixels = [], _previews = [];
  final List<Map<String, Object?>> _events = [];
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  DateTime? _epoch;
  int _nextFrame = 0, _nextSensor = 0, _generation = 0;
  int _activeCallbacks = 0, _peakCallbacks = 0, _finishedCallbacks = 0;
  int _lastResourceSampleUs = -1000000, _preloadedBytes = 0;
  int _omittedEvents = 0;
  bool _disposed = false, _completed = false;
  bool _hostDisposalAcknowledged = false;
  String _hostDisposalStage = 'not_started';
  void noteHostDisposal(String stage) => _hostDisposalStage = stage;
  void acknowledgeHostDisposal() => _hostDisposalAcknowledged = true;
  bool get disposed => _disposed;
  bool get completed => _completed;
  bool get running => _timer != null;
  Uint8List? preview;
  Future<void> Function(SimulationImage)? _onFrame;
  Map<String, Object?> Function()? runtimeSnapshot;
  final Completer<void> _finished = Completer<void>();
  Future<void> get finished => _finished.future;
  Stream<AccelerometerEvent> get accelerometer => _accelerometer.stream;
  Stream<GyroscopeEvent> get gyroscope => _gyroscope.stream;

  Map<String, Object?> get diagnostics => {
    'activeFrameCallbacks': _activeCallbacks,
    'peakFrameCallbacks': _peakCallbacks,
    'finishedFrameCallbacks': _finishedCallbacks,
    'preloadedBytes': _preloadedBytes,
    'omittedEvents': _omittedEvents,
    'elapsedUs': _clock.elapsedMicroseconds,
    'disposed': _disposed,
    'hostDisposalAcknowledged': _hostDisposalAcknowledged,
    'hostDisposalStage': _hostDisposalStage,
  };

  SimulationSession({
    required this.bundle,
    required this.sequence,
    required this.outputPath,
    this.runId = '',
  }) {
    requireSimulationBuild();
  }

  Future<void> prepare() async {
    if (_pixels.isNotEmpty) return;
    final bytesPerFrame = sequence.width * sequence.height * 3 ~/ 2;
    if (bytesPerFrame * sequence.frames.length > 256 * 1024 * 1024) {
      throw const FormatException('Sequence exceeds preload budget');
    }
    final pixels = <Uint8List>[], previews = <Uint8List>[];
    final cache = <String, Uint8List>{};
    var totalBytes = 0;
    Future<Uint8List> read(Map asset, int limit) async {
      final key = '${asset['path']}:${asset['sha256']}';
      final cached = cache[key];
      if (cached != null) {
        if (cached.length > limit) {
          throw const FormatException('Asset too large');
        }
        return cached;
      }
      final bytes = (await bundle.readAsset(
        asset,
        maximumBytes: limit,
      )).asUnmodifiableView();
      totalBytes += bytes.length;
      if (totalBytes > 256 * 1024 * 1024) {
        throw const FormatException('Sequence exceeds total preload budget');
      }
      return cache[key] = bytes;
    }

    for (final frame in sequence.frames) {
      final bytes = await read(frame['yuv'] as Map, bytesPerFrame);
      if (bytes.length != bytesPerFrame) {
        throw const FormatException('Wrong I420 byte count');
      }
      pixels.add(bytes.asUnmodifiableView());
      previews.add(
        await read(
          frame['preview'] as Map,
          sequence.width * sequence.height * 4 + 65536,
        ),
      );
    }
    if (_disposed) return;
    _pixels.addAll(pixels);
    _previews.addAll(previews);
    _preloadedBytes = totalBytes;
    preview = _previews.first;
    notifyListeners();
  }

  void start(Future<void> Function(SimulationImage) onFrame) {
    if (_disposed || _completed || running) return;
    if (_pixels.length != sequence.frames.length) {
      throw StateError('Prepare before playback');
    }
    _onFrame = onFrame;
    _epoch ??= DateTime.now();
    _clock.start();
    final generation = ++_generation;
    record('playback_started', {'generation': generation});
    unawaited(_writeProgress('playback_started'));
    _timer = Timer.periodic(
      const Duration(milliseconds: 4),
      (_) => _tick(generation),
    );
    _tick(generation);
  }

  void _tick(int generation) {
    if (_disposed || generation != _generation) return;
    final elapsed = _clock.elapsedMicroseconds;
    if (elapsed - _lastResourceSampleUs >= 1000000) {
      _lastResourceSampleUs = elapsed;
      record('resource_sample', {
        'currentRssBytes': ProcessInfo.currentRss,
        'maxRssBytes': ProcessInfo.maxRss,
        ...diagnostics,
        if (runtimeSnapshot != null) 'scheduler': runtimeSnapshot!(),
      });
    }
    while (_nextSensor < sequence.sensors.length &&
        (sequence.sensors[_nextSensor]['offsetUs'] as int) <= elapsed) {
      final sample = sequence.sensors[_nextSensor++];
      final at = _epoch!.add(Duration(microseconds: sample['offsetUs'] as int));
      final a = (sample['accelerometer'] as List).cast<num>();
      final g = (sample['gyroscope'] as List).cast<num>();
      _accelerometer.add(
        AccelerometerEvent(
          a[0].toDouble(),
          a[1].toDouble(),
          a[2].toDouble(),
          at,
        ),
      );
      _gyroscope.add(
        GyroscopeEvent(g[0].toDouble(), g[1].toDouble(), g[2].toDouble(), at),
      );
    }
    while (_nextFrame < sequence.frames.length) {
      final frame = sequence.frames[_nextFrame];
      final offset = frame['offsetUs'] as int;
      if (offset + (frame['deliveryDelayUs'] as int) > elapsed) break;
      final index = _nextFrame++;
      final id = frame['frameId'] as int;
      if (frame['drop'] == true) {
        record('frame_dropped', {'frameId': id, 'captureOffsetUs': offset});
        continue;
      }
      preview = _previews[index];
      final capture = _epoch!.add(Duration(microseconds: offset));
      record('frame_delivered', {
        'frameId': id,
        'captureOffsetUs': offset,
        'captureTimestampUs': capture.microsecondsSinceEpoch,
        'deliveryAgeUs': DateTime.now().difference(capture).inMicroseconds,
      });
      final image = SimulationImage(
        sourceFrameId: id,
        capturedAt: capture,
        width: sequence.width,
        height: sequence.height,
        i420: _pixels[index],
      );
      // The real scheduler decides whether to accept, drop or stagger work.
      // Awaiting inference here would silently slow the simulated camera.
      _activeCallbacks++;
      if (_activeCallbacks > _peakCallbacks) _peakCallbacks = _activeCallbacks;
      unawaited(
        Future<void>.sync(() => _onFrame!(image))
            .catchError((Object e, StackTrace stack) {
              record('callback_error', {'frameId': id, 'error': e.toString()});
            })
            .whenComplete(() {
              _activeCallbacks--;
              _finishedCallbacks++;
            }),
      );
      notifyListeners();
    }
    if (_nextFrame == sequence.frames.length &&
        _nextSensor == sequence.sensors.length) {
      _timer?.cancel();
      _timer = null;
      _completed = true;
      // Keep the app/cadence alive to observe stale data and pending work.
      record('input_ended', {'frames': _nextFrame});
      if (!_finished.isCompleted) _finished.complete();
      notifyListeners();
    }
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    _generation++;
    // Capture age includes time in the background. Never make old frames fresh.
    record('playback_paused', {});
  }

  void record(String type, Map<String, Object?> data) {
    if (_disposed) return;
    if (_events.length >= 30000) {
      _omittedEvents++;
      return;
    }
    _events.add({
      'type': type,
      'elapsedUs': _clock.elapsedMicroseconds,
      ...data,
    });
  }

  Future<void> _progressWrite = Future.value();
  Future<void> _writeProgress(String phase) {
    final snapshot = {
      'runId': runId,
      'sequenceId': sequence.id,
      'manifestSha256': bundle.manifestHash,
      'phase': phase,
      'promotionAllowed': false,
      ...diagnostics,
    };
    _progressWrite = _progressWrite
        .then((_) async {
          final file = File('$outputPath.progress.json');
          await file.parent.create(recursive: true);
          final temporary = File('${file.path}.tmp');
          await temporary.writeAsString(jsonEncode(snapshot));
          await temporary.rename(file.path);
        })
        .catchError((Object error) {
          record('progress_error', {'error': error.toString()});
        });
    return _progressWrite;
  }

  Future<void> writeDisposalReport({required bool routeCompleted}) async {
    final file = File('$outputPath.disposal.json');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'runId': runId,
        'sequenceId': sequence.id,
        'manifestSha256': bundle.manifestHash,
        'promotionAllowed': false,
        'routeCompleted': routeCompleted,
        'currentRssBytes': ProcessInfo.currentRss,
        ...diagnostics,
      }),
    );
  }

  Future<void> writeReport({Map<String, Object?> extra = const {}}) async {
    final file = File(outputPath);
    await file.parent.create(recursive: true);
    final payload = {
      'schemaVersion': 1,
      'sequenceId': sequence.id,
      'runId': runId,
      'synthetic': true,
      'manifestSha256': bundle.manifestHash,
      'promotionAllowed': false,
      'scope':
          'actual application with synthetic inputs; emulator results are not physical-device evidence',
      'completedInput': completed,
      'diagnostics': diagnostics,
      if (runtimeSnapshot != null) 'schedulerAtReport': runtimeSnapshot!(),
      'events': List.of(_events),
      ...extra,
    };
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    pause();
    record('session_disposed', diagnostics);
    _disposed = true;
    _clock.stop();
    _onFrame = null;
    runtimeSnapshot = null;
    _pixels.clear();
    _previews.clear();
    preview = null;
    unawaited(_accelerometer.close());
    unawaited(_gyroscope.close());
    super.dispose();
  }
}

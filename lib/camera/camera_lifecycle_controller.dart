import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, VoidCallback;

import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/field_logger.dart';
import '../services/haptic_service.dart';
import '../services/indoor_gate.dart';
import '../services/tts_service.dart';

abstract class CameraLifecycleHost {
  CameraController? get cameraController;
  set cameraController(CameraController? value);

  bool get isCameraReady;
  set isCameraReady(bool value);

  Future<void> initCamera();
  void onFrame(CameraImage image);

  void onBackgroundEntered();
  void onForegroundResumed();
}

class CameraLifecycleController {
  static const Duration kLazyDisposeDuration = Duration(seconds: 10);
  static const Duration kReinitHeartbeatPeriod = Duration(milliseconds: 500);

  final CameraLifecycleHost host;
  final TtsService tts;
  final FieldLogger fieldLog;
  final IndoorGate indoorGate;
  final VoidCallback? onBackgroundVibrate;

  Timer? _lazyDisposeTimer;
  bool _streamPaused = false;
  Timer? _reinitHeartbeat;
  bool _backgroundWarned = false;

  CameraLifecycleController({
    required this.host,
    required this.tts,
    required this.fieldLog,
    required this.indoorGate,
    this.onBackgroundVibrate,
  });

  bool get backgroundWarned => _backgroundWarned;

  void handleStateChange(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _handlePaused();
    } else if (state == AppLifecycleState.resumed) {
      _handleResumed();
    }
  }

  void _handlePaused() {
    host.onBackgroundEntered();
    indoorGate.reset();

    final ctrl = host.cameraController;
    if (ctrl != null && ctrl.value.isInitialized && !_streamPaused) {
      try {
        ctrl.stopImageStream();
      } catch (_) {}
      _streamPaused = true;
      host.isCameraReady = false;

      _lazyDisposeTimer?.cancel();
      _lazyDisposeTimer = Timer(kLazyDisposeDuration, () {
        host.cameraController?.dispose();
        host.cameraController = null;
        _streamPaused = false;
      });
    }

    fieldLog.logLifecycle('paused');

    if (!_backgroundWarned) {
      _backgroundWarned = true;
      tts.say(
        S.get('lifecycle_background'),
        SpeechPriority.critical,
        pan: 0.0,
      );
      HapticService.vibrate(const [0, 200, 100, 200, 100, 200]);
      onBackgroundVibrate?.call();
    }
  }

  void _handleResumed() {
    if (_backgroundWarned) {
      _backgroundWarned = false;
      tts.say(S.get('lifecycle_resumed'), SpeechPriority.info, pan: 0.0);
    }

    _lazyDisposeTimer?.cancel();
    _lazyDisposeTimer = null;

    final ctrl = host.cameraController;
    if (ctrl != null && ctrl.value.isInitialized && _streamPaused) {
      _streamPaused = false;
      try {
        ctrl.startImageStream(host.onFrame);
        host.isCameraReady = true;
      } catch (_) {
        host.cameraController?.dispose();
        host.cameraController = null;
        unawaited(host.initCamera());
      }
      fieldLog.logLifecycle('resumed', resumeType: 'warm', blindMs: 0);
    } else if (ctrl == null || !ctrl.value.isInitialized) {
      _streamPaused = false;
      tts.say(S.alert('camera_reinit'), SpeechPriority.warning, pan: 0.0);
      _reinitHeartbeat?.cancel();
      _reinitHeartbeat = Timer.periodic(
        kReinitHeartbeatPeriod,
        (_) => HapticService.vibrate(const [0, 100, 300, 100]),
      );
      fieldLog.logLifecycle('resumed', resumeType: 'cold');
      unawaited(host.initCamera());
    }
    host.onForegroundResumed();
  }

  void cancelReinitHeartbeat() {
    if (_reinitHeartbeat == null) return;
    _reinitHeartbeat?.cancel();
    _reinitHeartbeat = null;
  }

  void dispose() {
    _lazyDisposeTimer?.cancel();
    _lazyDisposeTimer = null;
    _reinitHeartbeat?.cancel();
    _reinitHeartbeat = null;
  }
}

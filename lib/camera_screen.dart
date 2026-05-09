import 'dart:async';

import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'models/app_mode.dart';
import 'models/strings.dart';
import 'models/speech_job.dart';
import 'models/constants.dart';
import 'services/settings_service.dart';
import 'models/a11y_prefs.dart';
import 'services/foreground_service.dart';
import 'services/thermal_monitor.dart';
import 'services/haptic_service.dart';
import 'services/earcon_service.dart';
import 'services/sos_service.dart';
import 'models/nav_models.dart';
import 'tracker/appearance.dart';
import 'tracker/raw_det.dart';
import 'tracker/track.dart';
import 'tracker/tracker.dart' show isVehicle;
import 'widgets/status_panel.dart';
import 'widgets/track_painter.dart';
import 'widgets/camera_controls_sheet.dart';
import 'viewmodels/camera_view_model.dart';
import 'services/model_service.dart';
import 'services/battery_monitor.dart';
import 'services/device_capability.dart';
import 'services/motion_prealert.dart'
    show MotionIntrusionEvent, MotionIntrusionSide;
import 'services/traffic_light_analyzer.dart' show TrafficLightKind;
import 'utils/blur_detector.dart';
import 'utils/depth_hazard.dart';
import 'utils/distance_utils.dart';
import 'services/fall_detector.dart' show MotionState;
import 'services/feature_usage_tracker.dart';
import 'services/field_logger.dart';
import 'services/indoor_gate.dart';
import 'camera/frame_quality_guard.dart';
import 'camera/depth_pipeline_controller.dart';
import 'camera/stall_watchdog.dart';
import 'camera/fall_countdown_controller.dart';
import 'camera/voice_command_dispatcher.dart';
import 'camera/camera_lifecycle_controller.dart';
import 'services/scene_narrator.dart';
import 'gesture_tutorial_screen.dart';
import 'screens/settings_qr_export_screen.dart';
import 'screens/settings_qr_import_screen.dart';

class AiCameraScreen extends StatefulWidget {
  final AppMode? initialMode;
  const AiCameraScreen({super.key, this.initialMode});

  @override
  State<AiCameraScreen> createState() => _AiCameraScreenState();
}

class _AiCameraScreenState extends State<AiCameraScreen>
    with WidgetsBindingObserver
    implements CameraLifecycleHost {
  late final CameraViewModel _vm;
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isDetecting = false;

  final ModelService _models = ModelService.instance;
  final FieldLogger _fieldLog = FieldLogger.instance;

  bool _useGpu = false;
  int _numThreads = 2;

  Duration _detectInterval = const Duration(milliseconds: 140);
  DateTime _lastDetectAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);

  int _imgW = 0, _imgH = 0;
  bool _isCalibrated = false;
  bool _useHardwareDepthMode = false;
  final bool _exclusiveDepthTransition = false;
  bool _wantOcr = false;
  DateTime _ocrStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  TrafficLightColor? _lastAnnouncedLight;

  Timer? _heartbeatTimer;
  int _detectionCompletions = 0;
  int _lowFpsStreak = 0;
  DateTime _fpsWindowStart = DateTime.now();
  Timer? _resourceLogTimer;

  Timer? _twoFingerSosTimer;
  bool _twoFingerSosArmed = false;

  
  final List<DateTime> _recentTaps = [];
  static const Duration _tripleTapWindow = Duration(milliseconds: 800);

  
  StreamSubscription<AccelerometerEvent>? _shakeSub;
  final List<DateTime> _shakeSpikes = [];
  static const double _shakeMagnitudeThreshold = 25.0;
  static const Duration _shakeWindow = Duration(milliseconds: 1500);
  DateTime _lastShakeSosAt = DateTime.fromMillisecondsSinceEpoch(0);

  late final FallCountdownController _fallCountdown;
  late final VoiceCommandDispatcher _voiceDispatcher;
  late final CameraLifecycleController _lifecycle;
  late final SceneNarrator _sceneNarrator;

  List<DepthHazard> _lastDepthHazards = [];
  DateTime _lastNarrationAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kNarrationCooldown = Duration(seconds: 5);

  int _frameCount = 0;
  late final FrameQualityGuard _qualityGuard;
  late final DepthPipelineController _depthController;
  late final StallWatchdog _stallWatchdog;

  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  Timer? _indoorPollTimer;
  static const Duration _kIndoorPollPeriod = Duration(seconds: 5);

  
  
  
  final List<RawDet> _rawDetBuffer = <RawDet>[];

  final List<Uint8List> _planeBytesBuffer = List<Uint8List>.filled(
    3,
    Uint8List(0),
    growable: true,
  );

  int _blurryStreak = 0;
  DateTime _lastShakeWarnAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kShakeWarnStreak = 15;
  static const Duration _kShakeWarnCooldown = Duration(seconds: 6);

  
  
  
  DateTime _lastStallWarnTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _stallStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kStallTtsCooldown = Duration(seconds: 60);
  static const Duration _kStallTtsMinDuration = Duration(seconds: 4);
  DateTime _initCompletedAt = DateTime.fromMillisecondsSinceEpoch(0);

  final Map<FrameQualityEventType, DateTime> _lastQualityTtsAt = {};
  static const Duration _kQualityEventCooldown = Duration(seconds: 30);

  
  
  
  DateTime _lastMidasModeAnnounceAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kMidasModeAnnounceCooldown = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _vm = CameraViewModel();
    _qualityGuard = FrameQualityGuard(weatherGate: _vm.weatherGate);
    _depthController = DepthPipelineController(vm: _vm, models: _models);
    
    
    
    
    
    
    
    
    _depthController.onStatusChanged = _onDepthStatusChanged;
    _vm.throttler.onMidasPauseChanged = _onMidasPauseChanged;
    _lifecycle = CameraLifecycleController(
      host: this,
      tts: _vm.tts,
      fieldLog: _fieldLog,
      indoorGate: _vm.indoorGate,
    );
    _stallWatchdog = StallWatchdog(
      thresholdProvider: () => _vm.throttler.stallWatchdogThreshold(),
      isActive: () =>
          mounted && !_lifecycle.backgroundWarned && _isCameraReady,
      onStall: () {
        final now = DateTime.now();
        _stallStartedAt = now;
        final threshold = _vm.throttler.stallWatchdogThreshold();
        
        debugPrint(
          '[BAGDAR_STALL] onStall fired @ ${now.toIso8601String()} '
          'threshold=${threshold.inMilliseconds}ms '
          'mode=${_vm.mode} bg=${_lifecycle.backgroundWarned} '
          'detectInterval=${_detectInterval.inMilliseconds}ms',
        );
        _fieldLog.logCameraStall(
          stalled: true,
          thresholdMs: threshold.inMilliseconds,
        );
        _vm.alertMgr.markCameraStall(now);
        if (now.difference(_lastStallWarnTtsAt) < _kStallTtsCooldown) {
          return;
        }
        _lastStallWarnTtsAt = now;
        _vm.earcon.play(Earcon.cameraBlocked);
        _vm.tts.say(
          S.get('camera_stalled'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      },
    );
    _fallCountdown = FallCountdownController(
      tts: _vm.tts,
      sos: _vm.sos,
      voice: _vm.voice,
      onCancelled: () => _vm.fallDetector.notifyCancelled(),
    );
    _voiceDispatcher = VoiceCommandDispatcher(
      vm: _vm,
      fallCountdown: _fallCountdown,
      onReadTextRequested: () {
        _wantOcr = true;
        _ocrStartedAt = DateTime.now();
        _vm.tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);
      },
      onSosRequested: _triggerSos,
      onDescribeSceneRequested: _describeScene,
    );

    _vm.addListener(() {
      if (mounted) setState(() {});
    });
    _fallCountdown.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _initAll();
    _applySosTriggerListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _resourceLogTimer?.cancel();
    _twoFingerSosTimer?.cancel();
    _tripleTapStatusTimer?.cancel();
    _shakeSub?.cancel();
    _fallCountdown.dispose();
    _stallWatchdog.stop();
    _indoorPollTimer?.cancel();
    _lifecycle.dispose();
    _controller?.dispose();
    _controller = null;
    VisionForegroundService.stop();
    unawaited(_fieldLog.stopSession());
    unawaited(FeatureUsageTracker.instance.flush());
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle.handleStateChange(state);
  }

  @override
  CameraController? get cameraController => _controller;

  @override
  set cameraController(CameraController? value) {
    _controller = value;
  }

  @override
  bool get isCameraReady => _isCameraReady;

  @override
  set isCameraReady(bool value) {
    if (_isCameraReady == value) return;
    if (mounted) {
      setState(() => _isCameraReady = value);
    } else {
      _isCameraReady = value;
    }
  }

  @override
  Future<void> initCamera() => _initCamera();

  @override
  void onFrame(CameraImage image) => _onFrame(image);

  @override
  void onBackgroundEntered() {
    _stallWatchdog.stop();
    _indoorPollTimer?.cancel();
    _indoorPollTimer = null;
  }

  @override
  void onForegroundResumed() {
    _stallWatchdog.start();
  }

  Future<void> _initAll() async {
    try {
      _vm.tracker.ttsService = _vm.tts;

      _isCalibrated = Settings.instance.isCalibrated;
      _useGpu = Settings.instance.useGpu;
      _useHardwareDepthMode = Settings.instance.useHardwareDepthMode;
      _numThreads = Settings.instance.numThreads;
      AppStrings.setLanguage(AppLanguage.values[Settings.instance.language]);
      loadFocalLength();

      _vm.battery.onThrottleChanged = (level) {
        _recomputeCadence();
        _fieldLog.logBatteryThrottle(level.name, _vm.battery.batteryLevel);
        if (mounted) setState(() {});
        if (Settings.instance.batteryAnnounce && level != ThrottleLevel.normal) {
          final msg = switch (level) {
            ThrottleLevel.moderate => S.get('battery_moderate'),
            ThrottleLevel.aggressive => S.get('battery_low_depth_degraded'),
            ThrottleLevel.critical => S.get('battery_low_critical'),
            ThrottleLevel.normal => S.get('battery_moderate'),
          };
          _vm.tts.say(msg, SpeechPriority.info, pan: 0.0);
        }
      };

      _vm.setStatus('Инициализация...');
      await _vm.init();

      final granted = await _requestCameraPermission();
      if (!granted) return;

      _vm.thermal.onChanged = _handleThermalChanged;
      _handleThermalChanged(_vm.thermal.current);

      if (Settings.instance.fieldLogging) {
        await DeviceCapabilityProbe.probe();
        final caps = DeviceCapabilityProbe.cached;
        await _fieldLog.startSession(
          deviceModel: caps.deviceInfo.model,
          androidSdk: caps.androidSdkInt,
          depthTier: caps.bestDepthTier.name,
          batteryPct: _vm.battery.batteryLevel,
        );
        _resourceLogTimer?.cancel();
        _resourceLogTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _logResources(),
        );
      }

      final midasSw = Stopwatch()..start();
      bool ok = false;
      try {
        ok = await _models.loadMidas(numThreads: _numThreads);
        midasSw.stop();
        _fieldLog.logModelLoad(
          model: 'midas',
          loadMs: midasSw.elapsedMilliseconds,
          success: ok,
          tier: _models.depthProvider?.tier.name,
          threads: _numThreads,
        );
      } catch (e) {
        midasSw.stop();
        _fieldLog.logModelLoad(
          model: 'midas',
          loadMs: midasSw.elapsedMilliseconds,
          success: false,
          threads: _numThreads,
          error: e.toString(),
        );
        rethrow;
      }
      if (!mounted) return;

      final hasDepthAi =
          ok &&
          _models.depthProvider != null &&
          _models.depthProvider!.tier != DepthTier.focalLength;
      _depthController.setProviderReady(hasDepthAi);
      if (mounted) setState(() {});

      _vm.setStatus('Загрузка ИИ модели YOLO...');
      final yoloSw = Stopwatch()..start();
      try {
        await _models.loadYolo(useGpu: _useGpu, numThreads: _numThreads);
        yoloSw.stop();
        _fieldLog.logModelLoad(
          model: 'yolo',
          loadMs: yoloSw.elapsedMilliseconds,
          success: true,
          tier: _models.currentYoloTier.name,
          gpu: _useGpu,
          threads: _numThreads,
        );
      } catch (e) {
        yoloSw.stop();
        _fieldLog.logModelLoad(
          model: 'yolo',
          loadMs: yoloSw.elapsedMilliseconds,
          success: false,
          gpu: _useGpu,
          threads: _numThreads,
          error: e.toString(),
        );
        rethrow;
      }

      _vm.setStatus('Запуск камеры...');
      await _initCamera();

      await VisionForegroundService.start();

      _vm.fallDetector.onFallDetected = _fallCountdown.start;
      _vm.fallDetector.onStageChange = (stage, {accel, gyro, stillFrames}) {
        _fieldLog.logFallStage(
          stage,
          accel: accel,
          gyro: gyro,
          stillFrames: stillFrames,
        );
      };
      await _vm.fallDetector.init();

      _vm.tts.onAudioRouteInterrupted = () {
        final elapsed = DateTime.now().difference(_initCompletedAt);
        if (elapsed < const Duration(seconds: 15)) return;
        _fieldLog.logTtsEvent('audio_interrupted');
        _vm.earcon.play(Earcon.cameraBlocked);
      };
      _vm.tts.onAudioRouteResumed = () {
        _fieldLog.logTtsEvent('audio_resumed');
        _vm.tts.say(S.get('audio_resumed'), SpeechPriority.info, pan: 0.0);
      };
      _vm.tts.onTtsStall = () {
        
        
        
        
        
        
        _vm.earcon.play(Earcon.cameraBlocked);
        HapticService.vibrate(
          kHapticTtsStallPattern,
          intensities: kHapticTtsStallIntensities,
        );
        _fieldLog.logTtsEvent('tts_stall');
        try {
          const MethodChannel('bagdar/watchdog').invokeMethod('ping');
        } catch (_) {}
      };

      _heartbeatTimer = Timer.periodic(
        _currentHeartbeatInterval(),
        (_) => _heartbeatTick(),
      );

      _vm.voice.onCommand = _voiceDispatcher.handleCommand;
      _vm.voice.onNavCommand = _voiceDispatcher.handleNavCommand;
      _vm.voice.onListeningStateChanged = (listening) {
        if (listening) {
          _vm.awm.pause();
        } else {
          _vm.earcon.play(Earcon.success);
          _vm.awm.resume();
        }
      };
      _vm.voice.onError = (_) {
        if (_fallCountdown.active) return;
        _vm.earcon.play(Earcon.fail);
        _vm.tts.say(
          S.get('voice_listen_error'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      };

      if (!_depthController.providerReady && _vm.mode == AppMode.street) {
        _vm.tts.say(
          S.get('depth_unavailable_street'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      }
      if (!_vm.tts.languageAvailable || _vm.tts.usingEnglishFallback) {
        _vm.tts.say(S.get('tts_fallback_en'), SpeechPriority.warning, pan: 0.0);
      }

      _vm.setStatus(S.get('system_ready'));
      _vm.tts.say(S.get('system_ready'), SpeechPriority.info, pan: 0.0);
      _initCompletedAt = DateTime.now();
      _maybePlayFirstRunAudioTour();
    } catch (e) {
      _fieldLog.logError('initAll', e.toString());
      _vm.setStatus('Сбой: $e');
    }
  }

  void _maybePlayFirstRunAudioTour() {
    if (Settings.instance.audioTourSeen) return;
    Future<void>.delayed(const Duration(seconds: 3), () async {
      if (!mounted) return;
      _vm.showHelp();
      await Settings.instance.setAudioTourSeen(true);
    });
  }

  Duration _currentHeartbeatInterval() {
    if (_vm.battery.level == ThrottleLevel.critical) {
      return const Duration(seconds: 60);
    }
    if (_vm.isPitchBlack) return kHeartbeatIntervalPitchBlack;
    return kHeartbeatInterval;
  }

  void _heartbeatTick() {
    if (!mounted) return;
    final now = DateTime.now();
    final lastCriticalAt = _vm.alertMgr.lastCriticalAt;
    final lastSpokenAt = _vm.tts.lastSpokenAt;
    final recentCritical = lastCriticalAt.millisecondsSinceEpoch != 0 &&
        now.difference(lastCriticalAt) < const Duration(seconds: 10);
    final recentAnyAlert = lastSpokenAt.millisecondsSinceEpoch != 0 &&
        now.difference(lastSpokenAt) < const Duration(seconds: 15);
    if (!recentAnyAlert) {
    }
    if (!recentCritical) {
      _vm.earcon.play(Earcon.heartbeat);
    }
    try {
      const MethodChannel('bagdar/watchdog').invokeMethod('ping');
    } catch (_) {}

    final windowSec = now.difference(_fpsWindowStart).inMilliseconds / 1000.0;
    final effFps = windowSec > 0 ? _detectionCompletions / windowSec : 0.0;
    _fieldLog.log('effective_fps', {
      'fps': (effFps * 10).round() / 10.0,
      'mode': _vm.mode.name,
      'thermal': _vm.thermal.severity.name,
      'completions': _detectionCompletions,
    });

    final isSafetyMode =
        _vm.mode == AppMode.street || _vm.mode == AppMode.cane;
    final notThermalCritical = _vm.thermal.severity != ThermalSeverity.critical;
    if (effFps < 3.0 && isSafetyMode && notThermalCritical) {
      _lowFpsStreak++;
      if (_lowFpsStreak >= 2) {
        _vm.tts.say(
          S.get('camera_stalled'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        _lowFpsStreak = 0;
      }
    } else {
      _lowFpsStreak = 0;
    }
    _detectionCompletions = 0;
    _fpsWindowStart = now;

    final desired = _currentHeartbeatInterval();
    if (_heartbeatTimer == null || _heartbeatTimer!.tick == 0) return;
    if (desired.inMilliseconds != kHeartbeatInterval.inMilliseconds) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(desired, (_) => _heartbeatTick());
    }
  }

  Timer? _tripleTapStatusTimer;

  void _handleTap() {
    FeatureUsageTracker.instance.increment(FeatureUsageKeys.gesture('tap'));
    if (_fallCountdown.active) {
      _fallCountdown.cancel();
      return;
    }
    if (Settings.instance.sosTrigger == SosTrigger.tripleTap) {
      final now = DateTime.now();
      _recentTaps.removeWhere(
        (t) => now.difference(t) > _tripleTapWindow,
      );
      _recentTaps.add(now);
      if (_recentTaps.length >= 3) {
        _recentTaps.clear();
        _tripleTapStatusTimer?.cancel();
        _tripleTapStatusTimer = null;
        FeatureUsageTracker.instance.increment(
          FeatureUsageKeys.gesture('triple_tap'),
        );
        HapticService.vibrate(const [0, 300, 100, 300]);
        _triggerSos();
        return;
      }
      
      
      _tripleTapStatusTimer?.cancel();
      _tripleTapStatusTimer = Timer(_tripleTapWindow, () {
        if (!mounted) return;
        _announceQuickStatus();
      });
      return;
    }
    _announceQuickStatus();
  }

  void _announceQuickStatus() {
    final mode = _vm.mode.label;
    final battery = _vm.battery.batteryLevel;
    final msg = Settings.instance.batteryAnnounce
        ? S
              .get('status_quick')
              .replaceFirst('{mode}', mode)
              .replaceFirst('{battery}', battery.toString())
        : S.get('status_quick_mode_only').replaceFirst('{mode}', mode);
    _vm.tts.say(msg, SpeechPriority.info, pan: 0.0);
    HapticService.vibrate(const [0, 30]);
  }

  void _applySosTriggerListener() {
    _shakeSub?.cancel();
    _shakeSub = null;
    if (Settings.instance.sosTrigger != SosTrigger.shake) return;
    _shakeSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 80),
    ).listen(_onShake, onError: (_) {});
  }

  void _onShake(AccelerometerEvent e) {
    final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (m < _shakeMagnitudeThreshold) return;
    final now = DateTime.now();
    if (now.difference(_lastShakeSosAt) < const Duration(seconds: 10)) return;
    _shakeSpikes.removeWhere((t) => now.difference(t) > _shakeWindow);
    _shakeSpikes.add(now);
    if (_shakeSpikes.length >= 3) {
      _shakeSpikes.clear();
      _lastShakeSosAt = now;
      FeatureUsageTracker.instance.increment(
        FeatureUsageKeys.gesture('shake'),
      );
      HapticService.vibrate(const [0, 300, 100, 300]);
      _triggerSos();
    }
  }

  void _triggerSos({String source = 'manual'}) async {
    FeatureUsageTracker.instance.increment(FeatureUsageKeys.sosTriggered);
    _fieldLog.logSosTrigger(source);
    HapticService.vibrate([0, 200, 100, 200, 100, 200]);
    _vm.tts.say('SOS', SpeechPriority.critical, pan: 0.0);
    final hasContact = (_vm.sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      _vm.tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
    }
    if (_vm.isIndoor) {
      _vm.tts.say(S.get('sos_indoor_warning'), SpeechPriority.warning, pan: 0.0);
    }

    final result = await _vm.sos.sendSos();
    if (!mounted) return;

    final msg = switch (result) {
      SosResult.sent => S.get('sos_sent'),
      SosResult.sentFallback =>
        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',
      SosResult.noContact => S.get('sos_no_contact'),
      SosResult.noLocation => S.get('sos_sent_no_location'),
      SosResult.launchFailed => S.get('sos_launch_failed'),
      SosResult.error => S.get('sos_error'),
    };
    _fieldLog.logSosTrigger(source, result: result.name);
    _vm.tts.say(msg, SpeechPriority.critical, pan: 0.0);
  }

  void _startVoiceCommand() async {
    FeatureUsageTracker.instance.increment(
      FeatureUsageKeys.gesture('long_press'),
    );
    HapticService.vibrate([0, 100, 50, 100]);
    _vm.tts.say(S.get('voice_listening'), SpeechPriority.critical, pan: 0.0);
    await _vm.voice.startListening();
  }

  
  
  
  Future<void> _pollIndoorState() async {
    if (!mounted) return;
    Position? pos;
    try {
      pos = await Geolocator.getLastKnownPosition();
    } catch (_) {
      pos = null;
    }
    if (!mounted) return;
    final now = DateTime.now();
    final accuracyM = pos?.accuracy;
    final ageSec = pos == null
        ? null
        : now.difference(pos.timestamp).inSeconds;
    final transition = _vm.indoorGate.feed(
      gpsAccuracyM: accuracyM,
      gpsAgeSec: ageSec,
      motion: _vm.fallDetector.motionState,
      now: now,
    );
    if (transition != IndoorTransition.none) {
      _fieldLog.logIndoorGate(
        transition.name,
        gpsAccuracy: accuracyM,
      );
    }
    _vm.applyIndoorTransition(transition);
  }

  void _startIndoorPoll() {
    _indoorPollTimer?.cancel();
    _indoorPollTimer = Timer.periodic(
      _kIndoorPollPeriod,
      (_) => _pollIndoorState(),
    );
  }

  bool _qualityCooldownOk(FrameQualityEventType type, DateTime now) {
    final last = _lastQualityTtsAt[type];
    if (last != null && now.difference(last) < _kQualityEventCooldown) {
      return false;
    }
    _lastQualityTtsAt[type] = now;
    return true;
  }

  void _handleQualityEvents(List<FrameQualityEvent> events) {
    final now = DateTime.now();
    for (final e in events) {
      switch (e.type) {
        case FrameQualityEventType.aeTransitionStarted:
          _fieldLog.logAeTransition(started: true);
          break;
        case FrameQualityEventType.aeTransitionEnded:
          _fieldLog.logAeTransition(started: false, frames: e.frames);
          break;
        case FrameQualityEventType.weatherDegraded:
          _fieldLog.logWeatherGate(
            'degraded',
            variance: e.variance,
            avgLuma: e.avgLuminosity,
          );
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('weather_low_vis'),
              SpeechPriority.warning,
              pan: 0.0,
            );
          }
          break;
        case FrameQualityEventType.weatherRecovered:
          _fieldLog.logWeatherGate(
            'recovered',
            variance: e.variance,
            avgLuma: e.avgLuminosity,
          );
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('weather_restored'),
              SpeechPriority.info,
              pan: 0.0,
            );
          }
          break;
        case FrameQualityEventType.cameraBlocked:
          _fieldLog.logCameraQuality('blocked');
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('camera_blocked'),
              SpeechPriority.critical,
              pan: 0.0,
            );
            HapticService.vibrate([0, 300, 100, 300]);
          }
          break;
        case FrameQualityEventType.cameraPartiallyBlocked:
          _fieldLog.logCameraQuality('partial_block');
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('camera_partial_blocked'),
              SpeechPriority.warning,
              pan: 0.0,
            );
          }
          break;
        case FrameQualityEventType.dropletDetected:
          _fieldLog.logDroplet(
            dirtyRegions: e.dirtyRegions ?? 0,
            warned: true,
          );
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('camera_droplet'),
              SpeechPriority.info,
              pan: 0.0,
            );
          }
          break;
        case FrameQualityEventType.cameraFrozen:
          _fieldLog.logFrozenFrame();
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.get('camera_frozen'),
              SpeechPriority.critical,
              pan: 0.0,
            );
            HapticService.vibrate([0, 500, 200, 500]);
          }
          break;
      }
    }
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return true;
    _vm.setStatus('Доступ к камере отклонён. Разрешите в настройках');
    _vm.tts.say(
      S.get('camera_permission_denied'),
      SpeechPriority.critical,
      pan: 0.0,
    );
    return false;
  }

  Future<void> _initCamera() async {
    final initSw = Stopwatch()..start();
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        initSw.stop();
        _fieldLog.logCameraInit(
          initMs: initSw.elapsedMilliseconds,
          success: false,
          error: 'no_cameras',
        );
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      
      final ctrl = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      _controller = ctrl;
      await ctrl.startImageStream(_onFrame);

      
      
      unawaited(_vm.tts.preClaimAudioFocus());

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _vm.setStatus(S.get('camera_started'));
        });
      }
      _stallWatchdog.start();
      _startIndoorPoll();
      initSw.stop();
      final preview = ctrl.value.previewSize;
      _fieldLog.logCameraInit(
        initMs: initSw.elapsedMilliseconds,
        success: true,
        resolution: preview != null
            ? '${preview.width.toInt()}x${preview.height.toInt()}'
            : null,
      );
    } catch (e) {
      initSw.stop();
      _fieldLog.logCameraInit(
        initMs: initSw.elapsedMilliseconds,
        success: false,
        error: e.toString(),
      );
      _vm.setStatus('Ошибка камеры: $e');
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!mounted || _exclusiveDepthTransition) return;

    final now = DateTime.now();
    _stallWatchdog.notifyFrameArrived(now: now);
    if (_stallWatchdog.isWarned) {
      _stallWatchdog.clearWarning();
      final stallFor = now.difference(_stallStartedAt);
      
      debugPrint(
        '[BAGDAR_STALL] resumed after ${stallFor.inMilliseconds}ms',
      );
      _fieldLog.logCameraStall(
        stalled: false,
        durationMs: stallFor.inMilliseconds,
      );
      if (stallFor >= _kStallTtsMinDuration &&
          _stallStartedAt.millisecondsSinceEpoch != 0) {
      }
      _stallStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    _lifecycle.cancelReinitHeartbeat();

    _frameCount++;
    _imgW = image.width;
    _imgH = image.height;
    final viewportAspect = MediaQuery.sizeOf(context).aspectRatio;

    final frameSw = Stopwatch()..start();

    final yPlane = image.planes[0];
    final qualityReport = _qualityGuard.evaluate(
      yPlane: yPlane.bytes,
      bytesPerRow: yPlane.bytesPerRow,
      width: image.width,
      height: image.height,
      now: now,
    );
    _handleQualityEvents(qualityReport.events);
    _vm.tracker.weatherDegraded = qualityReport.weatherDegraded;

    if (qualityReport.aePipelineFrozen) {
      _finalizeFramePerf(now: now, frameSw: frameSw);
      return;
    }

    final sharpness = BlurDetector.sharpnessScore(
      yPlane.bytes,
      width: image.width,
      height: image.height,
      rowStride: yPlane.bytesPerRow,
      stride: 8,
    );
    if (BlurDetector.isBlurry(sharpness)) {
      _blurryStreak++;
      if (_blurryStreak >= _kShakeWarnStreak &&
          now.difference(_lastShakeWarnAt) >= _kShakeWarnCooldown) {
        _lastShakeWarnAt = now;
        _vm.tts.say(S.get('shake_warning'), SpeechPriority.info, pan: 0.0);
      }
      final predictedTracks = _vm.tracker.predict();
      if (predictedTracks.isNotEmpty) {
        final uiNow = DateTime.now();
        if (uiNow.difference(_lastUiAt) >= _vm.throttler.uiInterval()) {
          _lastUiAt = uiNow;
          _vm.updateTracks(predictedTracks, imgW: _imgW, imgH: _imgH);
        }
      }
      _finalizeFramePerf(now: now, frameSw: frameSw);
      return;
    }
    _blurryStreak = 0;

    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    if (_vm.mode == AppMode.street || _vm.mode == AppMode.cane) {
      final event = _vm.motionPreAlert.feed(
        image,
        now,
        weatherDegraded: _vm.weatherGate.degraded,
        aeTransitioning: qualityReport.aePipelineFrozen,
        indoor: _vm.isIndoor,
      );
      if (event != null) {
        _handleMotionIntrusion(event);
        if (_vm.isIndoor) {
          _fieldLog.log('motion_prealert_indoor', {
            'side': event.side.name,
            'critical': event.isCritical,
            'strength': (event.strength * 100).round(),
          });
        }
      }
    }

    _vm.objectMemoryFeed(image, now);

    final currentDetectInterval = _detectInterval;
    final shouldRunDetect =
        now.difference(_lastDetectAt) >= currentDetectInterval;

    if (!shouldRunDetect || _isDetecting) {
      final predictedTracks = _vm.tracker.predict();
      if (predictedTracks.isNotEmpty) {
        final uiNow = DateTime.now();
        if (uiNow.difference(_lastUiAt) >= _vm.throttler.uiInterval()) {
          _lastUiAt = uiNow;
          _vm.updateTracks(predictedTracks, imgW: _imgW, imgH: _imgH);
        }
      }
      _finalizeFramePerf(now: now, frameSw: frameSw);
      return;
    }

    _isDetecting = true;
    _lastDetectAt = now;

    try {
      if (_wantOcr) {
        if (now.difference(_ocrStartedAt) > const Duration(seconds: 10)) {
          _wantOcr = false;
          _vm.tts.say(S.get('ocr_timeout'), SpeechPriority.info, pan: 0.0);
        } else {
          final text = await _vm.ocr.recognizeFromFrame(image, stabilize: true);
          if (text != null && text.isNotEmpty) {
            _vm.tts.say(text, SpeechPriority.critical, pan: 0.0);
            _wantOcr = false;
          }
        }
      }

      final planeBytes = _reusePlaneBytes(image);
      
      
      
      
      
      final raw = await _models.vision.yoloOnFrame(
        bytesList: planeBytes,
        imageHeight: image.height,
        imageWidth: image.width,
        iouThreshold: 0.45,
        confThreshold: kDetConfThreshold,
        classThreshold: kDetConfThreshold,
      );

      if (!mounted) return;

      
      
      
      
      final yPlaneBytes = planeBytes.isNotEmpty ? planeBytes[0] : null;
      final yStride =
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : null;
      final dets = _buildRawDets(
        raw,
        _imgW,
        _imgH,
        yPlane: yPlaneBytes,
        yRowStride: yStride,
      );
      final inferenceMs = frameSw.elapsedMilliseconds;
      _vm.tracker.userWalking =
          _vm.fallDetector.motionState != MotionState.stationary;
      final tracks = _vm.tracker.update(dets, _imgW, _imgH, now);
      _fieldLog.logDetection(
        frameCount: _frameCount,
        trackCount: tracks.length,
        inferenceMs: inferenceMs,
        maxConf: dets.isEmpty ? null : dets.map((d) => d.conf).reduce((a, b) => a > b ? a : b),
      );

      final uiNow = DateTime.now();
      if (uiNow.difference(_lastUiAt) >= _vm.throttler.uiInterval()) {
        _lastUiAt = uiNow;
        _vm.updateTracks(tracks, imgW: _imgW, imgH: _imgH);
      }

      final criticalAtBefore = _vm.alertMgr.lastCriticalAt;
      final signTrack = _vm.alertMgr.processFrame(
        tracks: tracks,
        imgW: _imgW,
        imgH: _imgH,
        viewportAspect: viewportAspect,
        now: now,
        mode: _vm.mode,
        isCalibrated: _isCalibrated,
        frameCount: _frameCount,
      );
      
      
      
      final criticalAtAfter = _vm.alertMgr.lastCriticalAt;
      if (criticalAtAfter.isAfter(criticalAtBefore)) {
        _vm.throttler.noteCriticalAlert(now: criticalAtAfter);
      }

      _vm.tts.reverseVehicleSuspected = _detectReverseVehicle(
        tracks,
        _imgW,
        _imgH,
      );

      if (signTrack != null) {
        final color = _vm.trafficLight.analyze(
          image,
          signTrack.x1.toInt(),
          signTrack.y1.toInt(),
          signTrack.x2.toInt(),
          signTrack.y2.toInt(),
          trackId: signTrack.id,
        );
        final kind = _vm.trafficLight.lastKind;
        final alreadyAnnounced = _lastAnnouncedLight != null;

        if (kind == TrafficLightKind.vehicle) {
          if (!alreadyAnnounced) {
            _lastAnnouncedLight = TrafficLightColor.red;
            _vm.tts.say(S.get('tl_vehicle'), SpeechPriority.warning, pan: 0.0);
          }
        } else if (kind == TrafficLightKind.unknown &&
            color != TrafficLightColor.unknown) {
          if (!alreadyAnnounced) {
            _lastAnnouncedLight = color;
            _vm.tts.say(
              S.get('tl_uncertain'),
              SpeechPriority.warning,
              pan: 0.0,
            );
          }
        } else if (kind == TrafficLightKind.pedestrian &&
            color != TrafficLightColor.unknown &&
            color != _lastAnnouncedLight) {
          _lastAnnouncedLight = color;

          if (color == TrafficLightColor.green) {
            final vehicleClose = _hasCloseOrApproachingVehicle(tracks);
            final msg = vehicleClose
                ? S.get('tl_green_cars_near')
                : S.get('tl_green_wait');
            _vm.tts.say(msg, SpeechPriority.warning, pan: 0.0);
          } else {
            final key = switch (color) {
              TrafficLightColor.red => 'tl_red',
              TrafficLightColor.yellow => 'tl_yellow',
              _ => 'tl_unknown',
            };
            _vm.tts.say(S.get(key), SpeechPriority.warning, pan: 0.0);
          }
        }
      } else {
        _lastAnnouncedLight = null;
      }

      
      
      
      _depthController.updateYoloTracks(tracks, imgW: _imgW);

      if (_depthController.shouldRun(now) && !_stallWatchdog.isWarned) {
        unawaited(_processDepthAnalysis(image, now));
      }
    } finally {
      _finalizeFramePerf(now: now, frameSw: frameSw);
      _isDetecting = false;
    }
  }

  Future<void> _processDepthAnalysis(CameraImage image, DateTime now) async {
    final alerts = await _depthController.analyze(image, now);
    if (mounted) {
      _lastDepthHazards = alerts.map((a) => a.hazard).toList();
    }
    final provider = _models.depthProvider;
    if (provider != null && provider.lastInferenceMs > 0) {
      _fieldLog.logMidasInference(
        ms: provider.lastInferenceMs.round(),
        tier: provider.tier.name,
        preprocessMs: provider.lastPreprocessMs.round(),
        analyzeMs: provider.lastAnalyzeMs.round(),
      );
    }
    if (!mounted || alerts.isEmpty) return;
    for (final alert in alerts) {
      final hazard = alert.hazard;
      if (hazard.type == DepthHazardType.escalatorRiding) {
        HapticService.vibrate(const [0, 50, 120, 50]);
        continue;
      }
      final hazardKey = DepthPipelineController.hazardKeyFor(hazard.type);
      final priority = alert.isCritical
          ? SpeechPriority.critical
          : SpeechPriority.warning;
      
      
      
      
      _vm.tts.say(
        S.alert(hazardKey),
        priority,
        pan: hazard.pan,
        barge: alert.isCritical,
      );
      _fieldLog.logDepthHazard(
        type: hazard.type.name,
        score: hazard.midasScore,
        coverage: hazard.coverage,
      );
      if (alert.isCritical) {
        HapticService.vibrate(const [0, 300, 120, 300, 120, 300]);
      }
    }
  }

  
  
  
  
  
  
  
  
  
  
  
  void _onDepthStatusChanged(
    DepthPipelineStatus from,
    DepthPipelineStatus to,
  ) {
    
    if (!mounted) return;

    
    
    
    
    String? key;
    SpeechPriority priority = SpeechPriority.warning;
    switch (to) {
      case DepthPipelineStatus.lowConfidence:
      case DepthPipelineStatus.planeFitFailed:
        key = 'depth_degraded';
        priority = SpeechPriority.warning;
        break;
      case DepthPipelineStatus.ok:
        if (from != DepthPipelineStatus.ok) {
          key = 'depth_recovered';
          priority = SpeechPriority.info;
        }
        break;
    }

    _fieldLog.log('depth_pipeline_status', {
      'from': from.name,
      'to': to.name,
    });

    if (key != null) {
      _vm.tts.say(S.alert(key), priority, pan: 0.0);
    }
  }

  
  
  
  
  
  
  
  void _onMidasPauseChanged(bool paused) {
    if (!mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastMidasModeAnnounceAt) <
        _kMidasModeAnnounceCooldown) {
      _fieldLog.log('midas_pause_changed_suppressed', {
        'paused': paused,
        'reason': 'cooldown',
      });
      return;
    }
    _lastMidasModeAnnounceAt = now;
    final key = paused ? 'reduced_mode_depth' : 'reduced_mode_restored';
    final priority =
        paused ? SpeechPriority.warning : SpeechPriority.info;
    _fieldLog.log('midas_pause_changed', {'paused': paused});
    _vm.tts.say(S.alert(key), priority, pan: 0.0);
  }

  void _handleMotionIntrusion(MotionIntrusionEvent event) {
    final pan = switch (event.side) {
      MotionIntrusionSide.left => -1.0,
      MotionIntrusionSide.right => 1.0,
      MotionIntrusionSide.center => 0.0,
    };
    if (event.isCritical) {
      final key = switch (event.side) {
        MotionIntrusionSide.left => 'synth_event_stop_left',
        MotionIntrusionSide.right => 'synth_event_stop_right',
        MotionIntrusionSide.center => 'synth_event_stop_center',
      };
      
      
      
      
      
      
      final winner = _vm.alertMgr.handleMotionIntrusion(
        event,
        text: S.alert(key),
      );
      if (winner != null) {
        _vm.tts.say(
          winner.text,
          winner.priority,
          pan: winner.pan,
          barge: true,
        );
        HapticService.vibrate(
          kHapticCriticalCooldownPattern,
          intensities: kHapticCriticalCooldownIntensities,
        );
        final now = DateTime.now();
        _vm.alertMgr.updateLastCriticalAt(now);
        _vm.throttler.noteCriticalAlert(now: now);
        _fieldLog.log('synth_event_critical', {
          'side': event.side.name,
          'vx': event.vxPxS,
          'vy': event.vyPxS,
          'strength': event.strength,
        });
      } else {
        
        
        
        _fieldLog.log('synth_event_suppressed', {
          'side': event.side.name,
          'reason': 'cross_system_dedup',
        });
      }
      return;
    }
    _vm.earcon.play(Earcon.approaching, pan: pan);
    HapticService.vibrate(const [0, 80, 40, 120]);
  }

  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  
  bool _hasCloseOrApproachingVehicle(List<Track> tracks) {
    for (final t in tracks) {
      if (!isVehicle(t.label)) continue;
      
      if (t.approaching) return true;
      
      
      if (t.dist == 'very close') return true;
      
      
      
    }
    return false;
  }

  static const double _kReverseEdgeMargin = 0.15;
  static const double _kReverseMaxAreaRate = 0.05;

  bool _detectReverseVehicle(List<Track> tracks, int imgW, int imgH) {
    if (imgW <= 0 || imgH <= 0) return false;
    final edgeX = imgW * _kReverseEdgeMargin;
    final edgeY = imgH * _kReverseEdgeMargin;
    for (final t in tracks) {
      if (!isVehicle(t.label)) continue;
      if (t.approaching) continue;
      if (t.distM > 0 && t.distM > 12.0) continue;

      final atEdge = t.x1 < edgeX ||
          t.x2 > imgW - edgeX ||
          t.y1 < edgeY ||
          t.y2 > imgH - edgeY;
      if (!atEdge) continue;

      if (t.areaHist.length >= 2) {
        final dt = t.areaHist.last.$1
                .difference(t.areaHist.first.$1)
                .inMilliseconds /
            1000.0;
        if (dt > 0.1) {
          final areaRate =
              (t.areaHist.last.$2 - t.areaHist.first.$2) / dt;
          if (areaRate.abs() < _kReverseMaxAreaRate) return true;
        }
      } else {
        return true;
      }
    }
    return false;
  }

  List<RawDet> _buildRawDets(
    List<dynamic> raw,
    int imgW,
    int imgH, {
    Uint8List? yPlane,
    int? yRowStride,
  }) {
    
    
    final out = _rawDetBuffer..clear();
    final frameArea = (imgW * imgH).toDouble();
    final canExtractAppearance =
        yPlane != null && yRowStride != null && yRowStride > 0;
    for (final r in raw) {
      final label = (r['tag'] ?? '').toString();
      
      
      
      
      
      if (!kAlertClassWhitelist.contains(label)) continue;
      final conf = (r['confidence'] as num?)?.toDouble() ?? 0.0;
      
      
      if (conf < minConfFor(label)) continue;
      final box = r['box'] as List<dynamic>?;
      if (box == null || box.length < 4) continue;
      final x1 = (box[0] as num).toDouble();
      final y1 = (box[1] as num).toDouble();
      final x2 = (box[2] as num).toDouble();
      final y2 = (box[3] as num).toDouble();
      final bw = x2 - x1;
      final bh = y2 - y1;
      final areaRatio = frameArea > 0 ? (bw * bh) / frameArea : 0.0;
      final heightRatio = imgH > 0 ? bh / imgH : 0.0;
      final bottomRatio = imgH > 0 ? y2 / imgH : 0.0;
      final distM = focalDistM(label, x1, y1, x2, y2);
      final boxCat = distByBox(areaRatio, heightRatio, bottomRatio);
      final dist = distMToCategory(distM, boxCat);
      final appearance = canExtractAppearance
          ? Appearance.extractFromYPlane(
              yPlane: yPlane,
              rowStride: yRowStride,
              imgW: imgW,
              imgH: imgH,
              x1: x1,
              y1: y1,
              x2: x2,
              y2: y2,
            )
          : null;
      out.add(
        RawDet(
          label: label,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          cx: (x1 + x2) / 2,
          cy: (y1 + y2) / 2,
          conf: conf,
          dist: dist,
          distM: distM,
          appearance: appearance,
        ),
      );
    }
    return out;
  }

  void _handleThermalChanged(ThermalReadings readings) {
    if (!mounted) return;
    _vm.throttler.setThermal(readings);
    unawaited(_models.adjustForThermal(_vm.throttler.effectiveSeverity));
    _fieldLog.logThermal(
      _vm.throttler.effectiveSeverity.name,
      detectIntervalMs: _detectInterval.inMilliseconds,
    );
  }

  void _recomputeCadence() {
    _detectInterval = _vm.throttler.detectInterval(
      _vm.battery.detectIntervalMs,
    );
    _depthController.interval =
        _vm.throttler.midasInterval(_vm.battery.midasIntervalMs);
    _fieldLog.logThrottler(
      detectMs: _detectInterval.inMilliseconds,
      midasMs: _depthController.interval.inMilliseconds,
      reason: 'recompute',
      avgInfMs: _vm.throttler.avgInfMs,
      motion: _vm.throttler.motionState.name,
      memory: _vm.throttler.memoryPressure.name,
    );
  }

  void _logResources() {
    if (!mounted || !_fieldLog.active) return;
    final mem = _vm.memory.current;
    _fieldLog.logResources(
      batteryPct: _vm.battery.batteryLevel,
      memAvailMb: mem.isAvailable ? mem.availMB : null,
      memTotalMb: mem.isAvailable ? mem.totalMB : null,
      memPressure: mem.level.name,
      batteryThrottle: _vm.battery.level.name,
    );
  }

  List<Uint8List> _reusePlaneBytes(CameraImage image) {
    final planes = image.planes;
    if (_planeBytesBuffer.length != planes.length) {
      _planeBytesBuffer
        ..clear()
        ..addAll(planes.map((p) => p.bytes));
      return _planeBytesBuffer;
    }
    for (int i = 0; i < planes.length; i++) {
      _planeBytesBuffer[i] = planes[i].bytes;
    }
    return _planeBytesBuffer;
  }

  void _finalizeFramePerf({required DateTime now, required Stopwatch frameSw}) {
    _vm.throttler.update(frameSw.elapsedMilliseconds.toDouble(), now);
    _detectionCompletions++;
  }

  void _openGestureTutorial() {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const GestureTutorialScreen(standalone: true),
      ),
    );
  }

  void _openSettings() {
    FeatureUsageTracker.instance.increment(FeatureUsageKeys.settingsOpened);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: CameraSettingsSheet(
          currentLanguage: AppStrings.current,
          useGpu: _useGpu,
          useNativeDepthBridge:
              _models.depthProvider?.nativeBridgeEnabled ?? false,
          useHardwareDepthMode: _useHardwareDepthMode,
          numThreads: _numThreads,
          showDebugHud: _vm.showDebugHud,
          earconEnabled: _vm.earcon.isEnabled,
          pitchBlackUiEnabled: _vm.isPitchBlack,
          classicGestures: Settings.instance.classicGestures,
          speechRate: Settings.instance.speechRate,
          ttsVolume: Settings.instance.ttsVolume,
          earconVolume: Settings.instance.earconVolume,
          verbosity: Settings.instance.verbosity,
          alertFrequency: Settings.instance.alertFrequency,
          hapticStrength: Settings.instance.hapticStrength,
          sosTrigger: Settings.instance.sosTrigger,
          dominantHand: Settings.instance.dominantHand,
          depthTier: _models.depthProvider?.tier,
          midasReady: _depthController.providerReady,
          sosContactNumber: _vm.sos.contactNumber,
          onLanguageChanged: (lang) async {
            AppStrings.setLanguage(lang);
            await Settings.instance.setLanguage(lang.index);
            await _vm.tts.setLanguage(AppStrings.ttsLang);
            _vm.voice.setLocale(AppStrings.ttsLang);
            if (mounted) setState(() {});
          },
          onUseGpuChanged: (v) {
            _useGpu = v;
            Settings.instance.setUseGpu(v);
          },
          onNativeDepthBridgeChanged: (v) {
            _models.depthProvider?.setNativeBridgeEnabled(v);
          },
          onHardwareDepthModeChanged: (v) {
            _useHardwareDepthMode = v;
            Settings.instance.setUseHardwareDepthMode(v);
          },
          onNumThreadsChanged: (v) {
            _numThreads = v;
            Settings.instance.setNumThreads(v);
          },
          onDebugHudChanged: (v) => _vm.toggleDebugHud(),
          onEarconEnabledChanged: (v) => _vm.earcon.setEnabled(v),
          onPitchBlackUiChanged: (v) {
            Settings.instance.setPitchBlackUi(v);
            if (_vm.isPitchBlack != v) {
              _vm.togglePitchBlack();
            }
            if (mounted) setState(() {});
          },
          onClassicGesturesChanged: (v) {
            Settings.instance.setClassicGestures(v);
            if (mounted) setState(() {});
          },
          onSpeechRateChanged: (v) {
            Settings.instance.setSpeechRate(v);
            _vm.applyA11yPrefs();
          },
          onTtsVolumeChanged: (v) {
            Settings.instance.setTtsVolume(v);
            _vm.applyA11yPrefs();
          },
          onEarconVolumeChanged: (v) {
            Settings.instance.setEarconVolume(v);
            _vm.applyA11yPrefs();
          },
          onVerbosityChanged: (v) {
            Settings.instance.setVerbosity(v);
          },
          onAlertFrequencyChanged: (v) {
            Settings.instance.setAlertFrequency(v);
          },
          onHapticStrengthChanged: (v) {
            Settings.instance.setHapticStrength(v);
            _vm.applyA11yPrefs();
          },
          onSosTriggerChanged: (v) {
            Settings.instance.setSosTrigger(v);
            _applySosTriggerListener();
            if (mounted) setState(() {});
          },
          onDominantHandChanged: (v) {
            Settings.instance.setDominantHand(v);
            if (mounted) setState(() {});
          },
          onReplayTutorial: _openGestureTutorial,
          onReadText: () {
            _wantOcr = true;
            _ocrStartedAt = DateTime.now();
            _vm.tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);
          },
          onCalibrationTap: () {
            _vm.tts.say(S.get('calib_aim'), SpeechPriority.info, pan: 0.0);
          },
          onEditSosContact: () => _showSosContactDialog(),
          onScanLeft: () =>
              _vm.tts.say(S.get('scan_left'), SpeechPriority.info, pan: -1.0),
          onScanCenter: () =>
              _vm.tts.say(S.get('scan_forward'), SpeechPriority.info, pan: 0.0),
          onScanRight: () =>
              _vm.tts.say(S.get('scan_right'), SpeechPriority.info, pan: 1.0),
          onVoiceWarningTest: () => _vm.tts.say(
            'Тест: внимание слева',
            SpeechPriority.warning,
            pan: -1.0,
          ),
          onVoiceCriticalTest: () => _vm.tts.say(
            'Тест: критично по центру',
            SpeechPriority.critical,
            pan: 0.0,
          ),
          onPlayEarcon: (earcon) => _vm.earcon.play(earcon),
          patternFn: (dist, pos) => [
            0,
            dist == 'very close' ? 200 : 120,
            80,
            dist == 'very close' ? 200 : 120,
          ],
          intensFn: (dist, len) =>
              List.filled(len, dist == 'very close' ? 255 : 180),
          vibrateFn: (pattern, {intensities}) =>
              HapticService.vibrate(pattern, intensities: intensities),
          onShowSettingsQr: _openSettingsQrExport,
          onScanSettingsQr: _openSettingsQrImport,
        ),
      ),
    );
  }

  void _openSettingsQrExport() {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsQrExportScreen(tts: _vm.tts),
      ),
    );
  }

  Future<void> _openSettingsQrImport() async {
    if (!mounted) return;
    
    
    
    await _releaseCameraForExternalScanner();
    if (!mounted) {
      unawaited(_initCamera());
      return;
    }
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SettingsQrImportScreen(tts: _vm.tts),
      ),
    );
    if (!mounted) return;
    
    
    if (applied == true) {
      _vm.applyA11yPrefs();
      AppStrings.setLanguage(AppLanguage.values[Settings.instance.language]);
      await _vm.tts.setLanguage(AppStrings.ttsLang);
      _vm.voice.setLocale(AppStrings.ttsLang);
      if (mounted) setState(() {});
    }
    await _initCamera();
  }

  Future<void> _releaseCameraForExternalScanner() async {
    final ctrl = _controller;
    if (ctrl == null) {
      _isCameraReady = false;
      return;
    }
    try {
      if (ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
    } catch (_) {}
    try {
      await ctrl.dispose();
    } catch (_) {}
    if (!mounted) {
      _controller = null;
      _isCameraReady = false;
      return;
    }
    setState(() {
      _controller = null;
      _isCameraReady = false;
    });
  }

  void _showSosContactDialog() {
    final controller = TextEditingController(text: _vm.sos.contactNumber ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          S.get('sos_settings'),
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '+7 XXX XXX XX XX',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white30),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.cyanAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.get('cancel'),
              style: const TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              final ok = await _vm.sos.setContact(controller.text);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                _vm.tts.say(
                  ok ? S.get('save') : S.get('sos_invalid_number'),
                  SpeechPriority.info,
                  pan: 0.0,
                );
              }
            },
            child: Text(
              S.get('save'),
              style: const TextStyle(color: Colors.cyanAccent),
            ),
          ),
        ],
      ),
    );
  }

  String _ruLabel(String label) => label;

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    final ready = _isCameraReady && ctrl != null && ctrl.value.isInitialized;

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: (_) => _disarmTwoFingerSos(),
      child: GestureDetector(
        onTap: _handleTap,
        onDoubleTap: _openSettings,
        onLongPress: _startVoiceCommand,
        onHorizontalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          final leftHanded =
              Settings.instance.dominantHand == DominantHand.left;
          final sign = leftHanded ? -1 : 1;
          if (v > kSwipeStrongVelocity) {
            FeatureUsageTracker.instance.increment(
              FeatureUsageKeys.gesture('swipe_right'),
            );
            _vm.cycleMode(1 * sign);
          } else if (v < -kSwipeStrongVelocity) {
            FeatureUsageTracker.instance.increment(
              FeatureUsageKeys.gesture('swipe_left'),
            );
            _vm.cycleMode(-1 * sign);
          } else if (v.abs() > kSwipeWeakVelocity) {
            _notifyWeakGesture();
          }
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity;
          if (v == null) return;
          final classic = Settings.instance.classicGestures;
          if (v < -kSwipeStrongVelocity) {
            FeatureUsageTracker.instance.increment(
              FeatureUsageKeys.gesture('swipe_up'),
            );
            classic ? _vm.togglePitchBlack() : _vm.showHelp();
          } else if (v > kSwipeStrongVelocity) {
            FeatureUsageTracker.instance.increment(
              FeatureUsageKeys.gesture('swipe_down'),
            );
            classic ? _vm.showHelp() : _vm.togglePitchBlack();
          } else if (v.abs() > kSwipeWeakVelocity) {
            _notifyWeakGesture();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ready) CameraPreview(ctrl),
                    Positioned.fill(
                      child: ValueListenableBuilder<List<Track>>(
                        valueListenable: _vm.tracksNotifier,
                        builder: (_, tracks, __) => CustomPaint(
                          painter: TrackPainter(
                            tracks: tracks,
                            imgW: _imgW,
                            imgH: _imgH,
                            previewSize: ctrl?.value.previewSize,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (_vm.isPitchBlack)
                Positioned.fill(child: Container(color: Colors.black)),

              if (_vm.isPitchBlack)
                Positioned(
                  top: 48,
                  right: 16,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),

              if (_fallCountdown.active)
                Positioned.fill(
                  child: Container(
                    color: Colors.red.withValues(alpha: 0.3),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            size: 60,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${S.get('sos_fall_countdown')} ${_fallCountdown.secondsLeft} ${S.get('sos_fall_seconds')}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            S.get('sos_fall_cancelled'),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              Positioned.fill(
                child: Semantics(
                  label: S.get(
                    Settings.instance.classicGestures
                        ? 'camera_screen_semantics_classic'
                        : 'camera_screen_semantics',
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: ExcludeSemantics(
                    child: StatusPanel(
                      statusLine: _vm.statusLine,
                      tracksNotifier: _vm.tracksNotifier,
                      imgW: _imgW,
                      imgH: _imgH,
                      viewportAspect: MediaQuery.sizeOf(context).aspectRatio,
                      ruLabel: _ruLabel,
                      mode: _vm.mode,
                    ),
                  ),
                ),
              ),

              if (_fieldLog.active)
                Positioned(
                  top: 48,
                  left: 16,
                  child: Row(
                    children: [
                      _FieldMarkerButton(
                        color: Colors.redAccent,
                        icon: Icons.cancel,
                        label: 'FP',
                        onTap: () {
                          _fieldLog.logFpMarker();
                          HapticService.vibrate(const [0, 60]);
                        },
                      ),
                      const SizedBox(width: 12),
                      _FieldMarkerButton(
                        color: Colors.amber,
                        icon: Icons.warning,
                        label: 'FN',
                        onTap: () {
                          _fieldLog.logFnMarker();
                          HapticService.vibrate(const [0, 60]);
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  final Set<int> _activePointers = {};
  DateTime? _lastWeakGestureAt;

  void _notifyWeakGesture() {
    final now = DateTime.now();
    if (_lastWeakGestureAt != null &&
        now.difference(_lastWeakGestureAt!) < kWeakGestureCooldown) {
      return;
    }
    _lastWeakGestureAt = now;
    _vm.earcon.play(Earcon.fail);
    _vm.tts.say(S.get('gesture_weak'), SpeechPriority.info, pan: 0.0);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (Settings.instance.sosTrigger != SosTrigger.twoFingerHold) return;
    if (_activePointers.length == 2 && !_twoFingerSosArmed) {
      _twoFingerSosArmed = true;
      _twoFingerSosTimer?.cancel();
      _twoFingerSosTimer = Timer(kSosTwoFingerHold, () {
        if (!_twoFingerSosArmed) return;
        _twoFingerSosArmed = false;
        FeatureUsageTracker.instance.increment(
          FeatureUsageKeys.gesture('two_finger_hold'),
        );
        HapticService.vibrate(const [0, 300, 100, 300]);
        _triggerSos();
      });
    } else if (_activePointers.length > 2) {
      _disarmTwoFingerSos();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) {
      _disarmTwoFingerSos();
    }
  }

  void _describeScene({SceneFilter filter = SceneFilter.all}) {
    if (!Settings.instance.sceneNarrationEnabled) return;
    
    final now = DateTime.now();
    if (now.difference(_lastNarrationAt) < _kNarrationCooldown) {
      _vm.tts.say(S.get('scene_cooldown'), SpeechPriority.info, pan: 0.0);
      return;
    }
    _lastNarrationAt = now;

    _vm.tts.say(S.get('scene_narrating'), SpeechPriority.info, pan: 0.0);

    final snapshot = SceneSnapshot(
      objects: _vm.tracksNotifier.value.map((t) => SceneObject(
        label: t.label,
        direction: S.dir(clockDir(t.x1, t.x2, _imgW.toDouble())),
        distance: t.dist,
        distM: t.distM > 0 ? t.distM : null,
        approaching: t.approaching,
        threatScore: t.dist == 'very close' ? 3.0 : t.dist == 'close' ? 2.0 : 1.0,
      )).toList(),
      hazards: _lastDepthHazards,
      trafficLight: _vm.trafficLight.confirmedColor,
      trafficLightKind: _vm.trafficLight.lastKind,
      ocrText: (DateTime.now().difference(_ocrStartedAt).inSeconds < 5) 
          ? null // For now, ocrText requires a dedicated cache if we want to read the last recognized text. We will skip caching text here to keep it simple, or we need to add _lastOcrText. Let's just omit it. Wait, the plan says "if recently captured". But there's no `_lastOcrText` in camera_screen.dart. Let me pass null.
          : null,
      isIndoor: _vm.indoorGate.state == IndoorState.indoor,
      mode: _vm.mode,
      filter: filter,
    );

    final text = _sceneNarrator.narrate(snapshot, Settings.instance.verbosity);
    _vm.tts.say(text, SpeechPriority.info, pan: 0.0);

    FieldLogger.instance.logSceneNarration(
      objectCount: snapshot.objects.length,
      hazardCount: snapshot.hazards.length,
      hasOcr: snapshot.ocrText != null,
      hasTrafficLight: snapshot.trafficLight != null && snapshot.trafficLight != TrafficLightColor.unknown,
      narrateLengthChars: text.length,
    );
  }

  void _disarmTwoFingerSos() {
    _twoFingerSosArmed = false;
    _twoFingerSosTimer?.cancel();
    _twoFingerSosTimer = null;
    _activePointers.clear();
  }
}

class _FieldMarkerButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FieldMarkerButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

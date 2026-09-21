import 'dart:async';

import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import 'core/core_feature_policy.dart';
import 'core/core_health_coordinator.dart';
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
import 'services/navigation_service.dart' show NavState;
import 'models/nav_models.dart';
import 'tracker/appearance.dart';
import 'tracker/raw_det.dart';
import 'tracker/track.dart';
import 'tracker/tracker.dart' show isVehicle;
import 'widgets/status_panel.dart';
import 'widgets/track_painter.dart';
import 'widgets/camera_controls_sheet.dart';
import 'widgets/quick_shelf.dart';
import 'widgets/a11y/voice_layer.dart';
import 'viewmodels/camera_view_model.dart';
import 'services/model_service.dart';
import 'services/battery_monitor.dart';
import 'services/device_capability.dart';
import 'services/motion_prealert.dart'
    show MotionIntrusionEvent, MotionIntrusionSide;
import 'services/traffic_light_analyzer.dart' show TrafficLightKind;
import 'utils/blur_detector.dart';
import 'utils/alert_filter.dart';
import 'utils/depth_hazard.dart';
import 'utils/distance_utils.dart';
import 'services/fall_detector.dart' show MotionState;
import 'models/tts_engine.dart' show KkTtsEngine;
import 'services/feature_usage_tracker.dart';
import 'services/field_logger.dart';
import 'services/indoor_gate.dart';
import 'services/orientation_service.dart' show DevicePitch;
import 'services/misalignment_watchdog.dart';
import 'services/phone_abandoned_detector.dart';
import 'camera/frame_quality_guard.dart';
import 'camera/depth_pipeline_controller.dart';
import 'camera/stall_watchdog.dart';
import 'camera/fall_countdown_controller.dart';
import 'camera/voice_command_dispatcher.dart';
import 'camera/camera_lifecycle_controller.dart';
import 'safety/world/local_scene_snapshot.dart';
import 'services/scene_narrator.dart';
import 'gesture_tutorial_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'models/language_pack.dart';
import 'screens/language_packs_screen.dart';
import 'screens/settings_qr_export_screen.dart';
import 'screens/settings_qr_import_screen.dart';
import 'services/language_pack_manager.dart';
import 'theme/bagdar_theme.dart';
import 'theme/bagdar_tokens.dart';

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
  double _viewportAspect = 1.0;
  bool _isCalibrated = false;
  bool _isCalibrating = false;
  Timer? _calibrationTimeoutTimer;
  bool _useHardwareDepthMode = false;
  final bool _exclusiveDepthTransition = false;
  bool _wantOcr = false;
  DateTime _ocrStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  TrafficLightColor? _lastAnnouncedLight;

  ShelfTask _shelfTask = ShelfTask.camera;
  bool _isVoiceListening = false;

  Timer? _pitchBlackHeartbeatTimer;
  static const Duration _kPitchBlackHeartbeatInterval = Duration(seconds: 30);

  Timer? _heartbeatTimer;
  int _detectionCompletions = 0;
  int _lowFpsStreak = 0;
  DateTime _fpsWindowStart = DateTime.now();
  Timer? _resourceLogTimer;
  Timer? _spatialSafetyTickTimer;
  static const Duration _kSpatialSafetyTickPeriod = Duration(milliseconds: 250);

  Timer? _twoFingerSosTimer;
  bool _twoFingerSosArmed = false;

  final List<DateTime> _recentTaps = [];
  static const Duration _tripleTapWindow = Duration(milliseconds: 800);

  StreamSubscription<AccelerometerEvent>? _shakeSub;

  /// Connectivity listener for the onboarding "remind me when online" path.
  /// Subscribed in initState, cancelled in dispose. One-shot: fires the
  /// announcement at most once per app process via `_onlineKkPromptDone`.
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _onlineKkPromptDone = false;
  final List<DateTime> _shakeSpikes = [];
  static const double _shakeMagnitudeThreshold = 25.0;
  static const Duration _shakeWindow = Duration(milliseconds: 1500);
  DateTime _lastShakeSosAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _sosContactPromptedThisSession = false;
  Timer? _nativeWatchdogTimer;

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

  /// V4.2: Timestamp of the most recent audio-route interruption (Bluetooth
  /// disconnect).  Used to decide whether a critical alert needs to be
  /// replayed after the route stabilises.
  DateTime? _routeChangeAt;

  AppMode? _lastObservedMode;

  final Map<FrameQualityEventType, DateTime> _lastQualityTtsAt = {};
  static const Duration _kQualityEventCooldown = Duration(seconds: 30);

  /// Safety audit D-1: AE transitions blind the motion-prealert safety net
  /// entirely (MotionPreAlert.feed returns null while aeTransitioning), so
  /// unlike the other quality events, an AE start must be surfaced far more
  /// often than the shared 30 s [_kQualityEventCooldown] — a second doorway
  /// transition inside 30 s must not be silent.
  DateTime _lastAeTransitionEarconAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAeTransitionTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kAeTransitionEarconCooldown = Duration(seconds: 5);
  static const Duration _kAeTransitionTtsCooldown = Duration(seconds: 10);

  DateTime _lastMidasModeAnnounceAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kMidasModeAnnounceCooldown = Duration(seconds: 30);

  final MisalignmentWatchdog _misalignmentWatchdog = MisalignmentWatchdog();
  Timer? _misalignmentTickTimer;
  static const Duration _kMisalignmentTickInterval = Duration(seconds: 1);

  final PhoneAbandonedDetector _phoneAbandoned = PhoneAbandonedDetector();

  DateTime _lastWinterHeartbeatAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kWinterHeartbeatInterval = Duration(seconds: 60);

  DateTime _lastWeatherDepthHeartbeatAt = DateTime.fromMillisecondsSinceEpoch(
    0,
  );
  static const Duration _kWeatherDepthHeartbeatInterval = Duration(seconds: 60);

  // Safety audit 2026-06 fix A-1: YOLO unavailability tracking
  Timer? _yoloRetryTimer;
  DateTime _yoloDownSince = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastYoloUnavailWarnAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kYoloDetectorWarnDelay = Duration(seconds: 10);
  static const Duration _kYoloRetryInterval = Duration(seconds: 30);
  static const Duration _kYoloDetectorWarnCooldown = Duration(seconds: 30);

  DateTime _lastGyroDegradedAnnounceAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _kGyroDegradedAnnounceCooldown = Duration(seconds: 60);

  bool _cameraPermissionDenied = false;
  Timer? _cameraPermissionTimer;
  Timer? _cameraInitRetryTimer;

  @override
  void initState() {
    super.initState();
    _vm = CameraViewModel();
    _qualityGuard = FrameQualityGuard(weatherGate: _vm.weatherGate);
    _depthController = DepthPipelineController(vm: _vm, models: _models);

    _depthController.onStatusChanged = _onDepthStatusChanged;
    // Safety audit 2026-06 fix A-1: subscribe to YOLO unavailability
    _models.onYoloUnavailable = _onYoloUnavailable;
    _vm.throttler.onMidasPauseChanged = _onMidasPauseChanged;
    _lifecycle = CameraLifecycleController(
      host: this,
      tts: _vm.tts,
      fieldLog: _fieldLog,
      indoorGate: _vm.indoorGate,
      motionStateProvider: () => _vm.fallDetector.motionState,
      onPausedWalkingEarcon: () => _vm.earcon.play(Earcon.heartbeat),
    );
    _stallWatchdog = StallWatchdog(
      thresholdProvider: () => _vm.throttler.stallWatchdogThreshold(),
      isActive: () => mounted && !_lifecycle.backgroundWarned && _isCameraReady,
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

        final stallCooldown =
            (_vm.mode == AppMode.street || _vm.mode == AppMode.cane)
            ? const Duration(seconds: 15)
            : _kStallTtsCooldown;
        if (now.difference(_lastStallWarnTtsAt) < stallCooldown) {
          return;
        }
        _vm.alertMgr.markCameraStall(now);
        _lastStallWarnTtsAt = now;
        _vm.submitCameraSafety(
          speechKey: 'camera_stalled',
          replaceKey: 'camera_stall',
          now: now,
          critical: _vm.fallDetector.motionState != MotionState.stationary,
          urgency: 0.9,
        );
      },
    );
    _fallCountdown = FallCountdownController(
      tts: _vm.tts,
      sos: _vm.sos,
      voice: _vm.voice,
      onCancelled: () {
        _vm.fallDetector.notifyCancelled();
        _vm.sos.cancelQueuedFollowUp();
      },
      onSosSent: () => _vm.fallDetector.notifyFallSosSent(),
      onSafetyFeedback: (speechKey, replaceKey, now) {
        _vm.submitEmergencySafety(
          speechKey: speechKey,
          replaceKey: replaceKey,
          now: now,
        );
      },
      winterModeProvider: () => _vm.winterMode.active,
      motionStateProvider: () => _vm.fallDetector.motionState,
      deliberateTapThresholdProvider: () =>
          Settings.instance.tapSensitivity.accelThresholdMps2,
    );
    _voiceDispatcher = VoiceCommandDispatcher(
      vm: _vm,
      fallCountdown: _fallCountdown,
      onReadTextRequested: () {
        if (!_isCameraReady) {
          _vm.tts.say(
            S.get('ocr_camera_not_ready'),
            SpeechPriority.warning,
            pan: 0.0,
          );
          _vm.earcon.play(Earcon.fail);
          HapticService.vibrate(const [0, 100, 50, 100]);
          return;
        }
        _wantOcr = true;
        _ocrStartedAt = DateTime.now();
        _vm.tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);
      },
      onSosRequested: _triggerSos,
      onDescribeSceneRequested: _describeScene,
      onShowLanguagePacks: _openLanguagePacks,
    );

    _vm.addListener(() {
      if (mounted) setState(() {});
      _managePitchBlackHeartbeat();

      _qualityGuard.setMode(scanModeActive: _vm.mode == AppMode.scan);

      final newMode = _vm.mode;
      if (newMode != _lastObservedMode) {
        final transitioningIntoSafetyMode =
            (newMode == AppMode.street || newMode == AppMode.cane) &&
            (_lastObservedMode == null ||
                !(_lastObservedMode == AppMode.street ||
                    _lastObservedMode == AppMode.cane));
        if (transitioningIntoSafetyMode &&
            _initCompletedAt.millisecondsSinceEpoch != 0 &&
            !_depthController.providerReady) {
          _vm.tts.say(
            S.get('depth_unavailable_street'),
            SpeechPriority.warning,
            pan: 0.0,
          );
        }

        if (transitioningIntoSafetyMode &&
            _initCompletedAt.millisecondsSinceEpoch != 0 &&
            Settings.instance.disclaimerNeedsReprompt) {
          _vm.tts.say(
            S.get('onb_secondary_aid_tts'),
            SpeechPriority.warning,
            pan: 0.0,
          );
          unawaited(Settings.instance.setDisclaimerAcknowledged(true));
          _fieldLog.log('disclaimer_reprompted', {'mode': newMode.name});
        }
        _lastObservedMode = newMode;
      }
    });
    _fallCountdown.addListener(() {
      if (mounted) setState(() {});
    });
    _vm.tracksNotifier.addListener(_onTracksUpdatedForWatchdog);
    _misalignmentTickTimer = Timer.periodic(
      _kMisalignmentTickInterval,
      (_) => _misalignmentTick(),
    );
    WidgetsBinding.instance.addObserver(this);
    _initAll();
    _applySosTriggerListener();
    _startConnectivityKkPromptListener();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewportAspect = MediaQuery.sizeOf(context).aspectRatio;
  }

  void _onTracksUpdatedForWatchdog() {
    if (_vm.tracksNotifier.value.isNotEmpty) {
      _misalignmentWatchdog.noteDetection();
    }
  }

  void _misalignmentTick() {
    if (!mounted) return;
    _misalignmentWatchdog.notePitchState(_vm.orientation.state);
    _misalignmentWatchdog.noteMotionState(_vm.fallDetector.motionState);
    final result = _misalignmentWatchdog.tick();
    if (result.fireHaptic && !result.shouldAnnounce) {
      HapticService.vibrate(const [0, 60, 60, 60]);
    }
    if (result.shouldAnnounce) {
      _vm.submitCameraSafety(
        speechKey: result.announceKey!,
        replaceKey: 'misalignment',
        now: DateTime.now(),
        critical: result.announcePriority == SpeechPriority.critical,
        urgency: result.announcePriority == SpeechPriority.critical
            ? 0.95
            : 0.7,
      );
      _fieldLog.log('misalignment_announced', {
        'priority': result.announcePriority!.name,
        'sustained_since': _misalignmentWatchdog.sustainedSinceAt
            ?.toIso8601String(),
      });
    }
    if (CoreFeaturePolicy.current.mayInitialize(CoreFeature.phoneAbandoned)) {
      _phoneAbandonedTick();
    }
    _winterHeartbeatTick();
    _weatherDepthHeartbeatTick();
  }

  void _weatherDepthHeartbeatTick() {
    if (!_vm.weatherGate.degraded) return;

    if (_vm.fallDetector.motionState != MotionState.walking) return;

    if (_vm.mode != AppMode.street && _vm.mode != AppMode.cane) return;
    final now = DateTime.now();
    if (now.difference(_lastWeatherDepthHeartbeatAt) <
        _kWeatherDepthHeartbeatInterval) {
      return;
    }
    _lastWeatherDepthHeartbeatAt = now;
    _vm.tts.say(
      S.get('weather_depth_off_walking'),
      SpeechPriority.warning,
      pan: 0.0,
    );
    _fieldLog.log('weather_depth_heartbeat', const {});
  }

  /// Winter Mode: while weather is degraded AND winter mode is active, speak
  /// a brief "плохая видимость — аккуратно" heartbeat every 60 s. Reminds
  /// the user that degradation is sustained (not a one-shot warning) and
  /// keeps them in slow-walk mental state.
  void _winterHeartbeatTick() {
    if (!_vm.winterMode.active) return;
    if (!_vm.weatherGate.degraded) return;
    final now = DateTime.now();
    if (now.difference(_lastWinterHeartbeatAt) < _kWinterHeartbeatInterval) {
      return;
    }
    _lastWinterHeartbeatAt = now;
    _vm.tts.say(
      S.get('winter_visibility_heartbeat'),
      SpeechPriority.warning,
      pan: 0.0,
    );
    _fieldLog.log('winter_heartbeat', const {});
  }

  /// M12: detect the "phone left on a bench / table" failure mode. Pulls the
  /// already-computed signals from FallDetector and FrameQualityGuard, ticks
  /// the detector, and dispatches the resulting alert / soft heartbeat.
  void _phoneAbandonedTick() {
    _phoneAbandoned.noteMotionState(_vm.fallDetector.motionState);
    _phoneAbandoned.noteCameraFrozen(_qualityGuard.cameraFrozenWarned);

    final lumaNormal =
        !_qualityGuard.cameraBlockedWarned && !_qualityGuard.aeTransitioning;
    _phoneAbandoned.noteLumaNormal(lumaNormal);

    final result = _phoneAbandoned.tick();
    if (result.fireCriticalAlert) {
      _vm.tts.say(
        S.get(PhoneAbandonedDetector.kAnnounceKey),
        SpeechPriority.critical,
        pan: 0.0,
      );
      final pattern = result.hapticPattern;
      if (pattern != null) {
        HapticService.vibrate(pattern);
      }
      _vm.earcon.play(Earcon.cameraBlocked);
      _fieldLog.log('phone_abandoned_critical', {
        'haptic_level': result.hapticEscalationLevel,
        'stationary_since': _phoneAbandoned.stationarySinceAt
            ?.toIso8601String(),
      });
    }
    if (result.fireSoftHeartbeat) {
      _vm.earcon.play(
        Earcon.heartbeat,
        volume: PhoneAbandonedDetector.kSoftHeartbeatVolume,
      );
    }
  }

  @override
  void dispose() {
    _stopNativeWatchdog();
    WidgetsBinding.instance.removeObserver(this);
    _cameraPermissionTimer?.cancel();
    _cameraInitRetryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _pitchBlackHeartbeatTimer?.cancel();
    _resourceLogTimer?.cancel();
    _stopSpatialSafetyCadence();
    _twoFingerSosTimer?.cancel();
    _tripleTapStatusTimer?.cancel();
    _shakeSub?.cancel();
    _connSub?.cancel();
    _fallCountdown.dispose();
    _stallWatchdog.stop();
    _indoorPollTimer?.cancel();
    _misalignmentTickTimer?.cancel();
    _calibrationTimeoutTimer?.cancel();
    _yoloRetryTimer?.cancel();
    _vm.tracksNotifier.removeListener(_onTracksUpdatedForWatchdog);
    _vm.sos.cancelQueuedFollowUp();
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
    _stopSpatialSafetyCadence();
    _vm.endCameraSession(DateTime.now());
    _stallWatchdog.stop();
    _stopNativeWatchdog();
    _indoorPollTimer?.cancel();
    _indoorPollTimer = null;
  }

  @override
  void onCameraSessionStarting() {
    final sessionGeneration = _vm.beginCameraSession(DateTime.now());
    _depthController.beginSession(sessionGeneration);
  }

  @override
  void onForegroundResumed() {
    _stallWatchdog.start();
    if (_isCameraReady) {
      _startNativeWatchdog();
      _startSpatialSafetyCadence();
    }
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
        if (Settings.instance.batteryAnnounce &&
            level != ThrottleLevel.normal) {
          final msg = switch (level) {
            ThrottleLevel.moderate => S.get('battery_moderate'),
            ThrottleLevel.aggressive => S.get('battery_low_depth_degraded'),
            ThrottleLevel.critical => S.get('battery_low_critical'),
            ThrottleLevel.normal => S.get('battery_moderate'),
          };
          _vm.tts.say(msg, SpeechPriority.info, pan: 0.0);
        }
      };

      // V5.4: Proactive battery remaining-time announcements at 50/30/15 %.
      _vm.battery.onProactiveAnnounce = (pct) {
        if (!mounted || !Settings.instance.batteryAnnounce) return;
        final msg = switch (pct) {
          kBattery50AnnounceThreshold => S.get('battery_50_remaining'),
          kBattery30AnnounceThreshold => S.get('battery_30_warning'),
          _ => S.get('battery_15_critical'),
        };
        _vm.tts.say(msg, SpeechPriority.warning, pan: 0.0);
      };

      // V1.2: Announce when the user starts running to prompt them to slow down.
      _vm.onMotionStateChanged = (state) {
        if (!mounted) return;
        if (state == MotionState.running) {
          _vm.tts.say(
            S.get('running_detected'),
            SpeechPriority.warning,
            pan: 0.0,
          );
        }
      };

      _vm.setStatus('Инициализация...');
      await _vm.init();

      final granted = await _requestCameraPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _cameraPermissionDenied = true;
          });
          _speakCameraPermissionDeniedLoop();
        }
        return;
      } else {
        if (mounted) {
          setState(() {
            _cameraPermissionDenied = false;
          });
        }
      }

      // F-18: Proactive SOS Contact Check on first run
      if ((_vm.sos.contactNumber ?? '').isEmpty &&
          !Settings.instance.sosContactPrompted &&
          !_sosContactPromptedThisSession) {
        _sosContactPromptedThisSession = true;
        await Settings.instance.setSosContactPrompted(true);
        _vm.tts.say(
          S.get('sos_setup_prompt_tts'),
          SpeechPriority.info,
          pan: 0.0,
        );
        _showSosContactDialog();
      }

      _startNativeWatchdog();

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

      _vm.fallDetector.onFallDetected = (fallClass) =>
          _fallCountdown.start(fallClass: fallClass);
      _vm.fallDetector.onSecondFallDuringLockout = () {
        _vm.sos.queueFollowUpFall();
        _fieldLog.log('second_fall_during_lockout', {
          'pending': _vm.sos.pendingFollowUpCount,
        });
      };
      _vm.fallDetector.onStageChange = (stage, {accel, gyro, stillFrames}) {
        _fieldLog.logFallStage(
          stage,
          accel: accel,
          gyro: gyro,
          stillFrames: stillFrames,
        );
      };
      _vm.fallDetector.onGyroUnavailable = _announceGyroDegraded;
      await _vm.fallDetector.init();
      _vm.health.note(
        component: CoreComponent.accelerometer,
        state: _vm.fallDetector.isReady
            ? ComponentState.available
            : ComponentState.unavailable,
        reasonCode: _vm.fallDetector.isReady ? 'accel_ok' : 'accel_missing',
        now: DateTime.now(),
        announce: false,
      );
      _vm.health.note(
        component: CoreComponent.gyroscope,
        state: _vm.fallDetector.isGyroAvailable
            ? ComponentState.available
            : ComponentState.degraded,
        reasonCode: _vm.fallDetector.isGyroAvailable
            ? 'gyro_ok'
            : 'gyro_unavailable',
        now: DateTime.now(),
        announce: false,
      );
      if (!_vm.fallDetector.isReady) {
        _vm.tts.say(
          S.get('fall_detector_unavailable'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      } else if (!_vm.fallDetector.isGyroAvailable) {
        // Accelerometer alive but gyroscope never started — announce the
        // degraded-accuracy profile immediately so the user knows rotational
        // confirmation is off.
        _announceGyroDegraded();
      }

      _vm.tts.onKazakhVoiceMissing = () {
        _vm.tts.say(S.get('tts_fallback_ru'), SpeechPriority.warning, pan: 0.0);
      };

      _vm.tts.onAudioRouteInterrupted = () {
        final elapsed = DateTime.now().difference(_initCompletedAt);
        if (elapsed < const Duration(seconds: 15)) return;
        if (CoreFeaturePolicy.current.mayInitialize(CoreFeature.sonar)) {
          unawaited(
            _vm.sonar.pauseForAudioInterruption('tts_audio_route_interrupted'),
          );
        }
        _fieldLog.logTtsEvent('audio_interrupted');
        _vm.earcon.play(Earcon.cameraBlocked);
        _routeChangeAt = DateTime.now();
      };
      _vm.tts.onAudioRouteResumed = () {
        _fieldLog.logTtsEvent('audio_resumed');
        // V4.2: Insert 50 ms silence so the audio path can stabilize, then
        // replay any critical alert that was in progress or queued during the
        // route change.  The "audio resumed" confirmation comes last so it
        // doesn't bury the hazard.
        Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
          if (!mounted) return;
          final interrupted = _routeChangeAt;
          final lastCritical = _vm.alertMgr.lastCriticalAt;
          if (interrupted != null &&
              lastCritical.isAfter(
                interrupted.subtract(const Duration(milliseconds: 300)),
              )) {
            _vm.tts.replayLastCritical();
          }
          _vm.tts.say(S.get('audio_resumed'), SpeechPriority.info, pan: 0.0);
        });
        _routeChangeAt = null;
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

      _vm.tts.onTtsUnavailable = () {
        try {
          _vm.earcon.play(Earcon.cameraBlocked);
        } catch (_) {}
        _fieldLog.logTtsEvent('tts_unavailable');

        unawaited(_vm.tts.init());
      };

      _heartbeatTimer = Timer.periodic(
        _currentHeartbeatInterval(),
        (_) => _heartbeatTick(),
      );

      _vm.voice.onCommand = _voiceDispatcher.handleCommand;
      _vm.voice.onNavCommand = _voiceDispatcher.handleNavCommand;
      _vm.voice.onListeningStateChanged = (listening) {
        if (mounted) {
          setState(() => _isVoiceListening = listening);
        }
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
      } else if (_vm.tts.activeKkEngine == KkTtsEngine.russianFallback) {
        _vm.tts.say(S.get('tts_fallback_ru'), SpeechPriority.warning, pan: 0.0);
      }

      // Capability health owns the ready announcement. Camera-init failure
      // already spoke critical TTS; we still record component state so UI
      // and tests never infer a second "ready" from YOLO or TTS alone.
      final healthNow = DateTime.now();
      _vm.health.note(
        component: CoreComponent.cameraPermission,
        state: _cameraPermissionDenied
            ? ComponentState.unavailable
            : ComponentState.available,
        reasonCode: _cameraPermissionDenied ? 'denied' : 'granted',
        now: healthNow,
      );
      _vm.health.note(
        component: CoreComponent.cameraSession,
        state: _isCameraReady
            ? ComponentState.available
            : ComponentState.unavailable,
        reasonCode: _isCameraReady ? 'session_ok' : 'session_failed',
        now: healthNow,
      );
      _vm.health.note(
        component: CoreComponent.imageStream,
        state: _isCameraReady
            ? ComponentState.available
            : ComponentState.unavailable,
        reasonCode: _isCameraReady ? 'stream_ok' : 'stream_failed',
        now: healthNow,
      );
      _vm.health.note(
        component: CoreComponent.alertAudio,
        state: ComponentState.available,
        reasonCode: 'tts_init',
        now: healthNow,
      );
      _vm.health.note(
        component: CoreComponent.haptics,
        state: ComponentState.available,
        reasonCode: 'haptic_init',
        now: healthNow,
      );
      _vm.health.note(
        component: CoreComponent.semanticObjects,
        state: _models.yoloLoaded
            ? ComponentState.available
            : ComponentState.degraded,
        reasonCode: _models.yoloLoaded ? 'yolo_ok' : 'yolo_not_loaded',
        now: healthNow,
        announce: false,
      );
      _vm.health.note(
        component: CoreComponent.genericGeometry,
        state: _depthController.providerReady
            ? ComponentState.available
            : ComponentState.degraded,
        reasonCode: _depthController.providerReady
            ? 'depth_ok'
            : 'depth_not_ready',
        now: healthNow,
        announce: false,
      );
      _vm.publishHealth(healthNow);
      _initCompletedAt = healthNow;
    } catch (e) {
      _fieldLog.logError('initAll', e.toString());
      _vm.setStatus('Сбой: $e');

      try {
        _vm.tts.say(
          S.get('init_failed'),
          SpeechPriority.critical,
          pan: 0.0,
          barge: true,
        );
      } catch (_) {}
      try {
        HapticService.vibrate(
          kHapticTtsStallPattern,
          intensities: kHapticTtsStallIntensities,
        );
      } catch (_) {}
      try {
        _vm.earcon.play(Earcon.cameraBlocked);
      } catch (_) {}
    }
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
    final recentCritical =
        lastCriticalAt.millisecondsSinceEpoch != 0 &&
        now.difference(lastCriticalAt) < const Duration(seconds: 10);
    final recentAnyAlert =
        lastSpokenAt.millisecondsSinceEpoch != 0 &&
        now.difference(lastSpokenAt) < const Duration(seconds: 15);
    if (!recentAnyAlert) {}
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

    final isSafetyMode = _vm.mode == AppMode.street || _vm.mode == AppMode.cane;
    final notThermalCritical = _vm.thermal.severity != ThermalSeverity.critical;
    if (effFps < 3.0 && isSafetyMode && notThermalCritical) {
      _lowFpsStreak++;
      if (_lowFpsStreak >= 2) {
        _vm.tts.say(S.get('camera_stalled'), SpeechPriority.warning, pan: 0.0);
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
      _fallCountdown.notifyTouch();
      return;
    }
    if (Settings.instance.sosTrigger == SosTrigger.tripleTap) {
      final now = DateTime.now();
      _recentTaps.removeWhere((t) => now.difference(t) > _tripleTapWindow);
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
      FeatureUsageTracker.instance.increment(FeatureUsageKeys.gesture('shake'));
      HapticService.vibrate(const [0, 300, 100, 300]);
      _triggerSos();
    }
  }

  void _triggerSos({String source = 'manual'}) async {
    FeatureUsageTracker.instance.increment(FeatureUsageKeys.sosTriggered);
    _fieldLog.logSosTrigger(source);
    _vm.submitEmergencySafety(
      speechKey: 'sos_sending',
      replaceKey: 'manual_sos_delivery',
      now: DateTime.now(),
    );
    final hasContact = (_vm.sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      _vm.tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
    }
    if (_vm.isIndoor) {
      _vm.tts.say(
        S.get('sos_indoor_warning'),
        SpeechPriority.warning,
        pan: 0.0,
      );
    }

    final result = await _vm.sos.sendSos();
    if (!mounted) return;

    final resultKey = switch (result) {
      SosResult.sent => 'sos_sent',
      SosResult.sentFallback => 'sos_sent',
      // E-1: native SMS unconfirmed; sms:// fallback was launched.
      SosResult.pendingEnqueued => 'sos_queued',
      SosResult.sentWithoutLocation => 'sos_sent_no_location',
      SosResult.noContact => 'sos_no_contact',
      SosResult.noLocation => 'sos_no_location',
      SosResult.launchFailed => 'sos_launch_failed',
      SosResult.error => 'sos_error',
      // E-2: guide the user to complete the action manually; no lockout.
      SosResult.composerOpened => 'sos_composer_opened',
      SosResult.dialerOpened => 'sos_dialer_opened',
    };
    _fieldLog.logSosTrigger(source, result: result.name);
    _vm.submitEmergencySafety(
      speechKey: resultKey,
      replaceKey: 'manual_sos_delivery',
      now: DateTime.now(),
    );
    // E-2: additional haptic cue to draw attention to the manual step.
    if (result == SosResult.composerOpened ||
        result == SosResult.dialerOpened) {
      HapticService.vibrate(const [0, 200, 100, 200]);
    }
  }

  Future<void> _startVoiceCommand() async {
    FeatureUsageTracker.instance.increment(
      FeatureUsageKeys.gesture('long_press'),
    );
    HapticService.vibrate([0, 100, 50, 100]);

    _vm.tts.say(S.get('voice_listening'), SpeechPriority.info, pan: 0.0);
    try {
      await _vm.voice.startListening();
    } catch (e) {
      _fieldLog.logError('startVoiceCommand', e.toString());
      _vm.earcon.play(Earcon.fail);
      _vm.tts.say(
        S.get('voice_not_available'),
        SpeechPriority.warning,
        pan: 0.0,
      );
    }
  }

  /// Quick Shelf is hidden when the camera surface needs to stay
  /// visually empty: pitch-black UI (blind-user mode), an active
  /// fall countdown that already covers the screen, or while
  /// turn-by-turn navigation owns the layout.
  bool _shouldShowShelf() {
    if (_vm.isPitchBlack) return false;
    if (_fallCountdown.active) return false;
    if (_vm.nav.state != NavState.idle) return false;
    return true;
  }

  /// Pitch-black mode hides every visual cue, so a periodic earcon
  /// every 30 s is the only way for a blind user to confirm the app
  /// is still running. Started/stopped from `_vm.addListener` and
  /// torn down in [dispose].
  void _managePitchBlackHeartbeat() {
    final shouldRun = _vm.isPitchBlack;
    final isRunning = _pitchBlackHeartbeatTimer != null;
    if (shouldRun && !isRunning) {
      _pitchBlackHeartbeatTimer = Timer.periodic(
        _kPitchBlackHeartbeatInterval,
        (_) => _vm.earcon.play(Earcon.heartbeat),
      );
    } else if (!shouldRun && isRunning) {
      _pitchBlackHeartbeatTimer?.cancel();
      _pitchBlackHeartbeatTimer = null;
    }
  }

  void _onShelfTaskSelected(ShelfTask task) {
    FeatureUsageTracker.instance.increment(
      FeatureUsageKeys.gesture('shelf_${task.name}'),
    );
    HapticService.vibrate(const [0, 30, 50, 30]);
    setState(() => _shelfTask = task);
    switch (task) {
      case ShelfTask.camera:
        if (_wantOcr) {
          _wantOcr = false;
        }
        break;
      case ShelfTask.read:
        _wantOcr = true;
        _ocrStartedAt = DateTime.now();
        _vm.tts.say(S.get('shelf_read_started'), SpeechPriority.info, pan: 0.0);
        break;
      case ShelfTask.navigate:
        _vm.tts.say(
          S.get('shelf_navigate_started'),
          SpeechPriority.warning,
          pan: 0.0,
          barge: true,
        );
        unawaited(_vm.voice.startListening());
        break;
    }
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
    final ageSec = pos == null ? null : now.difference(pos.timestamp).inSeconds;
    final transition = _vm.indoorGate.feed(
      gpsAccuracyM: accuracyM,
      gpsAgeSec: ageSec,
      motion: _vm.fallDetector.motionState,
      now: now,
    );
    if (transition != IndoorTransition.none) {
      _fieldLog.logIndoorGate(transition.name, gpsAccuracy: accuracyM);
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

  /// Announces the degraded-accuracy fall-detection profile (gyroscope
  /// unavailable) with a 60 s cooldown so a flaky gyro stream does not spam
  /// the user. Critical: without this the user believes full fall detection
  /// is active when rotational confirmation is actually off.
  void _announceGyroDegraded() {
    final now = DateTime.now();
    if (now.difference(_lastGyroDegradedAnnounceAt) <
        _kGyroDegradedAnnounceCooldown) {
      return;
    }
    _lastGyroDegradedAnnounceAt = now;
    _vm.health.note(
      component: CoreComponent.gyroscope,
      state: ComponentState.degraded,
      reasonCode: 'gyro_unavailable',
      now: now,
      announce: false,
    );
    _fieldLog.log('gyro_unavailable', {'degraded': true});
    _vm.tts.say(
      S.get('fall_detector_degraded'),
      SpeechPriority.warning,
      pan: 0.0,
    );
  }

  void _handleQualityEvents(List<FrameQualityEvent> events) {
    final now = DateTime.now();
    for (final e in events) {
      switch (e.type) {
        case FrameQualityEventType.aeTransitionStarted:
          _fieldLog.logAeTransition(started: true);
          // D-1: dedicated, much shorter cooldowns than the generic quality
          // events above — the motion-prealert fallback is fully dark for
          // the duration of every AE transition, so the user must be told
          // every time, not just once per 30 s.
          if (now.difference(_lastAeTransitionEarconAt) >=
              _kAeTransitionEarconCooldown) {
            _lastAeTransitionEarconAt = now;
            _vm.earcon.play(Earcon.cameraBlocked);
          }
          if (now.difference(_lastAeTransitionTtsAt) >=
              _kAeTransitionTtsCooldown) {
            _lastAeTransitionTtsAt = now;
            _vm.tts.say(
              S.alert('camera_ae_transition'),
              SpeechPriority.warning,
              pan: 0.0,
            );
          }
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
          _fieldLog.logDroplet(dirtyRegions: e.dirtyRegions ?? 0, warned: true);
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('camera_droplet'),
              SpeechPriority.info,
              pan: 0.0,
            );
          }
          break;
        case FrameQualityEventType.lensSmearDetected:
          _fieldLog.logCameraQuality('lens_smear');
          if (_qualityCooldownOk(e.type, now)) {
            _vm.tts.say(
              S.alert('camera_smear'),
              SpeechPriority.warning,
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
        _vm.tts.say(
          S.get('camera_not_found'),
          SpeechPriority.critical,
          barge: true,
          pan: 0.0,
        );
        HapticService.vibrate(kHapticTtsStallPattern);
        return;
      }

      final backCameras = cameras
          .where(
            (c) =>
                c.lensDirection == CameraLensDirection.back ||
                c.lensDirection == CameraLensDirection.external,
          )
          .toList();
      if (backCameras.isEmpty) {
        initSw.stop();
        _fieldLog.logCameraInit(
          initMs: initSw.elapsedMilliseconds,
          success: false,
          error: 'no_back_camera',
        );
        _vm.tts.say(
          S.get('camera_not_found'),
          SpeechPriority.critical,
          barge: true,
          pan: 0.0,
        );
        HapticService.vibrate(kHapticTtsStallPattern);
        return;
      }
      final back = backCameras.first;

      final ctrl = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await ctrl.initialize();
      _controller = ctrl;

      _vm.ocr.sensorOrientationDeg = back.sensorOrientation;
      _vm.cameraSensorRotationDeg = back.sensorOrientation;
      _vm.cameraMirrored = back.lensDirection == CameraLensDirection.front;
      // Establish the generation before the callback can deliver its first
      // frame. Results from a provider call owned by an older camera are then
      // rejected before they can reach fusion or alerts.
      onCameraSessionStarting();
      await ctrl.startImageStream(_onFrame);

      unawaited(_vm.tts.preClaimAudioFocus());

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _vm.setStatus(S.get('camera_started'));
        });
      }
      _stallWatchdog.start();
      _startSpatialSafetyCadence();
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
      // Safety audit 2026-06 fix: camera HAL failure must NOT be silent.
      // A blind user walking with dead detection AND hearing "system ready"
      // is a physical-harm scenario. Mirror the _initAll catch pattern:
      // critical TTS (barge) + haptic + earcon, then keep reminding.
      try {
        _vm.tts.say(
          S.get('camera_init_failed_critical'),
          SpeechPriority.critical,
          barge: true,
          pan: 0.0,
        );
      } catch (_) {}
      try {
        HapticService.vibrate(
          kHapticTtsStallPattern,
          intensities: kHapticTtsStallIntensities,
        );
      } catch (_) {}
      try {
        _vm.earcon.play(Earcon.cameraBlocked);
      } catch (_) {}
      if (mounted) _speakCameraInitFailedLoop();
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!mounted || _exclusiveDepthTransition) return;

    final now = DateTime.now();
    _stallWatchdog.notifyFrameArrived(now: now);
    if (_stallWatchdog.isWarned) {
      _stallWatchdog.clearWarning();
      final stallFor = now.difference(_stallStartedAt);

      debugPrint('[BAGDAR_STALL] resumed after ${stallFor.inMilliseconds}ms');
      _fieldLog.logCameraStall(
        stalled: false,
        durationMs: stallFor.inMilliseconds,
      );
      if (stallFor >= _kStallTtsMinDuration &&
          _stallStartedAt.millisecondsSinceEpoch != 0) {
        _vm.earcon.play(Earcon.success);
        _vm.tts.say(S.get('camera_resumed'), SpeechPriority.warning, pan: 0.0);
      }
      _stallStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    _lifecycle.cancelReinitHeartbeat();

    _frameCount++;
    _imgW = image.width;
    _imgH = image.height;

    final frameSw = Stopwatch()..start();

    final yPlane = image.planes[0];
    final qualityReport = _qualityGuard.evaluate(
      yPlane: yPlane.bytes,
      bytesPerRow: yPlane.bytesPerRow,
      width: image.width,
      height: image.height,
      now: now,
      indoorHint: _vm.isIndoor,
    );
    _handleQualityEvents(qualityReport.events);
    _vm.tracker.weatherDegraded = qualityReport.weatherDegraded;

    if (qualityReport.aePipelineFrozen) {
      // D-1: MotionPreAlert.feed() short-circuits to null the instant
      // aeTransitioning is true (motion_prealert.dart), so calling it here
      // was dead code that gave the false impression of a motion-intrusion
      // safety net during AE blindness. The FrameQualityEventType
      // .aeTransitionStarted branch in _handleQualityEvents (above) now
      // carries the user notification instead. Do not run YOLO/depth on an
      // AE-blind frame (unchanged from before).
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
        aeTransitioning: false,
        indoor: _vm.isIndoor,
        rainActive: _vm.weatherGate.degraded,
        lowLight: _vm.weatherGate.degraded,
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

    if (!shouldRunDetect || _isDetecting || !_models.yoloLoaded) {
      // Safety audit 2026-06 fix A-1: warn if YOLO is down in street/cane mode
      if (!_models.yoloLoaded &&
          (_vm.mode == AppMode.street || _vm.mode == AppMode.cane)) {
        final warnNow = DateTime.now();
        if (_yoloDownSince.millisecondsSinceEpoch == 0) {
          _yoloDownSince = warnNow;
        } else if (warnNow.difference(_yoloDownSince) >=
                _kYoloDetectorWarnDelay &&
            warnNow.difference(_lastYoloUnavailWarnAt) >=
                _kYoloDetectorWarnCooldown) {
          _lastYoloUnavailWarnAt = warnNow;
          _vm.tts.say(
            S.get('yolo_detector_not_responding'),
            SpeechPriority.warning,
            pan: 0.0,
          );
        }
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

    _isDetecting = true;
    _lastDetectAt = now;
    // Safety audit 2026-06 fix A-1: YOLO is running — reset downtime tracker
    if (_yoloDownSince.millisecondsSinceEpoch != 0) {
      _yoloDownSince = DateTime.fromMillisecondsSinceEpoch(0);
    }

    try {
      if (_wantOcr) {
        if (now.difference(_ocrStartedAt) > const Duration(seconds: 10)) {
          _wantOcr = false;
          _vm.tts.say(S.get('ocr_timeout'), SpeechPriority.info, pan: 0.0);
        } else if (_vm.fallDetector.motionState == MotionState.walking) {
        } else {
          final text = await _vm.ocr.recognizeFromFrame(image, stabilize: true);
          if (text != null && text.isNotEmpty) {
            _vm.tts.say(text, SpeechPriority.info, pan: 0.0);
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

      // V4.4: Yield to the event loop after blocking YOLO inference so that
      // any TTS completion callbacks, haptic timing events, or audio-route
      // change notifications queued during inference can execute before we
      // proceed to alert generation.  45 ms of inference on a Dart-blocked
      // isolate can otherwise delay barge-interrupt delivery.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;

      final yPlaneBytes = planeBytes.isNotEmpty ? planeBytes[0] : null;
      final yStride = image.planes.isNotEmpty
          ? image.planes[0].bytesPerRow
          : null;
      final dets = _buildRawDets(
        raw,
        _imgW,
        _imgH,
        yPlane: yPlaneBytes,
        yRowStride: yStride,
      );
      final inferenceMs = frameSw.elapsedMilliseconds;
      if (_isCalibrating) {
        final personDet = dets.cast<RawDet?>().firstWhere(
          (d) => d != null && d.label == 'person',
          orElse: () => null,
        );
        if (personDet != null) {
          _isCalibrating = false;
          _calibrationTimeoutTimer?.cancel();
          unawaited(
            calibrateFocalLength(
              'person',
              personDet.x1,
              personDet.y1,
              personDet.x2,
              personDet.y2,
              2.0,
            ).then((_) async {
              await Settings.instance.setIsCalibrated(true);
              _isCalibrated = true;
              _vm.tracker.isCalibrated = true;
              await _vm.earcon.play(Earcon.success);
              _vm.tts.say(
                S.get('calib_saved'),
                SpeechPriority.warning,
                barge: true,
              );
              if (mounted) setState(() {});
            }),
          );
        }
      }

      _vm.tracker.userWalking =
          _vm.fallDetector.motionState != MotionState.stationary;
      // V1.4: Pass calibration and depth state to the tracker so it can
      // apply looser approach thresholds when no cross-checks are available.
      _vm.tracker.isCalibrated = _isCalibrated;
      _vm.tracker.depthProviderAvailable =
          _models.depthProvider?.isReady ?? false;
      final tracks = _vm.tracker.update(dets, _imgW, _imgH, now);
      _fieldLog.logDetection(
        frameCount: _frameCount,
        trackCount: tracks.length,
        inferenceMs: inferenceMs,
        maxConf: dets.isEmpty
            ? null
            : dets.map((d) => d.conf).reduce((a, b) => a > b ? a : b),
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
        viewportAspect: _viewportAspect,
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
      } else if (_vm.throttler.isGroundSafetyMidasDue(now) &&
          !_stallWatchdog.isWarned) {
        // V2.1: Ground-safety MiDaS burst at critical thermal.  Even when the
        // full MiDaS pipeline is paused by thermal throttling, run one pass
        // focused on the ground zone to preserve curb / step-down detection.
        _vm.throttler.markGroundSafetyMidasDone(now);
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
    _runSpatialSafetyRuntime(DateTime.now());
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

      _vm.alertMgr.handleDepthHazard(
        text: S.alert(hazardKey),
        speechKey: hazardKey,
        priority: priority,
        pan: hazard.pan,
        category: AlertCategory.obstacleClose,
        now: now,
      );
      _fieldLog.logDepthHazard(
        type: hazard.type.name,
        score: hazard.midasScore,
        coverage: hazard.coverage,
      );
    }
  }

  void _runSpatialSafetyRuntime(DateTime now) {
    final header = _depthController.lastAcceptedObservationHeader;
    final detection = _depthController.lastGenericDetection;
    final orientationValid =
        !_vm.orientation.isRollExcessive &&
        _vm.orientation.state == DevicePitch.optimal;
    final userMoving = _vm.fallDetector.motionState != MotionState.stationary;

    final result = header != null && detection != null
        ? _vm.spatialSafety.ingestGenericGeometry(
            header: header,
            detection: detection,
            tracks: _depthController.lastGenericTracks,
            now: now,
            orientationValid: orientationValid,
            userMoving: userMoving,
            poseQuality: orientationValid ? header.confidence : 0,
          )
        : _vm.spatialSafety.noteMissingObservation(
            providerId:
                _models.depthProvider?.runtimeType.toString() ??
                'depth-provider',
            providerState: switch (_depthController.status) {
              DepthPipelineStatus.providerUnavailable =>
                SceneSensorState.unavailable,
              DepthPipelineStatus.unalignedStale => SceneSensorState.stale,
              _ => SceneSensorState.degraded,
            },
            reason:
                _depthController.lastFrameRejectionReason ??
                'no_accepted_spatial_observation',
            now: now,
            orientationValid: orientationValid,
            userMoving: userMoving,
          );

    _fieldLog.log('spatial_runtime_trace', <String, dynamic>{
      ...result.trace.toDiagnosticMap(),
      'scene': result.snapshot.toDiagnosticMap(),
      'shadowCorrection': result.decision?.shadowCorrection?.name,
    });
  }

  void _startSpatialSafetyCadence() {
    _spatialSafetyTickTimer?.cancel();
    _spatialSafetyTickTimer = Timer.periodic(
      _kSpatialSafetyTickPeriod,
      (_) => _runSpatialSafetyTick(),
    );
  }

  void _stopSpatialSafetyCadence() {
    _spatialSafetyTickTimer?.cancel();
    _spatialSafetyTickTimer = null;
  }

  void _runSpatialSafetyTick() {
    if (!mounted ||
        !_isCameraReady ||
        _vm.spatialSafety.activeSessionGeneration < 0) {
      return;
    }
    final orientationValid =
        !_vm.orientation.isRollExcessive &&
        _vm.orientation.state == DevicePitch.optimal;
    final result = _vm.spatialSafety.tick(
      now: DateTime.now(),
      userMoving: _vm.fallDetector.motionState != MotionState.stationary,
      orientationValid: orientationValid,
    );
    _fieldLog.log('spatial_runtime_trace', <String, dynamic>{
      ...result.trace.toDiagnosticMap(),
      'scene': result.snapshot.toDiagnosticMap(),
      'cadence': true,
    });
  }

  void _onDepthStatusChanged(DepthPipelineStatus from, DepthPipelineStatus to) {
    if (!mounted) return;
    _misalignmentWatchdog.noteDepthStatus(to);

    String? key;
    SpeechPriority priority = SpeechPriority.warning;
    switch (to) {
      case DepthPipelineStatus.lowConfidence:
      case DepthPipelineStatus.planeFitFailed:
        key = 'depth_degraded';
        priority = SpeechPriority.warning;
        break;
      case DepthPipelineStatus.unalignedStale:
      case DepthPipelineStatus.providerUnavailable:
      case DepthPipelineStatus.legacyOnlyDegraded:
        key = 'spatial_analysis_limited';
        priority = SpeechPriority.warning;
        break;
      case DepthPipelineStatus.ok:
      case DepthPipelineStatus.healthyMetric:
      case DepthPipelineStatus.healthyRelative:
        if (from.isDegraded) {
          key = 'depth_recovered';
          priority = SpeechPriority.info;
        }
        break;
    }

    final geomState = to.isHealthy
        ? ComponentState.available
        : (to == DepthPipelineStatus.providerUnavailable
              ? ComponentState.unavailable
              : ComponentState.degraded);
    _vm.health.note(
      component: CoreComponent.genericGeometry,
      state: geomState,
      reasonCode: 'depth_${to.name}',
      now: DateTime.now(),
      announce: false,
    );

    _fieldLog.log('depth_pipeline_status', {'from': from.name, 'to': to.name});

    if (key != null) {
      final recovered = priority == SpeechPriority.info;
      _vm.submitCameraSafety(
        speechKey: key,
        replaceKey: 'depth_pipeline',
        now: DateTime.now(),
        recovered: recovered,
        urgency: recovered ? 0.2 : 0.75,
      );
    }
  }

  // Safety audit 2026-06 fix A-1: handle permanent YOLO failure
  void _onYoloUnavailable() {
    if (!mounted) return;
    _yoloDownSince = DateTime.now();
    _vm.health.note(
      component: CoreComponent.semanticObjects,
      state: ComponentState.unavailable,
      reasonCode: 'yolo_reload_failed',
      now: _yoloDownSince,
      sessionTerminal: true,
      announce: false,
    );
    _vm.health.note(
      component: CoreComponent.movingThreats,
      state: ComponentState.unavailable,
      reasonCode: 'yolo_reload_failed',
      now: _yoloDownSince,
      announce: false,
    );
    _lastYoloUnavailWarnAt = DateTime.now();
    _vm.submitCameraSafety(
      speechKey: 'yolo_unavailable',
      replaceKey: 'yolo_unavailable',
      now: _lastYoloUnavailWarnAt,
      critical: true,
      urgency: 0.95,
    );
    _yoloRetryTimer?.cancel();
    _yoloRetryTimer = Timer.periodic(_kYoloRetryInterval, (_) {
      if (!mounted || _models.yoloLoaded) {
        _yoloRetryTimer?.cancel();
        _yoloRetryTimer = null;
        return;
      }
      _vm.submitCameraSafety(
        speechKey: 'yolo_unavailable',
        replaceKey: 'yolo_unavailable',
        now: DateTime.now(),
        critical: true,
        urgency: 0.95,
      );
    });
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

    final key = paused ? 'depth_paused_explicit' : 'hazard_detection_resumed';
    final priority = paused ? SpeechPriority.warning : SpeechPriority.info;
    _fieldLog.log('midas_pause_changed', {'paused': paused});
    _vm.submitCameraSafety(
      speechKey: key,
      replaceKey: 'depth_pause',
      now: now,
      recovered: priority == SpeechPriority.info,
      urgency: paused ? 0.7 : 0.2,
    );
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
        if (!_vm.alertMgr.submitFilteredObjectAlert(winner, now: event.at)) {
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
        }
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

      if (t.dist == 'very close' || t.dist == 'close') return true;
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

      final atEdge =
          t.x1 < edgeX ||
          t.x2 > imgW - edgeX ||
          t.y1 < edgeY ||
          t.y2 > imgH - edgeY;
      if (!atEdge) continue;

      if (t.areaHist.length >= 2) {
        final dt =
            t.areaHist.last.$1.difference(t.areaHist.first.$1).inMilliseconds /
            1000.0;
        if (dt > 0.1) {
          final areaRate = (t.areaHist.last.$2 - t.areaHist.first.$2) / dt;
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

      // V5.2: In low-light conditions, lower the confidence floor for
      // safety-critical classes (vehicles, pedestrians) to reduce missed
      // detections at the cost of slightly more false positives.
      final isLowLight = _vm.weatherGate.degraded;
      final isSafetyCriticalClass = isVehicle(label) || label == 'person';
      final confFloor = (isLowLight && isSafetyCriticalClass)
          ? math.max(0.20, minConfFor(label) - kLowLightClassMinConfReduction)
          : minConfFor(label);
      if (conf < confFloor) continue;
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

      if (label == 'person' && dist == 'far' && conf < 0.50) {
        continue;
      }
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

  ThermalSeverity _lastAnnouncedThermalSeverity = ThermalSeverity.normal;

  void _handleThermalChanged(ThermalReadings readings) {
    if (!mounted) return;
    final prevSeverity = _vm.throttler.effectiveSeverity;
    _vm.throttler.setThermal(readings);
    final newSeverity = _vm.throttler.effectiveSeverity;

    _vm.winterMode.noteThermalReading(readings);
    unawaited(_models.adjustForThermal(newSeverity));
    _fieldLog.logThermal(
      newSeverity.name,
      detectIntervalMs: _detectInterval.inMilliseconds,
    );

    if (newSeverity == prevSeverity) return;

    // V5.1 / V2.1: Tier-specific TTS on escalation.
    if (newSeverity.index > prevSeverity.index &&
        newSeverity != _lastAnnouncedThermalSeverity) {
      _lastAnnouncedThermalSeverity = newSeverity;
      if (newSeverity == ThermalSeverity.warm) {
        // V5.1: Proactive warning to move to shade.
        _vm.tts.say(
          S.get('thermal_warm_move_to_shade'),
          SpeechPriority.info,
          pan: 0.0,
        );
      } else if (newSeverity == ThermalSeverity.critical) {
        // V2.1: Explicitly warn that ground-hazard detection is reduced.
        _vm.tts.say(
          S.get('thermal_ground_hazard_reduced'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      }
    }
  }

  void _recomputeCadence() {
    _detectInterval = _vm.throttler.detectInterval(
      _vm.battery.detectIntervalMs,
    );
    _depthController.interval = _vm.throttler.midasInterval(
      _vm.battery.midasIntervalMs,
    );
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
    final colors = BagdarTheme.colorsOf(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surfaceElevated,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        child: CameraSettingsSheet(
          currentLanguage: AppStrings.current,
          useGpu: _useGpu,
          useNativeDepthBridge:
              _models.depthProvider?.nativeBridgeEnabled ?? false,
          useHardwareDepthMode: _useHardwareDepthMode,
          showIndependentHardwareDepth: BuildProfile.current.isResearch,
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
            if (!_isCameraReady) {
              _vm.tts.say(
                S.get('ocr_camera_not_ready'),
                SpeechPriority.warning,
                pan: 0.0,
              );
              _vm.earcon.play(Earcon.fail);
              HapticService.vibrate(const [0, 100, 50, 100]);
              return;
            }
            _wantOcr = true;
            _ocrStartedAt = DateTime.now();
            _vm.tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);
          },
          onCalibrationTap: () {
            _startCalibration();
          },
          onEditSosContact: () => _showSosContactDialog(),
          onScanLeft: () =>
              _vm.tts.say(S.get('scan_left'), SpeechPriority.info, pan: -1.0),
          onScanCenter: () =>
              _vm.tts.say(S.get('scan_forward'), SpeechPriority.info, pan: 0.0),
          onScanRight: () =>
              _vm.tts.say(S.get('scan_right'), SpeechPriority.info, pan: 1.0),
          onVoiceWarningTest: () => _vm.tts.say(
            S.get('test_alert_warning'),
            SpeechPriority.warning,
            pan: -1.0,
          ),
          onVoiceCriticalTest: () => _vm.tts.say(
            S.get('test_alert_critical'),
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

  void _startCalibration() {
    _vm.tts.say(S.get('calib_aim'), SpeechPriority.warning, barge: true);
    setState(() => _isCalibrating = true);
    _calibrationTimeoutTimer?.cancel();
    _calibrationTimeoutTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && _isCalibrating) {
        setState(() => _isCalibrating = false);
        _vm.earcon.play(Earcon.fail);
        _vm.tts.say(
          S.get('calib_no_person'),
          SpeechPriority.warning,
          barge: true,
        );
      }
    });
  }

  void _openSettingsQrExport() {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SettingsQrExportScreen(tts: _vm.tts)),
    );
  }

  void _openLanguagePacks() {
    if (!mounted) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => LanguagePacksScreen(tts: _vm.tts)),
    );
  }

  /// Start the connectivity-driven kk pack re-prompt flow. Called once at
  /// initState. Handles two cases:
  /// 1. User is already online when the camera screen first opens -- we run
  ///    a one-shot check via `Connectivity.checkConnectivity()`.
  /// 2. User boots offline and later regains connectivity -- the
  ///    `onConnectivityChanged` stream fires and we announce then.
  ///
  /// Both paths route through `_maybePromptKkPackOnline`, which guards
  /// against duplicate announcements via `_onlineKkPromptDone` and clears
  /// the persisted `setPromptOnFirstOnline` flag so we don't nag again.
  void _startConnectivityKkPromptListener() {
    _connSub = Connectivity().onConnectivityChanged.listen(
      (results) => unawaited(_maybePromptKkPackOnline(results)),
      onError: (_) {},
    );
    unawaited(
      Connectivity().checkConnectivity().then(_maybePromptKkPackOnline),
    );
  }

  Future<void> _maybePromptKkPackOnline(
    List<ConnectivityResult> results,
  ) async {
    if (_onlineKkPromptDone) return;
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    if (!isOnline) return;
    final pm = LanguagePackManager.instance;
    if (!pm.isReady) return;
    if (pm.isInstalled(LanguagePackIds.voskKk)) return;
    final wants = await pm.shouldPromptOnFirstOnline();
    if (!wants) return;
    _onlineKkPromptDone = true;
    await pm.setPromptOnFirstOnline(false);

    unawaited(pm.fetchManifest());
    if (!mounted) return;
    _vm.tts.say(S.get('lang_pack_online_ready'), SpeechPriority.info, pan: 0.0);
    FieldLogger.instance.log('lang_pack_online_prompt', {});
  }

  Future<void> _openSettingsQrImport() async {
    if (!mounted) return;

    await _releaseCameraForExternalScanner();
    if (!mounted) {
      unawaited(_initCamera());
      return;
    }
    final applied = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SettingsQrImportScreen(tts: _vm.tts)),
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

  void _startNativeWatchdog() {
    _nativeWatchdogTimer?.cancel();
    _nativeWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      try {
        const MethodChannel('bagdar/watchdog').invokeMethod('ping');
      } catch (_) {}
    });
    try {
      const MethodChannel('bagdar/watchdog').invokeMethod('ping');
    } catch (_) {}
  }

  void _stopNativeWatchdog() {
    _nativeWatchdogTimer?.cancel();
    _nativeWatchdogTimer = null;
    try {
      const MethodChannel('bagdar/watchdog').invokeMethod('stop');
    } catch (_) {}
  }

  void _showSosContactDialog() {
    final controller = TextEditingController(text: _vm.sos.contactNumber ?? '');
    final colors = BagdarTheme.colorsOf(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surfaceElevated,
        title: Text(
          S.get('sos_settings'),
          style: BagdarTypography.title.copyWith(color: colors.textPrimary),
        ),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.phone,
                style: BagdarTypography.body.copyWith(
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: '+7 XXX XXX XX XX',
                  hintStyle: BagdarTypography.body.copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.6),
                  ),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: colors.divider),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: colors.accentPrimary,
                      width: BagdarBorders.thin,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.contact_phone, color: colors.accentPrimary),
              onPressed: () async {
                try {
                  final picker = FlutterNativeContactPicker();
                  final contact = await picker.selectContact();
                  if (contact != null &&
                      contact.phoneNumbers != null &&
                      contact.phoneNumbers!.isNotEmpty) {
                    controller.text = contact.phoneNumbers!.first;
                  }
                } catch (e) {
                  debugPrint('Error picking contact: $e');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              S.get('cancel'),
              style: BagdarTypography.body.copyWith(
                color: colors.textSecondary,
              ),
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
              style: BagdarTypography.body.copyWith(
                color: colors.accentPrimary,
                fontWeight: BagdarTypography.weightBold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _speakCameraPermissionDeniedLoop() {
    _cameraPermissionTimer?.cancel();
    _vm.tts.say(
      S.get('camera_perm_recovery_tts'),
      SpeechPriority.critical,
      pan: 0.0,
    );
    _cameraPermissionTimer = Timer.periodic(const Duration(seconds: 15), (
      timer,
    ) {
      if (mounted && _cameraPermissionDenied) {
        _vm.tts.say(
          S.get('camera_perm_recovery_tts'),
          SpeechPriority.critical,
          pan: 0.0,
        );
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _retryCameraPermission() async {
    _cameraPermissionTimer?.cancel();
    final granted = await _requestCameraPermission();
    if (granted) {
      if (mounted) {
        setState(() {
          _cameraPermissionDenied = false;
        });
      }
      unawaited(_initAll());
    } else {
      _speakCameraPermissionDeniedLoop();
    }
  }

  /// Safety audit 2026-06 fix: when the camera HAL fails to initialize
  /// (HAL crash, camera busy, sensor unavailable), keep reminding the blind
  /// user that recognition is dead until they restart. Mirrors the
  /// permission-denied loop pattern.
  void _speakCameraInitFailedLoop() {
    _cameraInitRetryTimer?.cancel();
    _vm.tts.say(
      S.get('camera_init_failed_critical'),
      SpeechPriority.critical,
      barge: true,
      pan: 0.0,
    );
    _cameraInitRetryTimer = Timer.periodic(const Duration(seconds: 15), (
      timer,
    ) {
      if (mounted && !_isCameraReady) {
        _vm.tts.say(
          S.get('camera_init_failed_critical'),
          SpeechPriority.critical,
          barge: true,
          pan: 0.0,
        );
        try {
          HapticService.vibrate(
            kHapticTtsStallPattern,
            intensities: kHapticTtsStallIntensities,
          );
        } catch (_) {}
      } else {
        timer.cancel();
      }
    });
  }

  Widget _buildPermissionDeniedView() {
    final colors = BagdarTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: colors.surfaceBg,
      body: SafeArea(
        child: Semantics(
          liveRegion: true,
          label: S.get('camera_perm_recovery_tts'),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retryCameraPermission,
            onDoubleTap: openAppSettings,
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.no_photography,
                    color: colors.stateDanger,
                    size: 56,
                  ),
                  const SizedBox(height: BagdarSpacing.l),
                  Text(
                    S.get('camera_perm_title'),
                    style: BagdarTypography.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: BagdarSpacing.m),
                  Text(
                    S.get('camera_perm_recovery_tts'),
                    style: BagdarTypography.body.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: openAppSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accentPrimary,
                      foregroundColor: colors.accentOnPrimary,
                      minimumSize: const Size.fromHeight(
                        BagdarSpacing.tapMinimum,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BagdarRadius.card),
                      ),
                    ),
                    child: Text(
                      S.get('settings'),
                      style: BagdarTypography.body.copyWith(
                        fontWeight: BagdarTypography.weightHeavy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _retryCameraPermission,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.textSecondary,
                      minimumSize: const Size.fromHeight(
                        BagdarSpacing.tapMinimum,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BagdarRadius.card),
                        side: BorderSide(
                          color: colors.divider,
                          width: BagdarBorders.hairline,
                        ),
                      ),
                    ),
                    child: Text(
                      S.get('onb_btn_continue'),
                      style: BagdarTypography.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraPermissionDenied) {
      return _buildPermissionDeniedView();
    }
    final ctrl = _controller;
    final ready = _isCameraReady && ctrl != null && ctrl.value.isInitialized;
    final colors = BagdarTheme.colorsOf(context);

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
                    color: BagdarOverlay.statusFill(
                      BagdarStatusLevel.danger,
                      colors,
                    ).withValues(alpha: 0.3),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber,
                            size: 60,
                            color: BagdarOverlay.foreground,
                          ),
                          const SizedBox(height: BagdarSpacing.m),
                          Text(
                            '${S.get('sos_fall_countdown')} ${_fallCountdown.secondsLeft} ${S.get('sos_fall_seconds')}',
                            style: BagdarTypography.title.copyWith(
                              color: BagdarOverlay.foreground,
                              shadows: BagdarOverlay.textShadows,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: BagdarSpacing.s),
                          Text(
                            S.get('sos_fall_cancelled'),
                            style: BagdarTypography.caption.copyWith(
                              color: BagdarOverlay.foregroundMuted,
                              shadows: BagdarOverlay.textShadows,
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
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(
                        child: StatusPanel(
                          statusLine: _vm.statusLine,
                          tracksNotifier: _vm.tracksNotifier,
                          imgW: _imgW,
                          imgH: _imgH,
                          viewportAspect: MediaQuery.sizeOf(
                            context,
                          ).aspectRatio,
                          mode: _vm.mode,
                        ),
                      ),
                      if (_shouldShowShelf())
                        QuickShelf(
                          activeTask: _shelfTask,
                          onTaskSelected: _onShelfTaskSelected,
                        ),
                    ],
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
                        color: BagdarOverlay.statusFill(
                          BagdarStatusLevel.danger,
                          colors,
                        ),
                        icon: Icons.cancel,
                        label: 'FP',
                        onActivate: () {
                          _fieldLog.logFpMarker();
                          HapticService.vibrate(const [0, 60, 40, 60]);
                        },
                      ),
                      const SizedBox(width: 12),
                      _FieldMarkerButton(
                        color: BagdarOverlay.statusFill(
                          BagdarStatusLevel.caution,
                          colors,
                        ),
                        icon: Icons.warning,
                        label: 'FN',
                        onActivate: () {
                          _fieldLog.logFnMarker();
                          HapticService.vibrate(const [0, 60, 40, 60]);
                        },
                      ),
                    ],
                  ),
                ),

              if (_isVoiceListening)
                VoiceLayer(
                  onCancel: () {
                    unawaited(_vm.voice.stopListening());
                  },
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
      objects: _vm.tracksNotifier.value
          .map(
            (t) => SceneObject(
              label: t.label,
              direction: S.dir(clockDir(t.x1, t.x2, _imgW.toDouble())),
              distance: t.dist,
              distM: t.distM > 0 ? t.distM : null,
              approaching: t.approaching,
              threatScore: t.dist == 'very close'
                  ? 3.0
                  : t.dist == 'close'
                  ? 2.0
                  : 1.0,
            ),
          )
          .toList(),
      hazards: _lastDepthHazards,
      trafficLight: _vm.trafficLight.confirmedColor,
      trafficLightKind: _vm.trafficLight.lastKind,

      ocrText: null,
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
      hasTrafficLight:
          snapshot.trafficLight != null &&
          snapshot.trafficLight != TrafficLightColor.unknown,
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
  final VoidCallback onActivate;

  const _FieldMarkerButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onActivate,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BagdarSpacing.m,
          vertical: BagdarSpacing.s,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(BagdarRadius.card),
          border: Border.all(color: color, width: BagdarBorders.thin),
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

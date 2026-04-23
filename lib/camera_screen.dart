import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/app_mode.dart';
import 'models/strings.dart';
import 'models/speech_job.dart';
import 'models/constants.dart';
import 'services/settings_service.dart';
import 'services/foreground_service.dart';
import 'services/thermal_monitor.dart';
import 'services/haptic_service.dart';
import 'services/earcon_service.dart';
import 'services/sos_service.dart';
import 'services/voice_command_service.dart';
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
import 'services/fall_detector.dart' show MotionState;
import 'services/motion_prealert.dart'
    show MotionIntrusionEvent, MotionIntrusionSide;
import 'services/weather_gate.dart' show WeatherTransition;
import 'services/orientation_service.dart' show OrientationService;
import 'services/traffic_light_analyzer.dart' show TrafficLightKind;
import 'utils/blur_detector.dart';
import 'utils/depth_hazard.dart' show DepthHazardType;
import 'utils/distance_utils.dart';

class AiCameraScreen extends StatefulWidget {
  final AppMode? initialMode;
  const AiCameraScreen({super.key, this.initialMode});

  @override
  State<AiCameraScreen> createState() => _AiCameraScreenState();
}

class _AiCameraScreenState extends State<AiCameraScreen>
    with WidgetsBindingObserver {
  late final CameraViewModel _vm;
  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isDetecting = false;

  final ModelService _models = ModelService.instance;

  bool _useGpu = false;
  int _numThreads = 2;

  Duration _detectInterval = const Duration(milliseconds: 140);
  DateTime _lastDetectAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiAt = DateTime.fromMillisecondsSinceEpoch(0);

  int _imgW = 0, _imgH = 0;
  bool _isCalibrated = false;
  bool _useHardwareDepthMode = false;
  bool _depthProviderReady = false;
  final bool _exclusiveDepthTransition = false;
  bool _wantOcr = false;
  DateTime _ocrStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  TrafficLightColor? _lastAnnouncedLight;

  Timer? _heartbeatTimer;

  Timer? _twoFingerSosTimer;
  bool _twoFingerSosArmed = false;
  static const Duration _twoFingerSosHold = Duration(milliseconds: 1500);

  Timer? _fallCountdownTimer;
  int _fallCountdownSec = 0;
  bool _fallCountdownActive = false;
  bool _fallCancelListenerActive = false;

  Timer? _lazyDisposeTimer;
  static const Duration _kLazyDisposeDuration = Duration(seconds: 10);
  bool _streamPaused = false;
  Timer? _reinitHeartbeat;

  int _lowLuminosityFrames = 0;
  static const int _lowLuminosityThreshold = 45;
  static const double _luminosityMinValue = 10.0;
  bool _cameraBlockedWarned = false;
  int _frameCount = 0;

  
  int _partialOcclusionFrames = 0;
  bool _partialOcclusionWarned = false;
  static const int _kPartialOcclusionStreak = 20;

  
  
  
  
  int _aeTransitionFrames = 0;
  DateTime? _aeTransitionEndedAt;
  static const double _kAeVarianceThreshold = 100.0;
  static const double _kAeAvgBrightThreshold = 200.0;
  static const double _kAeAvgDarkThreshold = 15.0;
  static const int _kAeTransitionMinFrames = 2;
  static const int _kAeTransitionMaxFrames = 30;
  static const Duration _kAePostTransitionGuard = Duration(milliseconds: 3000);

  bool get _aeTransitioning =>
      _aeTransitionFrames >= _kAeTransitionMinFrames &&
      _aeTransitionFrames <= _kAeTransitionMaxFrames;

  bool _aePipelineFrozen(DateTime now) {
    if (_aeTransitioning) return true;
    final endedAt = _aeTransitionEndedAt;
    if (endedAt == null) return false;
    return now.difference(endedAt) < _kAePostTransitionGuard;
  }

  int? _lastImageHash;
  DateTime _lastImageChangeAt = DateTime.now();
  bool _cameraFrozenWarned = false;

  DateTime _lastDepthAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _depthInterval = const Duration(milliseconds: 400);

  bool _lifecycleBackgroundWarned = false;

  Timer? _stallWatchdog;
  DateTime _lastFrameArrivedAt = DateTime.now();
  bool _cameraStallWarned = false;

  
  
  
  
  Timer? _indoorPollTimer;
  static const Duration _kIndoorPollPeriod = Duration(seconds: 2);

  final List<Uint8List> _planeBytesBuffer = List<Uint8List>.filled(
    3,
    Uint8List(0),
    growable: true,
  );

  int _blurryStreak = 0;
  DateTime _lastShakeWarnAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _kShakeWarnStreak = 15;
  static const Duration _kShakeWarnCooldown = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _vm = CameraViewModel();

    _vm.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _twoFingerSosTimer?.cancel();
    _fallCountdownTimer?.cancel();
    _stallWatchdog?.cancel();
    _indoorPollTimer?.cancel();
    _lazyDisposeTimer?.cancel();
    _reinitHeartbeat?.cancel();
    _controller?.dispose();
    _controller = null;
    VisionForegroundService.stop();
    _vm.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stallWatchdog?.cancel();
      _stallWatchdog = null;
      _cameraStallWarned = false;
      _indoorPollTimer?.cancel();
      _indoorPollTimer = null;
      _vm.indoorGate.reset();

      final ctrl = _controller;
      if (ctrl != null && ctrl.value.isInitialized && !_streamPaused) {
        try {
          ctrl.stopImageStream();
        } catch (_) {}
        _streamPaused = true;
        _isCameraReady = false;

        _lazyDisposeTimer?.cancel();
        _lazyDisposeTimer = Timer(_kLazyDisposeDuration, () {
          _controller?.dispose();
          _controller = null;
          _streamPaused = false;
        });
      }

      if (!_lifecycleBackgroundWarned) {
        _lifecycleBackgroundWarned = true;
        _vm.tts.say(
          S.get('lifecycle_background'),
          SpeechPriority.critical,
          pan: 0.0,
        );
        HapticService.vibrate(const [0, 200, 100, 200, 100, 200]);
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_lifecycleBackgroundWarned) {
        _lifecycleBackgroundWarned = false;
        _vm.tts.say(S.get('lifecycle_resumed'), SpeechPriority.info, pan: 0.0);
      }

      _lazyDisposeTimer?.cancel();
      _lazyDisposeTimer = null;

      final ctrl = _controller;
      if (ctrl != null && ctrl.value.isInitialized && _streamPaused) {
        _streamPaused = false;
        try {
          ctrl.startImageStream(_onFrame);
          _isCameraReady = true;
        } catch (_) {
          _controller?.dispose();
          _controller = null;
          _initCamera();
        }
      } else if (_controller == null ||
          !(_controller?.value.isInitialized ?? false)) {
        _streamPaused = false;
        _vm.tts.say(
          S.alert('camera_reinit'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        _reinitHeartbeat?.cancel();
        _reinitHeartbeat = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => HapticService.vibrate(const [0, 100, 300, 100]),
        );
        _initCamera();
      }
      _startStallWatchdog();
    }
  }

  void _startStallWatchdog() {
    _stallWatchdog?.cancel();
    _lastFrameArrivedAt = DateTime.now();
    _cameraStallWarned = false;
    _stallWatchdog = Timer.periodic(kStallWatchdogPeriod, (_) {
      if (!mounted) return;
      if (_lifecycleBackgroundWarned) return;
      if (!_isCameraReady) return;
      final gap = DateTime.now().difference(_lastFrameArrivedAt);
      final threshold = _vm.throttler.stallWatchdogThreshold();
      if (gap >= threshold && !_cameraStallWarned) {
        _cameraStallWarned = true;
        _vm.earcon.play(Earcon.cameraBlocked);
        HapticService.vibrate(const [0, 400, 150, 400, 150, 400, 150, 400]);
        _vm.tts.say(S.get('camera_stalled'), SpeechPriority.critical, pan: 0.0);
      }
    });
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
        if (mounted) setState(() {});
        if (level != ThrottleLevel.normal) {
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

      final ok = await _models.loadMidas(numThreads: _numThreads);
      if (!mounted) return;

      final hasDepthAi =
          ok &&
          _models.depthProvider != null &&
          _models.depthProvider!.tier != DepthTier.focalLength;
      setState(() => _depthProviderReady = hasDepthAi);

      _vm.setStatus('Загрузка ИИ модели YOLO...');
      await _models.loadYolo(useGpu: _useGpu, numThreads: _numThreads);

      _vm.setStatus('Запуск камеры...');
      await _initCamera();

      await VisionForegroundService.start();

      _vm.fallDetector.onFallDetected = _handleFallDetected;
      await _vm.fallDetector.init();

      _vm.tts.onAudioRouteInterrupted = () {
        HapticService.vibrate([0, 200, 100, 200, 100, 200]);
        _vm.earcon.play(Earcon.cameraBlocked);
        _vm.tts.say(
          S.get('audio_route_interrupted'),
          SpeechPriority.critical,
          pan: 0.0,
        );
      };
      _vm.tts.onAudioRouteResumed = () {
        _vm.tts.say(S.get('audio_resumed'), SpeechPriority.info, pan: 0.0);
      };
      _vm.tts.onTtsStall = () {
        HapticService.vibrate([0, 400, 200, 400, 200, 400]);
        _vm.earcon.play(Earcon.cameraBlocked);
        try {
          const MethodChannel('bagdar/watchdog').invokeMethod('ping');
        } catch (_) {}
      };

      _heartbeatTimer = Timer.periodic(
        _currentHeartbeatInterval(),
        (_) => _heartbeatTick(),
      );

      _vm.voice.onCommand = _handleVoiceCommand;
      _vm.voice.onNavCommand = _handleNavCommand;
      _vm.voice.onListeningStateChanged = (listening) {
        if (!listening) {
          _vm.earcon.play(Earcon.success);
        }
      };

      if (!_depthProviderReady && _vm.mode == AppMode.street) {
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
    } catch (e) {
      _vm.setStatus('Сбой: $e');
    }
  }

  Duration _currentHeartbeatInterval() {
    if (_vm.battery.level == ThrottleLevel.critical) {
      return const Duration(seconds: 60);
    }
    if (_vm.isPitchBlack) return kHeartbeatIntervalPitchBlack;
    return kHeartbeatInterval;
  }

  void _handleFallDetected() {
    if (_fallCountdownActive) return;
    _fallCountdownActive = true;
    _fallCountdownSec = 15;

    _vm.tts.say(S.get('sos_fall_detected'), SpeechPriority.critical, pan: 0.0);
    _vm.tts.say(
      S.get('sos_fall_cancel_hint'),
      SpeechPriority.warning,
      pan: 0.0,
    );
    HapticService.vibrate([0, 300, 200, 300, 200, 300]);

    _startFallCancelListener();

    _fallCountdownTimer?.cancel();
    _fallCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _fallCountdownSec--;
      if (_fallCountdownSec <= 0) {
        timer.cancel();
        _fallCountdownActive = false;
        _stopFallCancelListener();
        _sendFallSos();
      } else if (_fallCountdownSec == 10 ||
          _fallCountdownSec == 5 ||
          _fallCountdownSec <= 3) {
        _vm.tts.say(
          '${S.get('sos_fall_countdown')} $_fallCountdownSec ${S.get('sos_fall_seconds')}',
          SpeechPriority.warning,
          pan: 0.0,
        );
        if (_fallCountdownSec == 10 || _fallCountdownSec == 5) {
          _restartFallCancelListener();
        }
      }
    });
  }

  void _sendFallSos() async {
    final hasContact = (_vm.sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      _vm.tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
    }
    _vm.tts.say(S.get('sos_sending'), SpeechPriority.critical, pan: 0.0);
    final result = await _vm.sos.sendSos();
    if (!mounted) return;
    final msg = switch (result) {
      SosResult.sent => S.get('sos_fall_sent'),
      SosResult.sentFallback =>
        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',
      SosResult.noLocation => S.get('sos_sent_no_location'),
      SosResult.launchFailed => S.get('sos_launch_failed'),
      SosResult.noContact => S.get('sos_no_contact'),
      SosResult.error => S.get('sos_error'),
    };
    _vm.tts.say(msg, SpeechPriority.critical, pan: 0.0);
  }

  void _startFallCancelListener() {
    if (_fallCancelListenerActive) return;
    _fallCancelListenerActive = true;
    unawaited(_vm.voice.startListening());
  }

  void _restartFallCancelListener() {
    if (!_fallCancelListenerActive) return;
    unawaited(_vm.voice.startListening());
  }

  void _stopFallCancelListener() {
    _fallCancelListenerActive = false;
    unawaited(_vm.voice.stopListening());
  }

  void _cancelFallCountdown() {
    if (!_fallCountdownActive) return;
    _fallCountdownTimer?.cancel();
    _fallCountdownActive = false;
    _fallCountdownSec = 0;
    _stopFallCancelListener();
    _vm.tts.say(S.get('sos_fall_cancelled'), SpeechPriority.critical, pan: 0.0);
    HapticService.vibrate([0, 100]);
  }

  void _heartbeatTick() {
    if (!mounted) return;
    HapticService.vibrate([0, 50]);
    _vm.earcon.play(Earcon.heartbeat);
    try {
      const MethodChannel('bagdar/watchdog').invokeMethod('ping');
    } catch (_) {}

    final desired = _currentHeartbeatInterval();
    if (_heartbeatTimer == null || _heartbeatTimer!.tick == 0) return;
    if (desired.inMilliseconds != kHeartbeatInterval.inMilliseconds) {
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(desired, (_) => _heartbeatTick());
    }
  }

  void _handleTap() {
    if (_fallCountdownActive) {
      _cancelFallCountdown();
      return;
    }
  }

  void _triggerSos() async {
    HapticService.vibrate([0, 200, 100, 200, 100, 200]);
    _vm.tts.say('SOS', SpeechPriority.critical, pan: 0.0);
    final hasContact = (_vm.sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      _vm.tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
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
    _vm.tts.say(msg, SpeechPriority.critical, pan: 0.0);
  }

  void _startVoiceCommand() async {
    HapticService.vibrate([0, 100, 50, 100]);
    _vm.tts.say(S.get('voice_listening'), SpeechPriority.critical, pan: 0.0);
    await _vm.voice.startListening();
  }

  void _handleVoiceCommand(VoiceCommand cmd) {
    if (_fallCountdownActive) {
      if (cmd == VoiceCommand.cancelFall || cmd == VoiceCommand.sos) {
        if (cmd == VoiceCommand.cancelFall) {
          _cancelFallCountdown();
          return;
        }
        _cancelFallCountdown();
        _triggerSos();
        return;
      }
    }

    switch (cmd) {
      case VoiceCommand.cancelFall:
        _vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.scanAll:
      case VoiceCommand.scanLeft:
      case VoiceCommand.scanRight:
      case VoiceCommand.scanForward:
        _vm.tts.say(S.get('scan_see'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.readText:
        _wantOcr = true;
        _ocrStartedAt = DateTime.now();
        _vm.tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.modeStreet:
        _vm.setMode(AppMode.street);
        _vm.tts.say(S.get('mode_street'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.modeCane:
        _vm.setMode(AppMode.cane);
        _vm.tts.say(S.get('mode_cane'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.modeScan:
        _vm.setMode(AppMode.scan);
        _vm.tts.say(S.get('mode_scan'), SpeechPriority.critical, pan: 0.0);
        break;
      case VoiceCommand.toggleMode:
        _vm.cycleMode(1);
        break;
      case VoiceCommand.togglePitchBlackUi:
        _vm.togglePitchBlack();
        break;
      case VoiceCommand.toggleGuideDogMode:
        _vm.toggleGuideDogMode();
        break;
      case VoiceCommand.stopNavigation:
        _vm.nav.stopNavigation();
        _vm.tts.say(S.get('nav_stopped'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.whereAmI:
        _vm.tts.say(_vm.nav.getWhereAmI(), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.navStatus:
        _vm.tts.say(_vm.nav.getStatusSummary(), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.confirmBoarded:
        _vm.nav.confirmBoarded();
        break;
      case VoiceCommand.saveWaypoint:
        _saveWaypointFromVoice();
        break;
      case VoiceCommand.sos:
        _triggerSos();
        break;
      case VoiceCommand.unknown:
        _vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      case VoiceCommand.navigateTo:
      case VoiceCommand.transitTo:
      case VoiceCommand.nearestStop:
      case VoiceCommand.busRoute:
      case VoiceCommand.busSchedule:
      case VoiceCommand.downloadMap:
        _vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
    }
  }

  void _handleNavCommand(VoiceCommand cmd, String destination) {
    switch (cmd) {
      case VoiceCommand.navigateTo:
        _vm.tts.say(
          '${S.get('nav_searching')} $destination',
          SpeechPriority.info,
          pan: 0.0,
        );
        unawaited(_startNavigateTo(destination));
        break;
      case VoiceCommand.transitTo:
        _vm.tts.say(
          '${S.get('nav_searching')} $destination',
          SpeechPriority.info,
          pan: 0.0,
        );
        unawaited(_startTransitTo(destination));
        break;
      case VoiceCommand.busRoute:
      case VoiceCommand.busSchedule:
      case VoiceCommand.downloadMap:
        _vm.tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
        break;
      default:
        break;
    }
  }

  Future<void> _startNavigateTo(String destination) async {
    try {
      final pos = await _currentPositionForNav();
      if (pos == null) {
        _vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final places = _vm.offlineRouting.poiReady
          ? await _vm.offlineRouting.searchPlaces(
              destination,
              pos.latitude,
              pos.longitude,
            )
          : await _vm.twoGis.searchPlaces(
              destination,
              pos.latitude,
              pos.longitude,
            );
      if (places.isEmpty) {
        
        _vm.tts.say(S.get('nav_not_found'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final target = places.first;
      _vm.tts.say(S.get('nav_building_route'), SpeechPriority.info, pan: 0.0);
      final route = _vm.offlineRouting.isReady
          ? await _vm.offlineRouting.getWalkRoute(
              pos.latitude,
              pos.longitude,
              target.lat,
              target.lng,
              destinationName: target.name,
            )
          : await _vm.twoGis.getWalkRoute(
              pos.latitude,
              pos.longitude,
              target.lat,
              target.lng,
              destinationName: target.name,
            );
      if (route == null) {
        _vm.tts.say(
          S.get('nav_route_failed'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        return;
      }
      _vm.nav.startWalkNavigation(route);
      
    } catch (e) {
      debugPrint('startNavigateTo error: $e');
      _vm.tts.say(S.get('nav_route_failed'), SpeechPriority.warning, pan: 0.0);
    }
  }

  Future<void> _startTransitTo(String destination) async {
    try {
      final pos = await _currentPositionForNav();
      if (pos == null) {
        _vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      if (!_vm.twoGis.hasApiKey) {
        _vm.tts.say(S.get('nav_no_api_key'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final places = await _vm.twoGis.searchPlaces(
        destination,
        pos.latitude,
        pos.longitude,
      );
      if (places.isEmpty) {
        _vm.tts.say(S.get('nav_not_found'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      final target = places.first;
      _vm.tts.say(S.get('nav_building_route'), SpeechPriority.info, pan: 0.0);
      final route = await _vm.twoGis.getTransitRoute(
        pos.latitude,
        pos.longitude,
        target.lat,
        target.lng,
        destinationName: target.name,
      );
      if (route == null) {
        _vm.tts.say(
          S.get('nav_route_failed'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        return;
      }
      _vm.nav.startTransitNavigation(route);
    } catch (e) {
      debugPrint('startTransitTo error: $e');
      _vm.tts.say(S.get('nav_route_failed'), SpeechPriority.warning, pan: 0.0);
    }
  }

  Future<Position?> _currentPositionForNav() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
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
    final ageSec = pos == null
        ? null
        : now.difference(pos.timestamp).inSeconds;
    final transition = _vm.indoorGate.feed(
      gpsAccuracyM: accuracyM,
      gpsAgeSec: ageSec,
      motion: _vm.fallDetector.motionState,
      now: now,
    );
    _vm.applyIndoorTransition(transition);
  }

  void _startIndoorPoll() {
    _indoorPollTimer?.cancel();
    _indoorPollTimer = Timer.periodic(
      _kIndoorPollPeriod,
      (_) => _pollIndoorState(),
    );
  }

  void _saveWaypointFromVoice() async {
    try {
      final name = 'WP ${DateTime.now().toIso8601String().substring(11, 16)}';
      final wp = await _vm.waypoints.saveCurrentLocation(name);
      if (wp == null) {
        _vm.tts.say(S.get('nav_no_gps'), SpeechPriority.warning, pan: 0.0);
        return;
      }
      _vm.tts.say(S.get('waypoint_saved'), SpeechPriority.info, pan: 0.0);
    } catch (e) {
      debugPrint('saveWaypointFromVoice error: $e');
    }
  }

  void _checkLuminosity(CameraImage image) {
    final yPlane = image.planes[0].bytes;
    if (yPlane.isEmpty) return;

    final rowStride = image.planes[0].bytesPerRow;
    final w = image.width;
    final h = image.height;
    final halfW = w >> 1;
    final halfH = h >> 1;

    double sum = 0;
    double sumSq = 0;
    int count = 0;
    
    
    
    final quadSum = List<double>.filled(4, 0);
    final quadCount = List<int>.filled(4, 0);

    for (int i = 0; i < yPlane.length; i += 100) {
      final v = yPlane[i].toDouble();
      sum += v;
      sumSq += v * v;
      count++;
      final y = i ~/ rowStride;
      final x = i - y * rowStride;
      if (y >= h || x >= w) continue;
      final quad = (y < halfH ? 0 : 2) + (x < halfW ? 0 : 1);
      quadSum[quad] += v;
      quadCount[quad]++;
    }
    if (count == 0) return;

    final avgLuminosity = sum / count;
    
    
    final variance = (sumSq / count) - (avgLuminosity * avgLuminosity);

    
    
    
    
    final isAeTransition = variance < _kAeVarianceThreshold &&
        (avgLuminosity > _kAeAvgBrightThreshold ||
            avgLuminosity < _kAeAvgDarkThreshold);
    if (isAeTransition) {
      _aeTransitionFrames++;
      _aeTransitionEndedAt = null;
    } else {
      if (_aeTransitionFrames >= _kAeTransitionMinFrames) {
        _aeTransitionEndedAt = DateTime.now();
      }
      _aeTransitionFrames = 0;
    }

    
    
    
    
    
    
    if (!isAeTransition) {
      final transition = _vm.weatherGate.feed(variance, avgLuminosity);
      switch (transition) {
        case WeatherTransition.degraded:
          _vm.tts.say(
            S.alert('weather_low_vis'),
            SpeechPriority.warning,
            pan: 0.0,
          );
          HapticService.vibrate(const [0, 200, 80, 200]);
          break;
        case WeatherTransition.recovered:
          _vm.tts.say(
            S.alert('weather_restored'),
            SpeechPriority.info,
            pan: 0.0,
          );
          break;
        case WeatherTransition.none:
          break;
      }
      
      
      
      _vm.tracker.weatherDegraded = _vm.weatherGate.degraded;
    }

    if (avgLuminosity < _luminosityMinValue) {
      _lowLuminosityFrames++;
      if (_lowLuminosityFrames >= _lowLuminosityThreshold &&
          !_cameraBlockedWarned) {
        _cameraBlockedWarned = true;
        _vm.tts.say(
          S.alert('camera_blocked'),
          SpeechPriority.critical,
          pan: 0.0,
        );
        HapticService.vibrate([0, 300, 100, 300]);
      }
    } else {
      if (_cameraBlockedWarned) {
        _cameraBlockedWarned = false;
      }
      _lowLuminosityFrames = 0;
    }

    
    
    
    
    int deadQuads = 0;
    for (int q = 0; q < 4; q++) {
      if (quadCount[q] == 0) continue;
      final avg = quadSum[q] / quadCount[q];
      if (avg < _luminosityMinValue) deadQuads++;
    }
    final isPartial = deadQuads >= 1 &&
        deadQuads <= 2 &&
        avgLuminosity >= _luminosityMinValue;
    if (isPartial) {
      _partialOcclusionFrames++;
      if (_partialOcclusionFrames >= _kPartialOcclusionStreak &&
          !_partialOcclusionWarned) {
        _partialOcclusionWarned = true;
        _vm.tts.say(
          S.alert('camera_partial_blocked'),
          SpeechPriority.warning,
          pan: 0.0,
        );
        HapticService.vibrate(const [0, 200, 80, 200]);
      }
    } else {
      _partialOcclusionFrames = 0;
      if (_partialOcclusionWarned && deadQuads == 0) {
        _partialOcclusionWarned = false;
      }
    }
  }

  void _checkFrozenFrame(CameraImage image, DateTime now) {
    final bytes = image.planes[0].bytes;
    if (bytes.length < 10) return;

    final stride = bytes.length ~/ 10;
    int hash = 0;
    for (int i = 0; i < 10; i++) {
      hash = (hash * 31) + bytes[i * stride];
    }

    if (hash != _lastImageHash) {
      _lastImageHash = hash;
      _lastImageChangeAt = now;
      if (_cameraFrozenWarned) {
        _cameraFrozenWarned = false;
      }
    } else {
      if (now.difference(_lastImageChangeAt) > const Duration(seconds: 5) &&
          !_cameraFrozenWarned) {
        _cameraFrozenWarned = true;
        _vm.tts.say(S.get('camera_frozen'), SpeechPriority.critical, pan: 0.0);
        HapticService.vibrate([0, 500, 200, 500]);
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
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

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

      if (mounted) {
        setState(() {
          _isCameraReady = true;
          _vm.setStatus(S.get('camera_started'));
        });
      }
      _startStallWatchdog();
      _startIndoorPoll();
    } catch (e) {
      _vm.setStatus('Ошибка камеры: $e');
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (!mounted || _exclusiveDepthTransition) return;

    final now = DateTime.now();
    _lastFrameArrivedAt = now;
    if (_cameraStallWarned) {
      _cameraStallWarned = false;
      _vm.tts.say(S.get('camera_resumed'), SpeechPriority.info, pan: 0.0);
    }
    if (_reinitHeartbeat != null) {
      _reinitHeartbeat?.cancel();
      _reinitHeartbeat = null;
    }

    _frameCount++;
    _imgW = image.width;
    _imgH = image.height;
    final viewportAspect = MediaQuery.sizeOf(context).aspectRatio;

    final frameSw = Stopwatch()..start();

    _checkLuminosity(image);
    _checkFrozenFrame(image, now);

    
    
    
    
    
    if (_aePipelineFrozen(now)) {
      _finalizeFramePerf(now: now, frameSw: frameSw);
      return;
    }

    final yPlane = image.planes[0];
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
          _vm.updateTracks(predictedTracks);
        }
      }
      _finalizeFramePerf(now: now, frameSw: frameSw);
      return;
    }
    _blurryStreak = 0;

    
    
    
    
    
    
    
    
    
    
    if ((_vm.mode == AppMode.street || _vm.mode == AppMode.cane) &&
        !_vm.weatherGate.degraded &&
        !_vm.isIndoor) {
      final event = _vm.motionPreAlert.feed(image, now);
      if (event != null) _handleMotionIntrusion(event);
    }

    final currentDetectInterval = _detectInterval;
    final shouldRunDetect =
        now.difference(_lastDetectAt) >= currentDetectInterval;

    if (!shouldRunDetect || _isDetecting) {
      final predictedTracks = _vm.tracker.predict();
      if (predictedTracks.isNotEmpty) {
        final uiNow = DateTime.now();
        if (uiNow.difference(_lastUiAt) >= _vm.throttler.uiInterval()) {
          _lastUiAt = uiNow;
          _vm.updateTracks(predictedTracks);
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
        confThreshold: 0.35,
        classThreshold: 0.35,
      );

      if (!mounted) return;

      
      
      
      
      final yPlane = planeBytes.isNotEmpty ? planeBytes[0] : null;
      final yStride =
          image.planes.isNotEmpty ? image.planes[0].bytesPerRow : null;
      final dets = _buildRawDets(
        raw,
        _imgW,
        _imgH,
        yPlane: yPlane,
        yRowStride: yStride,
      );
      final tracks = _vm.tracker.update(dets, _imgW, _imgH, now);

      final uiNow = DateTime.now();
      if (uiNow.difference(_lastUiAt) >= _vm.throttler.uiInterval()) {
        _lastUiAt = uiNow;
        _vm.updateTracks(tracks);
      }

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

      if (_depthProviderReady &&
          now.difference(_lastDepthAt) >= _depthInterval) {
        _lastDepthAt = now;
        _runDepthAnalysis(image);
      }
    } finally {
      _finalizeFramePerf(now: now, frameSw: frameSw);
      _isDetecting = false;
    }
  }

  void _runDepthAnalysis(CameraImage image) async {
    final depthProvider = _models.depthProvider;
    if (depthProvider == null || !depthProvider.isReady) return;

    try {
      final cropTopFrac = OrientationService.cropTopFracForPitch(
        _vm.orientation.pitch,
      );
      
      
      
      
      
      
      final userStationary =
          _vm.fallDetector.motionState == MotionState.stationary;
      final hazards = await depthProvider.analyze(
        image,
        cropTopFrac: cropTopFrac,
        userStationary: userStationary,
        
        
        weatherDegraded: _vm.weatherGate.degraded,
      );
      if (!mounted || hazards.isEmpty) return;

      final rollExcessive = _vm.orientation.isRollExcessive;
      for (final hazard in hazards) {
        
        
        
        
        if (hazard.type == DepthHazardType.escalatorRiding) {
          HapticService.vibrate(const [0, 50, 120, 50]);
          continue;
        }
        final hazardKey = switch (hazard.type.name) {
          'stepDown' => 'hazard_step_down',
          'stepUp' => 'hazard_step_up',
          'pothole' => 'hazard_pothole',
          'curb' => 'hazard_curb',
          'lowCurb' => 'hazard_low_curb',
          'deadZone' => 'hazard_dead_zone',
          'stairsDown' => 'hazard_stairs_down',
          'overhead' => 'hazard_overhead',
          'glassDoor' => 'hazard_glass_door',
          'slippery' => 'hazard_slippery',
          
          
          
          'nearFieldIntrusion' => 'hazard_near_field',
          _ => 'hazard_unknown',
        };
        final naturallyCritical =
            hazard.type == DepthHazardType.stairsDown ||
            hazard.type == DepthHazardType.overhead;
        final isCritical = naturallyCritical && !rollExcessive;
        final priority = isCritical
            ? SpeechPriority.critical
            : SpeechPriority.warning;
        _vm.tts.say(S.alert(hazardKey), priority, pan: hazard.pan);
        HapticService.vibrate(
          isCritical
              ? const [0, 300, 120, 300, 120, 300]
              : const [0, 200, 100, 200],
        );
      }
    } catch (e) {
      debugPrint('Depth analysis error: $e');
    }
  }

  void _handleMotionIntrusion(MotionIntrusionEvent event) {
    final pan = switch (event.side) {
      MotionIntrusionSide.left => -1.0,
      MotionIntrusionSide.right => 1.0,
      MotionIntrusionSide.center => 0.0,
    };
    _vm.earcon.play(Earcon.approaching, pan: pan);
    HapticService.vibrate(const [0, 80, 40, 120]);
  }

  bool _hasCloseOrApproachingVehicle(List<Track> tracks) {
    for (final t in tracks) {
      if (!isVehicle(t.label)) continue;
      if (t.approaching) return true;
      if (t.dist == 'very close' || t.dist == 'close') return true;
      if (t.distM > 0 && t.distM < 8.0) return true;
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
    final out = <RawDet>[];
    final frameArea = (imgW * imgH).toDouble();
    final canExtractAppearance =
        yPlane != null && yRowStride != null && yRowStride > 0;
    for (final r in raw) {
      final label = (r['tag'] ?? '').toString();
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
          conf: (r['confidence'] as num?)?.toDouble() ?? 0.0,
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
  }

  void _recomputeCadence() {
    _detectInterval = _vm.throttler.detectInterval(
      _vm.battery.detectIntervalMs,
    );
    _depthInterval = _vm.throttler.midasInterval(_vm.battery.midasIntervalMs);
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
  }

  void _openSettings() {
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
          pitchBlackUiEnabled: false,
          depthTier: _models.depthProvider?.tier,
          midasReady: _depthProviderReady,
          sosContactNumber: _vm.sos.contactNumber,
          onLanguageChanged: (lang) async {
            AppStrings.setLanguage(lang);
            await Settings.instance.setLanguage(lang.index);
            await _vm.tts.setLanguage(AppStrings.ttsLang);
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
          onPitchBlackUiChanged: (v) {},
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
        ),
      ),
    );
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
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! > 500) {
            _vm.cycleMode(1);
          } else if (details.primaryVelocity! < -500) {
            _vm.cycleMode(-1);
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -500) {
            _vm.togglePitchBlack();
          } else if (details.primaryVelocity! > 500) {
            _vm.showHelp();
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

              if (_fallCountdownActive)
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
                            '${S.get('sos_fall_countdown')} $_fallCountdownSec ${S.get('sos_fall_seconds')}',
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
                  label: S.get('camera_screen_semantics'),
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
            ],
          ),
        ),
      ),
    );
  }

  final Set<int> _activePointers = {};

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length == 2 && !_twoFingerSosArmed) {
      _twoFingerSosArmed = true;
      _twoFingerSosTimer?.cancel();
      _twoFingerSosTimer = Timer(_twoFingerSosHold, () {
        if (!_twoFingerSosArmed) return;
        _twoFingerSosArmed = false;
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

  void _disarmTwoFingerSos() {
    _twoFingerSosArmed = false;
    _twoFingerSosTimer?.cancel();
    _twoFingerSosTimer = null;
    _activePointers.clear();
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';

import '../models/app_mode.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/ocr_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';
import '../services/battery_monitor.dart';
import '../services/foreground_service.dart';
import '../services/sos_service.dart';
import '../services/waypoint_service.dart';
import '../tracker/raw_det.dart';
import '../tracker/track.dart';
import '../tracker/tracker.dart';
import '../camera/alert_manager.dart';
import '../services/depth_provider.dart';
import '../services/device_capability.dart';
import '../utils/depth_hazard.dart';
import '../utils/distance_utils.dart';
import '../utils/midas_service.dart';
import '../widgets/camera_controls_sheet.dart';
import '../widgets/debug_hud.dart';
import '../widgets/status_panel.dart';
import '../widgets/track_painter.dart';
import '../widgets/waypoint_sheet.dart';

class AiCameraScreen extends StatefulWidget {
  final AppMode? initialMode;
  const AiCameraScreen({super.key, this.initialMode});

  @override
  State<AiCameraScreen> createState() => _AiCameraScreenState();
}

class _AiCameraScreenState extends State<AiCameraScreen>
    with WidgetsBindingObserver {

  CameraController? _controller;
  bool _isCameraReady = false;
  bool _isDetecting   = false;
  late FlutterVision _vision;
  bool _useGpu     = false;
  int  _numThreads = 2;

  Duration _detectInterval      = const Duration(milliseconds: 140);
  Duration _minUiInterval = const Duration(milliseconds: 120);
  DateTime _lastDetectAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastUiAt     = DateTime.fromMillisecondsSinceEpoch(0);

  int _imgW = 0, _imgH = 0;

  final Tracker _tracker = Tracker();

  final ValueNotifier<List<Track>> _tracksNotifier =
      ValueNotifier(const []);

  final TtsService    _tts    = TtsService();
  final EarconService _earcon = EarconService();
  late final AlertManager _alertMgr;

  final OcrService _ocr = OcrService();
  CameraImage? _lastFrame;
  DateTime _lastOcrAt     = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastAutoOcrAt = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _autoOcrInterval = const Duration(seconds: 8);
  bool     _ocrBusy       = false;
  String   _lastOcrText   = '';

  final BatteryMonitor  _battery   = BatteryMonitor();
  final WaypointService _waypoints = WaypointService();
  final SosService      _sos       = SosService();

  bool _isDark = false;
  DateTime _lastLumCheckAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasNightMode = false;

  DepthProvider? _depthProvider;
  final FusionEngine _fusion = FusionEngine();
  bool _depthProviderReady = false;

  Duration _midasInterval = const Duration(milliseconds: 500);
  DateTime _lastMidasAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _midasPausedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _burstModeEndsAt = DateTime.fromMillisecondsSinceEpoch(0);
  DepthHazard? _latestMidasHazard;

  bool _isCalibrated = false;

  String _lastScanDescription = '';
  int    _scanRepeatCount     = 0;

  int      _tapCount  = 0;
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);

  AppMode _mode = AppMode.street;

  final VoiceCommandService _voice = VoiceCommandService();
  bool _voiceListening = false;
  bool _voiceAvailable = false;

  String _statusLine   = 'Запуск VisionGuide...';
  bool   _showDebugHud = false;
  double _avgInfMs     = 0;
  double _detectFps    = 0;
  int    _frameCount   = 0;
  DateTime _lastFpsTick = DateTime.now();

  static const Set<String> _streetObjects = {
    'person', 'dog', 'cat', 'car', 'bus', 'truck', 'motorcycle', 'bicycle',
    'traffic light', 'stop sign', 'fire hydrant', 'parking meter', 'bench',
    'backpack', 'handbag', 'suitcase', 'umbrella',
  };

  @override
  void initState() {
    super.initState();
    _vision   = FlutterVision();
    _alertMgr = AlertManager(tts: _tts, earcon: _earcon);
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  Future<void> _initAll() async {
    try {
      if (mounted) setState(() => _statusLine = 'Инициализация голоса (TTS)...');
      await _tts.init();
      _earcon.init();
      _tracker.ttsService = _tts;

      if (mounted) setState(() => _statusLine = 'Инициализация батареи...');
      await _battery.init();

      if (mounted) setState(() => _statusLine = 'Инициализация GPS...');
      await _waypoints.init();

      if (mounted) setState(() => _statusLine = 'Инициализация SOS/Настроек...');
      await _sos.init();

      if (mounted) setState(() => _statusLine = 'Инициализация фонового режима...');
      await VisionForegroundService.init();

      _battery.onThrottleChanged = (level) {
        if (mounted) setState(() {});
        if (level != ThrottleLevel.normal) {
          final msg = level == ThrottleLevel.aggressive 
              ? S.get('battery_low') 
              : S.get('battery_moderate');
          _tts.say(msg, SpeechPriority.info, pan: 0.0);
        }
      };

      _waypoints.onNearWaypoint = (wp) {
        _tts.say('${S.get('waypoint_near')} ${wp.name}.', SpeechPriority.warning, pan: 0.0);
      };
      _waypoints.startProximityMonitor();

      DeviceCapabilityProbe.probe().then((caps) {
        debugPrint('DeviceCaps: $caps');
        final provider = DepthProviderFactory.create(caps);
        provider.init(threads: Settings.instance.numThreads).then((ok) {
          if (!mounted) return;
          _depthProvider = provider;
          final hasDepthAi = ok && provider.tier != DepthTier.focalLength;
          setState(() => _depthProviderReady = hasDepthAi);
          if (!hasDepthAi) {
            if (mounted) {
              _tts.say(S.get('depth_unavailable'), SpeechPriority.info, pan: 0.0);
            }
          }
        });
      });

      _voice.onCommand              = _onVoiceCommand;
      _voice.onListeningStateChanged = (listening) {
        if (mounted) setState(() => _voiceListening = listening);
      };
      _voice.init(locale: AppStrings.ttsLang).then((available) {
        if (mounted) setState(() => _voiceAvailable = available);
      });

      loadFocalLength();
      _isCalibrated = Settings.instance.isCalibrated;
      _useGpu       = Settings.instance.useGpu;
      _numThreads   = Settings.instance.numThreads;

      AppStrings.setLanguage(AppLanguage.values[Settings.instance.language]);
      await _tts.setLanguage(AppStrings.ttsLang);

      if (widget.initialMode != null) {
        setState(() => _mode = widget.initialMode!);
      } else {
        final modeName = Settings.instance.onboardingMode;
        final saved = AppMode.values.where((m) => m.name == modeName).firstOrNull;
        if (saved != null) setState(() => _mode = saved);
      }

      if (mounted) setState(() => _statusLine = 'Запрос доступа к камере...');
      final granted = await _requestCameraPermission();
      if (!granted) return;

      if (mounted) setState(() => _statusLine = 'Запуск камеры...');
      await _initCamera();

      if (mounted) setState(() => _statusLine = 'Загрузка ИИ модели YOLO...');
      await _loadModel();

      if (mounted) setState(() => _statusLine = S.get('system_ready'));
      
      if (mounted) setState(() => _statusLine = 'Запуск фоновой службы...');
      await VisionForegroundService.start();

      if (mounted) setState(() => _statusLine = S.get('system_ready'));

      if (!_isCalibrated) {
        Future.delayed(const Duration(seconds: 6), () {
          if (mounted) {
            _tts.say(S.get('calib_recommend'), SpeechPriority.info, pan: 0.0);
          }
        });
      }
    } catch (e, stack) {
      debugPrint('INIT ERROR: $e\n$stack');
      if (mounted) {
        setState(() => _statusLine = 'Сбой: $e');
      }
    }
  }

  Future<bool> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied && mounted) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title:   const Text('Нет доступа к камере'),
          content: const Text(
            'Камера необходима для работы VisionGuide.\n'
            'Откройте Настройки и разрешите доступ к камере.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(S.get('cancel')),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openAppSettings();
              },
              child: Text(S.get('settings')),
            ),
          ],
        ),
      );
    } else {
      _setStatus('Доступ к камере отклонён');
      _tts.say(S.get('camera_unavailable'), SpeechPriority.critical);
    }
    return false;
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) { _setStatus(S.get('camera_not_found')); return; }

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
          _statusLine    = S.get('camera_started');
        });
      }
    } catch (e) {
      _setStatus('Ошибка камеры: $e');
      _tts.say(S.get('camera_unavailable'), SpeechPriority.critical);
    }
  }

  Future<void> _loadModel() async {
    Future<void> tryLoad(bool gpu) async {
      await _vision.closeYoloModel();
      await _vision.loadYoloModel(
        labels:       'assets/labels.txt',
        modelPath:    'assets/yolov8n_int8.tflite',
        modelVersion: 'yolov8',
        numThreads:   _numThreads,
        useGpu:       gpu,
      );
    }

    try {
      await tryLoad(_useGpu);
      _setStatus('Нейросеть (${_useGpu ? "GPU" : "CPU"}, $_numThreads пот.)');
    } catch (_) {
      if (_useGpu) {
        try {
          await tryLoad(false);
          _useGpu = false;
          _setStatus('GPU недоступен, CPU $_numThreads пот.');
        } catch (e2) {
          _setStatus('Ошибка ИИ: $e2');
        }
      } else {
        _setStatus('Ошибка ИИ (CPU)');
      }
    }
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _statusLine = s);
  }

  Future<void> _onFrame(CameraImage image) async {
    _imgW = image.width;
    _imgH = image.height;
    _lastFrame = image;

    final now = DateTime.now();

    if (now.difference(_lastLumCheckAt) >= const Duration(seconds: 2)) {
      _lastLumCheckAt = now;
      _updateLuminosity(image);
    }

    if (_depthProviderReady &&
        _depthProvider != null &&
        _battery.midasEnabled &&
        now.isAfter(_midasPausedUntil) &&
        _midasInterval.inMilliseconds > 0 &&
        now.difference(_lastMidasAt) >= _midasInterval) {
      _lastMidasAt = now;
      _runMidas(image, now);
    }

    final inBurstMode = now.isBefore(_burstModeEndsAt);
    final currentDetectInterval = inBurstMode
        ? _effectiveBurstDetectInterval()
        : _detectInterval;

    if (now.difference(_lastDetectAt) < currentDetectInterval) return;
    if (_isDetecting) return;

    _isDetecting  = true;
    _lastDetectAt = now;
    final sw = Stopwatch()..start();

    try {
      final planeBytes = image.planes.map((p) => p.bytes).toList(growable: false);
      final raw = await _vision.yoloOnFrame(
        bytesList:      planeBytes,
        imageHeight:    image.height,
        imageWidth:     image.width,
        iouThreshold:   0.45,
        confThreshold:  0.35,
        classThreshold: 0.35,
      );

      if (!mounted) return;

      final dets   = _buildRawDets(raw, _imgW, _imgH);
      final tracks = _tracker.update(dets, _imgW, _imgH, now);

      final uiNow = DateTime.now();
      if (uiNow.difference(_lastUiAt) >= _minUiInterval) {
        _lastUiAt             = uiNow;
        _tracksNotifier.value = List.unmodifiable(tracks);
      }

      if (_latestMidasHazard != null) {
        final result = _fusion.evaluate(
          hazard: _latestMidasHazard!,
          yoloHazardConf: _getYoloHazardConf(),
          now: now,
        );
        if (result != null) _handleFusionResult(result, now);
      }

      final nightNow = _isDark;
      if (nightNow != _wasNightMode) {
        _wasNightMode = nightNow;
        _tts.say(nightNow ? S.get('night_mode_on') : S.get('night_mode_off'), SpeechPriority.info, pan: 0.0);
        
        try {
          if (_controller != null && _controller!.value.isInitialized) {
            final minO = await _controller!.getMinExposureOffset();
            final maxO = await _controller!.getMaxExposureOffset();
            final target = nightNow ? (maxO * 0.4) : 0.0;
            final safeTarget = target.clamp(minO, maxO);
            await _controller!.setExposureOffset(safeTarget);
          }
        } catch (e) {
          debugPrint('Ошибка изменения экспозиции: $e');
        }
      }

      final signTrack = _alertMgr.processFrame(
        tracks:      tracks,
        imgW:        _imgW,
        imgH:        _imgH,
        now:         now,
        mode:        _mode,
        isCalibrated: _isCalibrated,
        frameCount:  _frameCount,
      );
      _maybeAutoOcr(signTrack, now);
    } catch (e) {
      _setStatus('Ошибка кадра: $e');
    } finally {
      sw.stop();
      _updatePerf(sw.elapsedMilliseconds.toDouble(), now);
      _isDetecting = false;
    }
  }

  List<RawDet> _buildRawDets(
      List<Map<String, dynamic>> raw, int imgW, int imgH) {
    final frameArea = imgW * imgH;
    final out = <RawDet>[];

    for (final r in raw) {
      final label = (r['tag'] ?? '').toString();
      if (label.isEmpty) continue;

      if (_mode == AppMode.street && !_streetObjects.contains(label)) continue;

      final box = r['box'] as List<dynamic>?;
      if (box == null || box.length < 4) continue;

      final conf = _toDouble(box.length > 4 ? box[4] : null) ??
          _toDouble(r['confidence']) ?? 0.0;
      if (conf < kDetConfThreshold) continue;

      double x1 = _toDouble(box[0]) ?? 0;
      double y1 = _toDouble(box[1]) ?? 0;
      double x2 = _toDouble(box[2]) ?? 0;
      double y2 = _toDouble(box[3]) ?? 0;

      if (x1 <= 1 && x2 <= 1 && y1 <= 1 && y2 <= 1) {
        x1 *= imgW; x2 *= imgW; y1 *= imgH; y2 *= imgH;
      }

      x1 = x1.clamp(0.0, imgW.toDouble());
      x2 = x2.clamp(0.0, imgW.toDouble());
      y1 = y1.clamp(0.0, imgH.toDouble());
      y2 = y2.clamp(0.0, imgH.toDouble());

      if (x2 <= x1 || y2 <= y1) continue;

      final bw = x2 - x1, bh = y2 - y1;
      if (frameArea > 0 && (bw * bh) / frameArea < kMinBboxAreaRatio) continue;

      final cx          = (x1 + x2) / 2;
      final cy          = (y1 + y2) / 2;
      final areaRatio   = frameArea > 0 ? (bw * bh) / frameArea : 0.0;
      final heightRatio = imgH > 0 ? bh / imgH : 0.0;
      final bottomRatio = imgH > 0 ? y2 / imgH : 0.0;

      final distFallback = distByBox(areaRatio, heightRatio, bottomRatio);
      final distM        = focalDistM(label, x1, y1, x2, y2);
      final dist         = distMToCategory(distM, distFallback);

      out.add(RawDet(
        label: label, x1: x1, y1: y1, x2: x2, y2: y2,
        cx: cx, cy: cy, conf: conf, dist: dist, distM: distM,
      ));
    }
    return out;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int)    return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _runMidas(CameraImage image, DateTime now) async {
    final hazards = await _depthProvider!.analyze(image);
    if (!mounted || hazards.isEmpty) {
      _latestMidasHazard = null;
      return;
    }

    _latestMidasHazard = hazards.first;

    if (_latestMidasHazard!.midasScore > 0.3) {
      _burstModeEndsAt = now.add(const Duration(milliseconds: 500));
    }
  }

  double _getYoloHazardConf() {
    return 0.0;
  }

  void _handleFusionResult(FusionResult result, DateTime now) {
    final h   = result.hazard;
    final pan = h.pan;
    final lbl = _hazardLabel(h.type);
    final dir = _zoneDir(h.zone);

    if (result.level == AlertLevel.critical) {
      if (now.difference(_alertMgr.lastCriticalAt) >= kCriticalCooldown) {
        _alertMgr.updateLastCriticalAt(now);
        _tts.say(
          '${S.get('stop')}! $lbl $dir.',
          SpeechPriority.critical,
          pan: pan,
        );
        _vibrate([0, 250, 80, 450]);
      }
    } else {
      _tts.say(
        '${S.get('hazard_warning')} $lbl $dir.',
        SpeechPriority.warning,
        pan: pan,
      );
      _vibrate([0, 120]);
    }
  }

  String _hazardLabel(DepthHazardType type) {
    switch (type) {
      case DepthHazardType.stepDown: return S.get('hazard_step_down');
      case DepthHazardType.pothole:  return S.get('hazard_pothole');
      case DepthHazardType.unknown:  return S.get('hazard_unknown');
    }
  }

  String _zoneDir(HazardZone zone) {
    switch (zone) {
      case HazardZone.left:        return S.get('left');
      case HazardZone.centerLeft:  return S.get('nav_slight_left');
      case HazardZone.center:      return S.get('forward_loc');
      case HazardZone.centerRight: return S.get('nav_slight_right');
      case HazardZone.right:       return S.get('right');
    }
  }

  void _maybeAutoOcr(Track? signTrack, DateTime now) {
    if (_ocrBusy || signTrack == null) return;
    if (_lastFrame == null) return;
    if (now.difference(_lastAutoOcrAt) < _autoOcrInterval) return;

    _lastAutoOcrAt = now;
    final frame    = _lastFrame!;
    _ocrBusy       = true;
    _ocr.recognizeFromFrame(frame, stabilize: true).then((text) {
      _ocrBusy = false;
      if (text == null || text.isEmpty) return;
      if (text == _lastOcrText) return;
      _lastOcrText = text;
      if (mounted) {
        _tts.say('${S.get('sign')}: $text', SpeechPriority.info, pan: 0.0);
      }
    }).catchError((_) { _ocrBusy = false; });
  }

  Future<void> _readText() async {
    if (_ocrBusy) return;

    final now = DateTime.now();
    if (now.difference(_lastOcrAt) < const Duration(seconds: 3)) return;
    _lastOcrAt = now;

    final frame = _lastFrame;
    if (frame == null) {
      _tts.say(S.get('ocr_camera_not_ready'), SpeechPriority.info, pan: 0.0);
      return;
    }

    _ocrBusy = true;
    _tts.say(S.get('ocr_reading'), SpeechPriority.info, pan: 0.0);

    try {
      final text = await _ocr.recognizeFromFrame(frame, stabilize: false);
      if (!mounted) return;

      if (text == null || text.isEmpty) {
        _earcon.play(Earcon.fail);
        _tts.say(S.get('ocr_not_found'), SpeechPriority.info, pan: 0.0);
      } else {
        _lastOcrText = text;
        _earcon.play(Earcon.success);
        _tts.say(text, SpeechPriority.warning, pan: 0.0);
      }
    } finally {
      _ocrBusy = false;
    }
  }

  Future<void> _vibrate(List<int> pattern) async {
    final now = DateTime.now();
    if (now.difference(_lastVibrateAt) < kVibrateCooldown) return;
    _lastVibrateAt = now;
    try {
      if (!await Vibration.hasVibrator()) return;
      final hasAmp = await Vibration.hasAmplitudeControl();
      if (hasAmp && pattern.length >= 4) {
        Vibration.vibrate(pattern: pattern,
            intensities: const [0, 255, 0, 200]);
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    } catch (_) {}
  }

  void _scanAround({String? sector}) {
    final tracks = _tracksNotifier.value;

    if (tracks.isEmpty) {
      _tts.say(S.get('nothing_seen'), SpeechPriority.warning, pan: 0.0);
      _lastScanDescription = '';
      _scanRepeatCount     = 0;
      return;
    }

    final filtered = sector == null
        ? tracks
        : tracks
            .where((t) => posFromCx(t.cx, _imgW.toDouble()) == sector)
            .toList();

    if (filtered.isEmpty) {
      final where = sector == 'left'
          ? S.get('left')
          : sector == 'right'
              ? S.get('right')
              : S.get('forward_loc');
      _tts.say('${S.get('nothing_here')} $where.',
          SpeechPriority.warning, pan: 0.0);
      return;
    }

    String buildGroup(List<Track> list, String prefix) {
      if (list.isEmpty) return '';
      final counts = <String, int>{};
      for (final t in list) {
        counts[t.label] = (counts[t.label] ?? 0) + 1;
      }
      final items =
          counts.entries.map((e) => '${e.value} ${S.label(e.key)}').join(', ');
      return '$prefix $items. ';
    }

    String desc = '';
    if (sector == null) {
      final lefts =
          filtered.where((t) => posFromCx(t.cx, _imgW.toDouble()) == 'left').toList();
      final centers =
          filtered.where((t) => posFromCx(t.cx, _imgW.toDouble()) == 'center').toList();
      final rights =
          filtered.where((t) => posFromCx(t.cx, _imgW.toDouble()) == 'right').toList();
      desc += buildGroup(lefts,   S.get('scan_left'));
      desc += buildGroup(centers, S.get('scan_forward'));
      desc += buildGroup(rights,  S.get('scan_right'));
    } else {
      desc = buildGroup(filtered, S.get('scan_see'));
    }

    Track? closest;
    for (final t in filtered) {
      if (t.distM > 0 && (closest == null || t.distM < closest.distM)) {
        closest = t;
      }
    }
    if (closest != null && closest.distM > 0) {
      desc +=
          '${S.get('closest')} ${closest.distM.toStringAsFixed(1)} ${S.get('meters')}.';
    }

    final trimmed = desc.trim();

    if (sector == null && trimmed == _lastScanDescription) {
      _scanRepeatCount++;
      if (_scanRepeatCount >= 2) {
        _scanRepeatCount = 0;
        _tts.say(S.get('no_change'), SpeechPriority.info, pan: 0.0);
      }
      return;
    }

    _lastScanDescription = trimmed;
    _scanRepeatCount     = 0;
    _tts.say(trimmed, SpeechPriority.warning, pan: 0.0);
  }

  void _updateLuminosity(CameraImage image) {
    try {
      final plane     = image.planes[0];
      final yBytes    = plane.bytes;
      final w         = image.width;
      final h         = image.height;
      final rowStride = plane.bytesPerRow;
      final step      = (w / 32).floor().clamp(1, w);
      final rowStep   = (h / 32).floor().clamp(1, h);
      int sum = 0, count = 0;
      for (int row = 0; row < 32 && row * rowStep < h; row++) {
        final rowOff = row * rowStep * rowStride;
        for (int col = 0; col < 32 && col * step < w; col++) {
          sum += yBytes[rowOff + col * step];
          count++;
        }
      }
      if (count > 0) _isDark = (sum / count) < 60;
    } catch (_) {
      final hour = DateTime.now().hour;
      _isDark = hour < 7 || hour >= 19;
    }
  }

  void _updatePerf(double ms, DateTime now) {
    _avgInfMs = _avgInfMs == 0 ? ms : (_avgInfMs * 0.85 + ms * 0.15);

    _detectInterval  = _effectiveDetectInterval();
    _midasInterval   = _effectiveMidasInterval();
    _minUiInterval   = _effectiveUiInterval();
    _autoOcrInterval = _effectiveAutoOcrInterval();

    if (_avgInfMs > 240) {
      _midasPausedUntil = now.add(const Duration(seconds: 4));
    } else if (_avgInfMs > 180) {
      _midasPausedUntil = now.add(const Duration(seconds: 2));
    } else if (_avgInfMs < 110 && now.isAfter(_midasPausedUntil)) {
      _midasPausedUntil = DateTime.fromMillisecondsSinceEpoch(0);
    }

    _frameCount++;
    final fpsNow = DateTime.now();
    final diffMs = fpsNow.difference(_lastFpsTick).inMilliseconds;
    if (diffMs >= 1000) {
      _detectFps   = _frameCount * 1000 / diffMs;
      _frameCount  = 0;
      _lastFpsTick = fpsNow;
    }
  }

  Duration _effectiveDetectInterval() {
    final perfMs = _avgInfMs > 240
        ? 320
        : _avgInfMs > 180
            ? 240
            : _avgInfMs > 130
                ? 180
                : _avgInfMs < 90
                    ? 120
                    : 140;
    return Duration(milliseconds: math.max(_battery.detectIntervalMs, perfMs));
  }

  Duration _effectiveBurstDetectInterval() {
    if (_battery.level == ThrottleLevel.aggressive) {
      return Duration(milliseconds: _battery.detectIntervalMs);
    }

    final burstMs = _avgInfMs > 240
        ? (_battery.level == ThrottleLevel.moderate ? 160 : 120)
        : _avgInfMs > 180
            ? (_battery.level == ThrottleLevel.moderate ? 120 : 90)
            : (_battery.level == ThrottleLevel.moderate ? 100 : 50);

    return Duration(milliseconds: math.min(_battery.detectIntervalMs, burstMs));
  }

  Duration _effectiveMidasInterval() {
    final baseMs = _battery.midasIntervalMs;
    if (baseMs <= 0) return Duration.zero;

    final loadMultiplier = _avgInfMs > 240
        ? 5
        : _avgInfMs > 180
            ? 4
            : _avgInfMs > 130
                ? 2
                : 1;
    final effectiveMs = math.max(baseMs * loadMultiplier, baseMs);
    return Duration(milliseconds: effectiveMs);
  }

  Duration _effectiveAutoOcrInterval() {
    if (_avgInfMs > 240) return const Duration(seconds: 15);
    if (_avgInfMs > 180) return const Duration(seconds: 12);
    if (_avgInfMs > 130) return const Duration(seconds: 10);
    return const Duration(seconds: 8);
  }

  Duration _effectiveUiInterval() {
    if (_avgInfMs > 240) return const Duration(milliseconds: 240);
    if (_avgInfMs > 180) return const Duration(milliseconds: 200);
    if (_avgInfMs > 130) return const Duration(milliseconds: 160);
    return const Duration(milliseconds: 120);
  }

  String _ruLabel(String label) => S.label(label);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _safeStop(ctrl);
    } else if (state == AppLifecycleState.resumed) {
      _safeStart(ctrl);
    }
  }

  Future<void> _safeStop(CameraController ctrl) async {
    try {
      if (ctrl.value.isStreamingImages) await ctrl.stopImageStream();
    } catch (_) {}
  }

  Future<void> _safeStart(CameraController ctrl) async {
    try {
      if (!ctrl.value.isStreamingImages && ctrl.value.isInitialized) {
        await ctrl.startImageStream(_onFrame);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tracksNotifier.dispose();
    _tts.stop();
    _earcon.dispose();
    _ocr.dispose();
    _depthProvider?.dispose();
    _fusion.reset();
    _voice.dispose();
    _battery.dispose();
    _waypoints.dispose();
    VisionForegroundService.stop();

    final ctrl = _controller;
    _controller = null;

    Future<void> cleanup() async {
      try {
        if (ctrl?.value.isStreamingImages ?? false) {
          await ctrl!.stopImageStream();
        }
      } catch (_) {}
      try { await ctrl?.dispose(); } catch (_) {}
      try { await _vision.closeYoloModel(); } catch (_) {}
    }
    cleanup();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl  = _controller;
    final ready = _isCameraReady && ctrl != null && ctrl.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Semantics(
          label: 'VisionGuide AI — режим ${_mode.label}',
          child: const Text(
            'VisionGuide AI',
            style: TextStyle(color: Colors.white),
          ),
        ),
        actions: [
          Semantics(
            label:  'Переключить режим (сейчас: ${_mode.label})',
            button: true,
            child: IconButton(
              tooltip:   'Режим: ${_mode.label}',
              icon:      Icon(_mode.icon, color: Colors.white),
              onPressed: _cycleMode,
            ),
          ),
          Semantics(
            label:  'Прочитать текст в кадре',
            button: true,
            child: IconButton(
              tooltip:   'Прочитать текст',
              icon:      const Icon(Icons.text_fields, color: Colors.white),
              onPressed: _readText,
            ),
          ),
          Semantics(
            label:  'Что вижу вокруг',
            button: true,
            child: IconButton(
              tooltip:   'Что вокруг?',
              icon:      const Icon(Icons.hearing, color: Colors.white),
              onPressed: _scanAround,
            ),
          ),
          Semantics(
            label:  'Настройки',
            button: true,
            child: IconButton(
              tooltip:   'Настройки',
              icon:      const Icon(Icons.tune, color: Colors.white),
              onPressed: _showSettings,
            ),
          ),
        ],
      ),
      body: !ready
          ? Center(
              child: Text(
                _statusLine,
                style: const TextStyle(color: Colors.white),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(child: CameraPreview(ctrl)),
                Positioned.fill(
                  child: ValueListenableBuilder<List<Track>>(
                    valueListenable: _tracksNotifier,
                    builder: (_, tracks, __) => CustomPaint(
                      painter: TrackPainter(
                        tracks:      tracks,
                        imgW:        _imgW,
                        imgH:        _imgH,
                        previewSize: ctrl.value.previewSize,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Semantics(
                    label: S.get('voice_hint'),
                    child: GestureDetector(
                      behavior:         HitTestBehavior.translucent,
                      onTapDown:        (_) => _handleScreenTap(),
                      onLongPressStart: (_) => _startVoiceListening(),
                      onLongPressEnd:   (_) => _stopVoiceListening(),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (_showDebugHud)
                  Positioned(
                    top: 16, left: 16,
                    child: DebugHud(
                      fps:         _detectFps,
                      inferenceMs: _avgInfMs,
                      intervalMs:  _detectInterval.inMilliseconds.toDouble(),
                      useGpu:      _useGpu,
                      threads:     _numThreads,
                      mode:        _mode,
                      depthTier:   _depthProvider?.tier,
                    ),
                  ),
                if (_depthProviderReady)
                  Positioned(
                    top: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _depthTierLabel(),
                        style: const TextStyle(
                          color:     Colors.cyanAccent,
                          fontSize:  10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                if (_voiceListening)
                  Positioned(
                    bottom: 130, left: 0, right: 0,
                    child: Center(
                      child: Semantics(
                        label: S.get('voice_listening'),
                        child: Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color:  Colors.red.withValues(alpha: 0.88),
                            shape:  BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                              Icons.mic, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SafeArea(
                    child: StatusPanel(
                      statusLine:     _statusLine,
                      tracksNotifier: _tracksNotifier,
                      imgW:           _imgW,
                      imgH:           _imgH,
                      ruLabel:        _ruLabel,
                      mode:           _mode,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _cycleMode() {
    setState(() {
      _mode = _mode.next;
      _resetModeState();
    });
    _tts.say('${S.get('mode_changed')}: ${_mode.label}.',
        SpeechPriority.warning, pan: 0.0);
  }

  void _setMode(AppMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _resetModeState();
    });
    _earcon.play(_earconForMode(mode));
    _tts.say('${S.get('mode_changed')}: ${_mode.label}.',
        SpeechPriority.warning, pan: 0.0);
  }

  void _resetModeState() {
    _tracker.clear();
    _fusion.reset();
    _alertMgr.reset();
    _lastScanDescription = '';
    _scanRepeatCount     = 0;
  }

  String _depthTierLabel() {
    final p = _depthProvider;
    if (p == null) return 'DEPTH';
    switch (p.tier) {
      case DepthTier.hardware:   return 'DEPTH·HW';
      case DepthTier.midasNnapi: return 'DEPTH·NPU';
      case DepthTier.midasCpu:   return 'DEPTH·CPU';
      case DepthTier.focalLength: return 'DEPTH';
    }
  }

  Earcon _earconForMode(AppMode mode) {
    switch (mode) {
      case AppMode.street: return Earcon.modeStreet;
      case AppMode.cane:   return Earcon.modeCane;
      case AppMode.scan:   return Earcon.modeScan;
    }
  }

  void _handleScreenTap() {
    final now = DateTime.now();
    if (now.difference(_lastTapAt) > const Duration(milliseconds: 500)) {
      _tapCount = 0;
    }
    _tapCount++;
    _lastTapAt = now;

    if (_tapCount == 3) {
      _tapCount = 0;
      _vibrate([0, 50, 50, 50, 50, 50]);
      _sos.sendSos().then((res) {
        if (mounted) {
          switch (res) {
            case SosResult.sent:
              _tts.say(S.get('sos_sent'), SpeechPriority.critical, pan: 0.0);
            case SosResult.noContact:
              _tts.say(S.get('sos_no_contact'), SpeechPriority.warning, pan: 0.0);
            case SosResult.noLocation:
              _tts.say(S.get('sos_no_location'), SpeechPriority.warning, pan: 0.0);
            case SosResult.launchFailed:
              _tts.say(S.get('sos_launch_failed'), SpeechPriority.warning, pan: 0.0);
            case SosResult.error:
              _tts.say(S.get('sos_no_location'), SpeechPriority.warning, pan: 0.0);
          }
        }
      });
    }
  }

  Future<void> _startVoiceListening() async {
    if (!_voiceAvailable) {
      _tts.say(S.get('voice_not_available'), SpeechPriority.info, pan: 0.0);
      return;
    }
    await _tts.stop();
    final started = await _voice.startListening();
    if (!started && mounted) {
      _tts.say(S.get('voice_no_permission'), SpeechPriority.info, pan: 0.0);
    }
  }

  Future<void> _stopVoiceListening() async {
    await _voice.stopListening();
  }

  void _onVoiceCommand(VoiceCommand cmd) {
    switch (cmd) {
      case VoiceCommand.scanAll:
        _scanAround();
      case VoiceCommand.scanLeft:
        _scanAround(sector: 'left');
      case VoiceCommand.scanRight:
        _scanAround(sector: 'right');
      case VoiceCommand.scanForward:
        _scanAround(sector: 'center');
      case VoiceCommand.readText:
        _readText();
      case VoiceCommand.toggleMode:
        _cycleMode();
      case VoiceCommand.saveWaypoint:
        final name = '${S.get('lbl_object')} ${_waypoints.waypoints.length + 1}';
        _waypoints.saveCurrentLocation(name).then((wp) {
          if (wp != null) {
            _tts.say(S.get('waypoint_saved'), SpeechPriority.info, pan: 0.0);
            _vibrate([0, 100]);
          }
        });
      case VoiceCommand.modeStreet:
        _setMode(AppMode.street);
      case VoiceCommand.modeCane:
        _setMode(AppMode.cane);
      case VoiceCommand.modeScan:
        _setMode(AppMode.scan);
      case VoiceCommand.unknown:
        _earcon.play(Earcon.fail);
        _tts.say(S.get('voice_unknown'), SpeechPriority.info, pan: 0.0);
    }
  }

  void _showCalibrationDialog() {
    final tracks = _tracksNotifier.value;
    final person = tracks.where((t) => t.label == 'person').toList();
    if (person.isEmpty) {
      _tts.say(S.get('calib_aim'), SpeechPriority.warning, pan: 0.0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Нет человека в кадре. Наведите камеру и попробуйте снова.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final target = person.reduce((a, b) {
      final aDist = ((a.cx / _imgW) - 0.5).abs();
      final bDist = ((b.cx / _imgW) - 0.5).abs();
      return aDist <= bDist ? a : b;
    });

    showDialog<String>(
      context: context,
      builder: (_) => const CameraCalibrationDialog(),
    ).then((raw) async {
      if (raw == null) return;

      final dist = double.tryParse(raw.replaceAll(',', '.'));
      if (dist == null || dist <= 0 || dist > 50) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Введите корректное расстояние (0–50 м)'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await calibrateFocalLength(
        target.label,
        target.x1, target.y1,
        target.x2, target.y2,
        dist,
      );
      setState(() => _isCalibrated = true);
      await Settings.instance.setIsCalibrated(true);
      _earcon.play(Earcon.success);
      _tts.say(S.get('calib_saved'), SpeechPriority.warning, pan: 0.0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.get('calib_saved')),
            backgroundColor: Colors.green,
          ),
        );
      }
    });
  }

  void _showWaypointSheet() {
    showModalBottomSheet<void>(
      context:         context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => WaypointSheet(
        waypointService: _waypoints,
        onDeleted: (name) {
          _tts.say(S.get('waypoint_deleted'), SpeechPriority.info, pan: 0.0);
        },
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context:         context,
      showDragHandle:  true,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => CameraSettingsSheet(
        currentLanguage: AppStrings.current,
        useGpu: _useGpu,
        numThreads: _numThreads,
        showDebugHud: _showDebugHud,
        earconEnabled: _earcon.isEnabled,
        midasReady: _depthProviderReady,
        sosContactNumber: _sos.contactNumber,
        onLanguageChanged: (lang) async {
          AppStrings.setLanguage(lang);
          await Settings.instance.setLanguage(lang.index);
          await _tts.setLanguage(AppStrings.ttsLang);
          _voice.setLocale(AppStrings.ttsLang);
          if (mounted) {
            setState(() {});
            _tts.say(S.get('mode_changed'), SpeechPriority.info, pan: 0.0);
          }
        },
        onUseGpuChanged: (v) async {
          setState(() => _useGpu = v);
          await Settings.instance.setUseGpu(v);
          await _loadModel();
        },
        onNumThreadsChanged: (v) async {
          setState(() => _numThreads = v);
          await Settings.instance.setNumThreads(v);
          await _loadModel();
        },
        onDebugHudChanged: (v) {
          setState(() => _showDebugHud = v);
        },
        onEarconEnabledChanged: (v) {
          _earcon.setEnabled(v);
        },
        onReadText: _readText,
        onCalibrationTap: _showCalibrationDialog,
        onEditSosContact: () async {
          final ctrl = TextEditingController(text: _sos.contactNumber);
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(S.get('sos_settings')),
              content: TextField(
                controller: ctrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: '+7(123)456-78-90',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(S.get('cancel')),
                ),
                TextButton(
                  onPressed: () async {
                    final nav   = Navigator.of(c);
                    final saved = await _sos.setContact(ctrl.text);
                    if (!mounted) return;
                    nav.pop();
                    if (saved) {
                      setState(() {});
                    } else {
                      _tts.say(S.get('sos_invalid_number'),
                          SpeechPriority.info, pan: 0.0);
                    }
                  },
                  child: Text(S.get('save')),
                ),
              ],
            ),
          );
        },
        onScanLeft: () => _scanAround(sector: 'left'),
        onScanCenter: () => _scanAround(sector: 'center'),
        onScanRight: () => _scanAround(sector: 'right'),
        onVoiceWarningTest: () {
          _tts.say('${S.label('person')} ${S.get('close')}.',
              SpeechPriority.warning,
              pan: -1.0);
        },
        onVoiceCriticalTest: () {
          _tts.say('${S.get('stop')}. ${S.get('ocr_not_found')}',
              SpeechPriority.critical,
              pan: 0.0);
          _vibrate([0, 250, 80, 450]);
        },
        onPlayEarcon: (earcon) => _earcon.play(earcon),
        patternFn: _alertMgr.patternFor,
        intensFn: _alertMgr.intensitiesFor,
        vibrateFn: _alertMgr.vibrateCane,
        onViewWaypoints: _showWaypointSheet,
      ),
    );
  }
}

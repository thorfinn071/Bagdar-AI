import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audio_session/audio_session.dart';

import '../../camera/frame_quality_guard.dart';
import '../../models/strings.dart';
import '../../models/tts_engine.dart';
import '../../safety/alerts/feedback_command.dart';
import '../../safety/alerts/haptic_policy.dart';
import '../../services/haptic_service.dart';
import '../../services/orientation_service.dart';
import '../../services/settings_service.dart';
import '../../services/thermal_monitor.dart';
import '../../services/tts_service.dart';
import '../../services/weather_gate.dart';
import 'onboarding_state.dart';
import 'alignment_probe.dart';
import 'onboarding_speech.dart';

import 'onboarding_gateway.dart';

class NativeOnboardingGateway implements OnboardingGateway {
  final TtsService _tts = TtsService.instance;
  final HapticPolicy _haptics = HapticPolicy();
  AudioSession? _audioSession;
  CameraController? _camera;
  StreamSubscription<AccelerometerEvent>? _sensor;
  int _generation = 0;

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  bool _voiceUnavailable(AppLanguage language) =>
      !_tts.languageAvailable ||
      _tts.usingEnglishFallback ||
      (language == AppLanguage.kk &&
          _tts.activeKkEngine == KkTtsEngine.russianFallback);

  @override
  Future<OnboardingSpeechResult> speak(
    String text,
    AppLanguage language, {
    bool critical = false,
  }) async {
    final generation = _generation;
    StreamSubscription<AudioInterruptionEvent>? interruption;
    StreamSubscription<void>? noisy;
    var interrupted = false;
    try {
      final session = await AudioSession.instance;
      _audioSession = session;
      interruption = session.interruptionEventStream.listen((event) {
        if (event.begin) interrupted = true;
      });
      noisy = session.becomingNoisyEventStream.listen((_) {
        interrupted = true;
      });
      await _tts.init().timeout(const Duration(seconds: 6));
      if (generation != _generation || interrupted) {
        return OnboardingSpeechResult.interrupted;
      }
      if (!_tts.isReady) return OnboardingSpeechResult.engineUnavailable;
      await _tts
          .setLanguage(switch (language) {
            AppLanguage.ru => 'ru-RU',
            AppLanguage.kk => 'kk-KZ',
            AppLanguage.en => 'en-US',
          })
          .timeout(const Duration(seconds: 6));
      if (generation != _generation || interrupted) {
        return OnboardingSpeechResult.interrupted;
      }
      if (!_tts.isReady) return OnboardingSpeechResult.engineUnavailable;
      if (_voiceUnavailable(language)) {
        return OnboardingSpeechResult.voiceUnavailable;
      }
      AppStrings.setLanguage(language);
      final errors = _tts.playbackErrors;
      final stalls = _tts.playbackStalls;
      if (critical) {
        if (!_tts.submitFeedbackCommand(
          trainingStopCommand(DateTime.now()),
          localizedText: text,
        )) {
          return OnboardingSpeechResult.failed;
        }
        await _tts.awaitIdle().timeout(const Duration(seconds: 15));
      } else {
        for (final segment in onboardingSpeechSegments(text)) {
          if (generation != _generation || interrupted) {
            return OnboardingSpeechResult.interrupted;
          }
          _tts.sayInstruction(segment);
          await _tts.awaitIdle().timeout(const Duration(seconds: 35));
          if (generation != _generation || interrupted) {
            return OnboardingSpeechResult.interrupted;
          }
          if (!_tts.isReady) return OnboardingSpeechResult.engineUnavailable;
          if (_voiceUnavailable(language)) {
            return OnboardingSpeechResult.voiceUnavailable;
          }
          if (_tts.playbackStalls != stalls) {
            return OnboardingSpeechResult.timedOut;
          }
          if (_tts.playbackErrors != errors) {
            return OnboardingSpeechResult.failed;
          }
        }
      }
      if (generation != _generation || interrupted) {
        return OnboardingSpeechResult.interrupted;
      }
      if (_tts.playbackStalls != stalls) return OnboardingSpeechResult.timedOut;
      if (_tts.playbackErrors != errors) return OnboardingSpeechResult.failed;
      if (_voiceUnavailable(language)) {
        return OnboardingSpeechResult.voiceUnavailable;
      }
      return _tts.isReady
          ? OnboardingSpeechResult.played
          : OnboardingSpeechResult.engineUnavailable;
    } on TimeoutException {
      if (generation == _generation) await _tts.stop();
      return OnboardingSpeechResult.timedOut;
    } catch (_) {
      if (generation == _generation) await _tts.stop();
      return OnboardingSpeechResult.failed;
    } finally {
      await interruption?.cancel();
      await noisy?.cancel();
      if (generation == _generation) {
        try {
          await _audioSession?.setActive(false);
        } catch (_) {
          /* optional audio focus */
        }
      }
    }
  }

  @override
  Future<bool> openSpeechSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await const MethodChannel(
            'bagdar/onboarding',
          ).invokeMethod<bool>('openSpeechSettings') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> speechRate(double rate) async {
    await _tts.setUserRate(rate);
    if (Settings.instance.isReady) await Settings.instance.setSpeechRate(rate);
  }

  @override
  Future<bool> stopHaptic() async {
    try {
      final device = await HapticService.safetyCapabilities();
      final decision = _haptics.decide(
        FeedbackHapticPattern.immediateStop,
        now: DateTime.now(),
        device: device,
      );
      return decision.cue != null &&
          await HapticService.emitSafetyCue(decision.cue!);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<CameraAccess> cameraPermission({bool request = false}) async {
    if (!_mobile) return CameraAccess.restricted;
    try {
      final status = request
          ? await Permission.camera.request()
          : await Permission.camera.status;
      if (status.isGranted) return CameraAccess.granted;
      if (status.isPermanentlyDenied) return CameraAccess.permanentlyDenied;
      if (status.isRestricted) return CameraAccess.restricted;
      return CameraAccess.denied;
    } catch (_) {
      return CameraAccess.restricted;
    }
  }

  @override
  Future<DeviceProbe> checkCamera() async {
    final now = DateTime.now();
    ProbeResult camera = ProbeResult(
      ProbeStatus.unavailable,
      'cameraUnavailable',
      now,
    );
    ProbeResult thermal = ProbeResult(
      ProbeStatus.unavailable,
      'thermalUnavailable',
      now,
    );
    if (!_mobile || await cameraPermission() != CameraAccess.granted) {
      return DeviceProbe(camera, thermal);
    }
    final generation = _generation;
    final monitor = ThermalMonitor();
    CameraController? controller;
    try {
      await monitor.refresh().timeout(const Duration(seconds: 3));
      thermal = ProbeResult(
        monitor.current.isAvailable &&
                monitor.severity.index < ThermalSeverity.hot.index
            ? ProbeStatus.available
            : ProbeStatus.unavailable,
        monitor.current.isAvailable ? 'thermalHot' : 'thermalUnavailable',
        DateTime.now(),
      );
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 5),
      );
      if (generation != _generation || cameras.isEmpty) {
        return DeviceProbe(camera, thermal);
      }
      final rear = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (rear.isEmpty) return DeviceProbe(camera, thermal);
      controller = CameraController(
        rear.first,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      _camera = controller;
      await controller.initialize().timeout(const Duration(seconds: 8));
      if (generation != _generation) return DeviceProbe(camera, thermal);
      final guard = FrameQualityGuard(weatherGate: WeatherGate());
      var frames = 0;
      var darkFrames = 0;
      DateTime? first;
      DateTime? last;
      var frozen = false;
      var obstructed = false;
      await controller
          .startImageStream((image) {
            if (generation != _generation || image.planes.isEmpty) return;
            final at = DateTime.now();
            first ??= at;
            last = at;
            frames++;
            final plane = image.planes.first;
            Uint8List bytes = plane.bytes;
            var stride = plane.bytesPerRow;
            if (image.format.group == ImageFormatGroup.bgra8888) {
              bytes = Uint8List(image.width * image.height);
              for (var y = 0; y < image.height; y++) {
                for (var x = 0; x < image.width; x++) {
                  final offset = y * stride + x * 4;
                  if (offset + 2 >= plane.bytes.length) return;
                  bytes[y * image.width + x] =
                      (plane.bytes[offset] +
                          plane.bytes[offset + 1] +
                          plane.bytes[offset + 2]) ~/
                      3;
                }
              }
              stride = image.width;
            } else if (image.format.group != ImageFormatGroup.yuv420) {
              // Unknown layouts are not interpretable evidence.
              frames = 0;
              return;
            }
            final report = guard.evaluate(
              yPlane: bytes,
              bytesPerRow: stride,
              width: image.width,
              height: image.height,
              now: at,
              indoorHint: true,
            );
            frozen = guard.cameraFrozenWarned;
            obstructed =
                guard.cameraBlockedWarned || guard.partialOcclusionWarned;
            final dark = report.events.any(
              (event) =>
                  event.type == FrameQualityEventType.cameraBlocked ||
                  event.type == FrameQualityEventType.cameraPartiallyBlocked,
            );
            if (dark) darkFrames++;
          })
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(seconds: 4));
      final end = DateTime.now();
      final fresh =
          generation == _generation &&
          frames >= 10 &&
          first != null &&
          last != null &&
          last!.difference(first!) >= const Duration(seconds: 2) &&
          end.difference(last!) < const Duration(milliseconds: 600);
      camera = ProbeResult(
        fresh && !frozen && !obstructed && darkFrames == 0
            ? ProbeStatus.available
            : ProbeStatus.unavailable,
        frozen
            ? 'cameraFrozen'
            : obstructed || darkFrames > 0
            ? 'cameraDark'
            : 'cameraUnavailable',
        end,
      );
    } catch (_) {
      camera = ProbeResult(
        ProbeStatus.unavailable,
        'cameraUnavailable',
        DateTime.now(),
      );
    } finally {
      monitor.dispose();
      if (identical(_camera, controller)) _camera = null;
      if (controller != null) {
        try {
          await controller.dispose();
        } catch (_) {
          /* already stopped */
        }
      }
    }
    return DeviceProbe(camera, thermal);
  }

  @override
  Future<ProbeResult> checkAlignment() async {
    if (!_mobile) {
      return ProbeResult(
        ProbeStatus.unavailable,
        'alignmentUnavailable',
        DateTime.now(),
      );
    }
    final generation = _generation;
    final probe = OnboardingAlignmentProbe();
    StreamSubscription<AccelerometerEvent>? sensor;
    try {
      sensor =
          accelerometerEventStream(
            samplingPeriod: const Duration(milliseconds: 100),
          ).listen(
            (event) {
              if (generation != _generation) return;
              final pitch = math.atan2(event.y.abs(), event.z) * 180 / math.pi;
              final roll = OrientationService.computeRoll(event.x, event.z);
              probe.observe(pitch: pitch, roll: roll, at: DateTime.now());
            },
            onError: (Object error) {
              probe.unavailable();
            },
          );
      _sensor = sensor;
      await Future<void>.delayed(const Duration(seconds: 3));
      final now = DateTime.now();
      return generation == _generation
          ? probe.result(now)
          : ProbeResult(ProbeStatus.unavailable, 'alignmentUnavailable', now);
    } catch (_) {
      return ProbeResult(
        ProbeStatus.unavailable,
        'alignmentUnavailable',
        DateTime.now(),
      );
    } finally {
      await sensor?.cancel();
      if (identical(_sensor, sensor)) _sensor = null;
    }
  }

  @override
  Future<bool> openSettings() async => _mobile ? openAppSettings() : false;

  @override
  Future<void> stop() async {
    final generation = ++_generation;
    final camera = _camera;
    _camera = null;
    final sensor = _sensor;
    _sensor = null;
    await sensor?.cancel();
    if (camera != null) {
      try {
        await camera.dispose();
      } catch (_) {
        /* cancelled probe */
      }
    }
    try {
      await _tts.stop();
    } catch (_) {
      /* optional output */
    }
    try {
      await HapticService.cancel();
    } catch (_) {
      /* optional output */
    }
    if (generation == _generation) {
      try {
        await _audioSession?.setActive(false);
      } catch (_) {
        /* optional audio focus */
      }
    }
  }
}

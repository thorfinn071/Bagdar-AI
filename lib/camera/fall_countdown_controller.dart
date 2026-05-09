import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/fall_detector.dart' show FallClass;
import '../services/haptic_service.dart';
import '../services/sos_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';

class FallCountdownController extends ChangeNotifier {
  final TtsService tts;
  final SosService sos;
  final VoiceCommandService voice;
  final VoidCallback? onCancelled;

  static const Duration kInitialDuration = Duration(seconds: 15);
  static const Duration kCollapseDuration = Duration(seconds: 30);

  static const Duration kVoiceConfirmWindow = Duration(seconds: 4);
  static const Duration kCorroborationWindow = Duration(seconds: 3);
  static const double kDeliberateTapThresholdMps2 = 14.7;
  static const Duration kDeliberateTapMaxDuration =
      Duration(milliseconds: 100);

  Timer? _timer;
  int _secondsLeft = 0;
  Duration _currentDuration = kInitialDuration;
  bool _active = false;
  bool _cancelListenerActive = false;
  bool _disposed = false;

  bool _voiceConfirmPending = false;
  Timer? _voiceConfirmTimeout;
  DateTime? _lastTouchAt;
  DateTime? _lastDeliberateTapAt;
  DateTime? _userAccelAboveStartedAt;
  StreamSubscription<UserAccelerometerEvent>? _userAccelSub;

  FallCountdownController({
    required this.tts,
    required this.sos,
    required this.voice,
    this.onCancelled,
  });

  int get secondsLeft => _secondsLeft;
  bool get active => _active;

  void start({FallClass fallClass = FallClass.tumble}) {
    if (_active) return;
    _active = true;
    _currentDuration = fallClass == FallClass.collapse
        ? kCollapseDuration
        : kInitialDuration;
    _secondsLeft = _currentDuration.inSeconds;

    final detectedKey = fallClass == FallClass.collapse
        ? 'sos_fall_classb_detected'
        : 'sos_fall_detected';
    tts.say(
      S.get(detectedKey),
      SpeechPriority.critical,
      pan: 0.0,
      barge: true,
    );
    tts.say(
      S.get('sos_fall_cancel_hint'),
      SpeechPriority.warning,
      pan: 0.0,
    );
    HapticService.vibrate([0, 300, 200, 300, 200, 300]);

    _startFallCancelListener();
    _startCorroborationSensor();

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) => _tick(t));
    notifyListeners();
  }

  void cancel() {
    if (!_active) return;
    _timer?.cancel();
    _active = false;
    _secondsLeft = 0;
    _stopFallCancelListener();
    _stopCorroborationSensor();
    _resetVoiceConfirm();
    tts.say(S.get('sos_fall_cancelled'), SpeechPriority.critical, pan: 0.0);
    HapticService.vibrate([0, 100]);
    onCancelled?.call();
    notifyListeners();
  }

  void notifyTouch() {
    _lastTouchAt = DateTime.now();
    if (_active) cancel();
  }

  void requestVoiceCancel() {
    if (!_active) return;
    final now = DateTime.now();
    if (!_voiceConfirmPending) {
      _voiceConfirmPending = true;
      tts.say(
        S.get('sos_fall_voice_confirm_prompt'),
        SpeechPriority.critical,
        pan: 0.0,
        barge: true,
      );
      _voiceConfirmTimeout?.cancel();
      _voiceConfirmTimeout = Timer(kVoiceConfirmWindow, () {
        _voiceConfirmTimeout = null;
        _voiceConfirmPending = false;
      });
      return;
    }
    final touchOk = _lastTouchAt != null &&
        now.difference(_lastTouchAt!) <= kCorroborationWindow;
    final tapOk = _lastDeliberateTapAt != null &&
        now.difference(_lastDeliberateTapAt!) <= kCorroborationWindow;
    if (!touchOk && !tapOk) {
      tts.say(
        S.get('sos_fall_voice_cancel_rejected'),
        SpeechPriority.critical,
        pan: 0.0,
        barge: true,
      );
      _resetVoiceConfirm();
      return;
    }
    _resetVoiceConfirm();
    cancel();
  }

  void _resetVoiceConfirm() {
    _voiceConfirmPending = false;
    _voiceConfirmTimeout?.cancel();
    _voiceConfirmTimeout = null;
  }

  void _tick(Timer t) {
    _secondsLeft--;
    if (_secondsLeft <= 0) {
      t.cancel();
      _active = false;
      _stopFallCancelListener();
      _stopCorroborationSensor();
      _resetVoiceConfirm();
      notifyListeners();
      unawaited(_sendFallSos());
      return;
    }
    if (_secondsLeft == 10 ||
        _secondsLeft == 5 ||
        _secondsLeft <= 3) {
      tts.say(
        '${S.get('sos_fall_countdown')} $_secondsLeft ${S.get('sos_fall_seconds')}',
        SpeechPriority.warning,
        pan: 0.0,
      );
      if (_secondsLeft == 10 || _secondsLeft == 5) {
        _restartFallCancelListener();
      }
      if (_secondsLeft == 5) {
        HapticService.vibrate([0, 400, 100, 400, 100, 400]);
      }
    }
    notifyListeners();
  }

  Future<void> _sendFallSos() async {
    final hasContact = (sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
    }
    tts.say(S.get('sos_sending'), SpeechPriority.critical, pan: 0.0);
    final result = await sos.sendSos();
    if (_disposed) return;
    final msg = switch (result) {
      SosResult.sent => S.get('sos_fall_sent'),
      SosResult.sentFallback =>
        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',
      SosResult.noLocation => S.get('sos_sent_no_location'),
      SosResult.launchFailed => S.get('sos_launch_failed'),
      SosResult.noContact => S.get('sos_no_contact'),
      SosResult.error => S.get('sos_error'),
    };
    tts.say(msg, SpeechPriority.critical, pan: 0.0);
  }

  void _startFallCancelListener() {
    if (_cancelListenerActive) return;
    _cancelListenerActive = true;
    unawaited(
      voice.startContinuousListening(
        sessionDuration: _currentDuration,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  void _restartFallCancelListener() {
    if (!_cancelListenerActive) return;
    if (voice.isListening) return;
    unawaited(
      voice.startContinuousListening(
        sessionDuration: Duration(seconds: _secondsLeft + 1),
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      ),
    );
  }

  void _stopFallCancelListener() {
    _cancelListenerActive = false;
    unawaited(voice.stopListening());
  }

  void _startCorroborationSensor() {
    _userAccelSub?.cancel();
    _userAccelAboveStartedAt = null;
    _lastDeliberateTapAt = null;
    try {
      _userAccelSub = userAccelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen(_onUserAccel, onError: (_) {});
    } catch (_) {
      _userAccelSub = null;
    }
  }

  void _stopCorroborationSensor() {
    _userAccelSub?.cancel();
    _userAccelSub = null;
    _userAccelAboveStartedAt = null;
  }

  void _onUserAccel(UserAccelerometerEvent e) {
    final mag = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    final now = DateTime.now();
    if (mag > kDeliberateTapThresholdMps2) {
      _userAccelAboveStartedAt ??= now;
      return;
    }
    final aboveStart = _userAccelAboveStartedAt;
    if (aboveStart == null) return;
    final duration = now.difference(aboveStart);
    _userAccelAboveStartedAt = null;
    if (duration <= kDeliberateTapMaxDuration) {
      _lastDeliberateTapAt = now;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _voiceConfirmTimeout?.cancel();
    _userAccelSub?.cancel();
    super.dispose();
  }
}

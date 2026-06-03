import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/fall_detector.dart' show FallClass, MotionState;
import '../services/field_logger.dart';
import '../services/haptic_service.dart';
import '../services/sos_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';

class FallCountdownController extends ChangeNotifier {
  final TtsService tts;
  final SosService sos;
  final VoiceCommandService voice;
  final VoidCallback? onCancelled;
  final VoidCallback? onSosSent;

  /// Optional probe for Winter Mode. When it returns true at the moment
  /// [start] is called, the countdown window is scaled by
  /// [WinterModeService.kCancelWindowScale] (= 0.7, 30 % shorter) per the
  /// Winter Mode spec. Two-phrase confirmation for voice cancel is already
  /// always mandatory (C1), so the only additional tightening is the timer.
  final bool Function()? winterModeProvider;

  /// Optional motion-state probe for the dazed-user SOS path (audit 4.2).
  /// When provided, the controller reads the current [MotionState] at the
  /// 5-second dazed check to decide whether to cancel (user moving) or
  /// escalate to early SOS (user stationary and unresponsive).
  final MotionState Function()? motionStateProvider;

  static const Duration kInitialDuration = Duration(seconds: 15);
  static const Duration kCollapseDuration = Duration(seconds: 30);
  static const double kWinterCancelWindowScale = 0.7;

  static const Duration kVoiceConfirmWindow = Duration(seconds: 4);
  static const Duration kCorroborationWindow = Duration(seconds: 3);
  
  
  static const double kDeliberateTapThresholdMps2 = 14.7;
  static const Duration kDeliberateTapMaxDuration =
      Duration(milliseconds: 100);

  
  final double Function()? deliberateTapThresholdProvider;

  Timer? _timer;
  int _secondsLeft = 0;
  Duration _currentDuration = kInitialDuration;
  bool _active = false;
  bool _cancelListenerActive = false;
  bool _disposed = false;

  bool _voiceConfirmPending = false;
  bool _dazedCheckPending = false;
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
    this.onSosSent,
    this.winterModeProvider,
    this.motionStateProvider,
    this.deliberateTapThresholdProvider,
  });

  int get secondsLeft => _secondsLeft;
  bool get active => _active;

  @visibleForTesting
  bool get dazedCheckPendingForTesting => _dazedCheckPending;

  /// Sets up the countdown state without starting the real [Timer] or any
  /// platform channels (voice listener, accel stream). Use in unit tests to
  /// drive [processTickForTesting] manually.
  @visibleForTesting
  void initForTesting({
    required int secondsLeft,
    Duration duration = kInitialDuration,
  }) {
    _active = true;
    _currentDuration = duration;
    _secondsLeft = secondsLeft;
  }

  void start({FallClass fallClass = FallClass.tumble}) {
    if (_active) return;
    _active = true;
    final baseDuration = fallClass == FallClass.collapse
        ? kCollapseDuration
        : kInitialDuration;
    final winterActive = winterModeProvider?.call() ?? false;
    _currentDuration = winterActive
        ? _scaleDuration(baseDuration, kWinterCancelWindowScale)
        : baseDuration;
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
    _dazedCheckPending = false;
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

  void _tick(Timer t) => _processTick();

  @visibleForTesting
  void processTickForTesting() => _processTick();

  void _processTick() {
    _secondsLeft--;
    if (_secondsLeft <= 0) {
      _timer?.cancel();
      _active = false;
      _dazedCheckPending = false;
      _stopFallCancelListener();
      _stopCorroborationSensor();
      _resetVoiceConfirm();
      notifyListeners();
      unawaited(_sendFallSos());
      return;
    }

    if (_secondsLeft == 12 && _currentDuration.inSeconds >= 13) {
      _triggerDazedCheck();
    }

    if (_dazedCheckPending && _secondsLeft == 7) {
      _evaluateDazedCheck();
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

  void _triggerDazedCheck() {
    _dazedCheckPending = true;
    HapticService.vibrate([0, 600, 200, 600, 200, 600]);
    tts.say(
      S.get('sos_fall_are_you_ok'),
      SpeechPriority.critical,
      pan: 0.0,
      barge: true,
    );
    _restartFallCancelListener();
  }

  void _evaluateDazedCheck() {
    if (!_dazedCheckPending) return;
    _dazedCheckPending = false;

    final motion = motionStateProvider?.call();
    if (motion != null && motion != MotionState.stationary) {
      FieldLogger.instance.log('fall_dazed_path', {
        'outcome': 'mobile_cancel',
        'secondsLeft': _secondsLeft,
      });
      cancel();
    } else {
      FieldLogger.instance.log('fall_dazed_path', {
        'outcome': 'stationary_early_sos',
        'secondsLeft': _secondsLeft,
      });
      _timer?.cancel();
      _active = false;
      _stopFallCancelListener();
      _stopCorroborationSensor();
      _resetVoiceConfirm();
      notifyListeners();
      unawaited(_sendFallSos());
    }
  }

  Future<void> _sendFallSos() async {
    final hasContact = (sos.contactNumber ?? '').isNotEmpty;
    if (!hasContact) {
      tts.say(S.get('sos_112_fallback'), SpeechPriority.critical, pan: 0.0);
    }
    tts.say(S.get('sos_sending'), SpeechPriority.critical, pan: 0.0);
    final result = await sos.sendSos();
    if (_disposed) return;
    
    
    final delivered = result == SosResult.sent ||
        result == SosResult.sentFallback ||
        result == SosResult.sentWithoutLocation;
    if (delivered) onSosSent?.call();
    final msg = switch (result) {
      SosResult.sent => S.get('sos_fall_sent'),
      SosResult.sentFallback =>
        '${S.get('sos_112_fallback')} ${S.get('sos_sent')}',
      SosResult.sentWithoutLocation => S.get('sos_sent_no_location'),
      SosResult.noLocation => S.get('sos_no_location'),
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
    
    
    voice.extendContinuousDeadline(Duration(seconds: _secondsLeft + 1));
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
    
    
    final threshold =
        deliberateTapThresholdProvider?.call() ?? kDeliberateTapThresholdMps2;
    if (mag > threshold) {
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

  /// Ceil-rounded second scaling so a 15 s window at 0.7 becomes 11 s
  /// (10.5 rounded up), not 10 s — the ceiling errs on the side of leaving
  /// the user slightly more time rather than slightly less.
  @visibleForTesting
  static Duration scaleDurationForTesting(Duration base, double scale) =>
      _scaleDuration(base, scale);

  static Duration _scaleDuration(Duration base, double scale) {
    final scaled = (base.inMilliseconds * scale).ceil();
    final seconds = (scaled / 1000).ceil();
    return Duration(seconds: seconds.clamp(1, 1 << 30));
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

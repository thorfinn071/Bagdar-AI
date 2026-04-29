import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/haptic_service.dart';
import '../services/sos_service.dart';
import '../services/tts_service.dart';
import '../services/voice_command_service.dart';

class FallCountdownController extends ChangeNotifier {
  final TtsService tts;
  final SosService sos;
  final VoiceCommandService voice;

  static const Duration kInitialDuration = Duration(seconds: 15);

  Timer? _timer;
  int _secondsLeft = 0;
  bool _active = false;
  bool _cancelListenerActive = false;
  bool _disposed = false;

  FallCountdownController({
    required this.tts,
    required this.sos,
    required this.voice,
  });

  int get secondsLeft => _secondsLeft;
  bool get active => _active;

  void start() {
    if (_active) return;
    _active = true;
    _secondsLeft = kInitialDuration.inSeconds;

    tts.say(
      S.get('sos_fall_detected'),
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
    tts.say(S.get('sos_fall_cancelled'), SpeechPriority.critical, pan: 0.0);
    HapticService.vibrate([0, 100]);
    notifyListeners();
  }

  void _tick(Timer t) {
    _secondsLeft--;
    if (_secondsLeft <= 0) {
      t.cancel();
      _active = false;
      _stopFallCancelListener();
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
    unawaited(voice.startListening());
  }

  void _restartFallCancelListener() {
    if (!_cancelListenerActive) return;
    unawaited(voice.startListening());
  }

  void _stopFallCancelListener() {
    _cancelListenerActive = false;
    unawaited(voice.stopListening());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

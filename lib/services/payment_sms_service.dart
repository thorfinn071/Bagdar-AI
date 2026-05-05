import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import 'earcon_service.dart';
import 'field_logger.dart';
import 'settings_service.dart';
import 'tts_service.dart';
import 'payment_sms_parser.dart';

class PaymentSmsService {
  static const EventChannel _channel = EventChannel('bagdar/incoming_sms');

  final TtsService _tts;
  final EarconService _earcon;

  StreamSubscription<dynamic>? _subscription;
  final Map<String, DateTime> _recentKeys = {};
  bool _enabled = false;
  bool _permissionGranted = false;

  PaymentSmsService({
    required TtsService tts,
    required EarconService earcon,
  })  : _tts = tts,
        _earcon = earcon;

  bool get isEnabled => _enabled;
  bool get isPermissionGranted => _permissionGranted;
  bool get isListening => _subscription != null;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> init() async {
    if (!_isAndroid) return;
    _enabled = Settings.instance.paymentSmsEnabled;
    if (!_enabled) return;
    final granted = await _checkPermission();
    _permissionGranted = granted;
    if (granted) {
      _startListening();
    }
  }

  Future<bool> enable({bool announce = true}) async {
    if (!_isAndroid) {
      if (announce) {
        _tts.say(
          S.get('sms_permission_denied'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      }
      return false;
    }
    final granted = await _requestPermission();
    _permissionGranted = granted;
    if (!granted) {
      if (announce) {
        _tts.say(
          S.get('sms_permission_denied'),
          SpeechPriority.warning,
          pan: 0.0,
        );
      }
      return false;
    }
    _enabled = true;
    await Settings.instance.setPaymentSmsEnabled(true);
    _startListening();
    if (announce) {
      _tts.say(
        S.get('sms_notifications_enabled'),
        SpeechPriority.info,
        pan: 0.0,
      );
    }
    return true;
  }

  Future<void> disable({bool announce = true}) async {
    _enabled = false;
    await Settings.instance.setPaymentSmsEnabled(false);
    _stopListening();
    if (announce) {
      _tts.say(
        S.get('sms_notifications_disabled'),
        SpeechPriority.info,
        pan: 0.0,
      );
    }
  }

  Future<bool> toggle({bool announce = true}) async {
    if (_enabled) {
      await disable(announce: announce);
      return false;
    }
    return enable(announce: announce);
  }

  void dispose() {
    _stopListening();
    _recentKeys.clear();
  }

  Future<bool> _checkPermission() async {
    try {
      final s = await Permission.sms.status;
      return s.isGranted;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    try {
      final current = await Permission.sms.status;
      if (current.isGranted) return true;
      final result = await Permission.sms.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('PaymentSmsService: permission request failed: $e');
      return false;
    }
  }

  void _startListening() {
    if (_subscription != null) return;
    try {
      _subscription = _channel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (Object e) {
          debugPrint('PaymentSmsService: stream error: $e');
        },
        cancelOnError: false,
      );
      debugPrint('PaymentSmsService: listening for SMS');
    } catch (e) {
      debugPrint('PaymentSmsService: start listen failed: $e');
    }
  }

  void _stopListening() {
    final sub = _subscription;
    _subscription = null;
    if (sub != null) {
      unawaited(sub.cancel());
      debugPrint('PaymentSmsService: stopped listening');
    }
  }

  void _handleEvent(Object? raw) {
    if (raw is! Map) return;
    final sender = (raw['sender'] ?? '').toString();
    final body = (raw['body'] ?? '').toString();
    if (body.isEmpty) return;
    final event = PaymentSmsParser.parse(sender: sender, body: body);
    if (event == null) return;
    final key = event.dedupKey();
    final now = DateTime.now();
    _gcRecent(now);
    final last = _recentKeys[key];
    if (last != null && now.difference(last) < kPaymentSmsDedupWindow) {
      return;
    }
    _recentKeys[key] = now;

    final text = PaymentSmsParser.formatTts(event);
    FieldLogger.instance.logTtsSay(
      text: 'payment_sms:${event.direction.name}',
      priority: SpeechPriority.critical.name,
      pan: 0.0,
      trackId: null,
    );
    _earcon.play(Earcon.paymentReceived);
    _tts.say(text, SpeechPriority.critical, pan: 0.0);
  }

  void _gcRecent(DateTime now) {
    if (_recentKeys.length < 16) return;
    final cutoff = now.subtract(kPaymentSmsDedupWindow);
    _recentKeys.removeWhere((_, ts) => ts.isBefore(cutoff));
  }
}

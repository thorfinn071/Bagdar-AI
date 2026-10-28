import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/strings.dart';
import 'voice_input.dart';

/// A separate, opt-in input. Never uses EXTRA_PREFER_OFFLINE as a privacy
/// guarantee and never falls back to the default/network recognizer.
class OnDeviceVoiceInput implements VoiceInput {
  static final Map<String, OnDeviceVoiceInput> _channelOwners = {};
  final MethodChannel _channel;
  VoiceInputTurn? _turn;
  void Function()? _onReady;
  bool _attached = false;
  bool _disposed = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _routeChanges;
  bool _interrupted = false;

  OnDeviceVoiceInput({
    MethodChannel channel = const MethodChannel('bagdar/onboarding_voice'),
  }) : _channel = channel;

  @override
  Future<VoiceInputAvailability> prepare({
    required bool requestPermission,
  }) async {
    if (_disposed) return VoiceInputAvailability.unavailable;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return VoiceInputAvailability.unsupported;
    }
    try {
      final capability = await _channel
          .invokeMethod<String>('availability')
          .timeout(const Duration(seconds: 3));
      if (capability == 'unsupported') {
        return VoiceInputAvailability.unsupported;
      }
      if (capability != 'ready') return VoiceInputAvailability.unavailable;
      var permission = await Permission.microphone.status;
      if (!permission.isGranted && requestPermission) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) return VoiceInputAvailability.permissionDenied;
      if (_disposed) return VoiceInputAvailability.unavailable;
      if (!_attached) {
        final audio = await AudioSession.instance;
        if (_disposed) return VoiceInputAvailability.unavailable;
        _attached = true;
        _interruptions = audio.interruptionEventStream.listen((event) {
          if (event.begin) _interrupt();
        });
        _routeChanges = audio.becomingNoisyEventStream.listen(
          (_) => _interrupt(),
        );
      }
      // Onboarding remains mounted while inspection is pushed. Reclaim the
      // channel on return without letting an old instance clear a new owner.
      final owner = _channelOwners[_channel.name];
      if (owner != null && !identical(owner, this) && owner._turn != null) {
        return VoiceInputAvailability.unavailable;
      }
      _channelOwners[_channel.name] = this;
      _channel.setMethodCallHandler((call) async {
        final args = call.arguments;
        if (call.method == 'ready' &&
            args is Map &&
            args['sessionId'] == _turn?.sessionId &&
            args['turnId'] == _turn?.turnId) {
          _onReady?.call();
        }
      });
      return VoiceInputAvailability.ready;
    } catch (_) {
      return VoiceInputAvailability.unavailable;
    }
  }

  void _interrupt() {
    if (_turn == null) return;
    _interrupted = true;
    unawaited(cancel().catchError((Object _) {}));
  }

  @override
  Future<VoiceInputResult> listen(
    VoiceInputTurn turn, {
    required void Function() onReady,
  }) async {
    VoiceInputResult failure(VoiceInputOutcome outcome) => VoiceInputResult(
      sessionId: turn.sessionId,
      turnId: turn.turnId,
      outcome: outcome,
    );
    if (_disposed ||
        !_attached ||
        !identical(_channelOwners[_channel.name], this)) {
      return failure(VoiceInputOutcome.unavailable);
    }
    if (!await Permission.microphone.isGranted) {
      return failure(VoiceInputOutcome.permissionDenied);
    }
    if (_disposed ||
        !identical(_channelOwners[_channel.name], this) ||
        _turn != null) {
      return failure(VoiceInputOutcome.cancelled);
    }
    _turn = turn;
    _onReady = onReady;
    _interrupted = false;
    try {
      final result = await _channel
          .invokeMapMethod<String, dynamic>('listen', {
            'sessionId': turn.sessionId,
            'turnId': turn.turnId,
            'language': switch (turn.language) {
              AppLanguage.ru => 'ru-RU',
              AppLanguage.kk => 'kk-KZ',
              AppLanguage.en => 'en-US',
            },
            'durationMs': turn.duration.inMilliseconds,
          })
          .timeout(turn.duration + const Duration(seconds: 3));
      if (_interrupted) return failure(VoiceInputOutcome.interrupted);
      if (result == null) return failure(VoiceInputOutcome.unavailable);
      return VoiceInputResult(
        sessionId: result['sessionId'] as int? ?? -1,
        turnId: result['turnId'] as int? ?? -1,
        outcome: VoiceInputOutcome.values.firstWhere(
          (value) => value.name == result['outcome'],
          orElse: () => VoiceInputOutcome.unavailable,
        ),
        text: result['text'] as String? ?? '',
        isFinal: result['isFinal'] == true,
        confidence: (result['confidence'] as num?)?.toDouble(),
      );
    } catch (_) {
      await cancel();
      return failure(VoiceInputOutcome.unavailable);
    } finally {
      if (identical(_turn, turn)) {
        _turn = null;
        _onReady = null;
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (!_attached || !identical(_channelOwners[_channel.name], this)) return;
    _onReady = null;
    // Failure is not a confirmed shutdown. Callers must not hand microphone
    // ownership to another screen after a timeout or channel error.
    await _channel
        .invokeMethod<void>('cancel')
        .timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    try {
      await cancel();
    } catch (_) {
      // Activity pause/destroy also closes the native recognizer. Disposal
      // makes no claim that platform cancellation was acknowledged.
    }
    await _interruptions?.cancel();
    await _routeChanges?.cancel();
    if (identical(_channelOwners[_channel.name], this)) {
      _channelOwners.remove(_channel.name);
      _channel.setMethodCallHandler(null);
    }
    _attached = false;
  }
}

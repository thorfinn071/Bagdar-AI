import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'wake_word_input.dart';

class VoskWakeWordInput implements WakeWordInput {
  final MethodChannel channel;
  static final Map<String, VoskWakeWordInput> _owners = {};
  bool _disposed = false, _attached = false, _interrupted = false;
  int? _session;
  void Function()? _onReady;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _routes;
  VoskWakeWordInput({this.channel = const MethodChannel('bagdar/wake_word')});

  @override
  Future<WakeWordAvailability> prepare({
    required bool requestPermission,
  }) async {
    if (_disposed) return WakeWordAvailability.unavailable;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return WakeWordAvailability.unsupported;
    }
    try {
      final availability = await channel
          .invokeMethod<String>('availability')
          .timeout(const Duration(seconds: 3));
      if (availability != 'ready') {
        return switch (availability) {
          'disabled' => WakeWordAvailability.disabled,
          'modelMissing' => WakeWordAvailability.modelMissing,
          _ => WakeWordAvailability.unavailable,
        };
      }
      var permission = await Permission.microphone.status;
      if (!permission.isGranted && requestPermission) {
        permission = await Permission.microphone.request();
      }
      if (!permission.isGranted) return WakeWordAvailability.permissionDenied;
      if (_disposed) return WakeWordAvailability.unavailable;
      final owner = _owners[channel.name];
      if (owner != null && !identical(owner, this) && owner._session != null) {
        return WakeWordAvailability.unavailable;
      }
      _owners[channel.name] = this;
      channel.setMethodCallHandler((call) async {
        if (call.method == 'ready' &&
            call.arguments is Map &&
            call.arguments['sessionId'] == _session) {
          _onReady?.call();
        }
      });
      if (!_attached) {
        final audio = await AudioSession.instance;
        if (_disposed) return WakeWordAvailability.unavailable;
        _interruptions = audio.interruptionEventStream.listen((event) {
          if (event.begin) _interrupt();
        });
        _routes = audio.becomingNoisyEventStream.listen((_) => _interrupt());
        _attached = true;
      }
      final ready = await channel
          .invokeMethod<String>('prepare')
          .timeout(const Duration(seconds: 30));
      return !_disposed && ready == 'ready'
          ? WakeWordAvailability.ready
          : WakeWordAvailability.unavailable;
    } catch (_) {
      return WakeWordAvailability.unavailable;
    }
  }

  void _interrupt() {
    if (_session == null) return;
    _interrupted = true;
    unawaited(cancel().catchError((Object _) {}));
  }

  @override
  Future<WakeWordResult> listen({
    required int sessionId,
    required Duration duration,
    required void Function() onReady,
  }) async {
    WakeWordResult failure(String outcome) =>
        WakeWordResult(sessionId: sessionId, outcome: outcome);
    if (_disposed ||
        !_attached ||
        _session != null ||
        !identical(_owners[channel.name], this) ||
        duration.inMilliseconds < 1000 ||
        duration.inMilliseconds > 300000 ||
        !await Permission.microphone.isGranted) {
      return failure('unavailable');
    }
    if (_disposed ||
        _session != null ||
        !identical(_owners[channel.name], this)) {
      return failure('unavailable');
    }
    _session = sessionId;
    _onReady = onReady;
    _interrupted = false;
    try {
      final result = await channel
          .invokeMapMethod<String, dynamic>('listen', {
            'sessionId': sessionId,
            'durationMs': duration.inMilliseconds,
            'experimental': true,
          })
          .timeout(duration + const Duration(seconds: 3));
      if (_interrupted) return failure('interrupted');
      if (result == null) return failure('unavailable');
      return WakeWordResult(
        sessionId: result['sessionId'] as int? ?? -1,
        outcome: result['outcome'] as String? ?? 'unavailable',
        backend: result['backend'] as String? ?? '',
        keyword: result['keyword'] as String? ?? '',
        released: result['released'] == true,
        confidence: (result['confidence'] as num?)?.toDouble(),
        wordDurationMs: (result['wordDurationMs'] as num?)?.toDouble(),
        ageMs: (result['ageMs'] as num?)?.toInt(),
      );
    } catch (_) {
      await cancel();
      return failure('unavailable');
    } finally {
      if (_session == sessionId) {
        _session = null;
        _onReady = null;
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (!identical(_owners[channel.name], this)) return;
    _onReady = null;
    await channel
        .invokeMethod<void>('cancel')
        .timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    try {
      await cancel();
    } catch (_) {}
    await _interruptions?.cancel();
    await _routes?.cancel();
    if (identical(_owners[channel.name], this)) {
      _owners.remove(channel.name);
      channel.setMethodCallHandler(null);
    }
  }
}

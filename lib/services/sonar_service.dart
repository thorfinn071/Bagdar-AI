import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import '../models/external_hazard.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import 'device_capability.dart';
import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'settings_service.dart';

/// Compact range estimate produced by the native FMCW DSP pipeline.
class SonarRangeEstimate {
  final double rangeM;
  final double confidence;
  final DateTime at;

  const SonarRangeEstimate({
    required this.rangeM,
    required this.confidence,
    required this.at,
  });

  bool get isUsable => confidence >= kSonarMinConfidence;
}

/// State of the sonar prototype.
enum SonarState {
  idle,
  calibrating,
  active,
  paused,
  error,
}

/// FMCW chirp echolocation depth prototype.
///
/// Phase 5 — Direction 1. Research-gated acoustic depth modality.
/// All DSP (chirp generation, echo cancellation, cross-correlation/FFT,
/// peak picking, calibration, confidence scoring) runs natively for
/// performance. Dart receives only compact range estimates.
///
/// Safety controls:
/// - Disabled when headphones are connected.
/// - Disabled when call audio is active.
/// - Disabled when microphone permission is missing.
/// - Disabled when volume is unsafe.
/// - Disabled when AWM/ASR owns the mic (via SensorSessionCoordinator).
///
/// Risk gate: Ships only as experimental until range estimates are
/// repeatable across representative budget Android devices.
class SonarService {
  SonarService._();

  static final SonarService instance = SonarService._();

  static const MethodChannel _channel = MethodChannel('bagdar/sonar');

  void Function(ExternalHazardEvent event)? onHazard;

  SonarState _state = SonarState.idle;
  SessionLease? _micLease;
  SessionLease? _speakerLease;

  double _lastRangeM = -1;
  double _lastConfidence = 0;
  bool _calibrated = false;
  DateTime _lastHazardAt = DateTime.fromMillisecondsSinceEpoch(0);

  SonarState get state => _state;
  double get lastRangeM => _lastRangeM;
  double get lastConfidence => _lastConfidence;
  bool get isCalibrated => _calibrated;
  bool get isActive => _state == SonarState.active;

  /// Start the sonar prototype. Requires exclusive mic + speaker.
  /// No-op if the feature flag is off, the device doesn't support
  /// 48 kHz mic, or the mic/speaker is already claimed.
  Future<bool> start() async {
    if (_state == SonarState.active || _state == SonarState.calibrating) {
      return _state == SonarState.active;
    }
    if (!Settings.instance.sonarDepth) {
      FieldLogger.instance.logSonarChirp('start_blocked_flag_off');
      return false;
    }

    try {
      final caps = DeviceCapabilityProbe.cached;
      if (!caps.sonarFeasible) {
        FieldLogger.instance.logSonarChirp('start_blocked_no_48k');
        return false;
      }
    } catch (_) {
      FieldLogger.instance.logSonarChirp('start_blocked_probe_failed');
      return false;
    }

    // Acquire exclusive mic.
    final micGrant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.microphone,
      priority: SessionPriority.optional,
      owner: 'SonarService',
    );
    if (!micGrant.isGranted) {
      FieldLogger.instance.logSonarChirp('start_blocked_mic_busy', data: {
        'holder': micGrant.denyDetail ?? 'unknown',
      });
      return false;
    }
    _micLease = micGrant.lease;

    // Acquire exclusive speaker.
    final spkGrant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.speaker,
      priority: SessionPriority.optional,
      owner: 'SonarService',
    );
    if (!spkGrant.isGranted) {
      SensorSessionCoordinator.instance.release(_micLease);
      _micLease = null;
      FieldLogger.instance.logSonarChirp('start_blocked_speaker_busy', data: {
        'holder': spkGrant.denyDetail ?? 'unknown',
      });
      return false;
    }
    _speakerLease = spkGrant.lease;

    _state = SonarState.calibrating;

    try {
      final ok = await _channel
          .invokeMethod<bool>('startSonar')
          .timeout(const Duration(seconds: 10));
      if (ok != true) {
        _releaseAll();
        FieldLogger.instance.logSonarChirp('start_plugin_failed');
        return false;
      }
      _channel.setMethodCallHandler(_handleNativeCall);
      FieldLogger.instance.logSonarChirp('started');
      return true;
    } on MissingPluginException {
      _releaseAll();
      FieldLogger.instance.logSonarChirp('start_plugin_missing');
      return false;
    } catch (e) {
      _releaseAll();
      FieldLogger.instance.logSonarChirp('start_error', data: {
        'error': e.toString(),
      });
      return false;
    }
  }

  /// Stop the sonar prototype and release mic + speaker.
  Future<void> stop() async {
    if (_state == SonarState.idle) return;
    try {
      await _channel.invokeMethod<void>('stopSonar');
    } catch (_) {}
    _releaseAll();
    FieldLogger.instance.logSonarChirp('stopped');
  }

  void dispose() {
    unawaited(stop());
  }

  void _releaseAll() {
    SensorSessionCoordinator.instance.release(_micLease);
    SensorSessionCoordinator.instance.release(_speakerLease);
    _micLease = null;
    _speakerLease = null;
    _state = SonarState.idle;
  }

  void _handleRangeEstimate(double rangeM, double confidence) {
    if (rangeM <= 0 || rangeM > kSonarMaxRangeM) return;
    if (confidence < kSonarMinConfidence) return;

    _lastRangeM = rangeM;
    _lastConfidence = confidence;

    final now = DateTime.now();
    if (rangeM < 1.5 &&
        now.difference(_lastHazardAt) >= kSonarHazardCooldown) {
      _lastHazardAt = now;

      final text =
          '${S.alert('sonar_near_field')}, ~${rangeM.toStringAsFixed(1)} ${S.alert('approx_meters')}';
      try {
        onHazard?.call(ExternalHazardEvent(
          source: ExternalHazardSource.sonarChirp,
          text: text,
          priority: rangeM < 0.5
              ? SpeechPriority.critical
              : SpeechPriority.warning,
          category: AlertCategory.obstacleClose,
          urgency: (1.0 - rangeM / 1.5).clamp(0.3, 0.9),
          distanceM: rangeM,
          at: now,
          correlationId: 'sonar_range',
        ));
      } catch (e) {
        FieldLogger.instance.logSonarChirp('emit_error', data: {
          'error': e.toString(),
        });
      }
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSonarCalibrated':
        _calibrated = true;
        _state = SonarState.active;
        FieldLogger.instance.logSonarChirp('calibrated');
        break;
      case 'onSonarRange':
        final args = call.arguments as Map?;
        if (args != null) {
          _handleRangeEstimate(
            (args['range'] as num?)?.toDouble() ?? -1,
            (args['conf'] as num?)?.toDouble() ?? 0,
          );
        }
        break;
      case 'onSonarError':
        _state = SonarState.error;
        FieldLogger.instance.logSonarChirp('native_error', data: {
          'error': call.arguments?.toString() ?? 'unknown',
        });
        break;
      case 'onSonarHeadphones':
        await stop();
        FieldLogger.instance.logSonarChirp('stopped_headphones');
        break;
      case 'onSonarCallActive':
        await stop();
        FieldLogger.instance.logSonarChirp('stopped_call_active');
        break;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _state = SonarState.idle;
    _lastRangeM = -1;
    _lastConfidence = 0;
    _calibrated = false;
    _lastHazardAt = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/constants.dart';
import 'device_capability.dart';
import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'settings_service.dart';

bool _isKnownSonarRoute(String value) =>
    value.trim().isNotEmpty && !value.toLowerCase().contains('unknown');

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

/// Exact native capability admission. Unknown values fail closed.
class SonarCapabilityContract {
  final bool micNearUltrasound;
  final bool speakerNearUltrasound;
  final bool unprocessedInput;
  final int sampleRateHz;
  final String inputRoute;
  final String outputRoute;

  const SonarCapabilityContract({
    required this.micNearUltrasound,
    required this.speakerNearUltrasound,
    required this.unprocessedInput,
    required this.sampleRateHz,
    required this.inputRoute,
    required this.outputRoute,
  });

  factory SonarCapabilityContract.fromMap(Map<dynamic, dynamic> map) =>
      SonarCapabilityContract(
        micNearUltrasound: map['micNearUltrasound'] == true,
        speakerNearUltrasound: map['speakerNearUltrasound'] == true,
        unprocessedInput: map['unprocessedInput'] == true,
        sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 0,
        inputRoute: map['inputRoute']?.toString() ?? 'unknown',
        outputRoute: map['outputRoute']?.toString() ?? 'unknown',
      );

  bool get admitted =>
      micNearUltrasound &&
      speakerNearUltrasound &&
      unprocessedInput &&
      sampleRateHz >= 48000 &&
      _isKnownSonarRoute(inputRoute) &&
      _isKnownSonarRoute(outputRoute);

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'micNearUltrasound': micNearUltrasound,
    'speakerNearUltrasound': speakerNearUltrasound,
    'unprocessedInput': unprocessedInput,
    'sampleRateHz': sampleRateHz,
    'inputRoute': inputRoute,
    'outputRoute': outputRoute,
    'admitted': admitted,
  };
}

/// Calibration evidence required before shadow observations are accepted.
/// The current native prototype reports missing DSP/safety evidence and is
/// therefore rejected until that implementation and a device run exist.
class SonarCalibrationReport {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int chirpCount;
  final int sampleRateHz;
  final bool directPathCancellationApplied;
  final bool multipathPeakSelectionApplied;
  final bool acousticLevelValidated;
  final double repeatabilityMadM;
  final String routeFingerprint;

  const SonarCalibrationReport({
    required this.schemaVersion,
    required this.chirpCount,
    required this.sampleRateHz,
    required this.directPathCancellationApplied,
    required this.multipathPeakSelectionApplied,
    required this.acousticLevelValidated,
    required this.repeatabilityMadM,
    required this.routeFingerprint,
  });

  factory SonarCalibrationReport.fromMap(
    Map<dynamic, dynamic> map,
  ) => SonarCalibrationReport(
    schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 0,
    chirpCount: (map['chirpCount'] as num?)?.toInt() ?? 0,
    sampleRateHz: (map['sampleRateHz'] as num?)?.toInt() ?? 0,
    directPathCancellationApplied: map['directPathCancellationApplied'] == true,
    multipathPeakSelectionApplied: map['multipathPeakSelectionApplied'] == true,
    acousticLevelValidated: map['acousticLevelValidated'] == true,
    repeatabilityMadM:
        (map['repeatabilityMadM'] as num?)?.toDouble() ?? double.infinity,
    routeFingerprint: map['routeFingerprint']?.toString() ?? 'unknown',
  );

  bool get admitted =>
      schemaVersion == currentSchemaVersion &&
      chirpCount >= 8 &&
      sampleRateHz >= 48000 &&
      directPathCancellationApplied &&
      multipathPeakSelectionApplied &&
      acousticLevelValidated &&
      repeatabilityMadM.isFinite &&
      repeatabilityMadM >= 0 &&
      repeatabilityMadM <= 0.12 &&
      _isKnownSonarRoute(routeFingerprint);

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'chirpCount': chirpCount,
    'sampleRateHz': sampleRateHz,
    'directPathCancellationApplied': directPathCancellationApplied,
    'multipathPeakSelectionApplied': multipathPeakSelectionApplied,
    'acousticLevelValidated': acousticLevelValidated,
    'repeatabilityMadM': repeatabilityMadM,
    'routeFingerprint': routeFingerprint,
    'admitted': admitted,
  };
}

class SonarShadowObservation {
  final double rangeM;
  final double confidence;
  final double spreadM;
  final int chirpCount;
  final DateTime at;

  const SonarShadowObservation({
    required this.rangeM,
    required this.confidence,
    required this.spreadM,
    required this.chirpCount,
    required this.at,
  });

  Map<String, Object?> toDiagnosticMap() => <String, Object?>{
    'rangeM': rangeM,
    'confidence': confidence,
    'spreadM': spreadM,
    'chirpCount': chirpCount,
    'atUs': at.microsecondsSinceEpoch,
    'delivery': 'shadow',
  };
}

/// Requires agreement across several chirps. One correlation peak can never
/// become a sonar observation on its own.
class SonarMultiChirpConsensus {
  final int windowSize;
  final int minimumUsable;
  final double maximumSpreadM;
  final Duration maximumAge;
  final List<SonarRangeEstimate> _window = <SonarRangeEstimate>[];
  DateTime? _lastAt;

  SonarMultiChirpConsensus({
    this.windowSize = 5,
    this.minimumUsable = 4,
    this.maximumSpreadM = 0.25,
    this.maximumAge = const Duration(seconds: 2),
  }) : assert(windowSize > 0),
       assert(minimumUsable > 0 && minimumUsable <= windowSize),
       assert(maximumSpreadM >= 0),
       assert(maximumAge > Duration.zero);

  void reset() {
    _window.clear();
    _lastAt = null;
  }

  SonarShadowObservation? add(SonarRangeEstimate estimate) {
    final previousAt = _lastAt;
    if (previousAt != null && !estimate.at.isAfter(previousAt)) {
      reset();
      return null;
    }
    _lastAt = estimate.at;
    _window.removeWhere((item) => estimate.at.difference(item.at) > maximumAge);
    _window.add(estimate);
    while (_window.length > windowSize) {
      _window.removeAt(0);
    }
    if (_window.length < windowSize) return null;
    final usable = _window.where((item) => item.isUsable).toList();
    if (usable.length < minimumUsable) return null;

    final ranges = usable.map((item) => item.rangeM).toList()..sort();
    final confidences = usable.map((item) => item.confidence).toList()..sort();
    final spread = ranges.last - ranges.first;
    if (!spread.isFinite || spread > maximumSpreadM) return null;
    return SonarShadowObservation(
      rangeM: _median(ranges),
      confidence: _median(confidences),
      spreadM: spread,
      chirpCount: usable.length,
      at: estimate.at,
    );
  }

  static double _median(List<double> values) {
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }
}

/// State of the sonar prototype.
enum SonarState { idle, calibrating, active, paused, error }

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
  static const bool userAlertsEnabled = false;

  void Function(SonarShadowObservation observation)? onShadowObservation;

  SonarState _state = SonarState.idle;
  SessionLease? _micLease;
  SessionLease? _speakerLease;
  final SonarMultiChirpConsensus _consensus = SonarMultiChirpConsensus();

  double _lastRangeM = -1;
  double _lastConfidence = 0;
  bool _calibrated = false;
  SonarCapabilityContract? _capability;
  SonarCalibrationReport? _calibration;
  SonarShadowObservation? _lastShadowObservation;

  SonarState get state => _state;
  double get lastRangeM => _lastRangeM;
  double get lastConfidence => _lastConfidence;
  bool get isCalibrated => _calibrated;
  bool get isActive => _state == SonarState.active;
  SonarCapabilityContract? get capability => _capability;
  SonarCalibrationReport? get calibration => _calibration;
  SonarShadowObservation? get lastShadowObservation => _lastShadowObservation;

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
      if (caps.deviceInfo.isEmulator) {
        FieldLogger.instance.logSonarChirp('start_blocked_emulator');
        return false;
      }
      if (!caps.hardware.micSupports48kHz) {
        FieldLogger.instance.logSonarChirp('start_blocked_no_48k');
        return false;
      }
    } catch (_) {
      FieldLogger.instance.logSonarChirp('start_blocked_probe_failed');
      return false;
    }

    _channel.setMethodCallHandler(_handleNativeCall);
    try {
      final rawCapability = await _channel
          .invokeMapMethod<dynamic, dynamic>('getCapabilities')
          .timeout(const Duration(seconds: 3));
      final capability = rawCapability == null
          ? null
          : SonarCapabilityContract.fromMap(rawCapability);
      _capability = capability;
      FieldLogger.instance.logSonarChirp(
        'capability_checked',
        data:
            capability?.toDiagnosticMap().cast<String, dynamic>() ??
            const <String, dynamic>{'admitted': false, 'reason': 'missing'},
      );
      if (capability == null || !capability.admitted) {
        _state = SonarState.error;
        FieldLogger.instance.logSonarChirp('start_blocked_capability');
        return false;
      }
    } on MissingPluginException {
      _state = SonarState.error;
      FieldLogger.instance.logSonarChirp('start_plugin_missing');
      return false;
    } catch (e) {
      _state = SonarState.error;
      FieldLogger.instance.logSonarChirp(
        'capability_error',
        data: {'error': e.toString()},
      );
      return false;
    }

    final micGrant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.microphone,
      priority: SessionPriority.optional,
      owner: 'SonarService',
    );
    if (!micGrant.isGranted) {
      FieldLogger.instance.logSonarChirp(
        'start_blocked_mic_busy',
        data: {'holder': micGrant.denyDetail ?? 'unknown'},
      );
      return false;
    }
    _micLease = micGrant.lease;

    final spkGrant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.speaker,
      priority: SessionPriority.optional,
      owner: 'SonarService',
    );
    if (!spkGrant.isGranted) {
      SensorSessionCoordinator.instance.release(_micLease);
      _micLease = null;
      FieldLogger.instance.logSonarChirp(
        'start_blocked_speaker_busy',
        data: {'holder': spkGrant.denyDetail ?? 'unknown'},
      );
      return false;
    }
    _speakerLease = spkGrant.lease;

    _consensus.reset();
    _calibration = null;
    _lastShadowObservation = null;
    _calibrated = false;
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
      FieldLogger.instance.logSonarChirp('started');
      return true;
    } on MissingPluginException {
      _releaseAll();
      FieldLogger.instance.logSonarChirp('start_plugin_missing');
      return false;
    } catch (e) {
      _releaseAll();
      FieldLogger.instance.logSonarChirp(
        'start_error',
        data: {'error': e.toString()},
      );
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

  Future<void> pauseForAudioInterruption(String reason) async {
    if (_state != SonarState.active && _state != SonarState.calibrating) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopSonar');
    } catch (_) {}
    _releaseAll(nextState: SonarState.paused);
    FieldLogger.instance.logSonarChirp(
      'paused_audio_interruption',
      data: {'reason': reason},
    );
  }

  void _releaseAll({SonarState nextState = SonarState.idle}) {
    SensorSessionCoordinator.instance.release(_micLease);
    SensorSessionCoordinator.instance.release(_speakerLease);
    _micLease = null;
    _speakerLease = null;
    _state = nextState;
    _calibrated = false;
    _consensus.reset();
  }

  SonarShadowObservation? _handleRangeEstimate(
    double rangeM,
    double confidence, {
    DateTime? at,
  }) {
    if (_state != SonarState.active || !_calibrated) return null;
    if (!rangeM.isFinite || rangeM <= 0 || rangeM > kSonarMaxRangeM) {
      return null;
    }
    if (!confidence.isFinite || confidence < 0 || confidence > 1) return null;

    _lastRangeM = rangeM;
    _lastConfidence = confidence;
    final estimate = SonarRangeEstimate(
      rangeM: rangeM,
      confidence: confidence,
      at: at ?? DateTime.now(),
    );
    final observation = _consensus.add(estimate);
    FieldLogger.instance.logSonarChirp(
      'range_shadow_sample',
      data: {
        'rangeM': rangeM,
        'confidence': confidence,
        'consensusReady': observation != null,
      },
    );
    if (observation == null) return null;
    _lastShadowObservation = observation;
    FieldLogger.instance.logSonarChirp(
      'range_shadow_consensus',
      data: observation.toDiagnosticMap().cast<String, dynamic>(),
    );
    try {
      onShadowObservation?.call(observation);
    } catch (e) {
      FieldLogger.instance.logSonarChirp(
        'shadow_observer_error',
        data: {'error': e.toString()},
      );
    }
    return observation;
  }

  Future<void> _rejectCalibration(SonarCalibrationReport? report) async {
    _calibration = report;
    FieldLogger.instance.logSonarChirp(
      'calibration_rejected',
      data:
          report?.toDiagnosticMap().cast<String, dynamic>() ??
          const <String, dynamic>{'admitted': false, 'reason': 'missing'},
    );
    try {
      await _channel.invokeMethod<void>('stopSonar');
    } catch (_) {}
    _releaseAll(nextState: SonarState.error);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onSonarCalibrated':
        final args = call.arguments as Map?;
        if (args == null) {
          await _rejectCalibration(null);
          break;
        }
        final report = SonarCalibrationReport.fromMap(args);
        _calibration = report;
        if (!report.admitted) {
          await _rejectCalibration(report);
          break;
        }
        _calibrated = true;
        _state = SonarState.active;
        FieldLogger.instance.logSonarChirp(
          'calibrated',
          data: report.toDiagnosticMap().cast<String, dynamic>(),
        );
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
        _releaseAll(nextState: SonarState.error);
        FieldLogger.instance.logSonarChirp(
          'native_error',
          data: {'error': call.arguments?.toString() ?? 'unknown'},
        );
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
    SensorSessionCoordinator.instance.release(_micLease);
    SensorSessionCoordinator.instance.release(_speakerLease);
    _micLease = null;
    _speakerLease = null;
    _state = SonarState.idle;
    _lastRangeM = -1;
    _lastConfidence = 0;
    _calibrated = false;
    _capability = null;
    _calibration = null;
    _lastShadowObservation = null;
    _consensus.reset();
    onShadowObservation = null;
  }
}

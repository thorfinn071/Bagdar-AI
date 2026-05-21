import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/external_hazard.dart';
import '../models/speech_job.dart';
import '../utils/alert_filter.dart' show AlertCategory;
import '../utils/performance_throttler.dart';
import 'field_logger.dart';
import 'sensor_session_coordinator.dart';
import 'settings_service.dart';
import 'thermal_monitor.dart';

/// State of the VLM companion inference.
enum VlmState { idle, loading, inferring, answering, error }

/// Extends `SceneNarrator` with a `SceneQuestionService` so the same
/// voice command (\"что вокруг\" / \"describe scene\") can use templates
/// on low-end devices and a VLM on capable devices with the model
/// pack installed.
///
/// Phase 4 — Direction 11. The VLM model is treated as a large optional
/// download (MobileVLM / MiniCPM / Phi vision). Inference runs on a
/// dedicated llama.cpp-style Android native plugin (`bagdar/vlm_engine`)
/// off the UI isolate and is cancellable.
///
/// Gates (all must pass):
/// - Charger connected
/// - Battery > 40%
/// - Thermal below hot
/// - Memory normal or low (not critical)
/// - User explicitly requests Q&A
///
/// Fallback: `SceneNarrator`, OCR, traffic-light analyzer, object list,
/// and depth hazards remain the default path. VLM latency never blocks
/// hazard detection, camera frames, TTS critical alerts, or SOS.
class SceneQuestionService {
  SceneQuestionService._();

  static final SceneQuestionService instance = SceneQuestionService._();

  static const MethodChannel _channel = MethodChannel('bagdar/vlm_engine');

  VlmState _state = VlmState.idle;
  bool _modelLoaded = false;
  SessionLease? _modelLease;

  void Function(ExternalHazardEvent event)? onAnswer;

  VlmState get state => _state;
  bool get isModelLoaded => _modelLoaded;
  bool get isAvailable => Settings.instance.vlmCompanion;

  /// Whether all runtime gates pass for VLM inference.
  bool canRun({
    required bool charging,
    required int batteryPct,
    required ThermalSeverity thermal,
    required MemoryPressureLevel memory,
  }) =>
      charging &&
      batteryPct > 40 &&
      thermal != ThermalSeverity.hot &&
      thermal != ThermalSeverity.critical &&
      memory != MemoryPressureLevel.critical;

  /// Attempt to load the VLM model into memory. No-op if the feature
  /// flag is off, runtime gates fail, or the model is already loaded.
  Future<bool> loadModel({
    required bool charging,
    required int batteryPct,
    required ThermalSeverity thermal,
    required MemoryPressureLevel memory,
  }) async {
    if (_modelLoaded) return true;
    if (!isAvailable) {
      FieldLogger.instance.logVlmCompanion('load_blocked_flag_off');
      return false;
    }
    if (!canRun(
      charging: charging,
      batteryPct: batteryPct,
      thermal: thermal,
      memory: memory,
    )) {
      FieldLogger.instance.logVlmCompanion('load_blocked_gates', data: {
        'charging': charging,
        'battery': batteryPct,
        'thermal': thermal.name,
        'memory': memory.name,
      });
      return false;
    }

    final grant = SensorSessionCoordinator.instance.request(
      resource: SensorResource.optionalModelSlot,
      priority: SessionPriority.optional,
      owner: 'SceneQuestionService',
    );
    if (!grant.isGranted) {
      FieldLogger.instance.logVlmCompanion('load_blocked_slot_busy');
      return false;
    }
    _modelLease = grant.lease;

    _state = VlmState.loading;
    try {
      final ok = await _channel
          .invokeMethod<bool>('loadVlmModel')
          .timeout(const Duration(seconds: 60));
      if (ok == true) {
        _modelLoaded = true;
        _state = VlmState.idle;
        FieldLogger.instance.logVlmCompanion('model_loaded');
        return true;
      }
      _releaseModel();
      FieldLogger.instance.logVlmCompanion('load_failed');
      return false;
    } on MissingPluginException {
      _releaseModel();
      FieldLogger.instance.logVlmCompanion('plugin_missing');
      return false;
    } catch (e) {
      _releaseModel();
      FieldLogger.instance.logVlmCompanion('load_error', data: {
        'error': e.toString(),
      });
      return false;
    }
  }

  /// Ask the VLM a question about the current scene. If the VLM is
  /// not loaded, falls back to the template-based `SceneNarrator`.
  /// Returns immediately; answers arrive via [onAnswer].
  Future<void> askQuestion({
    required String question,
    required Uint8List? imageBytes,
    String? fallbackNarration,
  }) async {
    if (!_modelLoaded || _state == VlmState.inferring) {
      if (fallbackNarration != null && fallbackNarration.isNotEmpty) {
        _emitFallback(fallbackNarration);
      }
      return;
    }

    _state = VlmState.inferring;
    try {
      final result = await _channel.invokeMethod<String>(
        'inferVlm',
        {
          'question': question,
          if (imageBytes != null) 'image': imageBytes,
        },
      ).timeout(const Duration(seconds: 30));

      if (result != null && result.isNotEmpty) {
        _state = VlmState.answering;
        try {
          onAnswer?.call(ExternalHazardEvent(
            source: ExternalHazardSource.vlmCompanion,
            text: result,
            priority: SpeechPriority.info,
            category: AlertCategory.acousticEvent,
            urgency: 0.3,
            at: DateTime.now(),
            correlationId: 'vlm_answer',
          ));
        } catch (_) {}
        FieldLogger.instance.logVlmCompanion('answer', data: {
          'len': result.length,
        });
      } else if (fallbackNarration != null) {
        _emitFallback(fallbackNarration);
      }
    } on TimeoutException {
      FieldLogger.instance.logVlmCompanion('timeout');
      if (fallbackNarration != null) {
        _emitFallback(fallbackNarration);
      }
    } catch (e) {
      _state = VlmState.error;
      FieldLogger.instance.logVlmCompanion('infer_error', data: {
        'error': e.toString(),
      });
      if (fallbackNarration != null) {
        _emitFallback(fallbackNarration);
      }
    } finally {
      if (_state != VlmState.error) _state = VlmState.idle;
    }
  }

  /// Cancel any running inference.
  Future<void> cancelInference() async {
    if (_state != VlmState.inferring) return;
    try {
      await _channel.invokeMethod<void>('cancelVlm');
    } catch (_) {}
    _state = VlmState.idle;
    FieldLogger.instance.logVlmCompanion('cancelled');
  }

  /// Unload the VLM model from memory.
  Future<void> unloadModel() async {
    if (!_modelLoaded) return;
    try {
      await _channel.invokeMethod<void>('unloadVlmModel');
    } catch (_) {}
    _releaseModel();
    FieldLogger.instance.logVlmCompanion('model_unloaded');
  }

  void dispose() {
    unawaited(cancelInference());
    unawaited(unloadModel());
  }

  void _emitFallback(String text) {
    if (onAnswer != null) {
      onAnswer!.call(ExternalHazardEvent(
        source: ExternalHazardSource.vlmCompanion,
        text: text,
        priority: SpeechPriority.info,
        category: AlertCategory.acousticEvent,
        urgency: 0.2,
        at: DateTime.now(),
        correlationId: 'vlm_fallback',
      ));
    } else {
      FieldLogger.instance.logVlmCompanion('fallback_no_handler', data: {
        'text_len': text.length,
      });
    }
  }

  void _releaseModel() {
    _modelLoaded = false;
    _state = VlmState.idle;
    SensorSessionCoordinator.instance.release(_modelLease);
    _modelLease = null;
  }

  @visibleForTesting
  void resetForTesting() {
    _state = VlmState.idle;
    _modelLoaded = false;
    SensorSessionCoordinator.instance.release(_modelLease);
    _modelLease = null;
  }
}

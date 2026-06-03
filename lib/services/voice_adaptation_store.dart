import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'field_logger.dart';
import 'settings_service.dart';

/// A single successful voice command sample retained for future
/// on-device ASR adaptation (LoRA training). No raw audio in v1 —
/// only metadata. Audio features come after explicit opt-in UX.
class VoiceAdaptationSample {
  /// Two-letter locale code active at recognition time.
  final String locale;

  /// The recognised transcript (final result string).
  final String transcript;

  /// Name of the `VoiceCommand` enum value that matched.
  final String commandId;

  /// Backend-reported confidence, if available. Null otherwise.
  final double? confidence;

  /// When the recognition happened.
  final DateTime at;

  const VoiceAdaptationSample({
    required this.locale,
    required this.transcript,
    required this.commandId,
    required this.at,
    this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'l': locale,
        't': transcript,
        'c': commandId,
        'ts': at.millisecondsSinceEpoch,
        if (confidence != null) 'cf': confidence,
      };

  factory VoiceAdaptationSample.fromJson(Map<String, dynamic> json) =>
      VoiceAdaptationSample(
        locale: json['l'] as String,
        transcript: json['t'] as String,
        commandId: json['c'] as String,
        at: DateTime.fromMillisecondsSinceEpoch((json['ts'] as num).toInt()),
        confidence:
            json['cf'] == null ? null : (json['cf'] as num).toDouble(),
      );
}

/// Encrypted-capable, deletable, quota-bounded local store for
/// successful voice command samples. All data stays on-device; never
/// uploaded unless a future federated opt-in exists.
///
/// Writes only when `SettingsService.localAsrAdaptation` is true.
/// Fire-and-forget from the voice command dispatch path.
///
/// Phase 1 — Direction 12 foundations. The store lifecycle, consent,
/// deletion, and quota enforcement ship first; on-device LoRA training
/// comes after backend stability.
class VoiceAdaptationStore {
  VoiceAdaptationStore._();

  static final VoiceAdaptationStore instance = VoiceAdaptationStore._();

  /// Hard cap on the number of samples stored. FIFO eviction when
  /// exceeded. 500 samples × ~200 bytes ≈ 100 KB — negligible.
  static const int kMaxSamples = 500;

  static const String _kFileName = 'bagdar_voice_adaptation.json';

  File? _fileCached;
  List<VoiceAdaptationSample>? _cache;

  Future<File> _file() async {
    final cached = _fileCached;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/$_kFileName');
    _fileCached = file;
    return file;
  }

  /// Record a successful voice command recognition. No-op when the
  /// feature flag is off or the command was `unknown`.
  Future<void> record({
    required String locale,
    required String transcript,
    required String commandId,
    double? confidence,
  }) async {
    if (!Settings.instance.localAsrAdaptation) return;
    if (commandId == 'unknown' || transcript.trim().isEmpty) return;

    try {
      final samples = await _loadCache();
      samples.add(VoiceAdaptationSample(
        locale: locale,
        transcript: transcript.trim(),
        commandId: commandId,
        at: DateTime.now(),
        confidence: confidence,
      ));

      
      while (samples.length > kMaxSamples) {
        samples.removeAt(0);
      }

      await _persist(samples);

      FieldLogger.instance.log('voice_adapt_record', {
        'locale': locale,
        'cmd': commandId,
        'count': samples.length,
      });
    } catch (e) {
      debugPrint('VoiceAdaptationStore.record error: $e');
    }
  }

  /// Total number of stored samples.
  Future<int> sampleCount() async {
    final samples = await _loadCache();
    return samples.length;
  }

  /// Delete all stored samples. Idempotent.
  Future<void> deleteAll() async {
    try {
      final file = await _file();
      if (file.existsSync()) {
        await file.delete();
      }
      _cache = <VoiceAdaptationSample>[];
      FieldLogger.instance.log('voice_adapt_cleared', {});
    } catch (e) {
      debugPrint('VoiceAdaptationStore.deleteAll error: $e');
    }
  }

  /// Export all samples as a JSON list. Used by future training
  /// harness; never called by the main app in v1.
  Future<List<Map<String, dynamic>>> export() async {
    final samples = await _loadCache();
    return samples.map((s) => s.toJson()).toList();
  }

  
  Future<List<VoiceAdaptationSample>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!file.existsSync()) {
        _cache = <VoiceAdaptationSample>[];
        return _cache!;
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .whereType<Map<String, dynamic>>()
          .map(VoiceAdaptationSample.fromJson)
          .toList();
    } catch (e) {
      debugPrint('VoiceAdaptationStore._loadCache error: $e');
      _cache = <VoiceAdaptationSample>[];
    }
    return _cache!;
  }

  Future<void> _persist(List<VoiceAdaptationSample> samples) async {
    try {
      final file = await _file();
      final json = jsonEncode(samples.map((s) => s.toJson()).toList());
      await file.writeAsString(json, flush: true);
    } catch (e) {
      debugPrint('VoiceAdaptationStore._persist error: $e');
    }
  }

  @visibleForTesting
  void debugClearCache() {
    _cache = null;
    _fileCached = null;
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/constants.dart';
import 'field_logger.dart';

/// A single near-miss event captured by explicit voice command or safe
/// UI action. Stores short multimodal context (no raw images or audio)
/// with strict quotas and deletion support.
///
/// Phase 3 — Direction 4. Local-only; never uploaded unless a future
/// federated opt-in exists.
class NearMissRecord {
  final String id;
  final DateTime at;
  final String triggerSource;
  final List<String> labels;
  final double? closestDistM;
  final String? hazardType;
  final double? depthScore;
  final String? acousticClass;
  final double? lat;
  final double? lng;
  final String? userNote;

  const NearMissRecord({
    required this.id,
    required this.at,
    required this.triggerSource,
    required this.labels,
    this.closestDistM,
    this.hazardType,
    this.depthScore,
    this.acousticClass,
    this.lat,
    this.lng,
    this.userNote,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'src': triggerSource,
    'labels': labels,
    if (closestDistM != null) 'distM': closestDistM,
    if (hazardType != null) 'hazType': hazardType,
    if (depthScore != null) 'depth': depthScore,
    if (acousticClass != null) 'acoustic': acousticClass,
    if (lat != null) 'lat': lat,
    if (lng != null) 'lng': lng,
    if (userNote != null) 'note': userNote,
  };

  factory NearMissRecord.fromJson(Map<String, dynamic> json) => NearMissRecord(
    id: json['id'] as String,
    at: DateTime.fromMillisecondsSinceEpoch((json['at'] as num).toInt()),
    triggerSource: json['src'] as String? ?? 'unknown',
    labels:
        (json['labels'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        const [],
    closestDistM: (json['distM'] as num?)?.toDouble(),
    hazardType: json['hazType'] as String?,
    depthScore: (json['depth'] as num?)?.toDouble(),
    acousticClass: json['acoustic'] as String?,
    lat: (json['lat'] as num?)?.toDouble(),
    lng: (json['lng'] as num?)?.toDouble(),
    userNote: json['note'] as String?,
  );
}

/// Quota-bounded, deletable local buffer for near-miss events.
///
/// Captures multimodal context when the user explicitly triggers a
/// near-miss report (voice command or safe UI action). No automatic
/// capture — this is always opt-in.
///
/// Data lifecycle:
/// - Maximum [kMaxRecords] records (FIFO eviction).
/// - All data stays on device.
/// - [deleteAll] wipes the entire store immediately.
/// - [deleteRecord] removes a single record by id.
///
/// Future training scheduler reads from this store to prototype tiny
/// adapter files for the YOLO classification head.
class NearMissBuffer {
  NearMissBuffer._();

  static final NearMissBuffer instance = NearMissBuffer._();

  static const String _kFileName = 'bagdar_near_miss.json';

  File? _fileCached;
  List<NearMissRecord>? _cache;

  Future<File> _file() async {
    final cached = _fileCached;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final file = File('${docs.path}/$_kFileName');
    _fileCached = file;
    return file;
  }

  /// Record a near-miss event. No-op when the command was not explicit.
  Future<void> record({
    required String triggerSource,
    required List<String> labels,
    double? closestDistM,
    String? hazardType,
    double? depthScore,
    String? acousticClass,
    double? lat,
    double? lng,
    String? userNote,
  }) async {
    try {
      final records = await _loadCache();
      final now = DateTime.now();
      records.add(
        NearMissRecord(
          id: 'nm_${now.millisecondsSinceEpoch.toRadixString(36)}',
          at: now,
          triggerSource: triggerSource,
          labels: labels,
          closestDistM: closestDistM,
          hazardType: hazardType,
          depthScore: depthScore,
          acousticClass: acousticClass,
          lat: lat,
          lng: lng,
          userNote: userNote,
        ),
      );

      while (records.length > kNearMissMaxRecords) {
        records.removeAt(0);
      }

      await _persist(records);

      FieldLogger.instance.log('near_miss_recorded', {
        'source': triggerSource,
        'labels': labels.length,
        'count': records.length,
      });
    } catch (e) {
      debugPrint('NearMissBuffer.record error: $e');
    }
  }

  Future<int> recordCount() async {
    final records = await _loadCache();
    return records.length;
  }

  Future<List<NearMissRecord>> all() async {
    return List.unmodifiable(await _loadCache());
  }

  Future<void> deleteRecord(String id) async {
    try {
      final records = await _loadCache();
      records.removeWhere((r) => r.id == id);
      await _persist(records);
    } catch (e) {
      debugPrint('NearMissBuffer.deleteRecord error: $e');
    }
  }

  Future<void> deleteAll() async {
    try {
      final file = await _file();
      if (file.existsSync()) {
        await file.delete();
      }
      _cache = <NearMissRecord>[];
      FieldLogger.instance.log('near_miss_cleared', {});
    } catch (e) {
      debugPrint('NearMissBuffer.deleteAll error: $e');
    }
  }

  Future<List<Map<String, dynamic>>> export() async {
    final records = await _loadCache();
    return records.map((r) => r.toJson()).toList();
  }

  Future<List<NearMissRecord>> _loadCache() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (!file.existsSync()) {
        _cache = <NearMissRecord>[];
        return _cache!;
      }
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      _cache = list
          .whereType<Map<String, dynamic>>()
          .map(NearMissRecord.fromJson)
          .toList();
    } catch (e) {
      debugPrint('NearMissBuffer._loadCache error: $e');
      _cache = <NearMissRecord>[];
    }
    return _cache!;
  }

  Future<void> _persist(List<NearMissRecord> records) async {
    try {
      final file = await _file();
      final json = jsonEncode(records.map((r) => r.toJson()).toList());
      await file.writeAsString(json, flush: true);
    } catch (e) {
      debugPrint('NearMissBuffer._persist error: $e');
    }
  }

  @visibleForTesting
  void debugClearCache() {
    _cache = null;
    _fileCached = null;
  }
}

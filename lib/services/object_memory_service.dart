import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../tracker/appearance.dart';
import '../tracker/track.dart';
import 'earcon_service.dart';
import 'tts_service.dart';

class RememberedObject {
  final String name;
  final Float32List embedding;
  int sampleCount;
  final DateTime createdAt;
  DateTime updatedAt;
  final String backendId;

  RememberedObject({
    required this.name,
    required this.embedding,
    required this.sampleCount,
    required this.createdAt,
    required this.updatedAt,
    required this.backendId,
  });

  Map<String, dynamic> toJson() {
    final bytes = embedding.buffer.asUint8List(
      embedding.offsetInBytes,
      embedding.lengthInBytes,
    );
    return {
      'name': name,
      'embedding': base64Encode(bytes),
      'sampleCount': sampleCount,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'backendId': backendId,
    };
  }

  static RememberedObject? fromJson(Map<String, dynamic> j) {
    try {
      final name = (j['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) return null;
      final encoded = j['embedding'] as String?;
      if (encoded == null || encoded.isEmpty) return null;
      final bytes = base64Decode(encoded);
      final byteData = ByteData.sublistView(bytes);
      final dim = bytes.lengthInBytes ~/ 4;
      final emb = Float32List(dim);
      for (int i = 0; i < dim; i++) {
        emb[i] = byteData.getFloat32(i * 4, Endian.host);
      }
      return RememberedObject(
        name: name,
        embedding: emb,
        sampleCount: (j['sampleCount'] as int?) ?? 1,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        backendId: (j['backendId'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

abstract class EmbeddingBackend {
  String get id;
  int get dim;
  double get matchThreshold;

  Float32List? embedFromYPlane({
    required Uint8List yPlane,
    required int rowStride,
    required int imgW,
    required int imgH,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  });

  double similarity(Float32List a, Float32List b);

  Float32List blend(
    Float32List existing,
    Float32List update, {
    double alpha = kObjectMemoryBlendAlpha,
  });
}

class YHistogramBackend implements EmbeddingBackend {
  @override
  String get id => 'yhist_v1';

  @override
  int get dim => kObjectMemoryEmbedDimYHist;

  @override
  double get matchThreshold => kObjectMemoryYHistMatchThreshold;

  @override
  Float32List? embedFromYPlane({
    required Uint8List yPlane,
    required int rowStride,
    required int imgW,
    required int imgH,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
  }) {
    return Appearance.extractFromYPlane(
      yPlane: yPlane,
      rowStride: rowStride,
      imgW: imgW,
      imgH: imgH,
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
    );
  }

  @override
  double similarity(Float32List a, Float32List b) =>
      Appearance.similarity(a, b);

  @override
  Float32List blend(
    Float32List existing,
    Float32List update, {
    double alpha = kObjectMemoryBlendAlpha,
  }) =>
      Appearance.blend(existing, update, alpha: alpha);
}

class _RememberState {
  final String name;
  final DateTime startedAt;
  final List<Float32List> candidates = [];
  _RememberState(this.name, this.startedAt);
}

class ObjectMemoryService {
  EmbeddingBackend backend = YHistogramBackend();

  final Map<String, RememberedObject> _items = {};
  _RememberState? _remember;

  TtsService? _tts;
  EarconService? _earcon;
  String? _filePath;
  bool _initialized = false;

  bool get isReady => _initialized;
  bool get rememberActive => _remember != null;
  int get itemCount => _items.length;
  Iterable<RememberedObject> get items => _items.values;

  Future<void> init({TtsService? tts, EarconService? earcon}) async {
    _tts = tts;
    _earcon = earcon;
    try {
      final dir = await getApplicationDocumentsDirectory();
      _filePath = '${dir.path}/object_memory.json';
      await _load();
    } catch (e) {
      debugPrint('ObjectMemoryService.init: $e');
    }
    _initialized = true;
  }

  Future<void> _load() async {
    final path = _filePath;
    if (path == null) return;
    try {
      final f = File(path);
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;
      final items = data['items'];
      if (items is! List) return;
      _items.clear();
      for (final j in items) {
        if (j is! Map<String, dynamic>) continue;
        final ro = RememberedObject.fromJson(j);
        if (ro == null) continue;
        if (ro.backendId != backend.id) continue;
        if (ro.embedding.length != backend.dim) continue;
        _items[ro.name] = ro;
      }
    } catch (e) {
      debugPrint('ObjectMemoryService._load: $e');
    }
  }

  Future<void> _save() async {
    final path = _filePath;
    if (path == null) return;
    try {
      final data = {
        'version': 1,
        'backendId': backend.id,
        'items': _items.values.map((r) => r.toJson()).toList(),
      };
      await File(path).writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('ObjectMemoryService._save: $e');
    }
  }

  static String normalizeName(String raw) {
    var s = raw.toLowerCase().trim();
    const prefixes = [
      'мой ',
      'моя ',
      'моё ',
      'мое ',
      'мои ',
      'my ',
      'менің ',
      'meniñ ',
    ];
    for (final p in prefixes) {
      if (s.startsWith(p)) {
        s = s.substring(p.length).trim();
        break;
      }
    }
    return s;
  }

  bool contains(String rawName) =>
      _items.containsKey(normalizeName(rawName));

  RememberedObject? get(String rawName) => _items[normalizeName(rawName)];

  Future<bool> startRemember(String rawName) async {
    final name = normalizeName(rawName);
    if (name.isEmpty) return false;
    if (!_items.containsKey(name) &&
        _items.length >= kObjectMemoryMaxItems) {
      _tts?.say(
        S.get('obj_remember_capacity'),
        SpeechPriority.warning,
        pan: 0.0,
      );
      return false;
    }
    _remember = _RememberState(name, DateTime.now());
    _tts?.say(
      S.get('obj_remember_listening').replaceAll('{name}', name),
      SpeechPriority.info,
      pan: 0.0,
    );
    return true;
  }

  void cancelRemember() {
    _remember = null;
  }

  void onTracks(List<Track> tracks, int imgW, int imgH) {
    final state = _remember;
    if (state == null || imgW <= 0 || imgH <= 0) return;
    if (_isExpired(state)) {
      _failRemember();
      return;
    }
    final emb = _bestTrackEmbedding(tracks, imgW, imgH);
    if (emb != null) _addCandidate(state, emb);
  }

  void feed(CameraImage image, DateTime now) {
    final state = _remember;
    if (state == null) return;
    if (_isExpired(state)) {
      _failRemember();
      return;
    }
    if (image.planes.isEmpty) return;
    final emb = _centerCropEmbedding(image);
    if (emb != null) _addCandidate(state, emb);
  }

  bool _isExpired(_RememberState state) {
    return DateTime.now().difference(state.startedAt).inMilliseconds >
        kObjectMemoryRememberTimeoutMs;
  }

  Float32List? _bestTrackEmbedding(
    List<Track> tracks,
    int imgW,
    int imgH,
  ) {
    final w = imgW.toDouble();
    final h = imgH.toDouble();
    final marginX = w * (1 - kObjectMemoryRememberCentralityRatio) / 2;
    final marginY = h * (1 - kObjectMemoryRememberCentralityRatio) / 2;
    final cxMin = marginX;
    final cxMax = w - marginX;
    final cyMin = marginY;
    final cyMax = h - marginY;
    final frameArea = w * h;

    Track? best;
    double bestArea = 0.0;
    for (final t in tracks) {
      final emb = t.appearance;
      if (emb == null) continue;
      if (t.avgConf < 0.5) continue;
      if (t.cx < cxMin || t.cx > cxMax) continue;
      if (t.cy < cyMin || t.cy > cyMax) continue;
      final area = (t.x2 - t.x1) * (t.y2 - t.y1);
      if (area / frameArea < kObjectMemoryRememberMinAreaRatio) continue;
      if (area > bestArea) {
        bestArea = area;
        best = t;
      }
    }
    final src = best?.appearance;
    if (src == null) return null;
    return Float32List.fromList(src);
  }

  Float32List? _centerCropEmbedding(CameraImage image) {
    final yPlane = image.planes[0];
    final w = image.width.toDouble();
    final h = image.height.toDouble();
    final cropW = w * kObjectFinderCenterCropRatio;
    final cropH = h * kObjectFinderCenterCropRatio;
    final x1 = (w - cropW) / 2;
    final y1 = (h - cropH) / 2;
    return backend.embedFromYPlane(
      yPlane: yPlane.bytes,
      rowStride: yPlane.bytesPerRow,
      imgW: image.width,
      imgH: image.height,
      x1: x1,
      y1: y1,
      x2: x1 + cropW,
      y2: y1 + cropH,
    );
  }

  void _addCandidate(_RememberState state, Float32List emb) {
    if (state.candidates.isEmpty) {
      state.candidates.add(emb);
      return;
    }
    final sim = backend.similarity(state.candidates.first, emb);
    if (sim < kObjectMemoryRememberStableSimilarity) return;
    state.candidates.add(emb);
    if (state.candidates.length >= kObjectMemoryRememberMinFrames) {
      _commitRemember(state);
    }
  }

  void _commitRemember(_RememberState state) {
    final n = state.candidates.length;
    final dim = state.candidates.first.length;
    final avg = Float32List(dim);
    for (final c in state.candidates) {
      for (int i = 0; i < dim; i++) {
        avg[i] += c[i];
      }
    }
    final invN = 1.0 / n;
    for (int i = 0; i < dim; i++) {
      avg[i] *= invN;
    }

    final now = DateTime.now();
    final existing = _items[state.name];
    if (existing != null) {
      final blended = backend.blend(existing.embedding, avg);
      existing.embedding.setAll(0, blended);
      existing.sampleCount += n;
      existing.updatedAt = now;
    } else {
      if (_items.length >= kObjectMemoryMaxItems) {
        _evictLru();
      }
      _items[state.name] = RememberedObject(
        name: state.name,
        embedding: avg,
        sampleCount: n,
        createdAt: now,
        updatedAt: now,
        backendId: backend.id,
      );
    }

    _remember = null;
    _tts?.say(
      S.get('obj_remember_saved').replaceAll('{name}', state.name),
      SpeechPriority.info,
      pan: 0.0,
    );
    _earcon?.play(Earcon.success);
    unawaited(_save());
  }

  void _failRemember() {
    _remember = null;
    _tts?.say(
      S.get('obj_remember_failed'),
      SpeechPriority.info,
      pan: 0.0,
    );
    _earcon?.play(Earcon.fail);
  }

  void _evictLru() {
    if (_items.isEmpty) return;
    String? oldestKey;
    DateTime oldestTs = DateTime.now();
    var first = true;
    _items.forEach((k, v) {
      if (first || v.updatedAt.isBefore(oldestTs)) {
        oldestTs = v.updatedAt;
        oldestKey = k;
        first = false;
      }
    });
    final key = oldestKey;
    if (key != null) _items.remove(key);
  }

  Future<bool> forget(String rawName) async {
    final name = normalizeName(rawName);
    final removed = _items.remove(name);
    if (removed == null) {
      _tts?.say(
        S.get('obj_forget_unknown').replaceAll('{name}', name),
        SpeechPriority.info,
        pan: 0.0,
      );
      return false;
    }
    _tts?.say(
      S.get('obj_forget_done').replaceAll('{name}', name),
      SpeechPriority.info,
      pan: 0.0,
    );
    await _save();
    return true;
  }

  void dispose() {
    _remember = null;
  }
}

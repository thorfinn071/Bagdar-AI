import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/haptic_service.dart';
import '../services/object_memory_service.dart';
import '../services/tts_service.dart';
import '../tracker/track.dart';
import '../utils/distance_utils.dart';

enum _Side { left, center, right }

class _MatchCandidate {
  final double score;
  final _Side side;
  final double pan;
  final String direction;
  final double? distM;
  final bool isCenterCrop;

  const _MatchCandidate({
    required this.score,
    required this.side,
    required this.pan,
    required this.direction,
    required this.distM,
    required this.isCenterCrop,
  });
}

class ObjectFinderSession {
  final TtsService tts;
  final EarconService earcon;
  final ObjectMemoryService memory;

  ObjectFinderSession({
    required this.tts,
    required this.earcon,
    required this.memory,
  });

  String? _targetName;
  Float32List? _targetEmbedding;
  DateTime _startedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastHapticAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastSeenAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastLostAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFeedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _steadyCloseFrames = 0;

  List<Track> _lastTracks = const [];
  int _lastImgW = 0;
  int _lastImgH = 0;

  bool get active => _targetEmbedding != null;
  String? get targetName => _targetName;

  bool start(String rawName) {
    if (memory.rememberActive) {
      tts.say(
        S.get('obj_busy_remembering'),
        SpeechPriority.info,
        pan: 0.0,
      );
      return false;
    }
    final target = memory.get(rawName);
    if (target == null) {
      final normalized = ObjectMemoryService.normalizeName(rawName);
      tts.say(
        S
            .get('obj_unknown_target')
            .replaceAll('{name}', normalized),
        SpeechPriority.info,
        pan: 0.0,
      );
      return false;
    }
    final wasActive = active;
    _targetName = target.name;
    _targetEmbedding = Float32List.fromList(target.embedding);
    final now = DateTime.now();
    _startedAt = now;
    _lastTtsAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastHapticAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastSeenAt = now;
    _lastLostAt = DateTime.fromMillisecondsSinceEpoch(0);
    _steadyCloseFrames = 0;
    if (!wasActive) {
      tts.say(
        S
            .get('obj_find_started')
            .replaceAll('{name}', target.name),
        SpeechPriority.info,
        pan: 0.0,
      );
    }
    return true;
  }

  void stop({bool announce = true}) {
    if (!active) return;
    _targetEmbedding = null;
    _targetName = null;
    _lastTracks = const [];
    if (announce) {
      tts.say(
        S.get('obj_find_stopped'),
        SpeechPriority.info,
        pan: 0.0,
      );
    }
  }

  void onTracks(List<Track> tracks, int imgW, int imgH) {
    if (!active) return;
    _lastTracks = tracks;
    _lastImgW = imgW;
    _lastImgH = imgH;
  }

  void feed(CameraImage image, DateTime now) {
    final target = _targetEmbedding;
    if (target == null) return;
    if (now.difference(_startedAt).inMilliseconds >
        kObjectFinderMaxSessionMs) {
      stop();
      return;
    }
    if (now.difference(_lastFeedAt) < kObjectFinderFeedThrottle) return;
    _lastFeedAt = now;

    final imgW = image.width;
    final imgH = image.height;
    if (_lastImgW == 0) _lastImgW = imgW;
    if (_lastImgH == 0) _lastImgH = imgH;

    final best = _scoreFrame(image, target, imgW, imgH);
    final tau = memory.backend.matchThreshold;

    if (best != null && best.score >= tau) {
      _onMatch(best, now);
    } else {
      _onNoMatch(now);
    }
  }

  _MatchCandidate? _scoreFrame(
    CameraImage image,
    Float32List target,
    int imgW,
    int imgH,
  ) {
    _MatchCandidate? best;

    for (final t in _lastTracks) {
      final emb = t.appearance;
      if (emb == null) continue;
      final s = memory.backend.similarity(target, emb);
      if (best != null && s <= best.score) continue;
      final pan = imgW > 0
          ? (((t.cx / imgW) * 2.0 - 1.0).clamp(-1.0, 1.0)).toDouble()
          : 0.0;
      final dir = clockDir(t.x1, t.x2, imgW.toDouble());
      final side = _sideForCx(t.cx, imgW);
      best = _MatchCandidate(
        score: s,
        side: side,
        pan: pan,
        direction: dir,
        distM: t.distM > 0 ? t.distM : null,
        isCenterCrop: false,
      );
    }

    if (image.planes.isNotEmpty) {
      final yPlane = image.planes[0];
      final w = imgW.toDouble();
      final h = imgH.toDouble();
      final cropW = w * kObjectFinderCenterCropRatio;
      final cropH = h * kObjectFinderCenterCropRatio;
      final x1 = (w - cropW) / 2;
      final y1 = (h - cropH) / 2;
      final emb = memory.backend.embedFromYPlane(
        yPlane: yPlane.bytes,
        rowStride: yPlane.bytesPerRow,
        imgW: imgW,
        imgH: imgH,
        x1: x1,
        y1: y1,
        x2: x1 + cropW,
        y2: y1 + cropH,
      );
      if (emb != null) {
        final s = memory.backend.similarity(target, emb);
        if (best == null || s > best.score) {
          best = _MatchCandidate(
            score: s,
            side: _Side.center,
            pan: 0.0,
            direction: S.dir('forward'),
            distM: null,
            isCenterCrop: true,
          );
        }
      }
    }

    return best;
  }

  void _onMatch(_MatchCandidate best, DateTime now) {
    _lastSeenAt = now;
    _lastLostAt = DateTime.fromMillisecondsSinceEpoch(0);

    final tau = memory.backend.matchThreshold;
    final foundScoreT = (tau + (1.0 - tau) * 0.55).clamp(tau, 0.99);
    final isClose = (best.distM != null && best.distM! <= kObjectFinderFoundDistM) ||
        (best.isCenterCrop && best.score >= foundScoreT);
    if (best.score >= foundScoreT && isClose) {
      _steadyCloseFrames++;
      if (_steadyCloseFrames >= kObjectFinderFoundSteadyFrames) {
        _emitFound();
        return;
      }
    } else {
      _steadyCloseFrames = 0;
    }

    if (now.difference(_lastHapticAt) >= kObjectFinderHapticCooldown) {
      _lastHapticAt = now;
      _emitHaptic(best.side, best.distM);
    }

    if (now.difference(_lastTtsAt) >= kObjectFinderTtsCooldown) {
      _lastTtsAt = now;
      final name = _targetName ?? '';
      String msg;
      if (best.distM != null) {
        final distStr = best.distM! >= 10
            ? best.distM!.toStringAsFixed(0)
            : best.distM!.toStringAsFixed(1);
        msg = S
            .get('obj_find_position')
            .replaceAll('{name}', name)
            .replaceAll('{dist}', distStr)
            .replaceAll('{dir}', best.direction);
      } else {
        msg = S
            .get('obj_find_position_no_dist')
            .replaceAll('{name}', name)
            .replaceAll('{dir}', best.direction);
      }
      tts.say(msg, SpeechPriority.info, pan: best.pan);
    }
  }

  void _onNoMatch(DateTime now) {
    _steadyCloseFrames = 0;
    final sinceSeen = now.difference(_lastSeenAt).inMilliseconds;
    if (sinceSeen < kObjectFinderLostAnnounceMs) return;
    final sinceLost = now.difference(_lastLostAt).inMilliseconds;
    if (sinceLost < kObjectFinderLostAnnounceMs) return;
    _lastLostAt = now;
    final name = _targetName ?? '';
    tts.say(
      S.get('obj_find_lost').replaceAll('{name}', name),
      SpeechPriority.info,
      pan: 0.0,
    );
  }

  void _emitFound() {
    final name = _targetName ?? '';
    earcon.play(Earcon.success);
    tts.say(
      S.get('obj_find_found').replaceAll('{name}', name),
      SpeechPriority.critical,
      pan: 0.0,
    );
    _targetEmbedding = null;
    _targetName = null;
    _lastTracks = const [];
    _steadyCloseFrames = 0;
  }

  Future<void> _emitHaptic(_Side side, double? distM) async {
    final close = distM != null && distM <= 1.5;
    final List<int> pattern;
    switch (side) {
      case _Side.left:
        pattern = close ? kHapticCloseLeft : kHapticFarLeft;
        break;
      case _Side.right:
        pattern = close ? kHapticCloseRight : kHapticFarRight;
        break;
      case _Side.center:
        pattern = close ? kHapticCloseCenter : kHapticFarCenter;
        break;
    }
    await HapticService.vibrate(pattern);
  }

  _Side _sideForCx(double cx, int imgW) {
    if (imgW <= 0) return _Side.center;
    final n = cx / imgW;
    if (n < 0.38) return _Side.left;
    if (n > 0.62) return _Side.right;
    return _Side.center;
  }

  void dispose() {
    _targetEmbedding = null;
    _targetName = null;
    _lastTracks = const [];
  }
}

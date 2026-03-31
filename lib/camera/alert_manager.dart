import 'package:vibration/vibration.dart';

import '../models/app_mode.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/tts_service.dart';
import '../tracker/track.dart';
import '../utils/alert_filter.dart';
import '../utils/decision_engine.dart';
import '../utils/distance_utils.dart';

class AlertManager {
  final TtsService _tts;
  final EarconService _earcon;
  final AlertFilter _filter = AlertFilter();
  final DecisionEngine _engine = DecisionEngine();

  AlertManager({
    required TtsService tts,
    required EarconService earcon,
  })  : _tts = tts,
        _earcon = earcon;

  DateTime _lastApproachSay = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastGuideSay = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastGuideText = '';
  DateTime _objectLastSeen = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _emptySince = DateTime.fromMillisecondsSinceEpoch(0);
  bool _clearAnnounced = false;
  DateTime _lastCriticalAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _guidanceGiven = false;

  String _pendingHint = '';
  int _pendingHintFrames = 0;

  final Set<int> _prevCloseTrackIds = {};

  DateTime _lastVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCaneVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime get lastCriticalAt => _lastCriticalAt;

  void updateLastCriticalAt(DateTime t) => _lastCriticalAt = t;

  void reset() {
    _filter.reset();
    _engine.reset();
    _guidanceGiven = false;
    _lastGuideText = '';
    _pendingHint = '';
    _pendingHintFrames = 0;
    _lastCaneVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);
    _prevCloseTrackIds.clear();
  }

  Track? processFrame({
    required List<Track> tracks,
    required int imgW,
    required int imgH,
    required DateTime now,
    required AppMode mode,
    required bool isCalibrated,
    required int frameCount,
  }) {
    final hasTracks = tracks.isNotEmpty;

    if (mode == AppMode.street) {
      final currentCloseIds = <int>{};
      for (final t in tracks) {
        if (t.dist == 'close' || t.dist == 'very close') {
          currentCloseIds.add(t.id);
        }
      }
      final departed = _prevCloseTrackIds.difference(currentCloseIds);
      if (departed.isNotEmpty) _earcon.play(Earcon.objectLeft);
      _prevCloseTrackIds
        ..clear()
        ..addAll(currentCloseIds);
    }

    if (hasTracks) {
      _objectLastSeen = now;
      _emptySince = DateTime.fromMillisecondsSinceEpoch(0);
      _clearAnnounced = false;
    } else {
      if (_emptySince.millisecondsSinceEpoch == 0) _emptySince = now;
    }

    if (!hasTracks) {
      _handleEmpty(now, mode);
      return null;
    }

    if (mode == AppMode.cane) {
      _handleCaneMode(tracks, now, imgW, imgH);
      return null;
    }

    if (mode == AppMode.scan) return null;

    final frameArea = (imgW * imgH).toDouble();
    final frameScores = <int, double>{};
    for (final t in tracks) {
      final ar = frameArea > 0
          ? ((t.x2 - t.x1) * (t.y2 - t.y1)) / frameArea
          : 0.0;
      frameScores[t.id] = threatScore(
        t.label, posFromCx(t.cx, imgW.toDouble()), t.dist, ar,
      );
    }

    _handleApproaching(tracks, frameScores, imgW, now);
    _handleVeryClose(tracks, frameScores, imgW, now, isCalibrated);
    _handleCloseFar(tracks, frameScores, imgW, now, isCalibrated);
    _handleNavHint(tracks, imgW, imgH, now);

    final winner = _filter.flush(tracks.length, now);
    if (winner != null) {
      _tts.say(winner.text, winner.priority,
          pan: winner.pan, trackId: winner.trackId);
    }

    if (frameCount % 30 == 0) _tts.evictStale();

    return _signTrack(tracks);
  }

  void _handleEmpty(DateTime now, AppMode mode) {
    final emptyFor = now.difference(_emptySince);
    final gapSinceObj = now.difference(_objectLastSeen);

    final confirmDuration = mode == AppMode.cane
        ? kEmptyConfirmDurationCane
        : kEmptyConfirmDuration;
    final recentCritical =
        now.difference(_lastCriticalAt) < kPostCriticalClearDelay;

    if (!_clearAnnounced &&
        emptyFor >= confirmDuration &&
        gapSinceObj >= kClearAnnounceDuration &&
        !recentCritical) {
      if (mode == AppMode.cane) {
        _earcon.play(Earcon.pathClear);
        _tts.say(S.get('path_clear_cane'), SpeechPriority.info, pan: 0.0);
      } else {
        _earcon.play(Earcon.pathClear);
        _tts.say(S.get('path_clear'), SpeechPriority.info, pan: 0.0);
      }
      _clearAnnounced = true;
    }
  }

  void _handleApproaching(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    DateTime now,
  ) {
    Track? top;
    for (final t in tracks) {
      if (!t.approaching) continue;
      if (top == null ||
          (frameScores[t.id] ?? 0) > (frameScores[top.id] ?? 0)) {
        top = t;
      }
    }

    if (top != null &&
        now.difference(_lastApproachSay) >= kApproachCooldown &&
        top.dist != 'very close') {
      _lastApproachSay = now;
      _earcon.play(Earcon.approaching, pan: _pan(top.cx, imgW));
      _filter.add(AlertCandidate(
        text:     '${S.get('transport_approaching')}, '
                  '${clockDir(top.x1, top.x2, imgW.toDouble())}.',
        priority: SpeechPriority.warning,
        pan:      _pan(top.cx, imgW),
        category: AlertCategory.approachingVehicle,
        urgency:  0.85,
      ));
    }
  }

  void _handleVeryClose(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    DateTime now,
    bool isCalibrated,
  ) {
    Track? top;
    for (final t in tracks) {
      if (t.nearFrameCount < 2 && t.dist != 'far') continue;
      if (t.dist != 'very close') continue;
      if (now.difference(t.lastSpoken) < kCriticalCooldown) continue;
      if (t.avgConf < 0.40 && t.reliableFrames < 2) continue;

      final score = (frameScores[t.id] ?? 0) * t.avgConf;
      if (top == null ||
          score > (frameScores[top.id] ?? 0) * top.avgConf) {
        top = t;
      }
    }

    if (top == null) return;

    if (now.difference(_lastCriticalAt) >= kCriticalCooldown) {
      top.lastSpoken  = now;
      _lastCriticalAt = now;
      final dir      = clockDir(top.x1, top.x2, imgW.toDouble());
      final label    = S.label(top.label);
      final distPart = (isCalibrated && top.distM > 0)
          ? ' (~${top.distM.toStringAsFixed(1)} ${S.get('approx_meters')})'
          : '';
      _tts.say(
        '${S.get('stop')}. $label $dir$distPart.',
        SpeechPriority.critical,
        pan: _pan(top.cx, imgW),
      );
      _vibrate([0, 250, 80, 450]);
    } else {
      _vibrate([0, 150]);
    }
  }

  void _handleCloseFar(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    DateTime now,
    bool isCalibrated,
  ) {
    for (final t in tracks) {
      if (t.dist == 'very close') continue;
      if (t.nearFrameCount < 2 && t.dist != 'far') continue;
      if (t.avgConf < kMinAlertConf) continue;
      if (t.reliableFrames < 3 && t.dist == 'far') continue;

      final confFactor   = t.avgConf >= kHighConfLevel ? 1.0 : 1.5;
      final baseCooldown = t.label == 'person'
          ? kPersonCooldown
          : t.dist == 'close' ? kWarningCooldown : kInfoCooldown;
      final cooldown = Duration(
        milliseconds: (baseCooldown.inMilliseconds * confFactor).round(),
      );

      if (now.difference(t.lastSpoken) < cooldown) continue;

      final dir      = clockDir(t.x1, t.x2, imgW.toDouble());
      final label    = S.label(t.label);
      final distPart = (isCalibrated && t.distM > 0)
          ? ' (~${t.distM.toStringAsFixed(1)} ${S.get('approx_meters')})'
          : '';
      final pan   = _pan(t.cx, imgW);
      final score = frameScores[t.id] ?? 0.0;

      if (t.dist == 'close') {
        _vibrate([0, 150]);
        t.lastSpoken = now;
        _filter.add(AlertCandidate(
          text:     '$label ${S.get('close')}, $dir$distPart.',
          priority: SpeechPriority.warning,
          pan:      pan,
          category: AlertCategory.obstacleClose,
          urgency:  score * t.avgConf,
          trackId:  t.id,
        ));
      } else {
        _earcon.play(Earcon.objectAppeared, pan: pan);
        t.lastSpoken = now;
        _filter.add(AlertCandidate(
          text:     '$label $dir.',
          priority: SpeechPriority.info,
          pan:      pan,
          category: AlertCategory.obstacleFar,
          urgency:  score * t.avgConf,
          trackId:  t.id,
        ));
      }
    }
  }

  void _handleNavHint(
    List<Track> tracks,
    int imgW,
    int imgH,
    DateTime now,
  ) {
    final (hint5, centTh, bestTh) =
        bestDirectionHint(tracks, imgW.toDouble(), imgH.toDouble());
    final corridor         = findFreeCorridor(tracks, imgW.toDouble(), imgH.toDouble());
    final corridorDecision = _engine.evaluate(corridor);

    final needGuide = centTh >= kGuideMinCenterThreat &&
        (centTh - bestTh >= kGuideImprovementAbs) &&
        centTh >= bestTh * kGuideImprovementRatio &&
        hint5 != 'forward';

    String? corridorDir;
    if (corridor != null) {
      corridorDir = corridor.$2 == 'left'  ? S.get('nav_left')
                  : corridor.$2 == 'right' ? S.get('nav_right')
                  : null;
    }

    if (corridorDecision != null &&
        corridorDecision.priority == SpeechPriority.critical) {
      _filter.add(AlertCandidate(
        text:     corridorDecision.text,
        priority: SpeechPriority.critical,
        pan:      0.0,
        category: AlertCategory.corridorBlocked,
        urgency:  0.90,
      ));
    }

    String? unifiedHint;
    if (needGuide || corridorDir != null) {
      final dir = corridorDir ?? (needGuide ? hint5 : null);
      if (dir != null) {
        final corridorWidthM = corridor?.$1;
        if (corridorWidthM != null && corridorWidthM >= 0.6) {
          unifiedHint = '${S.get('deviate')} $dir. '
              '${S.get('passage')} ${corridorWidthM.toStringAsFixed(1)} '
              '${S.get('approx_meters')}.';
        } else {
          unifiedHint = '${S.get('deviate')} $dir.';
        }
      }
    }

    if (_guidanceGiven && !needGuide && corridorDir == null) {
      _guidanceGiven     = false;
      _pendingHint       = '';
      _pendingHintFrames = 0;
      _filter.add(AlertCandidate(
        text:     S.get('maneuver_ok'),
        priority: SpeechPriority.info,
        pan:      0.0,
        category: AlertCategory.navigationHint,
        urgency:  0.3,
      ));
    }

    if (unifiedHint != null) {
      if (unifiedHint == _pendingHint) {
        _pendingHintFrames++;
      } else {
        _pendingHint       = unifiedHint;
        _pendingHintFrames = 1;
      }

      final isStable   = _pendingHintFrames >= kHintStableFrames;
      final cooldownOk = now.difference(_lastGuideSay) >= kGuideCooldown;
      final isNew      = unifiedHint != _lastGuideText;

      if (isStable && cooldownOk && isNew) {
        _lastGuideText = unifiedHint;
        _lastGuideSay  = now;
        _guidanceGiven = true;
        _filter.add(AlertCandidate(
          text:     unifiedHint,
          priority: SpeechPriority.info,
          pan:      0.0,
          category: AlertCategory.navigationHint,
          urgency:  0.50,
        ));
      }
    } else {
      if (_pendingHintFrames > 0) {
        _pendingHint       = '';
        _pendingHintFrames = 0;
      }
      if (corridorDecision != null &&
          corridorDecision.priority != SpeechPriority.critical) {
        _filter.add(AlertCandidate(
          text:     corridorDecision.text,
          priority: corridorDecision.priority,
          pan:      corridorDecision.pan,
          category: AlertCategory.corridorNarrow,
          urgency:  0.50,
        ));
      }
    }
  }

  void _handleCaneMode(
    List<Track> tracks,
    DateTime now,
    int imgW,
    int imgH,
  ) {
    if (tracks.isEmpty) return;

    final frameArea = (imgW * imgH).toDouble();
    double score(Track t) => threatScore(
      t.label, posFromCx(t.cx, imgW.toDouble()), t.dist,
      frameArea > 0 ? ((t.x2 - t.x1) * (t.y2 - t.y1)) / frameArea : 0,
    );

    final sorted = List<Track>.from(tracks)
      ..sort((a, b) => score(b).compareTo(score(a)));

    final top    = sorted.first;
    final topPos = posFromCx(top.cx, imgW.toDouble());

    final effectiveDist = (top.dist == 'far' && top.approaching)
        ? 'close'
        : top.dist;

    final cooldown = effectiveDist == 'very close'
        ? kCaneVeryCloseCooldown
        : effectiveDist == 'close'
            ? kCaneCloseCooldown
            : kCaneFarCooldown;

    if (now.difference(top.lastSpoken) >= cooldown) {
      final pattern     = _patternFor(effectiveDist, topPos);
      final intensities = _intensitiesFor(effectiveDist, pattern.length);
      _vibrateCane(pattern, intensities: intensities);

      final dir = clockDir(top.x1, top.x2, imgW.toDouble());
      final pan = _pan(top.cx, imgW);

      if (effectiveDist != 'far') {
        final String ttsText;
        if (effectiveDist == 'very close') {
          ttsText = top.approaching
              ? '${S.get('stop')}! $dir.'
              : '${S.get('stop')}. $dir.';
        } else {
          ttsText = top.approaching
              ? '${S.label(top.label)} ${S.get('approaching')}, $dir.'
              : '$dir.';
        }
        top.lastSpoken = now;
        _tts.say(ttsText, SpeechPriority.info, pan: pan, trackId: top.id);
      } else {
        top.lastSpoken = now;
      }
    }

    if (sorted.length >= 2) {
      final second    = sorted[1];
      if (second.dist != 'far') {
        final secondPos  = posFromCx(second.cx, imgW.toDouble());
        final isOtherSide =
            (topPos == 'left'   && secondPos == 'right')  ||
            (topPos == 'right'  && secondPos == 'left')   ||
            (topPos == 'center' && secondPos != 'center');
        if (isOtherSide &&
            now.difference(second.lastSpoken) >= kCaneCloseCooldown) {
          Future.delayed(const Duration(milliseconds: 300), () {
            _vibrateCane([0, 80]);
          });
        }
      }
    }
  }

  Track? _signTrack(List<Track> tracks) {
    for (final t in tracks) {
      if ((t.label == 'stop sign' || t.label == 'traffic light') &&
          (t.dist == 'close' || t.dist == 'very close') &&
          t.avgConf >= kMinAlertConf &&
          t.reliableFrames >= 2) {
        return t;
      }
    }
    return null;
  }

  Future<void> _vibrate(List<int> pattern) async {
    final now = DateTime.now();
    if (now.difference(_lastVibrateAt) < kVibrateCooldown) return;
    _lastVibrateAt = now;
    try {
      if (!await Vibration.hasVibrator()) return;
      final hasAmp = await Vibration.hasAmplitudeControl();
      if (hasAmp && pattern.length >= 4) {
        Vibration.vibrate(
            pattern: pattern, intensities: const [0, 255, 0, 200]);
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    } catch (_) {}
  }

  Future<void> _vibrateCane(
    List<int> pattern, {
    List<int>? intensities,
  }) async {
    final now = DateTime.now();
    if (now.difference(_lastCaneVibrateAt) < kCaneVibrateCooldown) return;
    _lastCaneVibrateAt = now;
    try {
      if (!await Vibration.hasVibrator()) return;
      final hasAmp = await Vibration.hasAmplitudeControl();
      if (hasAmp && intensities != null) {
        Vibration.vibrate(pattern: pattern, intensities: intensities);
      } else {
        Vibration.vibrate(pattern: pattern);
      }
    } catch (_) {}
  }

  List<int> _patternFor(String dist, String pos) {
    switch (dist) {
      case 'very close':
        if (pos == 'left')  return kHapticVcLeft;
        if (pos == 'right') return kHapticVcRight;
        return kHapticVcCenter;
      case 'close':
        if (pos == 'left')  return kHapticCloseLeft;
        if (pos == 'right') return kHapticCloseRight;
        return kHapticCloseCenter;
      default:
        if (pos == 'left')  return kHapticFarLeft;
        if (pos == 'right') return kHapticFarRight;
        return kHapticFarCenter;
    }
  }

  List<int> _intensitiesFor(String dist, int patternLength) {
    final amp = dist == 'very close' ? 255
              : dist == 'close'      ? 180
              : 100;
    return List.generate(patternLength, (i) => i.isOdd ? amp : 0);
  }

  double _pan(double cx, int imgW) {
    if (imgW == 0) return 0.0;
    return ((cx / imgW).clamp(0.0, 1.0) * 2.0 - 1.0);
  }

  List<int> patternFor(String dist, String pos) => _patternFor(dist, pos);
  List<int> intensitiesFor(String dist, int patternLength) =>
      _intensitiesFor(dist, patternLength);
  Future<void> vibrateCane(List<int> pattern, {List<int>? intensities}) =>
      _vibrateCane(pattern, intensities: intensities);
}

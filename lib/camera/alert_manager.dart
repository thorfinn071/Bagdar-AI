import '../models/app_mode.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart';
import '../services/earcon_service.dart';
import '../services/haptic_service.dart';
import '../services/tts_service.dart';
import '../tracker/track.dart';
import '../tracker/tracker.dart' show isVehicle;
import '../utils/alert_filter.dart';
import '../utils/decision_engine.dart';
import '../utils/distance_utils.dart';

class AlertManager {
  final TtsService _tts;
  final EarconService _earcon;
  final void Function(double? distMeters, double pan)? onProximityChanged;
  final AlertFilter _filter = AlertFilter();
  
  final DecisionEngine _engine = DecisionEngine();
  final bool Function() _isGuideDogMode;
  
  
  
  
  final bool Function() _isIndoorMode;

  AlertManager({
    required TtsService tts,
    required EarconService earcon,
    this.onProximityChanged,
    bool Function()? isGuideDogMode,
    bool Function()? isIndoorMode,
  }) : _tts = tts,
       _earcon = earcon,
       _isGuideDogMode = isGuideDogMode ?? _noGuideDog,
       _isIndoorMode = isIndoorMode ?? _noIndoor;

  static bool _noGuideDog() => false;
  static bool _noIndoor() => false;

  
  
  
  static bool _isGuideDogTrack(Track t, int imgH) {
    if (t.label != 'dog' && t.label != 'cat') return false;
    if (imgH <= 0) return false;
    final h = t.y2 - t.y1;
    if (h < imgH * 0.3) return false;
    if (t.cy < imgH * 0.55) return false;
    return true;
  }

  
  
  
  
  
  
  
  
  static const int _kGuideDogLockFrames = 3;
  static const int _kGuideDogUnlockFrames = 10;
  final Map<int, int> _guideDogCandidateFrames = {};
  final Map<int, int> _guideDogLockedMissing = {};

  bool _isLockedGuideDog(int trackId) =>
      _guideDogLockedMissing.containsKey(trackId);

  void _updateGuideDogLocks(List<Track> tracks, int imgH) {
    final presentIds = <int>{};
    for (final t in tracks) {
      presentIds.add(t.id);
      final passes = _isGuideDogTrack(t, imgH);
      if (_guideDogLockedMissing.containsKey(t.id)) {
        
        _guideDogLockedMissing[t.id] = 0;
        continue;
      }
      if (passes) {
        final c = (_guideDogCandidateFrames[t.id] ?? 0) + 1;
        if (c >= _kGuideDogLockFrames) {
          _guideDogLockedMissing[t.id] = 0;
          _guideDogCandidateFrames.remove(t.id);
        } else {
          _guideDogCandidateFrames[t.id] = c;
        }
      } else {
        
        
        final c = _guideDogCandidateFrames[t.id];
        if (c != null) {
          if (c <= 1) {
            _guideDogCandidateFrames.remove(t.id);
          } else {
            _guideDogCandidateFrames[t.id] = c - 1;
          }
        }
      }
    }
    
    final staleLockIds = <int>[];
    _guideDogLockedMissing.forEach((id, missing) {
      if (presentIds.contains(id)) return;
      final next = missing + 1;
      if (next >= _kGuideDogUnlockFrames) {
        staleLockIds.add(id);
      } else {
        _guideDogLockedMissing[id] = next;
      }
    });
    for (final id in staleLockIds) {
      _guideDogLockedMissing.remove(id);
    }
    
    _guideDogCandidateFrames
        .removeWhere((id, _) => !presentIds.contains(id));
  }

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
  DateTime _lastCriticalVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCaneVibrateAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _proximityUpdated = false;
  double _proximityDistance = double.infinity;

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
    _proximityUpdated = false;
    _proximityDistance = double.infinity;
  }

  Track? processFrame({
    required List<Track> tracks,
    required int imgW,
    required int imgH,
    double? viewportAspect,
    required DateTime now,
    required AppMode mode,
    required bool isCalibrated,
    required int frameCount,
  }) {
    if (_isGuideDogMode()) {
      _updateGuideDogLocks(tracks, imgH);
      final filtered = tracks
          .where((t) =>
              !_isLockedGuideDog(t.id) && !_isGuideDogTrack(t, imgH))
          .toList(growable: false);
      if (filtered.length != tracks.length) tracks = filtered;
    } else if (_guideDogLockedMissing.isNotEmpty ||
        _guideDogCandidateFrames.isNotEmpty) {
      
      
      _guideDogLockedMissing.clear();
      _guideDogCandidateFrames.clear();
    }
    final hasTracks = tracks.isNotEmpty;
    _proximityUpdated = false;
    _proximityDistance = double.infinity;

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
      _pauseProximity();
      return null;
    }

    if (mode == AppMode.cane) {
      _handleCaneMode(tracks, now, imgW, imgH, viewportAspect);
      if (!_proximityUpdated) _pauseProximity();
      return null;
    }

    if (mode == AppMode.scan) {
      _pauseProximity();
      return null;
    }

    final frameArea = (imgW * imgH).toDouble();
    final frameScores = <int, double>{};
    for (final t in tracks) {
      final ar = frameArea > 0
          ? ((t.x2 - t.x1) * (t.y2 - t.y1)) / frameArea
          : 0.0;
      frameScores[t.id] = threatScore(
        t.label,
        posFromCx(
          t.cx,
          imgW.toDouble(),
          imgH: imgH.toDouble(),
          viewportAspect: viewportAspect,
        ),
        t.dist,
        ar,
      );
    }

    _handleApproaching(tracks, frameScores, imgW, imgH, viewportAspect, now);
    _handleVeryClose(
      tracks,
      frameScores,
      imgW,
      imgH,
      viewportAspect,
      now,
      isCalibrated,
    );
    _handleCloseFar(
      tracks,
      frameScores,
      imgW,
      imgH,
      viewportAspect,
      now,
      isCalibrated,
    );
    _handleNavHint(tracks, imgW, imgH, viewportAspect, now);

    final labels = tracks.map((t) => t.label).toList();
    
    
    
    
    
    final reliableTrackIds = <int>{
      for (final t in tracks)
        if (t.reliableFrames >= 3) t.id,
    };
    final winner = _filter.flush(
      tracks.length,
      now,
      labels: labels,
      reliableTrackIds: reliableTrackIds,
    );
    if (winner != null) {
      _tts.say(
        winner.text,
        winner.priority,
        pan: winner.pan,
        trackId: winner.trackId,
      );
      if (winner.trackId != null) {
        final spoken = tracks.firstWhere(
          (t) => t.id == winner.trackId,
          orElse: () => tracks.first,
        );
        if (spoken.id == winner.trackId) spoken.lastSpoken = now;
      }
    }

    if (frameCount % 30 == 0) _tts.evictStale();

    if (!_proximityUpdated) _pauseProximity();

    return _signTrack(tracks);
  }

  void _handleEmpty(DateTime now, AppMode mode) {
    final emptyFor = now.difference(_emptySince);
    final gapSinceObj = now.difference(_objectLastSeen);

    final baseConfirm = mode == AppMode.cane
        ? kEmptyConfirmDurationCane
        : kEmptyConfirmDuration;
    
    
    
    
    
    final confirmDuration = _isIndoorMode()
        ? baseConfirm + const Duration(milliseconds: 1500)
        : baseConfirm;
    final recentCritical =
        now.difference(_lastCriticalAt) < kPostCriticalClearDelay;

    if (!_clearAnnounced &&
        emptyFor >= confirmDuration &&
        gapSinceObj >= kClearAnnounceDuration &&
        !recentCritical) {
      if (mode == AppMode.cane) {
        _earcon.play(Earcon.pathClear);
        _tts.say(S.alert('path_clear_cane'), SpeechPriority.info, pan: 0.0);
      } else {
        _earcon.play(Earcon.pathClear);
        _tts.say(S.alert('path_clear'), SpeechPriority.info, pan: 0.0);
      }
      _clearAnnounced = true;
    }
  }

  void _handleApproaching(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    int imgH,
    double? viewportAspect,
    DateTime now,
  ) {
    Track? top;
    for (final t in tracks) {
      final bool labelThreat = t.approaching;
      final bool kinematicThreat =
          !t.approaching &&
          t.dynamicThreat &&
          
          t.avgConf >= 0.45 &&
          t.distM > 0 &&
          t.distM <= 8.0;
      if (!labelThreat && !kinematicThreat) continue;
      if (top == null ||
          (frameScores[t.id] ?? 0) > (frameScores[top.id] ?? 0)) {
        top = t;
      }
    }

    if (top != null && top.dist != 'very close') {
      final pan = _pan(top.cx, imgW, imgH, viewportAspect);
      _emitProximity(
        top.distM > 0 ? top.distM : _distanceEstimate(top.dist),
        pan,
      );
      if (now.difference(_lastApproachSay) >= kApproachCooldown) {
        _lastApproachSay = now;
        _earcon.play(Earcon.approaching, pan: pan);
        final phraseKey = isVehicle(top.label)
            ? 'transport_approaching'
            : 'object_approaching';
        _filter.add(
          AlertCandidate(
            text:
                '${S.alert(phraseKey)}, '
                '${clockDir(top.x1, top.x2, imgW.toDouble(), imgH: imgH.toDouble(), viewportAspect: viewportAspect, forAlert: true)}.',
            priority: SpeechPriority.warning,
            pan: pan,
            category: AlertCategory.approachingVehicle,
            urgency: 0.85,
          ),
        );
      }
    }
  }

  void _handleVeryClose(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    int imgH,
    double? viewportAspect,
    DateTime now,
    bool isCalibrated,
  ) {
    Track? top;
    for (final t in tracks) {
      if (!t.fastTrack && t.nearFrameCount < 2) continue;
      if (t.dist != 'very close') continue;
      if (now.difference(t.lastSpoken) < kCriticalCooldown) continue;
      if (!t.fastTrack && t.avgConf < 0.40 && t.reliableFrames < 2) continue;

      final score = (frameScores[t.id] ?? 0) * t.avgConf;
      if (top == null || score > (frameScores[top.id] ?? 0) * top.avgConf) {
        top = t;
      }
    }

    if (top == null) return;

    final pan = _pan(top.cx, imgW, imgH, viewportAspect);
    _emitProximity(
      top.distM > 0 ? top.distM : _distanceEstimate(top.dist),
      pan,
    );

    if (now.difference(_lastCriticalAt) >= kCriticalCooldown) {
      top.lastSpoken = now;
      _lastCriticalAt = now;
      final dir = clockDir(
        top.x1,
        top.x2,
        imgW.toDouble(),
        imgH: imgH.toDouble(),
        viewportAspect: viewportAspect,
        forAlert: true,
      );
      final label = S.alertLabel(top.label);
      final distPart = (isCalibrated && top.distM > 0)
          ? ' (~${top.distM.toStringAsFixed(1)} ${S.alert('approx_meters')})'
          : '';
      _tts.say(
        '${S.alert('stop')}. $label $dir$distPart.',
        SpeechPriority.critical,
        pan: pan,
      );
      _vibrate([0, 250, 80, 450], isCritical: true);
    } else {
      _vibrate([0, 150]);
    }
  }

  void _handleCloseFar(
    List<Track> tracks,
    Map<int, double> frameScores,
    int imgW,
    int imgH,
    double? viewportAspect,
    DateTime now,
    bool isCalibrated,
  ) {
    Track? topProximity;
    double topProximityScore = -1;
    double topProximityPan = 0.0;
    for (final t in tracks) {
      if (t.dist == 'very close') continue;
      if (t.nearFrameCount < 2 && t.dist != 'far') continue;
      if (t.avgConf < kMinAlertConf) continue;
      if (t.reliableFrames < 3 && t.dist == 'far') continue;

      final confFactor = t.avgConf >= kHighConfLevel ? 1.0 : 1.5;
      final baseCooldown = t.label == 'person'
          ? kPersonCooldown
          : t.dist == 'close'
          ? kWarningCooldown
          : kInfoCooldown;
      final cooldown = Duration(
        milliseconds: (baseCooldown.inMilliseconds * confFactor).round(),
      );

      if (now.difference(t.lastSpoken) < cooldown) continue;

      final dir = clockDir(
        t.x1,
        t.x2,
        imgW.toDouble(),
        imgH: imgH.toDouble(),
        viewportAspect: viewportAspect,
        forAlert: true,
      );
      final label = S.alertLabel(t.label);
      final distPart = (isCalibrated && t.distM > 0)
          ? ' (~${t.distM.toStringAsFixed(1)} ${S.alert('approx_meters')})'
          : '';
      final pan = _pan(t.cx, imgW, imgH, viewportAspect);
      final score = frameScores[t.id] ?? 0.0;

      if (t.dist == 'close') {
        final proximityScore = score * t.avgConf;
        if (topProximity == null || proximityScore > topProximityScore) {
          topProximity = t;
          topProximityScore = proximityScore;
          topProximityPan = pan;
        }
      }

      if (t.dist == 'close') {
        _vibrate([0, 150]);
        _filter.add(
          AlertCandidate(
            text: '$label ${S.alert('close')}, $dir$distPart.',
            priority: SpeechPriority.warning,
            pan: pan,
            category: AlertCategory.obstacleClose,
            urgency: score * t.avgConf,
            trackId: t.id,
          ),
        );
      } else {
        _earcon.play(Earcon.objectAppeared, pan: pan);
        _filter.add(
          AlertCandidate(
            text: '$label $dir.',
            priority: SpeechPriority.info,
            pan: pan,
            category: AlertCategory.obstacleFar,
            urgency: score * t.avgConf,
            trackId: t.id,
          ),
        );
      }
    }

    if (topProximity != null) {
      _emitProximity(
        topProximity.distM > 0
            ? topProximity.distM
            : _distanceEstimate(topProximity.dist),
        topProximityPan,
      );
    }
  }

  void _handleNavHint(
    List<Track> tracks,
    int imgW,
    int imgH,
    double? viewportAspect,
    DateTime now,
  ) {
    final (hint5, centTh, bestTh) = bestDirectionHint(
      tracks,
      imgW.toDouble(),
      imgH.toDouble(),
      viewportAspect: viewportAspect,
    );
    final corridor = findFreeCorridor(
      tracks,
      imgW.toDouble(),
      imgH.toDouble(),
      viewportAspect: viewportAspect,
    );
    final corridorDecision = _engine.evaluate(corridor);

    
    final needGuide = centTh >= kGuideMinCenterThreat && (centTh - bestTh >= kGuideImprovementAbs) && centTh >= bestTh * kGuideImprovementRatio && hint5 != 'forward';

    String? corridorDir;
    if (corridor != null) {
      corridorDir = corridor.$2 == 'left'
          ? S.alert('nav_left')
          : corridor.$2 == 'right'
          ? S.alert('nav_right')
          : null;
    }

    if (corridorDecision != null &&
        corridorDecision.priority == SpeechPriority.critical) {
      _filter.add(
        AlertCandidate(
          text: corridorDecision.text,
          priority: SpeechPriority.critical,
          pan: 0.0,
          category: AlertCategory.corridorBlocked,
          urgency: 0.90,
        ),
      );
    }

    String? unifiedHint;
    if (needGuide || corridorDir != null) {
      final dir = corridorDir ?? (needGuide ? hint5 : null);
      if (dir != null) {
        final corridorWidthM = corridor?.$1;
        if (corridorWidthM != null && corridorWidthM >= 0.6) {
          unifiedHint =
              '${S.alert('deviate')} $dir. '
              '${S.alert('passage')} ${corridorWidthM.toStringAsFixed(1)} '
              '${S.alert('approx_meters')}.';
        } else {
          unifiedHint = '${S.alert('deviate')} $dir.';
        }
      }
    }

    if (_guidanceGiven && !needGuide && corridorDir == null) {
      _guidanceGiven = false;
      _pendingHint = '';
      _pendingHintFrames = 0;
      _filter.add(
        AlertCandidate(
          text: S.alert('maneuver_ok'),
          priority: SpeechPriority.info,
          pan: 0.0,
          category: AlertCategory.navigationHint,
          urgency: 0.3,
        ),
      );
    }

    if (unifiedHint != null) {
      if (unifiedHint == _pendingHint) {
        _pendingHintFrames++;
      } else {
        _pendingHint = unifiedHint;
        _pendingHintFrames = 1;
      }

      final isStable = _pendingHintFrames >= kHintStableFrames;
      final cooldownOk = now.difference(_lastGuideSay) >= kGuideCooldown;
      final isNew = unifiedHint != _lastGuideText;

      if (isStable && cooldownOk && isNew) {
        _lastGuideText = unifiedHint;
        _lastGuideSay = now;
        _guidanceGiven = true;
        _filter.add(
          AlertCandidate(
            text: unifiedHint,
            priority: SpeechPriority.info,
            pan: 0.0,
            category: AlertCategory.navigationHint,
            urgency: 0.50,
          ),
        );
      }
    } else {
      if (_pendingHintFrames > 0) {
        _pendingHint = '';
        _pendingHintFrames = 0;
      }
      if (corridorDecision != null &&
          corridorDecision.priority != SpeechPriority.critical) {
        _filter.add(
          AlertCandidate(
            text: corridorDecision.text,
            priority: corridorDecision.priority,
            pan: corridorDecision.pan,
            category: AlertCategory.corridorNarrow,
            urgency: 0.50,
          ),
        );
      }
    }
  }

  void _handleCaneMode(
    List<Track> tracks,
    DateTime now,
    int imgW,
    int imgH,
    double? viewportAspect,
  ) {
    if (tracks.isEmpty) return;

    final frameArea = (imgW * imgH).toDouble();
    double score(Track t) => threatScore(
      t.label,
      posFromCx(
        t.cx,
        imgW.toDouble(),
        imgH: imgH.toDouble(),
        viewportAspect: viewportAspect,
      ),
      t.dist,
      frameArea > 0 ? ((t.x2 - t.x1) * (t.y2 - t.y1)) / frameArea : 0,
    );

    final sorted = List<Track>.from(tracks)
      ..sort((a, b) => score(b).compareTo(score(a)));

    final top = sorted.first;
    final topPos = posFromCx(
      top.cx,
      imgW.toDouble(),
      imgH: imgH.toDouble(),
      viewportAspect: viewportAspect,
    );

    final effectiveDist = (top.dist == 'far' && top.approaching)
        ? 'close'
        : top.dist;

    final cooldown = effectiveDist == 'very close'
        ? kCaneVeryCloseCooldown
        : effectiveDist == 'close'
        ? kCaneCloseCooldown
        : kCaneFarCooldown;

    if (now.difference(top.lastSpoken) >= cooldown) {
      final pattern = _patternFor(effectiveDist, topPos);
      final intensities = _intensitiesFor(effectiveDist, pattern.length);
      _vibrateCane(pattern, intensities: intensities);

      final dir = clockDir(
        top.x1,
        top.x2,
        imgW.toDouble(),
        imgH: imgH.toDouble(),
        viewportAspect: viewportAspect,
        forAlert: true,
      );
      final pan = _pan(top.cx, imgW, imgH, viewportAspect);

      if (effectiveDist != 'far') {
        final String ttsText;
        if (effectiveDist == 'very close') {
          ttsText = top.approaching
              ? '${S.alert('stop')}! $dir.'
              : '${S.alert('stop')}. $dir.';
        } else {
          ttsText = top.approaching
              ? '${S.alertLabel(top.label)} ${S.alert('approaching')}, $dir.'
              : '$dir.';
        }
        top.lastSpoken = now;
        _tts.say(ttsText, SpeechPriority.info, pan: pan, trackId: top.id);
      } else {
        top.lastSpoken = now;
      }
    }

    if (sorted.length >= 2) {
      final second = sorted[1];
      if (second.dist != 'far') {
        final secondPos = posFromCx(
          second.cx,
          imgW.toDouble(),
          imgH: imgH.toDouble(),
          viewportAspect: viewportAspect,
        );
        final isOtherSide =
            (topPos == 'left' && secondPos == 'right') ||
            (topPos == 'right' && secondPos == 'left') ||
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

  Future<void> _vibrate(List<int> pattern, {bool isCritical = false}) async {
    final now = DateTime.now();
    if (isCritical) {
      if (now.difference(_lastCriticalVibrateAt) <
          const Duration(milliseconds: 150))
        return;
      _lastCriticalVibrateAt = now;
      _lastVibrateAt = now;
    } else {
      if (now.difference(_lastVibrateAt) < kVibrateCooldown) return;
      _lastVibrateAt = now;
    }

    await HapticService.vibrate(
      pattern,
      intensities: pattern.length >= 4 ? const [0, 255, 0, 200] : null,
    );
  }

  Future<void> _vibrateCane(List<int> pattern, {List<int>? intensities}) async {
    final now = DateTime.now();
    if (now.difference(_lastCaneVibrateAt) < kCaneVibrateCooldown) return;
    _lastCaneVibrateAt = now;
    await HapticService.vibrate(pattern, intensities: intensities);
  }

  List<int> _patternFor(String dist, String pos) {
    switch (dist) {
      case 'very close':
        if (pos == 'left') return kHapticVcLeft;
        if (pos == 'right') return kHapticVcRight;
        return kHapticVcCenter;
      case 'close':
        if (pos == 'left') return kHapticCloseLeft;
        if (pos == 'right') return kHapticCloseRight;
        return kHapticCloseCenter;
      default:
        if (pos == 'left') return kHapticFarLeft;
        if (pos == 'right') return kHapticFarRight;
        return kHapticFarCenter;
    }
  }

  List<int> _intensitiesFor(String dist, int patternLength) {
    final amp = dist == 'very close'
        ? 255
        : dist == 'close'
        ? 180
        : 100;
    return List.generate(patternLength, (i) => i.isOdd ? amp : 0);
  }

  double _pan(double cx, int imgW, int imgH, double? viewportAspect) {
    if (imgW == 0) return 0.0;
    final n = visibleXFraction(
      cx,
      imgW.toDouble(),
      imgH: imgH.toDouble(),
      viewportAspect: viewportAspect,
    );
    return (n * 2.0 - 1.0).clamp(-1.0, 1.0);
  }

  void _emitProximity(double distMeters, double pan) {
    if (_proximityUpdated && distMeters >= _proximityDistance) return;
    _proximityUpdated = true;
    _proximityDistance = distMeters;
    onProximityChanged?.call(distMeters, pan);
  }

  void _pauseProximity() {
    onProximityChanged?.call(null, 0.0);
  }

  double _distanceEstimate(String dist) {
    switch (dist) {
      case 'very close':
        return 0.45;
      case 'close':
        return 1.1;
      default:
        return 2.4;
    }
  }

  List<int> patternFor(String dist, String pos) => _patternFor(dist, pos);
  List<int> intensitiesFor(String dist, int patternLength) =>
      _intensitiesFor(dist, patternLength);
  Future<void> vibrateCane(List<int> pattern, {List<int>? intensities}) =>
      _vibrateCane(pattern, intensities: intensities);
}

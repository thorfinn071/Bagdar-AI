import '../models/a11y_prefs.dart';
import '../models/constants.dart';
import '../models/speech_job.dart';
import '../models/strings.dart' show S;

enum AlertCategory {
  approachingVehicle,
  obstacleClose,
  obstacleFar,
  navigationHint,
  corridorBlocked,
  corridorNarrow,
  acousticEvent,
  genericObstacle,
}

class AlertCandidate {
  final String text;
  final SpeechPriority priority;
  final double pan;
  final AlertCategory category;

  final double urgency;
  final int? trackId;
  final bool isGroupAlert;

  final double? distanceM;

  const AlertCandidate({
    required this.text,
    required this.priority,
    required this.pan,
    required this.category,
    required this.urgency,
    this.trackId,
    this.isGroupAlert = false,
    this.distanceM,
  });
}

class AlertFilter {
  final List<AlertCandidate> _candidates = [];

  final Map<AlertCategory, DateTime> _lastByCat = {};
  final Map<AlertCategory, DateTime> _lastCriticalByCat = {};
  final Map<int, DateTime> _lastCriticalByTrack = {};

  final Map<AlertCategory, double> _lastCriticalDistMByCat = {};

  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  AlertCategory? _lastCategory;

  final Map<AlertCategory, DateTime> _suppressUntilByCategory = {};

  static const double kEscalationDistanceFraction = 0.70;

  List<AlertCandidate> _lastRejected = const [];

  List<AlertCandidate> get lastRejected => _lastRejected;

  void add(AlertCandidate candidate) => _candidates.add(candidate);

  AlertCandidate? flush(
    int trackCount,
    DateTime now, {
    List<String>? labels,
    Set<int>? reliableTrackIds,
    Verbosity verbosity = Verbosity.normal,
    AlertFrequency alertFrequency = AlertFrequency.normal,
  }) {
    if (_candidates.isEmpty) return null;

    if (labels != null && labels.length >= 3) {
      final counts = <String, int>{};
      for (final l in labels) {
        counts[l] = (counts[l] ?? 0) + 1;
      }

      for (final entry in counts.entries) {
        if (entry.value >= 3) {
          final label = entry.key;
          final alreadyHaveGroup = _candidates.any((c) => c.isGroupAlert);
          if (!alreadyHaveGroup) {
            final pluralLabel = S.alertLabel(label);

            _candidates.add(
              AlertCandidate(
                text: '${S.alert('group_ahead')}${entry.value} $pluralLabel',
                priority: SpeechPriority.info,
                pan: 0.0,
                category: AlertCategory.obstacleFar,
                urgency: 0.6,
                isGroupAlert: true,
              ),
            );
          }
        }
      }
    }

    _candidates.sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      return p != 0 ? p : b.urgency.compareTo(a.urgency);
    });

    AlertCandidate? picked;
    final rejected = <AlertCandidate>[];
    for (final cand in _candidates) {
      if (_isAllowed(
        cand,
        trackCount,
        now,
        reliableTrackIds,
        verbosity: verbosity,
        alertFrequency: alertFrequency,
      )) {
        picked = cand;
        break;
      } else {
        rejected.add(cand);
      }
    }
    _lastRejected = rejected;
    _candidates.clear();
    if (picked == null) return null;

    _lastSpokenAt = now;
    _lastCategory = picked.category;
    _updateCategoryState(
      picked.category,
      now,
      isCritical: picked.priority == SpeechPriority.critical,
      distanceM: picked.distanceM,
      trackId: picked.trackId,
    );
    return picked;
  }

  bool _isAllowed(
    AlertCandidate cand,
    int trackCount,
    DateTime now,
    Set<int>? reliableTrackIds, {
    Verbosity verbosity = Verbosity.normal,
    AlertFrequency alertFrequency = AlertFrequency.normal,
  }) {
    if (verbosity == Verbosity.minimal &&
        cand.priority == SpeechPriority.info &&
        cand.urgency < 0.7) {
      return false;
    }

    if (verbosity == Verbosity.minimal &&
        cand.category == AlertCategory.obstacleFar) {
      return false;
    }

    if (cand.priority == SpeechPriority.critical) {
      final repeatCooldown =
          cand.category == AlertCategory.obstacleClose ||
              cand.category == AlertCategory.corridorBlocked ||
              cand.category == AlertCategory.approachingVehicle ||
              cand.category == AlertCategory.genericObstacle
          ? kCriticalRepeatCooldownSafety
          : kCriticalRepeatCooldownDefault;

      // Stable track IDs: a genuinely new obstacle is not hidden by a
      // global category cooldown.
      if (cand.trackId != null) {
        final lastTrackAt = _lastCriticalByTrack[cand.trackId];
        if (lastTrackAt == null) return true;
        if (now.difference(lastTrackAt) >= repeatCooldown) return true;
        final lastDistM = _lastCriticalDistMByCat[cand.category];
        final candDistM = cand.distanceM;
        if (lastDistM != null &&
            lastDistM > 0 &&
            candDistM != null &&
            candDistM > 0 &&
            candDistM <= lastDistM * kEscalationDistanceFraction) {
          if (now.difference(lastTrackAt) >= kCriticalRepeatCooldownSafety) {
            return true;
          }
        }
        return false;
      }

      final lastSameAt = _lastCriticalByCat[cand.category];
      if (lastSameAt == null || now.difference(lastSameAt) >= repeatCooldown) {
        return true;
      }

      final lastDistM = _lastCriticalDistMByCat[cand.category];
      final candDistM = cand.distanceM;
      if (lastDistM != null &&
          lastDistM > 0 &&
          candDistM != null &&
          candDistM > 0 &&
          candDistM <= lastDistM * kEscalationDistanceFraction) {
        if (now.difference(lastSameAt) >= kCriticalRepeatCooldownSafety) {
          return true;
        }
      }
      return false;
    }

    final lastAt =
        _lastByCat[cand.category] ?? DateTime.fromMillisecondsSinceEpoch(0);
    final catGap = _categoryCooldown(cand.category, trackCount, alertFrequency);
    if (now.difference(lastAt) < catGap) return false;

    final suppressedUntil = _suppressUntilByCategory[cand.category];
    if (suppressedUntil != null && now.isBefore(suppressedUntil)) {
      return false;
    }

    if (cand.priority != SpeechPriority.critical &&
        now.difference(_lastSpokenAt) < const Duration(milliseconds: 1500)) {
      return false;
    }

    if (trackCount >= 5 &&
        cand.priority == SpeechPriority.info &&
        cand.urgency < 0.4) {
      final tid = cand.trackId;
      final reliable = reliableTrackIds;
      if (tid == null || reliable == null || !reliable.contains(tid)) {
        return false;
      }
    }

    if (cand.category == AlertCategory.navigationHint &&
        (trackCount >= 3 || _lastCategory == AlertCategory.obstacleClose)) {
      return false;
    }

    if (cand.category == AlertCategory.navigationHint &&
        (_lastCategory == AlertCategory.corridorNarrow ||
            _lastCategory == AlertCategory.corridorBlocked) &&
        now.difference(_lastSpokenAt) < const Duration(seconds: 8)) {
      return false;
    }

    if (cand.category == AlertCategory.corridorNarrow &&
        _lastCategory == AlertCategory.navigationHint &&
        now.difference(_lastSpokenAt) < const Duration(seconds: 8)) {
      return false;
    }

    return true;
  }

  /// Register a critical alert that was spoken outside the filter pipeline
  /// (e.g. very-close direct TTS path) so that subsequent [flush]/[flushMulti]
  /// calls respect the per-category cooldown and don't double-fire.
  void noteCritical(AlertCategory category, DateTime now) {
    _updateCategoryState(category, now, isCritical: true);
    _lastSpokenAt = now;
    _lastCategory = category;
  }

  /// Like [flush] but returns up to 2 winners: the highest-urgency allowed
  /// candidate, then the highest-urgency allowed candidate from a different
  /// category. This lets a simultaneously-approaching vehicle and a nearby
  /// obstacle both be announced in the same frame. D-2: as an exception, two
  /// CRITICAL candidates of the SAME category are also both allowed when
  /// they are on opposite sides (opposite-sign `pan`) — e.g. vehicles
  /// approaching from the left and right at a crossing — since dropping the
  /// second one loses directional safety information for
  /// [kCriticalRepeatCooldownSafety].
  List<AlertCandidate> flushMulti(
    int trackCount,
    DateTime now, {
    List<String>? labels,
    Set<int>? reliableTrackIds,
    Verbosity verbosity = Verbosity.normal,
    AlertFrequency alertFrequency = AlertFrequency.normal,
  }) {
    if (_candidates.isEmpty) return const [];

    if (labels != null && labels.length >= 3) {
      final counts = <String, int>{};
      for (final l in labels) {
        counts[l] = (counts[l] ?? 0) + 1;
      }
      for (final entry in counts.entries) {
        if (entry.value >= 3) {
          final alreadyHaveGroup = _candidates.any((c) => c.isGroupAlert);
          if (!alreadyHaveGroup) {
            final pluralLabel = S.alertLabel(entry.key);
            _candidates.add(
              AlertCandidate(
                text: '${S.alert('group_ahead')}${entry.value} $pluralLabel',
                priority: SpeechPriority.info,
                pan: 0.0,
                category: AlertCategory.obstacleFar,
                urgency: 0.6,
                isGroupAlert: true,
              ),
            );
          }
        }
      }
    }

    _candidates.sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      return p != 0 ? p : b.urgency.compareTo(a.urgency);
    });

    AlertCandidate? first;
    AlertCandidate? second;
    final rejected = <AlertCandidate>[];
    for (final cand in _candidates) {
      if (_isAllowed(
        cand,
        trackCount,
        now,
        reliableTrackIds,
        verbosity: verbosity,
        alertFrequency: alertFrequency,
      )) {
        if (first == null) {
          first = cand;
        } else if (second == null) {
          // D-2: two simultaneous critical hazards in the SAME category but
          // on opposite sides (e.g. a vehicle approaching from the left and
          // another from the right at a crossing) must both be announced.
          // Without this, the second one is silently dropped and its
          // directional cooldown (_lastCriticalByCat) then blocks its own
          // repeat for kCriticalRepeatCooldownSafety, losing "right" for
          // 2-4 s. Non-critical candidates keep the original same-category
          // exclusion (only one non-critical wins per flush).
          final sameCatOppositeSideCritical =
              cand.category == first.category &&
              cand.priority == SpeechPriority.critical &&
              first.priority == SpeechPriority.critical &&
              (cand.pan * first.pan < 0);
          if (cand.category != first.category || sameCatOppositeSideCritical) {
            second = cand;
            break;
          }
        }
      } else {
        rejected.add(cand);
      }
    }
    _lastRejected = rejected;
    _candidates.clear();

    final winners = <AlertCandidate>[];
    for (final w in [first, second]) {
      if (w == null) continue;
      winners.add(w);
      _lastSpokenAt = now;
      _lastCategory = w.category;
      _updateCategoryState(
        w.category,
        now,
        isCritical: w.priority == SpeechPriority.critical,
        distanceM: w.distanceM,
        trackId: w.trackId,
      );
    }
    return winners;
  }

  void reset() {
    _candidates.clear();
    _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCategory = null;
    _suppressUntilByCategory.clear();
    _lastByCat.clear();
    _lastCriticalByCat.clear();
    _lastCriticalByTrack.clear();
    _lastCriticalDistMByCat.clear();
    _lastRejected = const [];
  }

  Duration _categoryCooldown(
    AlertCategory cat,
    int trackCount,
    AlertFrequency freq,
  ) {
    final double trackScale = trackCount >= 5
        ? 1.4
        : trackCount >= 3
        ? 1.2
        : 1.0;
    final double freqScale = switch (freq) {
      AlertFrequency.rare => 1.6,
      AlertFrequency.normal => 1.0,
      AlertFrequency.frequent => 0.7,
    };
    final double scale = trackScale * freqScale;
    Duration scaled(int ms) => Duration(milliseconds: (ms * scale).round());
    switch (cat) {
      case AlertCategory.approachingVehicle:
        return scaled(1200);
      case AlertCategory.obstacleClose:
        return scaled(3000);
      case AlertCategory.genericObstacle:
        return scaled(3000);
      case AlertCategory.obstacleFar:
        return scaled(4000);
      case AlertCategory.navigationHint:
        return scaled(2500);
      case AlertCategory.corridorBlocked:
        return Duration(milliseconds: (1500 * freqScale).round());
      case AlertCategory.corridorNarrow:
        return scaled(2500);
      case AlertCategory.acousticEvent:
        return scaled(3000);
    }
  }

  void _updateCategoryState(
    AlertCategory category,
    DateTime now, {
    bool isCritical = false,
    double? distanceM,
    int? trackId,
  }) {
    if (isCritical && trackId != null) {
      _lastCriticalByTrack[trackId] = now;
    }
    final categoriesToUpdate =
        !isCritical &&
            (category == AlertCategory.approachingVehicle ||
                category == AlertCategory.obstacleClose)
        ? [AlertCategory.approachingVehicle, AlertCategory.obstacleClose]
        : [category];

    for (final cat in categoriesToUpdate) {
      _lastByCat[cat] = now;
      if (isCritical) {
        _lastCriticalByCat[cat] = now;
        _suppressUntilByCategory[cat] = now.add(
          const Duration(milliseconds: 2000),
        );
        if (distanceM != null && distanceM > 0) {
          _lastCriticalDistMByCat[cat] = distanceM;
        }
      }
    }
  }
}

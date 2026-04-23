import '../models/speech_job.dart';
import '../models/strings.dart' show S;

enum AlertCategory {
  clearPath,
  approachingVehicle,
  obstacleClose,
  obstacleFar,
  navigationHint,
  corridorBlocked,
  corridorNarrow,
}

class AlertCandidate {
  final String text;
  final SpeechPriority priority;
  final double pan;
  final AlertCategory category;

  final double urgency;
  final int? trackId;
  final bool isGroupAlert;

  const AlertCandidate({
    required this.text,
    required this.priority,
    required this.pan,
    required this.category,
    required this.urgency,
    this.trackId,
    this.isGroupAlert = false,
  });
}

class AlertFilter {
  final List<AlertCandidate> _candidates = [];

  final Map<AlertCategory, DateTime> _lastByCat = {};

  DateTime _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
  AlertCategory? _lastCategory;

  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void add(AlertCandidate candidate) => _candidates.add(candidate);

  AlertCandidate? flush(
    int trackCount,
    DateTime now, {
    List<String>? labels,
    Set<int>? reliableTrackIds,
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
          final alreadyHaveGroup = _candidates.any(
            (c) => c.isGroupAlert,
          );
          if (!alreadyHaveGroup) {
            final pluralLabel = S.alertLabel(label);

            _candidates.add(
              AlertCandidate(
                text:
                    '${S.alert('group_ahead')}${entry.value} $pluralLabel',
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
    for (final cand in _candidates) {
      if (_isAllowed(cand, trackCount, now, reliableTrackIds)) {
        picked = cand;
        break;
      }
    }
    _candidates.clear();
    if (picked == null) return null;

    _lastSpokenAt = now;
    _lastCategory = picked.category;
    _lastByCat[picked.category] = now;

    if (picked.priority == SpeechPriority.critical) {
      _suppressUntil = now.add(const Duration(milliseconds: 2000));
    }

    return picked;
  }

  bool _isAllowed(
    AlertCandidate cand,
    int trackCount,
    DateTime now,
    Set<int>? reliableTrackIds,
  ) {
    if (cand.priority == SpeechPriority.critical) return true;

    final lastAt =
        _lastByCat[cand.category] ?? DateTime.fromMillisecondsSinceEpoch(0);
    final catGap = _categoryCooldown(cand.category, trackCount);
    if (now.difference(lastAt) < catGap) return false;

    if (cand.category != AlertCategory.approachingVehicle &&
        now.isBefore(_suppressUntil)) {
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

  void reset() {
    _candidates.clear();
    _lastSpokenAt = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCategory = null;
    _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _lastByCat.clear();
  }

  Duration _categoryCooldown(AlertCategory cat, int trackCount) {
    final double scale = trackCount >= 5
        ? 1.4
        : trackCount >= 3
        ? 1.2
        : 1.0;
    Duration scaled(int ms) => Duration(milliseconds: (ms * scale).round());
    switch (cat) {
      case AlertCategory.approachingVehicle:
        return scaled(1200);
      case AlertCategory.obstacleClose:
        return scaled(2000);
      case AlertCategory.obstacleFar:
        return scaled(2000);
      case AlertCategory.navigationHint:
        return scaled(2500);
      case AlertCategory.corridorBlocked:
        return const Duration(milliseconds: 1500);
      case AlertCategory.corridorNarrow:
        return scaled(2500);
      case AlertCategory.clearPath:
        return const Duration(seconds: 6);
    }
  }
}

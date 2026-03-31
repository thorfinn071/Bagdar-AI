import '../models/speech_job.dart';



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

  const AlertCandidate({
    required this.text,
    required this.priority,
    required this.pan,
    required this.category,
    required this.urgency,
    this.trackId,
  });
}



class AlertFilter {
  final List<AlertCandidate> _candidates = [];

  DateTime _lastSpokenAt     = DateTime.fromMillisecondsSinceEpoch(0);
  AlertCategory? _lastCategory;

  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void add(AlertCandidate candidate) => _candidates.add(candidate);

  AlertCandidate? flush(int trackCount, DateTime now) {
    if (_candidates.isEmpty) return null;

    _candidates.sort((a, b) {
      final p = b.priority.index.compareTo(a.priority.index);
      return p != 0 ? p : b.urgency.compareTo(a.urgency);
    });

    final best = _candidates.first;
    _candidates.clear();

    final minGap = _minGap(best.priority, trackCount);
    if (now.difference(_lastSpokenAt) < minGap) return null;

    if (best.priority != SpeechPriority.critical &&
        now.isBefore(_suppressUntil)) {
      return null;
    }

    if (trackCount >= 5 && best.priority == SpeechPriority.info) return null;

    if (best.category == AlertCategory.navigationHint &&
        (trackCount >= 3 || _lastCategory == AlertCategory.obstacleClose)) {
      return null;
    }

    if (best.category == AlertCategory.navigationHint &&
        (_lastCategory == AlertCategory.corridorNarrow ||
         _lastCategory == AlertCategory.corridorBlocked)) {
      if (now.difference(_lastSpokenAt) < const Duration(seconds: 8)) return null;
    }
    if (best.category == AlertCategory.corridorNarrow &&
        _lastCategory == AlertCategory.navigationHint) {
      if (now.difference(_lastSpokenAt) < const Duration(seconds: 8)) return null;
    }

    _lastSpokenAt = now;
    _lastCategory = best.category;

    if (best.priority == SpeechPriority.critical) {
      _suppressUntil = now.add(const Duration(milliseconds: 2000));
    }

    return best;
  }

  void reset() {
    _candidates.clear();
    _lastSpokenAt  = DateTime.fromMillisecondsSinceEpoch(0);
    _lastCategory  = null;
    _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Duration _minGap(SpeechPriority priority, int trackCount) {
    if (priority == SpeechPriority.critical) {
      return const Duration(milliseconds: 1200);
    }
    if (trackCount >= 5) return const Duration(seconds: 5);
    if (trackCount >= 3) return const Duration(milliseconds: 3500);
    if (trackCount >= 2) return const Duration(milliseconds: 2500);
    return const Duration(milliseconds: 2000);
  }
}

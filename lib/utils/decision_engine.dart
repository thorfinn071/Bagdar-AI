import 'dart:collection';

import '../../models/constants.dart';
import '../../models/speech_job.dart';
import '../../models/strings.dart';

class NavigationDecision {
  final String text;
  final SpeechPriority priority;
  final double pan;
  final String category;

  const NavigationDecision(this.text, this.priority, this.pan, this.category);
}

class DecisionEngine {
  final ListQueue<(double, String)> _history = ListQueue<(double, String)>();
  double _historyWidthSum = 0.0;

  final Map<String, DateTime> _lastSpokenByCategory = {};
  static const Map<String, Duration> _cooldownsByCategory = {
    'corridor_blocked': kCriticalCooldown,
    'corridor_narrow': Duration(seconds: 4),
  };

  NavigationDecision? evaluate((double, String)? corridor) {
    if (corridor == null) {
      _history.clear();
      _historyWidthSum = 0.0;
      return null;
    }

    _history.addLast(corridor);
    _historyWidthSum += corridor.$1;
    if (_history.length > 5) {
      _historyWidthSum -= _history.removeFirst().$1;
    }

    final now = DateTime.now();
    final avgWidth = _historyWidthSum / _history.length;
    final pos = _history.last.$2;

    NavigationDecision? result;

    if (avgWidth < 0.6) {
      const category = 'corridor_blocked';
      final last = _lastSpokenByCategory[category];
      if (last != null && now.difference(last) < _cooldownFor(category)) {
        return null;
      }
      result = NavigationDecision(
        S.get('corridor_blocked'),
        SpeechPriority.critical,
        0.0,
        category,
      );
    } else if (avgWidth < 1.2 && pos != 'center') {
      const category = 'corridor_narrow';
      final last = _lastSpokenByCategory[category];
      if (last != null && now.difference(last) < _cooldownFor(category)) {
        return null;
      }
      final dirText = pos == 'left' ? S.get('nav_left') : S.get('nav_right');
      result = NavigationDecision(
        '${S.get('narrow')} ${S.get('deviate')} $dirText, '
        '${avgWidth.toStringAsFixed(1)} ${S.get('approx_meters')}.',
        SpeechPriority.warning,
        pos == 'left' ? -0.6 : 0.6,
        category,
      );
    }

    if (result != null) _lastSpokenByCategory[result.category] = now;
    return result;
  }

  void reset() {
    _history.clear();
    _historyWidthSum = 0.0;
    _lastSpokenByCategory.clear();
  }

  Duration _cooldownFor(String category) =>
      _cooldownsByCategory[category] ?? const Duration(seconds: 4);
}

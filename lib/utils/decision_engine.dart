import '../../models/speech_job.dart';
import '../../models/strings.dart';

class NavigationDecision {
  final String text;
  final SpeechPriority priority;
  final double pan;

  const NavigationDecision(this.text, this.priority, this.pan);
}

class DecisionEngine {
  final List<(double, String)> _history = [];

  DateTime _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _cooldown = Duration(seconds: 4);

  NavigationDecision? evaluate((double, String)? corridor) {
    if (corridor == null) {
      _history.clear();
      return null;
    }

    _history.add(corridor);
    if (_history.length > 5) _history.removeAt(0);

    final now = DateTime.now();
    if (now.difference(_lastSpoken) < _cooldown) return null;
    final avgWidth =
        _history.map((e) => e.$1).reduce((a, b) => a + b) / _history.length;
    final pos = _history.last.$2;

    NavigationDecision? result;

    if (avgWidth < 0.6) {
      result = NavigationDecision(
        S.get('corridor_blocked'),
        SpeechPriority.critical,
        0.0,
      );
    } else if (avgWidth < 1.2 && pos != 'center') {
      final dirText = pos == 'left' ? S.get('nav_left') : S.get('nav_right');
      result = NavigationDecision(
        '${S.get('narrow')} ${S.get('deviate')} $dirText, '
        '${avgWidth.toStringAsFixed(1)} ${S.get('approx_meters')}.',
        SpeechPriority.warning,
        pos == 'left' ? -0.6 : 0.6,
      );
    }

    if (result != null) _lastSpoken = now;
    return result;
  }

  void reset() {
    _history.clear();
    _lastSpoken = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

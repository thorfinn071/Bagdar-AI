import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/utils/alert_filter.dart';

AlertCandidate _cand(
  String text,
  SpeechPriority p,
  AlertCategory cat, {
  double urgency = 0.5,
  double pan = 0.0,
  int? trackId,
  double? distanceM,
}) => AlertCandidate(
  text: text,
  priority: p,
  pan: pan,
  category: cat,
  urgency: urgency,
  trackId: trackId,
  distanceM: distanceM,
);

void main() {
  group('Safety audit D-2: same-category critical on opposite sides', () {
    test('two critical approachingVehicle candidates on OPPOSITE sides '
        '(pan signs differ) are BOTH announced', () {
      final f = AlertFilter();
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      f.add(
        _cand(
          'car left',
          SpeechPriority.critical,
          AlertCategory.approachingVehicle,
          urgency: 0.9,
          pan: -0.5,
        ),
      );
      f.add(
        _cand(
          'car right',
          SpeechPriority.critical,
          AlertCategory.approachingVehicle,
          urgency: 0.9,
          pan: 0.5,
        ),
      );

      final winners = f.flushMulti(1, now);

      expect(
        winners.length,
        2,
        reason:
            'both simultaneous critical vehicles on opposite sides '
            'must be announced — directional info must not be dropped',
      );
      expect(
        winners.map((w) => w.text),
        containsAll(['car left', 'car right']),
      );
    });

    test('two critical approachingVehicle candidates on the SAME side '
        '(pan signs match) — only the higher-urgency one is announced', () {
      final f = AlertFilter();
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      f.add(
        _cand(
          'car A',
          SpeechPriority.critical,
          AlertCategory.approachingVehicle,
          urgency: 0.9,
          pan: -0.5,
        ),
      );
      f.add(
        _cand(
          'car B',
          SpeechPriority.critical,
          AlertCategory.approachingVehicle,
          urgency: 0.8,
          pan: -0.3,
        ),
      );

      final winners = f.flushMulti(1, now);

      expect(
        winners.length,
        1,
        reason:
            'same-side duplicates of the same category must still '
            'collapse to a single announcement',
      );
      expect(winners.single.text, 'car A');
    });

    test('critical + warning of the same category — only the critical wins '
        '(non-critical same-category exclusion is unchanged)', () {
      final f = AlertFilter();
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      f.add(
        _cand(
          'car critical',
          SpeechPriority.critical,
          AlertCategory.approachingVehicle,
          urgency: 0.9,
          pan: -0.5,
        ),
      );
      f.add(
        _cand(
          'car warning',
          SpeechPriority.warning,
          AlertCategory.approachingVehicle,
          urgency: 0.9,
          pan: 0.5,
        ),
      );

      final winners = f.flushMulti(1, now);

      expect(winners.length, 1);
      expect(winners.single.priority, SpeechPriority.critical);
      expect(winners.single.text, 'car critical');
    });

    test('a critical and a different-category candidate still both win '
        '(existing cross-category behavior is unaffected)', () {
      final f = AlertFilter();
      final now = DateTime(2025, 1, 1, 12, 0, 0);
      f.add(
        _cand(
          'wall ahead',
          SpeechPriority.critical,
          AlertCategory.corridorBlocked,
          urgency: 0.9,
          pan: 0.0,
        ),
      );
      f.add(
        _cand(
          'car right',
          SpeechPriority.warning,
          AlertCategory.approachingVehicle,
          urgency: 0.5,
          pan: 0.5,
        ),
      );

      final winners = f.flushMulti(1, now);

      expect(winners.length, 2);
      expect(winners.first.priority, SpeechPriority.critical);
      expect(winners.last.priority, SpeechPriority.warning);
    });
  });
}

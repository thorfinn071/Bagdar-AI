import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/utils/alert_filter.dart';

void main() {
  test(
    'new generic-obstacle track is not hidden by another track cooldown',
    () {
      final f = AlertFilter();
      final t0 = DateTime(2026, 1, 1, 12);
      f.add(
        const AlertCandidate(
          text: 'Препятствие впереди.',
          priority: SpeechPriority.critical,
          pan: 0,
          category: AlertCategory.genericObstacle,
          urgency: 0.9,
          trackId: 1,
        ),
      );
      expect(f.flush(0, t0), isNotNull);

      f.add(
        const AlertCandidate(
          text: 'Препятствие слева.',
          priority: SpeechPriority.critical,
          pan: -0.5,
          category: AlertCategory.genericObstacle,
          urgency: 0.9,
          trackId: 2,
        ),
      );
      final second = f.flush(0, t0.add(const Duration(milliseconds: 200)));
      expect(
        second,
        isNotNull,
        reason: 'new trackId must not inherit cooldown',
      );
      expect(second!.trackId, 2);
    },
  );

  test('same generic track is cooled down', () {
    final f = AlertFilter();
    final t0 = DateTime(2026, 1, 1, 12);
    f.add(
      const AlertCandidate(
        text: 'a',
        priority: SpeechPriority.critical,
        pan: 0,
        category: AlertCategory.genericObstacle,
        urgency: 0.9,
        trackId: 7,
      ),
    );
    expect(f.flush(0, t0), isNotNull);
    f.add(
      const AlertCandidate(
        text: 'b',
        priority: SpeechPriority.critical,
        pan: 0,
        category: AlertCategory.genericObstacle,
        urgency: 0.9,
        trackId: 7,
      ),
    );
    expect(f.flush(0, t0.add(const Duration(milliseconds: 200))), isNull);
  });

  test('no language claims the path is clear', () {
    const banned = [
      'Путь свободен',
      'Препятствий нет',
      'Жол бос',
      'Кедергі жоқ',
      'Path clear',
      'No obstacles',
    ];
    for (final lang in AppLanguage.values) {
      AppStrings.setLanguage(lang);
      for (final key in [
        'status_no_obstacle',
        'status_analysis_active',
        'path_clear',
        'path_clear_label',
        'path_clear_cane',
        'scene_see_none',
      ]) {
        final v = AppStrings.get(key);
        for (final b in banned) {
          expect(
            v.toLowerCase().contains(b.toLowerCase()),
            isFalse,
            reason: 'lang=${lang.name} key=$key still contains "$b": $v',
          );
        }
      }
    }
  });

  test('generic copy exists in RU/KK/EN', () {
    for (final lang in AppLanguage.values) {
      AppStrings.setLanguage(lang);
      for (final key in [
        'generic_obstacle_ahead',
        'generic_obstacle_stop',
        'generic_obstacle_left',
        'generic_obstacle_right',
        'generic_obstacle_overhead',
        'spatial_analysis_limited',
      ]) {
        final v = AppStrings.get(key);
        expect(v, isNot(key));
        expect(v, isNotEmpty);
      }
    }
  });
}

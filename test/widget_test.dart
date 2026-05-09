import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/main.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/models/strings.dart';
import 'package:bagdar/utils/alert_filter.dart';
import 'package:bagdar/utils/decision_engine.dart';

void main() {
  setUp(() {
    AppStrings.setLanguage(AppLanguage.ru);
  });

  testWidgets('BagdarApp builds with a provided home widget',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BagdarApp(home: SizedBox()));

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(SizedBox), findsOneWidget);
  });

  test('DecisionEngine returns a critical alert for blocked corridor', () {
    final engine = DecisionEngine();

    final result = engine.evaluate((0.4, 'center'));

    expect(result, isNotNull);
    expect(result!.priority, SpeechPriority.critical);
    expect(result.text, AppStrings.get('corridor_blocked'));
  });

  test('DecisionEngine returns a warning for a narrow side corridor', () {
    final engine = DecisionEngine();

    final result = engine.evaluate((0.9, 'left'));

    expect(result, isNotNull);
    expect(result!.priority, SpeechPriority.warning);
    expect(result.text, contains(AppStrings.get('nav_left')));
  });

  test('AlertFilter prefers the strongest candidate and suppresses noise', () {
    final filter = AlertFilter();
    final now = DateTime.now();

    filter.add(const AlertCandidate(
      text: 'info alert',
      priority: SpeechPriority.info,
      pan: 0.0,
      category: AlertCategory.obstacleFar,
      urgency: 0.2,
    ));
    filter.add(const AlertCandidate(
      text: 'critical alert',
      priority: SpeechPriority.critical,
      pan: 0.0,
      category: AlertCategory.obstacleClose,
      urgency: 0.9,
    ));

    final winner = filter.flush(1, now);

    expect(winner, isNotNull);
    expect(winner!.priority, SpeechPriority.critical);
    expect(winner.text, 'critical alert');
  });

  test('AlertFilter suppresses info alerts in dense scenes', () {
    final filter = AlertFilter();

    filter.add(const AlertCandidate(
      text: 'dense scene info',
      priority: SpeechPriority.info,
      pan: 0.0,
      category: AlertCategory.obstacleFar,
      urgency: 0.1,
    ));

    final winner = filter.flush(5, DateTime.now());

    expect(winner, isNull);
  });

  test(
      'AlertFilter (OPT-01) lets info alerts from reliable tracks through in '
      'dense scenes', () {
    final filter = AlertFilter();

    filter.add(const AlertCandidate(
      text: 'reliable track info',
      priority: SpeechPriority.info,
      pan: 0.0,
      category: AlertCategory.obstacleFar,
      urgency: 0.1,
      trackId: 42,
    ));

    final winner = filter.flush(
      5,
      DateTime.now(),
      reliableTrackIds: <int>{42},
    );

    expect(winner, isNotNull);
    expect(winner!.trackId, 42);
  });

  test(
      'AlertFilter (OPT-01) still suppresses info alerts from flickering '
      'tracks in dense scenes', () {
    final filter = AlertFilter();

    filter.add(const AlertCandidate(
      text: 'new flickering track info',
      priority: SpeechPriority.info,
      pan: 0.0,
      category: AlertCategory.obstacleFar,
      urgency: 0.1,
      trackId: 99,
    ));

    final winner = filter.flush(
      5,
      DateTime.now(),
      reliableTrackIds: <int>{42}, // 99 is not listed as reliable
    );

    expect(winner, isNull);
  });
}

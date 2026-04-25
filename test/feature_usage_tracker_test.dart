import 'package:bagdar/services/feature_usage_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FeatureUsageTracker', () {
    test('starts empty before init', () {
      final tracker = FeatureUsageTracker.instance;
      expect(tracker.count('mode_used_street'), 0);
      expect(tracker.snapshot(), isEmpty);
    });

    test('increment + flush persists across init()', () async {
      final tracker = FeatureUsageTracker.instance;
      await tracker.reset();
      await tracker.init();

      tracker.increment(FeatureUsageKeys.mode('street'));
      tracker.increment(FeatureUsageKeys.mode('street'));
      tracker.increment(FeatureUsageKeys.gesture('swipe_up'));
      await tracker.flush();

      expect(tracker.count('mode_used_street'), 2);
      expect(tracker.count('gesture_used_swipe_up'), 1);

      
      await tracker.init();
      expect(tracker.count('mode_used_street'), 2);
      expect(tracker.count('gesture_used_swipe_up'), 1);
    });

    test('reset clears counters and tutorial timestamp', () async {
      final tracker = FeatureUsageTracker.instance;
      await tracker.reset();
      await tracker.init();

      tracker.increment(FeatureUsageKeys.sosTriggered);
      await tracker.setTutorialCompletedNow();
      await tracker.flush();

      expect(tracker.count('sos_triggered'), 1);
      expect(tracker.tutorialCompletedAt, isNotNull);

      await tracker.reset();
      await tracker.init();
      expect(tracker.count('sos_triggered'), 0);
      expect(tracker.tutorialCompletedAt, isNull);
      expect(tracker.snapshot(), isEmpty);
    });

    test('snapshot is unmodifiable', () async {
      final tracker = FeatureUsageTracker.instance;
      await tracker.reset();
      await tracker.init();
      tracker.increment(FeatureUsageKeys.settingsOpened);

      final snap = tracker.snapshot();
      expect(() => snap['x'] = 1, throwsUnsupportedError);
    });

    test('ignores empty key and non-positive deltas', () async {
      final tracker = FeatureUsageTracker.instance;
      await tracker.reset();
      await tracker.init();

      tracker.increment('');
      tracker.increment('mode_used_street', by: 0);
      tracker.increment('mode_used_street', by: -3);
      await tracker.flush();

      expect(tracker.count('mode_used_street'), 0);
      expect(tracker.snapshot(), isEmpty);
    });
  });
}

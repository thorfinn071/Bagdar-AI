import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bagdar/camera/alert_manager.dart';
import 'package:bagdar/models/app_mode.dart';
import 'package:bagdar/models/speech_job.dart';
import 'package:bagdar/services/earcon_service.dart';
import 'package:bagdar/services/settings_service.dart';
import 'package:bagdar/services/tts_service.dart';
import 'package:bagdar/utils/alert_filter.dart';
import 'package:bagdar/viewmodels/camera_view_model.dart';

class _RecordingTts extends TtsService {
  final List<({String text, SpeechPriority priority})> calls = [];
  _RecordingTts() : super.forTesting();

  @override
  void say(
    String text,
    SpeechPriority priority, {
    double pan = 0.0,
    int? trackId,
    String? actionId,
    String? hazardId,
    DateTime? expiresAt,
    bool barge = false,
    bool skipHaptic = false,
  }) {
    calls.add((text: text, priority: priority));
  }
}

int _criticalCountFromRecorder(_RecordingTts tts) =>
    tts.calls.where((c) => c.priority == SpeechPriority.critical).length;

int _criticalCount(List<SpeechJob> jobs) =>
    jobs.where((j) => j.priority == SpeechPriority.critical).length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Settings.instance.init();
  });

  group('AlertManager.reset() — Safety audit C-2', () {
    test('reset() clears the AlertFilter per-category critical cooldown that '
        'previously survived indefinitely (AlertManager.reset() was dead code '
        '— never called anywhere in lib/)', () {
      final tts = _RecordingTts();
      final mgr = AlertManager(tts: tts, earcon: EarconService());
      final t0 = DateTime(2025, 1, 1, 12, 0, 0);

      mgr.handleDepthHazard(
        text: 'hazard corridor blocked A',
        priority: SpeechPriority.critical,
        pan: 0.0,
        category: AlertCategory.corridorBlocked,
        now: t0,
      );
      expect(_criticalCountFromRecorder(tts), 1);

      // Still well within kCriticalRepeatCooldownSafety (2000 ms) for this
      // safety category — a same-category critical must be suppressed.
      final t1 = t0.add(const Duration(milliseconds: 500));
      mgr.handleDepthHazard(
        text: 'hazard corridor blocked B',
        priority: SpeechPriority.critical,
        pan: 0.0,
        category: AlertCategory.corridorBlocked,
        now: t1,
      );
      expect(
        _criticalCountFromRecorder(tts),
        1,
        reason:
            'per-category critical cooldown must gate a repeat within '
            'the safety window',
      );

      mgr.reset();

      // Same instant, but reset() must have cleared _lastCriticalByCat so
      // this is treated as a brand-new hazard, not gated by a stale
      // cooldown timestamp from before the reset.
      mgr.handleDepthHazard(
        text: 'hazard corridor blocked C',
        priority: SpeechPriority.critical,
        pan: 0.0,
        category: AlertCategory.corridorBlocked,
        now: t1,
      );
      expect(
        _criticalCountFromRecorder(tts),
        2,
        reason:
            'reset() must fully clear AlertFilter cooldown/dedup state — a '
            'stale suppression window leaking across a mode switch could '
            'mute a genuinely new hazard in the new mode',
      );
    });

    test('CameraViewModel.setMode() calls alertMgr.reset() (previously only '
        'markModeSwitch ran, leaving AlertFilter cooldowns from the old mode '
        'active)', () {
      TtsService.instance.debugForceTestReady();
      final vm = CameraViewModel();
      final t0 = DateTime(2025, 1, 1, 12, 0, 0);

      vm.alertMgr.handleDepthHazard(
        text: 'hazard corridor blocked before switch',
        priority: SpeechPriority.critical,
        pan: 0.0,
        category: AlertCategory.corridorBlocked,
        now: t0,
      );
      expect(_criticalCount(TtsService.instance.queueSnapshot), 1);

      vm.setMode(AppMode.cane);

      // Immediately after the mode switch (well inside
      // kCriticalRepeatCooldownSafety), a fresh hazard in the same
      // safety category must NOT be swallowed by a cooldown timestamp
      // inherited from the old mode — proving setMode() actually invoked
      // alertMgr.reset().
      final t1 = t0.add(const Duration(milliseconds: 100));
      vm.alertMgr.handleDepthHazard(
        text: 'hazard corridor blocked after switch',
        priority: SpeechPriority.critical,
        pan: 0.0,
        category: AlertCategory.corridorBlocked,
        now: t1,
      );
      expect(
        _criticalCount(TtsService.instance.queueSnapshot),
        2,
        reason:
            'setMode() must call alertMgr.reset() so a new hazard right '
            'after a mode switch is not muted by a stale cooldown from the '
            'previous mode',
      );
    });
  });
}

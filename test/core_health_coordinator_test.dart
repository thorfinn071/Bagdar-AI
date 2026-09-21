import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/core/core_health_coordinator.dart';

void markRequiredVision(
  CoreHealthCoordinator h,
  DateTime t, {
  ComponentState vision = ComponentState.available,
  ComponentState audio = ComponentState.available,
  ComponentState haptics = ComponentState.available,
  ComponentState accel = ComponentState.available,
  ComponentState gyro = ComponentState.available,
}) {
  h.note(
    component: CoreComponent.cameraPermission,
    state: ComponentState.available,
    reasonCode: 'granted',
    now: t,
  );
  h.note(
    component: CoreComponent.cameraSession,
    state: vision,
    reasonCode: 'session',
    now: t,
  );
  h.note(
    component: CoreComponent.imageStream,
    state: vision,
    reasonCode: 'stream',
    now: t,
  );
  h.note(
    component: CoreComponent.alertAudio,
    state: audio,
    reasonCode: 'tts',
    now: t,
  );
  h.note(
    component: CoreComponent.haptics,
    state: haptics,
    reasonCode: 'haptic',
    now: t,
  );
  h.note(
    component: CoreComponent.accelerometer,
    state: accel,
    reasonCode: 'accel',
    now: t,
  );
  h.note(
    component: CoreComponent.gyroscope,
    state: gyro,
    reasonCode: 'gyro',
    now: t,
  );
}

void main() {
  late CoreHealthCoordinator health;
  late DateTime t0;

  setUp(() {
    health = CoreHealthCoordinator();
    t0 = DateTime.utc(2026, 1, 1, 12);
  });

  group('capability truth table', () {
    test('camera down makes mobility vision unavailable', () {
      markRequiredVision(health, t0, vision: ComponentState.unavailable);
      final snap = health.snapshot(t0);
      expect(
        snap.capability(CoreCapability.mobilityVision),
        ComponentState.unavailable,
      );
      expect(snap.runState, CoreRunState.unavailable);
      expect(snap.mayAnnounceOperational, isFalse);
    });

    test('YOLO down does not by itself make mobility vision unavailable', () {
      markRequiredVision(health, t0);
      health.note(
        component: CoreComponent.semanticObjects,
        state: ComponentState.unavailable,
        reasonCode: 'yolo_reload_failed',
        now: t0,
      );
      final snap = health.snapshot(t0);
      expect(
        snap.capability(CoreCapability.mobilityVision),
        ComponentState.available,
      );
      expect(
        snap.capability(CoreCapability.movingThreatAwareness),
        ComponentState.unavailable,
      );
      expect(snap.runState, CoreRunState.operational);
    });

    test('geometry unavailable degrades generic and surface capabilities', () {
      markRequiredVision(health, t0);
      health.note(
        component: CoreComponent.genericGeometry,
        state: ComponentState.unavailable,
        reasonCode: 'ncnn_session_disabled',
        now: t0,
      );
      final snap = health.snapshot(t0);
      expect(
        snap.capability(CoreCapability.genericObstacleAwareness),
        ComponentState.unavailable,
      );
      expect(snap.runState, CoreRunState.degraded);
    });

    test('gyro unavailable degrades fall detection, does not kill it', () {
      markRequiredVision(health, t0, gyro: ComponentState.unavailable);
      final snap = health.snapshot(t0);
      expect(
        snap.capability(CoreCapability.fallDetection),
        ComponentState.degraded,
      );
      expect(snap.runState, CoreRunState.degraded);
    });

    test('accelerometer unavailable makes fall detection unavailable', () {
      markRequiredVision(health, t0, accel: ComponentState.unavailable);
      expect(
        health.snapshot(t0).capability(CoreCapability.fallDetection),
        ComponentState.unavailable,
      );
    });

    test('TTS unavailable with haptic available is degraded, not silent', () {
      markRequiredVision(health, t0, audio: ComponentState.unavailable);
      final snap = health.snapshot(t0);
      expect(snap.runState, CoreRunState.degraded);
      expect(snap.reasonCode, 'alert_audio_unavailable');
    });

    test('haptic unavailable with TTS available is degraded', () {
      markRequiredVision(health, t0, haptics: ComponentState.unavailable);
      expect(health.snapshot(t0).runState, CoreRunState.degraded);
    });
  });

  group('startup announcements', () {
    test(
      'does not announce operational while camera is still initializing',
      () {
        health.note(
          component: CoreComponent.alertAudio,
          state: ComponentState.available,
          reasonCode: 'tts',
          now: t0,
        );
        health.drainAnnouncements();
        final snap = health.snapshot(t0);
        expect(snap.runState, CoreRunState.starting);
        expect(snap.mayAnnounceOperational, isFalse);
      },
    );

    test('announces system_ready only after required vision is available', () {
      markRequiredVision(health, t0);
      final notes = health.drainAnnouncements();
      expect(notes, isNotEmpty);
      expect(notes.last.stringKey, 'system_ready');
      expect(health.snapshot(t0).isOperational, isTrue);
    });

    test('camera unavailable never emits a ready event', () {
      markRequiredVision(health, t0, vision: ComponentState.unavailable);
      final keys = health.drainAnnouncements().map((a) => a.stringKey);
      expect(keys, isNot(contains('system_ready')));
    });

    test('recovery is announced once then not spammed', () {
      markRequiredVision(health, t0);
      health.drainAnnouncements();
      health.note(
        component: CoreComponent.imageStream,
        state: ComponentState.unavailable,
        reasonCode: 'camera_stall',
        now: t0.add(const Duration(seconds: 1)),
      );
      health.drainAnnouncements();
      health.note(
        component: CoreComponent.imageStream,
        state: ComponentState.available,
        reasonCode: 'stream_resumed',
        now: t0.add(const Duration(seconds: 2)),
      );
      health.note(
        component: CoreComponent.cameraSession,
        state: ComponentState.available,
        reasonCode: 'session',
        now: t0.add(const Duration(seconds: 2)),
      );
      final recovered = health.drainAnnouncements();
      expect(
        recovered.map((a) => a.stringKey),
        contains('core_health_recovered'),
      );
      health.note(
        component: CoreComponent.imageStream,
        state: ComponentState.available,
        reasonCode: 'stream_resumed',
        now: t0.add(const Duration(seconds: 3)),
      );
      expect(health.drainAnnouncements(), isEmpty);
    });

    test('degraded announcement is cooldown-deduplicated', () {
      markRequiredVision(health, t0);
      health.drainAnnouncements();
      health.note(
        component: CoreComponent.genericGeometry,
        state: ComponentState.degraded,
        reasonCode: 'low_confidence',
        now: t0.add(const Duration(seconds: 1)),
      );
      expect(health.drainAnnouncements(), isNotEmpty);
      health.note(
        component: CoreComponent.genericGeometry,
        state: ComponentState.degraded,
        reasonCode: 'plane_fit',
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(health.drainAnnouncements(), isEmpty);
    });
  });

  test('transition log is bounded', () {
    markRequiredVision(health, t0);
    for (var i = 0; i < 80; i++) {
      health.note(
        component: CoreComponent.genericGeometry,
        state: i.isEven ? ComponentState.degraded : ComponentState.available,
        reasonCode: 'tick_$i',
        now: t0.add(Duration(seconds: i)),
      );
    }
    expect(health.transitionLog.length, CoreHealthCoordinator.maxLog);
  });

  test('session reset clears operational latch', () {
    markRequiredVision(health, t0);
    health.drainAnnouncements();
    health.resetSession(t0.add(const Duration(seconds: 5)));
    markRequiredVision(health, t0.add(const Duration(seconds: 6)));
    expect(
      health.drainAnnouncements().map((a) => a.stringKey),
      contains('system_ready'),
    );
  });
}

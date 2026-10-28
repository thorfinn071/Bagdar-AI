import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:bagdar/safety/runtime/camera_scan_age_gate.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/passage_clearance_contract/scenarios.dart';

void main() {
  late int now;
  late CameraScanAgeGate gate;
  setUp(() {
    now = 1020000;
    gate = CameraScanAgeGate(clockUs: () => now)..beginSession(1);
  });
  CameraScanAgeOutcome process({
    int oldest = 1000000,
    PassageClearanceObservation? Function()? compute,
  }) => gate.process(
    oldestCaptureUs: oldest,
    captureContext: contractContext,
    calibration: fixtureCalibration(),
    request: contractRequest,
    compute: compute ?? () => fixtureObservation(),
  );

  void discarded(CameraScanAgeOutcome outcome, CameraScanAgeStatus status) {
    expect(outcome.status, status);
    expect(outcome.observation, isNull);
    expect(outcome.decision, isNull);
  }

  test('fresh decision releases once with original capture and expiry', () {
    final outcome = process();
    final released = gate.release(outcome);
    expect(released.status, CameraScanAgeStatus.admitted);
    expect(released.observation!.oldestEvidenceTimestampUs, 1000000);
    expect(released.decision!.validUntilUs, 1100000);
    discarded(gate.release(outcome), CameraScanAgeStatus.consumed);
  });
  test('stale oldest evidence rejects before invoking compute', () {
    var calls = 0;
    discarded(
      process(
        oldest: 0,
        compute: () {
          calls++;
          return fixtureObservation();
        },
      ),
      CameraScanAgeStatus.expiredBeforeCompute,
    );
    expect(calls, 0);
  });
  test('clock advances during compute and discards expired completion', () {
    discarded(
      process(
        compute: () {
          now = 1100001;
          return fixtureObservation();
        },
      ),
      CameraScanAgeStatus.expiredAfterCompute,
    );
  });
  test('dispatch delay discards previously admitted clear', () {
    final outcome = process();
    now = 1100001;
    discarded(gate.release(outcome), CameraScanAgeStatus.expiredBeforeDispatch);
  });
  test('exact 100ms boundary is admitted, next microsecond expires', () {
    now = 1100000;
    expect(gate.release(process()).status, CameraScanAgeStatus.admitted);
    now++;
    discarded(process(), CameraScanAgeStatus.expiredBeforeCompute);
  });
  test('clock rollback during compute discards', () {
    discarded(
      process(
        compute: () {
          now--;
          return fixtureObservation();
        },
      ),
      CameraScanAgeStatus.invalidClock,
    );
  });
  test('clock rollback at release discards', () {
    final outcome = process();
    now--;
    discarded(gate.release(outcome), CameraScanAgeStatus.invalidClock);
  });
  test('clock rollback before process discards', () {
    process();
    now--;
    discarded(process(), CameraScanAgeStatus.invalidClock);
  });
  test('session changes during compute discard', () {
    discarded(
      process(
        compute: () {
          gate.beginSession(2);
          return fixtureObservation();
        },
      ),
      CameraScanAgeStatus.rejectedSession,
    );
  });
  test('background/session end invalidates pending handle', () {
    final outcome = process();
    gate.endSession();
    discarded(gate.release(outcome), CameraScanAgeStatus.rejectedSession);
  });
  test('new process invalidates prior release', () {
    final previous = process();
    process();
    discarded(gate.release(previous), CameraScanAgeStatus.consumed);
  });
  test('changing declared oldest cannot renew captured evidence', () {
    discarded(process(oldest: 999000), CameraScanAgeStatus.invalidIdentity);
  });
  for (final fault in [
    'missing',
    'throw',
    'frame',
    'session',
    'depth-time',
    'future',
    'model',
    'relative',
    'unhealthy',
    'unknown',
  ]) {
    test('fails closed on $fault', () {
      final outcome = process(
        compute: () {
          if (fault == 'missing') return null;
          if (fault == 'throw') throw StateError('worker failure');
          return fixtureObservation(
            frame: fault == 'frame' ? 2 : 1,
            session: fault == 'session' ? 2 : 1,
            depthUs: fault == 'depth-time' ? 999000 : 1000000,
            producedUs: fault == 'future' ? 1020001 : 1010000,
            modelHash: fault == 'model' ? 'other' : 'synthetic-bounds-hash-v1',
            units: fault == 'relative'
                ? PassageUnits.relativeProximity
                : PassageUnits.metricMeters,
            healthy: fault != 'unhealthy',
            sections: fault == 'unknown'
                ? [fixtureSection(state: PassageSectionState.unknown, body: 0)]
                : null,
          );
        },
      );
      expect(outcome.status, isNot(CameraScanAgeStatus.admitted));
      expect(outcome.observation, isNull);
      expect(outcome.decision, isNull);
    });
  }
  test('blocked hazard can release a fresh stop, never clear', () {
    final released = gate.release(
      process(
        compute: () => fixtureObservation(
          sections: [fixtureSection(state: PassageSectionState.blocked)],
        ),
      ),
    );
    expect(released.status, CameraScanAgeStatus.admitted);
    expect(released.decision!.status, PassageClearanceStatus.blocked);
  });
}

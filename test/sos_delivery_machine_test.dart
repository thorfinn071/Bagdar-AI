import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/sos_delivery.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1);

  test('composer opened is not modem success', () {
    final m = SosDeliveryMachine();
    m.start(t0);
    m.composerOpened(t0);
    expect(m.status.phase, SosDeliveryPhase.composerOpened);
    expect(m.status.modemAccepted, isFalse);
    expect(m.status.recipientDelivered, isFalse);
    expect(m.status.isTerminal, isTrue);
  });

  test('dialer opened is not delivery', () {
    final m = SosDeliveryMachine();
    m.dialerOpened(t0);
    expect(m.status.phase, SosDeliveryPhase.dialerOpened);
    expect(m.status.modemAccepted, isFalse);
  });

  test('modem acceptance is distinct from recipient delivery', () {
    final m = SosDeliveryMachine();
    m.sending(t0);
    m.acceptedByModem(t0);
    expect(m.status.modemAccepted, isTrue);
    expect(m.status.recipientDelivered, isFalse);
    m.deliveryUnconfirmed(t0.add(const Duration(seconds: 10)));
    expect(m.status.phase, SosDeliveryPhase.deliveryUnconfirmed);
    expect(m.status.recipientDelivered, isFalse);
  });

  test('timeout is a terminal failure-shaped state', () {
    final m = SosDeliveryMachine();
    m.sending(t0);
    m.timeout(t0.add(const Duration(seconds: 10)));
    expect(m.status.phase, SosDeliveryPhase.timedOut);
    expect(m.status.isTerminal, isTrue);
  });
}

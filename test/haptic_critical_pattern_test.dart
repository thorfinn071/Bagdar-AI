import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/constants.dart';

void main() {
  test('critical alert pattern is distinct from stall/cooldown patterns', () {
    expect(
      identical(kHapticCriticalAlertPattern, kHapticTtsStallPattern),
      isFalse,
    );
    expect(
      identical(kHapticCriticalAlertPattern, kHapticCriticalCooldownPattern),
      isFalse,
    );
    expect(kHapticCriticalAlertPattern.length, greaterThan(1));
  });
}

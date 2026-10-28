import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_fast_motion_shadow_benchmark.dart';

void main() {
  test(
    'independent motion reaches shadow runtime without NN and cannot clear unknown',
    () => verifyFastMotionShadow(
      write: const bool.fromEnvironment('BAGDAR_WRITE_FAST_MOTION'),
    ),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

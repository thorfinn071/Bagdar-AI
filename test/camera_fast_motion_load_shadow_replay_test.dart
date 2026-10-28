import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_fast_motion_load_shadow_benchmark.dart';

void main() {
  test(
    'independent motion reaches shadow runtime without NN and cannot clear unknown',
    () => verifyFastMotionLoadShadow(
      write: const bool.fromEnvironment('BAGDAR_WRITE_FAST_MOTION_LOAD'),
    ),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

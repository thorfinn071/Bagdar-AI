import 'package:flutter_test/flutter_test.dart';
import 'harness/camera_fast_motion_packed_shadow_benchmark.dart';

void main() {
  test(
    'packed transport preserves frozen shadow decisions and unknown',
    verifyFastMotionPackedShadow,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

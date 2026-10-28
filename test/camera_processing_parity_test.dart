import 'package:flutter_test/flutter_test.dart';
import '../tool/model_benchmark/profile_camera_processing.dart' as profile;

void main() {
  test(
    'cached matcher is identical on all known scale-motion regression inputs',
    () {
      const write = bool.fromEnvironment('BAGDAR_WRITE_PROCESSING_PROFILE');
      profile.main([
        write ? '--write' : '--check',
        if (!write) '--known-corpus-regression',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

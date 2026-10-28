import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/core/simulation_build.dart';
import 'package:bagdar/services/sos_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'simulation never attempts SMS, location, dialer or follow-up dispatch',
    () async {
      if (!simulationBuild) return;
      final calls = <String>[];
      for (final name in [
        'bagdar/sms',
        'flutter.baseflow.com/geolocator',
        'plugins.flutter.io/url_launcher',
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), (call) async {
              calls.add('$name/${call.method}');
              throw StateError('External action must be unreachable');
            });
      }
      final sos = SosService();
      expect(await sos.sendSos(), SosResult.launchFailed);
      sos.queueFollowUpFall();
      expect(sos.pendingFollowUpCount, 0);
      expect(calls, isEmpty);
    },
  );
}

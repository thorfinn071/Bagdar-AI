import 'package:bagdar/services/acoustic_world_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bagdar/audio_capture');
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'start' ? {'started': false} : null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Core can dispose the never-initialized deferred service twice',
    () async {
      final model = AcousticWorldModel();
      model.dispose();
      model.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((c) => c == 'start'), isEmpty);
      expect(calls.where((c) => c == 'stop').length, 1);
      expect(model.isRunning, false);
      expect(model.isEnabled, false);
    },
  );
  test(
    'disposal during asynchronous initialization cannot start capture',
    () async {
      final model = AcousticWorldModel();
      final initializing = model.init();
      model.dispose();
      await initializing;
      expect(calls.where((c) => c == 'start'), isEmpty);
      expect(model.isRunning, false);
    },
  );
  test(
    'disabled initialized components dispose without opening audio',
    () async {
      final model = AcousticWorldModel()..setEnabled(false);
      await model.init();
      model.dispose();
      model.setEnabled(true);
      await model.init();
      expect(calls.where((c) => c == 'start'), isEmpty);
      expect(model.isEnabled, false);
    },
  );
  test(
    'repeated init never reassigns late components; failed capture stays stopped',
    () async {
      final model = AcousticWorldModel();
      await model.init();
      await model.init();
      expect(calls.where((c) => c == 'start').length, 1);
      expect(model.isRunning, false);
      model.dispose();
    },
  );
}

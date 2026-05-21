import 'package:flutter_test/flutter_test.dart';
import 'package:bagdar/services/model_pack_manager.dart';

void main() {
  group('ModelPack', () {
    test('round-trip JSON serialization', () {
      const pack = ModelPack(
        id: 'livestock_kz_v1',
        name: 'Kazakhstan Livestock',
        region: 'central_asia',
        modelFileName: 'livestock_kz.tflite',
        labelsFileName: 'livestock_kz_labels.txt',
        downloadUrl: 'https://example.com/livestock_kz.tflite',
        sha256: 'abc123def456',
        sizeBytes: 15000000,
        version: 1,
        classes: ['cow', 'horse', 'sheep', 'goat', 'chicken'],
      );
      final json = pack.toJson();
      final decoded = ModelPack.fromJson(json);

      expect(decoded.id, 'livestock_kz_v1');
      expect(decoded.name, 'Kazakhstan Livestock');
      expect(decoded.region, 'central_asia');
      expect(decoded.modelFileName, 'livestock_kz.tflite');
      expect(decoded.labelsFileName, 'livestock_kz_labels.txt');
      expect(decoded.sha256, 'abc123def456');
      expect(decoded.sizeBytes, 15000000);
      expect(decoded.version, 1);
      expect(decoded.classes, ['cow', 'horse', 'sheep', 'goat', 'chicken']);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'test',
        'name': 'Test Pack',
        'modelFile': 'test.tflite',
        'labelsFile': 'test_labels.txt',
        'url': 'https://example.com/test.tflite',
        'sha256': '',
      };
      final pack = ModelPack.fromJson(json);
      expect(pack.id, 'test');
      expect(pack.region, '');
      expect(pack.sizeBytes, 0);
      expect(pack.version, 1);
      expect(pack.classes, isEmpty);
    });
  });

  group('ModelPackManager', () {
    late ModelPackManager manager;

    setUp(() {
      manager = ModelPackManager.instance;
      manager.resetForTesting();
    });

    test('initial state has no active pack', () {
      expect(manager.activePackId, null);
      expect(manager.activePack, null);
    });

    test('availablePacks is empty before fetch', () {
      expect(manager.availablePacks, isEmpty);
    });

    test('isInstalled returns false for unknown pack', () {
      expect(manager.isInstalled('nonexistent'), false);
    });

    test('deactivate clears active pack', () {
      manager.deactivate();
      expect(manager.activePackId, null);
    });
  });
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bagdar/models/model_bakeoff_contract.dart';
import 'package:bagdar/models/yolo26_output_decoder.dart';
import 'package:bagdar/services/model_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

String _sha256(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

void main() {
  group('Stage 6 production selection', () {
    test('keeps YOLOv8 control and does not promote a challenger', () {
      final selection = ModelService.instance.productionSelection;

      expect(
        selection.detectorModelId,
        BagdarModelCatalog.yoloV8Control.modelId,
      );
      expect(
        BagdarModelCatalog.detectorExperiments.map(
          (candidate) => candidate.modelId,
        ),
        isNot(contains(selection.detectorModelId)),
      );
      expect(
        BagdarModelCatalog.detectorExperiments.every(
          (candidate) =>
              candidate.lifecycle == ModelLifecycle.exportedExperiment,
        ),
        isTrue,
      );
    });

    test('chooses an explicit provider outcome for every depth tier', () {
      final depth = BagdarModelCatalog.productionSelection.depthByTier;

      expect(depth.map((entry) => entry.tier).toSet(), {
        'hardware',
        'ncnnVulkan',
        'ncnnCpu',
        'focalLength',
      });
      expect(
        depth
            .where((entry) => entry.tier.startsWith('ncnn'))
            .every((entry) => entry.modelId == 'midas-small-ncnn'),
        isTrue,
      );
      final hardware = depth.singleWhere((entry) => entry.tier == 'hardware');
      expect(hardware.providerId, 'ncnn-relative');
      expect(hardware.modelId, 'midas-small-ncnn');
      expect(hardware.reason, contains('aligned control'));
      expect(
        depth
            .singleWhere((entry) => entry.tier == 'focalLength')
            .geometryAvailable,
        isFalse,
      );
    });

    test(
      'traversability is explicitly deferred rather than silently mocked',
      () {
        const selection = BagdarModelCatalog.productionSelection;

        expect(selection.traversabilityModelId, isNull);
        expect(selection.traversabilityDecision, startsWith('deferred:'));
      },
    );
  });

  group('Stage 6 pinned artifacts', () {
    test('control and candidate hashes match the catalog', () {
      final artifacts = <ModelArtifactContract>[
        BagdarModelCatalog.yoloV8Control,
        ...BagdarModelCatalog.detectorExperiments,
      ];

      for (final artifact in artifacts) {
        expect(
          File(artifact.artifactPath).existsSync(),
          isTrue,
          reason: artifact.modelId,
        );
        expect(
          _sha256(artifact.artifactPath),
          artifact.sha256,
          reason: artifact.modelId,
        );
      }
    });

    test('YOLO11 416 matches the pinned BCN decoder shape', () {
      expect(BagdarModelCatalog.yoloV8Control.output.shape, <int>[1, 84, 3549]);
      expect(BagdarModelCatalog.yolo11n416.output.shape, <int>[1, 84, 3549]);
      expect(BagdarModelCatalog.yolo11n416.output.layout, TensorLayout.bcn);
      expect(BagdarModelCatalog.yolo11n416.decoderId, 'yolov8-v11-bcn-v1');
    });

    test('YOLO26 remains on a separate BNC decoder contract', () {
      expect(BagdarModelCatalog.yolo26n416.output.shape, <int>[1, 300, 6]);
      expect(BagdarModelCatalog.yolo26n416.output.layout, TensorLayout.bnc);
      expect(
        BagdarModelCatalog.yolo26n416.decoderId,
        isNot(BagdarModelCatalog.yolo11n416.decoderId),
      );
    });

    test('generated manifest agrees with the Dart catalog', () {
      final manifest =
          jsonDecode(
                File(
                  'model_export/candidates/manifest.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final candidates = (manifest['candidates'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final contract in BagdarModelCatalog.detectorExperiments) {
        final entry = candidates.singleWhere(
          (candidate) => candidate['modelId'] == contract.modelId,
        );
        expect(entry['artifactSha256'], contract.sha256);
        expect(
          (entry['output'] as Map<String, dynamic>)['shape'],
          contract.output.shape,
        );
      }
    });
  });

  group('YOLO26 independent experiment decoder', () {
    test('decodes, clamps and filters the end-to-end tensor', () {
      final values = Float32List(
        Yolo26OutputDecoder.maxDetections *
            Yolo26OutputDecoder.fieldsPerDetection,
      );
      values.setAll(0, <double>[-4, 10, 420, 210, 0.9, 2]);
      values.setAll(6, <double>[10, 10, 30, 30, 0.1, 1]);
      values.setAll(12, <double>[10, 10, 30, 30, 0.8, 99]);

      final detections = const Yolo26OutputDecoder().decode(
        values,
        shape: const <int>[1, 300, 6],
        inputWidth: 416,
        inputHeight: 416,
        scoreThreshold: 0.25,
      );

      expect(detections, hasLength(1));
      expect(detections.single.left01, 0);
      expect(detections.single.right01, 1);
      expect(detections.single.classId, 2);
      expect(detections.single.score, closeTo(0.9, 1e-6));
    });

    test('rejects a YOLOv8/11 tensor shape', () {
      expect(
        () => const Yolo26OutputDecoder().decode(
          Float32List(300 * 6),
          shape: const <int>[1, 84, 3549],
          inputWidth: 416,
          inputHeight: 416,
        ),
        throwsArgumentError,
      );
    });
  });
}

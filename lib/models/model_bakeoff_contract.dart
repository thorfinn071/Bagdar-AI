enum ModelDomain { detector, depth, traversability }

enum ModelLifecycle {
  productionControl,
  exportedExperiment,
  blockedMissingArtifact,
  deferred,
}

enum TensorLayout { nhwc, nchw, bcn, bnc, hw }

class ModelTensorContract {
  final String name;
  final List<int> shape;
  final String dataType;
  final TensorLayout layout;

  const ModelTensorContract({
    required this.name,
    required this.shape,
    required this.dataType,
    required this.layout,
  });
}

class ModelArtifactContract {
  final String modelId;
  final ModelDomain domain;
  final ModelLifecycle lifecycle;
  final String artifactPath;
  final String sha256;
  final String format;
  final String licenseId;
  final String preprocessId;
  final String decoderId;
  final ModelTensorContract input;
  final ModelTensorContract output;

  const ModelArtifactContract({
    required this.modelId,
    required this.domain,
    required this.lifecycle,
    required this.artifactPath,
    required this.sha256,
    required this.format,
    required this.licenseId,
    required this.preprocessId,
    required this.decoderId,
    required this.input,
    required this.output,
  });

  bool get isProductionControl => lifecycle == ModelLifecycle.productionControl;
}

class DepthTierModelSelection {
  final String tier;
  final String providerId;
  final String modelId;
  final bool geometryAvailable;
  final String reason;

  const DepthTierModelSelection({
    required this.tier,
    required this.providerId,
    required this.modelId,
    required this.geometryAvailable,
    required this.reason,
  });
}

class ProductionModelSelection {
  final String detectorModelId;
  final List<DepthTierModelSelection> depthByTier;
  final String? traversabilityModelId;
  final String traversabilityDecision;

  const ProductionModelSelection({
    required this.detectorModelId,
    required this.depthByTier,
    required this.traversabilityModelId,
    required this.traversabilityDecision,
  });
}

/// Pinned Stage 6 artifact contracts. Challengers remain experiments until
/// recorded-scene correctness, license and named-device gates all pass.
class BagdarModelCatalog {
  BagdarModelCatalog._();

  static const yoloV8Control = ModelArtifactContract(
    modelId: 'yolov8n-int8-control-416',
    domain: ModelDomain.detector,
    lifecycle: ModelLifecycle.productionControl,
    artifactPath: 'assets/yolov8n_int8.tflite',
    sha256: '3f5c681641e439321ec529c26995de18a910d62a25a49ccb02da2a0a771cae02',
    format: 'tflite-float-io-int8-weights',
    licenseId: 'provenance-review-required',
    preprocessId: 'flutter-vision-yolov8-416-v1',
    decoderId: 'flutter-vision-yolov8-bcn-v1',
    input: ModelTensorContract(
      name: 'images',
      shape: <int>[1, 416, 416, 3],
      dataType: 'float32',
      layout: TensorLayout.nhwc,
    ),
    output: ModelTensorContract(
      name: 'Identity',
      shape: <int>[1, 84, 3549],
      dataType: 'float32',
      layout: TensorLayout.bcn,
    ),
  );

  static const yolo11n320 = ModelArtifactContract(
    modelId: 'yolo11n-onnx-320-experiment',
    domain: ModelDomain.detector,
    lifecycle: ModelLifecycle.exportedExperiment,
    artifactPath: 'model_export/candidates/yolo11n_320.onnx',
    sha256: 'b9152829ad8ff26a0b2bd2b4a1482910c91c549d1cdcc4587fecf4444741dbe4',
    format: 'onnx-opset17',
    licenseId: 'AGPL-3.0',
    preprocessId: 'ultralytics-rgb01-letterbox-320-v1',
    decoderId: 'yolov8-v11-bcn-v1',
    input: ModelTensorContract(
      name: 'images',
      shape: <int>[1, 3, 320, 320],
      dataType: 'float32',
      layout: TensorLayout.nchw,
    ),
    output: ModelTensorContract(
      name: 'output0',
      shape: <int>[1, 84, 2100],
      dataType: 'float32',
      layout: TensorLayout.bcn,
    ),
  );

  static const yolo11n416 = ModelArtifactContract(
    modelId: 'yolo11n-onnx-416-experiment',
    domain: ModelDomain.detector,
    lifecycle: ModelLifecycle.exportedExperiment,
    artifactPath: 'model_export/candidates/yolo11n_416.onnx',
    sha256: 'b9c6c86aa850523b970dff6aec9683dbafb363aa52051a449d4e1651c4a580ce',
    format: 'onnx-opset17',
    licenseId: 'AGPL-3.0',
    preprocessId: 'ultralytics-rgb01-letterbox-416-v1',
    decoderId: 'yolov8-v11-bcn-v1',
    input: ModelTensorContract(
      name: 'images',
      shape: <int>[1, 3, 416, 416],
      dataType: 'float32',
      layout: TensorLayout.nchw,
    ),
    output: ModelTensorContract(
      name: 'output0',
      shape: <int>[1, 84, 3549],
      dataType: 'float32',
      layout: TensorLayout.bcn,
    ),
  );

  static const yolo26n416 = ModelArtifactContract(
    modelId: 'yolo26n-onnx-416-experiment',
    domain: ModelDomain.detector,
    lifecycle: ModelLifecycle.exportedExperiment,
    artifactPath: 'model_export/candidates/yolo26n_416.onnx',
    sha256: 'b0db38ca8a0fe5c8ff00391b18206e07a423f218f5a8236e1f1dbe1b8a2e1332',
    format: 'onnx-opset17-end2end',
    licenseId: 'AGPL-3.0',
    preprocessId: 'ultralytics-rgb01-letterbox-416-v1',
    decoderId: 'yolo26-end2end-bnc-v1',
    input: ModelTensorContract(
      name: 'images',
      shape: <int>[1, 3, 416, 416],
      dataType: 'float32',
      layout: TensorLayout.nchw,
    ),
    output: ModelTensorContract(
      name: 'output0',
      shape: <int>[1, 300, 6],
      dataType: 'float32',
      layout: TensorLayout.bnc,
    ),
  );

  static const detectorExperiments = <ModelArtifactContract>[
    yolo11n320,
    yolo11n416,
    yolo26n416,
  ];

  static const productionSelection = ProductionModelSelection(
    detectorModelId: 'yolov8n-int8-control-416',
    depthByTier: <DepthTierModelSelection>[
      DepthTierModelSelection(
        tier: 'hardware',
        providerId: 'ncnn-relative',
        modelId: 'midas-small-ncnn',
        geometryAvailable: true,
        reason:
            'aligned control until ARCore shares the production camera owner',
      ),
      DepthTierModelSelection(
        tier: 'ncnnVulkan',
        providerId: 'ncnn-relative',
        modelId: 'midas-small-ncnn',
        geometryAvailable: true,
        reason: 'pinned monocular control',
      ),
      DepthTierModelSelection(
        tier: 'ncnnCpu',
        providerId: 'ncnn-relative',
        modelId: 'midas-small-ncnn',
        geometryAvailable: true,
        reason: 'pinned monocular control',
      ),
      DepthTierModelSelection(
        tier: 'focalLength',
        providerId: 'unavailable',
        modelId: 'none',
        geometryAvailable: false,
        reason: 'no validated depth model for this tier; fail degraded',
      ),
    ],
    traversabilityModelId: null,
    traversabilityDecision:
        'deferred: no converted artifact and no boundary-labelled corpus',
  );
}

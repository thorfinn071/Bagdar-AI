/// Proven input/output contract for `assets/midas_small.ncnn.{param,bin}`.
///
/// Evidence (Phase 1):
/// - `.param` Input blob `0` is consumed by `Sub_1` then `Div_3` against two
///   `MemoryData` tensors of shape 1x1x3. Mean/std therefore live **inside**
///   the graph; native/Dart preprocess must NOT apply them again.
/// - First six little-endian float32 values of the `.bin` are
///   RGB ImageNet mean `(0.485, 0.456, 0.406)` and std
///   `(0.229, 0.224, 0.225)`. Color order is RGB, not BGR, not grayscale.
/// - Input range expected by those in-graph constants is `[0, 1]` per channel.
/// - Layout fed to NCNN is CHW, 3 x [mapSize] x [mapSize].
/// - Resize policy: stretch (no letterbox). Crop: drop the top
///   `cropTopFrac` of the source height, then stretch the remainder.
/// - Spatial sampling uses the historical integer mapping
///   `sx = x * srcW ~/ mapSize` (nearest neighbour).
/// - Output is a 1-channel spatial map. Native code bilinear-resizes it to
///   [mapSize] x [mapSize]. Invalid samples are `NaN`, never an ambiguous 0.
/// - MiDaS small emits inverse-depth: **larger means nearer**. That direction
///   is the Dart-wide convention after the provider publishes a frame.
///   Rank-correlation against an on-device/reference run remains a Phase 1
///   exit gate and must not be fabricated.
class NcnnDepthContract {
  NcnnDepthContract._();

  static const String modelId = 'midas-small-ncnn';
  static const String modelHash =
      'sha256:param:'
      'd618bb98777ff7e7adeeef1c8cf50ede79c97c754876681d6a0b26330708e8d3;'
      'bin:'
      '324412b094f3309c0c7acd506a06ccdc60296749ac382dc58431efdde0f13242';
  static const String preprocessId =
      'yuv420-rgb01-chw-256-rotate-mirror-crop-stretch-v1';

  static const int mapSize = 256;
  static const int channels = 3;

  static const List<double> inGraphMeanRgb = <double>[0.485, 0.456, 0.406];
  static const List<double> inGraphStdRgb = <double>[0.229, 0.224, 0.225];

  /// JPEG / full-range BT.601 used for YUV_420_888 → RGB.
  static const double kr = 1.402;
  static const double kgU = 0.344136;
  static const double kgV = 0.714136;
  static const double kb = 1.772;
}

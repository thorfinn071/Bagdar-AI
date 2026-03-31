import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../utils/depth_hazard.dart';
import '../utils/midas_service.dart';
import 'device_capability.dart';



abstract class DepthProvider {
  DepthTier get tier;
  bool get isReady;
  Future<bool> init({int threads = 2});
  Future<List<DepthHazard>> analyze(CameraImage image);
  void dispose();
}



class MidasDepthProvider implements DepthProvider {
  final bool useNnApi;

  MidasDepthProvider({required this.useNnApi});

  final MidasService _service = MidasService();

  @override
  DepthTier get tier =>
      useNnApi ? DepthTier.midasNnapi : DepthTier.midasCpu;

  @override
  bool get isReady => _service.isReady;

  @override
  Future<bool> init({int threads = 2}) =>
      _service.init(threads: threads, useNnApi: useNnApi);

  @override
  Future<List<DepthHazard>> analyze(CameraImage image) =>
      _service.analyze(image);

  @override
  void dispose() => _service.dispose();
}



class FocalLengthDepthProvider implements DepthProvider {
  bool _ready = false;

  @override
  DepthTier get tier => DepthTier.focalLength;

  @override
  bool get isReady => _ready;

  @override
  Future<bool> init({int threads = 2}) async {
    _ready = true;
    return true;
  }

  @override
  Future<List<DepthHazard>> analyze(CameraImage image) async => const [];

  @override
  void dispose() {
    _ready = false;
  }
}



class DepthProviderFactory {
  DepthProviderFactory._();

  static DepthProvider create(DeviceCapabilities caps) {
    switch (caps.bestDepthTier) {
      case DepthTier.hardware:
        debugPrint('DepthProviderFactory: hardware tier, fallback → midasNnapi');
        return MidasDepthProvider(useNnApi: true);

      case DepthTier.midasNnapi:
        debugPrint('DepthProviderFactory: MidasDepthProvider(nnapi=true)');
        return MidasDepthProvider(useNnApi: true);

      case DepthTier.midasCpu:
        debugPrint('DepthProviderFactory: MidasDepthProvider(nnapi=false)');
        return MidasDepthProvider(useNnApi: false);

      case DepthTier.focalLength:
        debugPrint('DepthProviderFactory: FocalLengthDepthProvider');
        return FocalLengthDepthProvider();
    }
  }

  static DepthProvider createWithTier(DepthTier tier) {
    switch (tier) {
      case DepthTier.hardware:
      case DepthTier.midasNnapi:
        return MidasDepthProvider(useNnApi: true);
      case DepthTier.midasCpu:
        return MidasDepthProvider(useNnApi: false);
      case DepthTier.focalLength:
        return FocalLengthDepthProvider();
    }
  }
}

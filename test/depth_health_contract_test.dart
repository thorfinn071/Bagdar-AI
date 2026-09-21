import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/depth_provider.dart';

class _FakeCameraImage implements CameraImage {
  @override
  List<Plane> get planes => [_FakePlane()];
  @override
  int get width => 256;
  @override
  int get height => 256;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlane implements Plane {
  @override
  Uint8List get bytes => Uint8List(256 * 256);
  @override
  int get bytesPerRow => 256;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'focal fallback is generic-obstacle unavailable, not a healthy empty scene',
    () async {
      final p = FocalLengthDepthProvider();
      await p.init();
      final r = await p.analyzeDetailed(_FakeCameraImage());
      expect(r.frame, isNull);
      expect(r.legacyHazards, isEmpty);
      expect(r.health.genericObstacleAvailable, isFalse);
      expect(r.health.capability, DepthCapability.legacyOnlyDegraded);
      expect(r.health.rejectionReason, 'genericObstacleUnavailable');
    },
  );

  test('DepthFrame rejects mismatched confidence length', () {
    expect(
      () => DepthFrame(
        values: Float32List(4),
        confidence01: Float32List(3),
        width: 2,
        height: 2,
        timestampUs: 0,
        provider: DepthProviderKind.ncnnRelative,
        semantics: DepthValueSemantics.relativeProximity,
        modelId: 'test-depth',
        modelHash: 'test-hash',
        preprocessId: 'test-preprocess',
        cropTopFraction: 0,
        frameQuality: 0,
        alignedToImage: true,
      ),
      throwsArgumentError,
    );
  });

  test('DepthFrame rejects incomplete model identity', () {
    expect(
      () => DepthFrame(
        values: Float32List(1),
        confidence01: Float32List(1),
        width: 1,
        height: 1,
        timestampUs: 0,
        provider: DepthProviderKind.ncnnRelative,
        semantics: DepthValueSemantics.relativeProximity,
        modelId: '',
        modelHash: 'hash',
        preprocessId: 'preprocess',
        cropTopFraction: 0,
        frameQuality: 0,
        alignedToImage: true,
      ),
      throwsArgumentError,
    );
  });
}

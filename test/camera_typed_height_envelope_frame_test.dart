import 'dart:isolate';
import 'dart:typed_data';

import 'package:bagdar/safety/perception/camera_height_envelope_passage_source.dart';
import 'package:bagdar/safety/perception/camera_typed_height_envelope_frame.dart';
import 'package:bagdar/safety/perception/passage_clearance.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness/blender_scan_complete_fixture.dart';
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'single_camera_observability_test.dart' show opticalFrame;

CameraHeightEnvelopeFrame packet() => CameraHeightEnvelopeFrame(
  depth: copyVisibleFrame(
    opticalFrame(),
    range: List.generate(16, (i) => i.toDouble()),
    valid: List.generate(16, (i) => i.isEven),
  ),
  heightLowerM: List.filled(16, double.nan),
  heightUpperM: List.filled(16, double.infinity),
  firstZLowerM: List.filled(16, -.0),
);

List<List<double>> planes(CameraHeightEnvelopeFrame f) => [
  f.depth.rangeM,
  f.depth.freeZLowerM,
  f.depth.surfaceZUpperM,
  f.heightLowerM,
  f.heightUpperM,
  f.firstZLowerM,
];

void equalPacket(
  CameraHeightEnvelopeFrame actual,
  CameraHeightEnvelopeFrame expected,
) {
  final a = planes(actual), b = planes(expected);
  for (var pi = 0; pi < a.length; pi++) {
    expect(a[pi].length, b[pi].length);
    for (var i = 0; i < a[pi].length; i++) {
      final x = a[pi][i], y = b[pi][i];
      expect(x.isNaN, y.isNaN);
      if (!x.isNaN) {
        expect(x, y);
        if (x == 0) expect(x.isNegative, y.isNegative);
      }
    }
  }
  expect(actual.depth.valid, expected.depth.valid);
  expect(actual.depth.capturedAtUs, expected.depth.capturedAtUs);
  expect(actual.depth.frameId, expected.depth.frameId);
  expect(actual.depth.sessionGeneration, expected.depth.sessionGeneration);
  expect(actual.depth.units, expected.depth.units);
  expect(actual.depth.transformId, expected.depth.transformId);
  expect(actual.depth.rotation, expected.depth.rotation);
  expect(actual.depth.originM, expected.depth.originM);
  expect(actual.depth.structurallyValid, expected.depth.structurallyValid);
}

void immutable(CameraHeightEnvelopeFrame f) {
  for (final p in planes(f)) {
    expect(p, isA<Float64List>());
    expect(() => p[0] = 42, throwsUnsupportedError);
    expect(
      () => (p as Float64List).buffer.asFloat64List()[0] = 42,
      throwsUnsupportedError,
    );
    expect(
      () => Float64List.sublistView(p as Float64List)[0] = 42,
      throwsUnsupportedError,
    );
  }
  expect(() => f.depth.valid[0] = false, throwsUnsupportedError);
  expect(() => f.depth.valid.length = 0, throwsUnsupportedError);
}

void main() {
  test(
    'owned typed copy preserves NaN infinity signed zero validity and metadata',
    () {
      final original = packet(),
          copied = CameraTypedHeightEnvelopeFrame.copy(packet());
      equalPacket(copied, original);
      immutable(copied);
      expect(
        copied.payloadBytes,
        CameraTypedHeightEnvelopeFrame.headerBytes + 16 * 49,
      );
    },
  );
  test('transfer materializes once and exposes only immutable storage', () {
    final original = packet(),
        storage = CameraTypedHeightEnvelopeFrame.pack(packet());
    final restored = CameraTypedHeightEnvelopeFrame.fromTransferable(
      metadata: original.depth,
      storage: storage,
    );
    equalPacket(restored, original);
    immutable(restored);
    expect(() => storage.materialize(), throwsArgumentError);
  });
  test(
    'typed copy has independent numeric storage from another typed copy',
    () {
      final first = CameraTypedHeightEnvelopeFrame.copy(packet());
      final second = CameraTypedHeightEnvelopeFrame.copy(first);
      equalPacket(second, first);
      expect(
        identical(first.heightLowerM.buffer, second.heightLowerM.buffer),
        false,
      );
    },
  );
  test('published storage is independent of mutable sender bytes', () {
    const offset = CameraTypedHeightEnvelopeFrame.headerBytes;
    final bytes = Uint8List.fromList(
      CameraTypedHeightEnvelopeFrame.pack(packet()).materialize().asUint8List(),
    );
    bytes.buffer.asFloat64List(offset, 16 * 6)[0] = 1.5;
    final storage = TransferableTypedData.fromList([bytes]);
    bytes.buffer.asFloat64List(offset, 16 * 6)[0] = 100;
    final restored = CameraTypedHeightEnvelopeFrame.fromTransferable(
      metadata: packet().depth,
      storage: storage,
    );
    expect(restored.depth.rangeM[0], 1.5);
    immutable(restored);
  });
  test('invalid relative pose and identity metadata remain invalid', () {
    for (final fault in ['relative', 'pose', 'model', 'health']) {
      final f = packet();
      final invalid = completeFrameCopy(
        f,
        depth: copyVisibleFrame(
          f.depth,
          units: fault == 'relative' ? PassageUnits.relativeProximity : null,
          rotation: fault == 'pose' ? List.filled(9, 0) : null,
          modelHash: fault == 'model' ? '' : null,
          healthy: fault == 'health' ? false : null,
        ),
      );
      final restored = CameraTypedHeightEnvelopeFrame.copy(invalid);
      equalPacket(restored, invalid);
      expect(restored.depth.structurallyValid, false);
    }
  });
  test('malformed plane shape is rejected before publication', () {
    expect(
      () => CameraTypedHeightEnvelopeFrame.copy(
        completeFrameCopy(packet(), firstZLower: []),
      ),
      throwsFormatException,
    );
    expect(
      () => CameraTypedHeightEnvelopeFrame.pack(
        completeFrameCopy(packet(), heightUpper: [0]),
      ),
      throwsFormatException,
    );
  });
  test('short long and invalid-mask wire packets are rejected', () {
    final metadata = packet().depth;
    const offset = CameraTypedHeightEnvelopeFrame.headerBytes;
    for (final length in [0, offset + 16 * 49 - 1, offset + 16 * 49 + 1]) {
      expect(
        () => CameraTypedHeightEnvelopeFrame.fromTransferable(
          metadata: metadata,
          storage: TransferableTypedData.fromList([Uint8List(length)]),
        ),
        throwsFormatException,
      );
    }
    final bytes = Uint8List.fromList(
      CameraTypedHeightEnvelopeFrame.pack(packet()).materialize().asUint8List(),
    )..[offset + 16 * 48] = 2;
    expect(
      () => CameraTypedHeightEnvelopeFrame.fromTransferable(
        metadata: metadata,
        storage: TransferableTypedData.fromList([bytes]),
      ),
      throwsFormatException,
    );
  });
  test(
    'publication and isolated receive preserve the full immutable packet',
    () async {
      final original = packet(),
          storage = CameraTypedHeightEnvelopeFrame.pack(packet());
      final restored = await Isolate.run(
        () => CameraTypedHeightEnvelopeFrame.fromTransferable(
          metadata: original.depth,
          storage: storage,
        ),
      );
      equalPacket(restored, original);
      immutable(restored);
    },
  );
}

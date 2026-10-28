import 'dart:collection';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'camera_height_envelope_passage_source.dart';
import 'camera_passage_clearance_source.dart';

/// Immutable transport for six original optical planes and one validity mask.
/// Copies values exactly; never derives bounds, fills holes or changes clocks.
/// Admission and clearance still belong to the original measurement consumers.
final class CameraTypedHeightEnvelopeFrame extends CameraHeightEnvelopeFrame {
  static const headerBytes = 32;
  final Float64List _heightLower, _heightUpper, _first;
  final int payloadBytes;

  CameraTypedHeightEnvelopeFrame._owned(
    CameraVisibleDepthFrame metadata,
    ByteBuffer buffer,
    int n,
  ) : _heightLower = buffer
          .asFloat64List(headerBytes + n * 24, n)
          .asUnmodifiableView(),
      _heightUpper = buffer
          .asFloat64List(headerBytes + n * 32, n)
          .asUnmodifiableView(),
      _first = buffer
          .asFloat64List(headerBytes + n * 40, n)
          .asUnmodifiableView(),
      payloadBytes = buffer.lengthInBytes,
      super(
        depth: _TypedDepth(metadata, buffer, n),
        heightLowerM: const [],
        heightUpperM: const [],
        firstZLowerM: const [],
      );

  factory CameraTypedHeightEnvelopeFrame.copy(CameraHeightEnvelopeFrame frame) {
    final bytes = _encode(frame);
    return CameraTypedHeightEnvelopeFrame._owned(
      frame.depth,
      bytes.buffer,
      frame.depth.width * frame.depth.height,
    );
  }

  /// Publication copies into uniquely owned transferable storage. Include this
  /// work in latency measurements; materialization alone is not transport cost.
  static TransferableTypedData pack(CameraHeightEnvelopeFrame frame) =>
      TransferableTypedData.fromList([_encode(frame)]);

  factory CameraTypedHeightEnvelopeFrame.fromTransferable({
    required CameraVisibleDepthFrame metadata,
    required TransferableTypedData storage,
  }) {
    final n = _size(metadata);
    final buffer = storage.materialize();
    if (buffer.lengthInBytes != headerBytes + n * 49) {
      throw const FormatException('Invalid optical payload length');
    }
    final binding = _metadataBinding(metadata);
    final supplied = buffer.asUint8List(0, headerBytes);
    for (var i = 0; i < headerBytes; i++) {
      if (supplied[i] != binding[i]) {
        throw const FormatException('Optical payload metadata mismatch');
      }
    }
    final mask = buffer.asUint8List(headerBytes + n * 48, n);
    if (mask.any((v) => v > 1)) {
      throw const FormatException('Invalid optical validity byte');
    }
    return CameraTypedHeightEnvelopeFrame._owned(metadata, buffer, n);
  }

  /// Binds a published payload to its original clock/pose/identity. This is an
  /// accidental-pairing check, not authentication or sensor-accuracy evidence.
  static List<int> _metadataBinding(CameraVisibleDepthFrame f) {
    final numbers = [
      f.fx,
      f.fy,
      f.cx,
      f.cy,
      f.errorM,
      f.poseQuality,
      ...f.rotation,
      ...f.originM,
    ];
    final bits = ByteData(numbers.length * 8);
    for (var i = 0; i < numbers.length; i++) {
      bits.setFloat64(i * 8, numbers[i], Endian.little);
    }
    final encoded = jsonEncode([
      'bagdar-typed-optical-v2',
      f.width,
      f.height,
      f.frameId,
      f.capturedAtUs,
      f.sessionGeneration,
      f.cameraId,
      f.modelHash,
      f.transformId,
      f.referenceFrameId,
      f.units.name,
      f.providerHealthy,
      f.rotation.length,
      f.originM.length,
      base64Encode(bits.buffer.asUint8List()),
    ]);
    return sha256.convert(utf8.encode(encoded)).bytes;
  }

  static int _size(CameraVisibleDepthFrame f) {
    final n = f.width * f.height;
    if (f.width <= 0 || f.height <= 0 || n > 1048576) {
      throw const FormatException('Invalid optical payload dimensions');
    }
    return n;
  }

  static Uint8List _encode(CameraHeightEnvelopeFrame f) {
    final n = _size(f.depth);
    final planes = [
      f.depth.rangeM,
      f.depth.freeZLowerM,
      f.depth.surfaceZUpperM,
      f.heightLowerM,
      f.heightUpperM,
      f.firstZLowerM,
    ];
    if (f.depth.valid.length != n || planes.any((p) => p.length != n)) {
      throw const FormatException('Invalid optical plane shape');
    }
    final bytes = Uint8List(headerBytes + n * 49);
    bytes.setRange(0, headerBytes, _metadataBinding(f.depth));
    final values = bytes.buffer.asFloat64List(headerBytes, n * 6);
    for (var i = 0; i < planes.length; i++) {
      values.setRange(i * n, (i + 1) * n, planes[i]);
    }
    final mask = bytes.buffer.asUint8List(headerBytes + n * 48, n);
    for (var i = 0; i < n; i++) {
      mask[i] = f.depth.valid[i] ? 1 : 0;
    }
    return bytes;
  }

  @override
  Float64List get heightLowerM => _heightLower;
  @override
  Float64List get heightUpperM => _heightUpper;
  @override
  Float64List get firstZLowerM => _first;
}

final class _Mask extends ListBase<bool> {
  final Uint8List _bytes;
  _Mask(Uint8List bytes) : _bytes = bytes.asUnmodifiableView();
  @override
  int get length => _bytes.length;
  @override
  set length(int _) => throw UnsupportedError('Immutable validity');
  @override
  bool operator [](int i) => _bytes[i] == 1;
  @override
  void operator []=(int i, bool _) =>
      throw UnsupportedError('Immutable validity');
}

final class _TypedDepth extends CameraVisibleDepthFrame {
  final Float64List _range, _lower, _upper;
  final List<bool> _mask;
  _TypedDepth(CameraVisibleDepthFrame f, ByteBuffer buffer, int n)
    : _range = buffer
          .asFloat64List(CameraTypedHeightEnvelopeFrame.headerBytes, n)
          .asUnmodifiableView(),
      _lower = buffer
          .asFloat64List(CameraTypedHeightEnvelopeFrame.headerBytes + n * 8, n)
          .asUnmodifiableView(),
      _upper = buffer
          .asFloat64List(CameraTypedHeightEnvelopeFrame.headerBytes + n * 16, n)
          .asUnmodifiableView(),
      _mask = _Mask(
        buffer.asUint8List(
          CameraTypedHeightEnvelopeFrame.headerBytes + n * 48,
          n,
        ),
      ),
      super(
        width: f.width,
        height: f.height,
        frameId: f.frameId,
        capturedAtUs: f.capturedAtUs,
        sessionGeneration: f.sessionGeneration,
        fx: f.fx,
        fy: f.fy,
        cx: f.cx,
        cy: f.cy,
        errorM: f.errorM,
        poseQuality: f.poseQuality,
        cameraId: f.cameraId,
        modelHash: f.modelHash,
        transformId: f.transformId,
        referenceFrameId: f.referenceFrameId,
        units: f.units,
        providerHealthy: f.providerHealthy,
        rotation: f.rotation,
        originM: f.originM,
        rangeM: const [],
        freeZLowerM: const [],
        surfaceZUpperM: const [],
        valid: const [],
      );
  @override
  Float64List get rangeM => _range;
  @override
  Float64List get freeZLowerM => _lower;
  @override
  Float64List get surfaceZUpperM => _upper;
  @override
  List<bool> get valid => _mask;
}

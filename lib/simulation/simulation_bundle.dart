import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';

/// Runtime-only input format. It has no evaluator labels, geometry or depth.
class SimulationBundle {
  final File manifest;
  final String manifestHash;
  final List<SimulationSequence> sequences;

  SimulationBundle._(this.manifest, this.manifestHash, this.sequences);

  static Future<SimulationBundle> load(String path) async {
    final file = File(path);
    if (await file.length() > 16 * 1024 * 1024) {
      throw const FormatException('Simulation manifest too large');
    }
    final bytes = await file.readAsBytes();
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    if (map['schemaVersion'] != 1 ||
        map['synthetic'] != true ||
        map['promotionAllowed'] != false) {
      throw const FormatException('Not a supported synthetic runtime bundle');
    }
    final rows = map['sequences'] as List;
    if (rows.isEmpty || rows.length > 1000) {
      throw const FormatException('Invalid sequence count');
    }
    final sequences = rows
        .map((r) => SimulationSequence.fromJson(r as Map))
        .toList();
    if (sequences.map((s) => s.id).toSet().length != sequences.length) {
      throw const FormatException('Duplicate sequence ID');
    }
    return SimulationBundle._(
      file,
      sha256.convert(bytes).toString(),
      List.unmodifiable(sequences),
    );
  }

  Future<Uint8List> readAsset(Map asset, {required int maximumBytes}) async {
    final relative = asset['path'] as String;
    final expected = asset['sha256'] as String;
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.contains('\\') ||
        relative.contains(':') ||
        relative.split('/').any((p) => p.isEmpty || p == '.' || p == '..') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('Unsafe asset path/hash');
    }
    final root = await manifest.parent.resolveSymbolicLinks();
    final file = File('$root${Platform.pathSeparator}$relative');
    final resolved = await file.resolveSymbolicLinks();
    if (!resolved.startsWith('$root${Platform.pathSeparator}') ||
        await file.length() > maximumBytes) {
      throw const FormatException('Asset outside bundle or too large');
    }
    final bytes = await file.readAsBytes();
    if (sha256.convert(bytes).toString() != expected) {
      throw FormatException('Asset hash mismatch: $relative');
    }
    return bytes;
  }
}

class SimulationSequence {
  final String id;
  final int width, height, rotation;
  final bool mirrored;
  final List<Map> frames, sensors;

  SimulationSequence._(
    this.id,
    this.width,
    this.height,
    this.rotation,
    this.mirrored,
    this.frames,
    this.sensors,
  );

  factory SimulationSequence.fromJson(Map row) {
    final id = row['id'] as String;
    final width = row['width'] as int;
    final height = row['height'] as int;
    final rotation = row['rotationDegrees'] as int;
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,120}$').hasMatch(id) ||
        width < 2 ||
        height < 2 ||
        width > 2048 ||
        height > 2048 ||
        width.isOdd ||
        height.isOdd ||
        ![0, 90, 180, 270].contains(rotation) ||
        row['pixelFormat'] != 'i420-bt601-limited') {
      throw const FormatException('Invalid camera sequence metadata');
    }
    final frames = (row['frames'] as List).cast<Map>();
    final sensors = (row['sensors'] as List).cast<Map>();
    if (frames.isEmpty ||
        frames.length > 1800 ||
        sensors.isEmpty ||
        sensors.length > 20000) {
      throw const FormatException('Invalid sequence length');
    }
    var previousId = 0, previousTime = -1, previousDelivery = -1;
    for (final f in frames) {
      final id = f['frameId'] as int;
      final time = f['offsetUs'] as int;
      final delay = f['deliveryDelayUs'] as int;
      if (id <= previousId ||
          time <= previousTime ||
          time > 120000000 ||
          delay < 0 ||
          delay > 10000000 ||
          time + delay < previousDelivery ||
          f['drop'] is! bool ||
          f['yuv'] is! Map ||
          f['preview'] is! Map) {
        throw const FormatException('Invalid frame identity/time/transport');
      }
      previousId = id;
      previousTime = time;
      previousDelivery = time + delay;
    }
    var sensorTime = -1;
    for (final s in sensors) {
      final time = s['offsetUs'] as int;
      if (time <= sensorTime || time < 0 || time > 130000000) {
        throw const FormatException('Invalid sensor order');
      }
      for (final key in ['accelerometer', 'gyroscope']) {
        final vector = s[key] as List;
        if (vector.length != 3 ||
            vector.any((v) => v is! num || !v.isFinite || v.abs() > 200)) {
          throw const FormatException('Invalid inertial sample');
        }
      }
      sensorTime = time;
    }
    Map freeze(Map value) => Map.unmodifiable(
      value.map(
        (key, v) => MapEntry(
          key,
          v is Map
              ? freeze(v)
              : v is List
              ? List.unmodifiable(v)
              : v,
        ),
      ),
    );
    return SimulationSequence._(
      id,
      width,
      height,
      rotation,
      row['mirrored'] as bool,
      List.unmodifiable(frames.map(freeze)),
      List.unmodifiable(sensors.map(freeze)),
    );
  }
}

class SimulationImage implements CameraImage {
  final int sourceFrameId;
  final DateTime capturedAt;
  @override
  final int width;
  @override
  final int height;
  @override
  final List<Plane> planes;
  @override
  final ImageFormat format = const _I420Format();
  @override
  double? get lensAperture => null;
  @override
  int? get sensorExposureTime => null;
  @override
  double? get sensorSensitivity => null;

  SimulationImage({
    required this.sourceFrameId,
    required this.capturedAt,
    required this.width,
    required this.height,
    required Uint8List i420,
  }) : planes = _planes(i420, width, height);

  static List<Plane> _planes(Uint8List bytes, int width, int height) {
    final area = width * height;
    if (width < 2 ||
        height < 2 ||
        width.isOdd ||
        height.isOdd ||
        bytes.length != area * 3 ~/ 2) {
      throw const FormatException('Invalid I420 buffer');
    }
    return List.unmodifiable([
      _ReplayPlane(
        Uint8List.fromList(bytes.sublist(0, area)).asUnmodifiableView(),
        width,
        height,
      ),
      _ReplayPlane(
        Uint8List.fromList(
          bytes.sublist(area, area + area ~/ 4),
        ).asUnmodifiableView(),
        width ~/ 2,
        height ~/ 2,
      ),
      _ReplayPlane(
        Uint8List.fromList(
          bytes.sublist(area + area ~/ 4),
        ).asUnmodifiableView(),
        width ~/ 2,
        height ~/ 2,
      ),
    ]);
  }
}

class _I420Format implements ImageFormat {
  const _I420Format();
  @override
  ImageFormatGroup get group => ImageFormatGroup.yuv420;
  @override
  int get raw => 35;
}

class _ReplayPlane implements Plane {
  @override
  final Uint8List bytes;
  @override
  final int width, height;
  _ReplayPlane(this.bytes, this.width, this.height);
  @override
  int get bytesPerRow => width;
  @override
  int get bytesPerPixel => 1;
}

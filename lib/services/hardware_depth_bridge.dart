import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HardwareDepthBridge {
  static const MethodChannel _channel = MethodChannel('bagdar/hardware_depth');
  static const EventChannel _frameChannel = EventChannel(
    'bagdar/hardware_depth_frames',
  );

  StreamSubscription<dynamic>? _subscription;
  Float32List? _latestDepthMap;
  bool _started = false;
  bool _starting = false;

  bool get isStarted => _started;

  Float32List? get latestDepthMap => _latestDepthMap;

  Future<bool> isSupported() async {
    try {
      final supported = await _channel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } catch (e) {
      debugPrint('HardwareDepthBridge: isSupported failed ($e)');
      return false;
    }
  }

  Future<bool> start({int mapSize = 256}) async {
    if (_started || _starting) return true;
    try {
      _starting = true;
      _subscription ??= _frameChannel.receiveBroadcastStream().listen(
        _handleEvent,
        onError: (e) =>
            debugPrint('HardwareDepthBridge: frame stream error ($e)'),
      );
      final started = await _channel.invokeMethod<bool>('startSession', {
        'mapSize': mapSize,
      });
      if (started != true) {
        _starting = false;
        await _subscription?.cancel();
        _subscription = null;
        return false;
      }
      _starting = false;
      _started = true;
      return true;
    } catch (e) {
      debugPrint('HardwareDepthBridge: start failed ($e)');
      _starting = false;
      await _subscription?.cancel();
      _subscription = null;
      return false;
    }
  }

  Future<void> stop() async {
    if (!_started && !_starting) {
      await _subscription?.cancel();
      _subscription = null;
      _latestDepthMap = null;
      return;
    }
    try {
      await _channel.invokeMethod<void>('stopSession');
    } catch (e) {
      debugPrint('HardwareDepthBridge: stop failed ($e)');
    }
    await _subscription?.cancel();
    _subscription = null;
    _latestDepthMap = null;
    _started = false;
    _starting = false;
  }

  void _handleEvent(dynamic event) {
    final depth = _parseDepthFrame(event);
    if (depth != null) {
      _latestDepthMap = depth;
    }
  }

  Float32List? _parseDepthFrame(dynamic event) {
    if (event is Float32List) {
      return event;
    }
    if (event is Uint8List) {
      if (event.lengthInBytes % 4 != 0) return null;
      final values = Float32List(event.lengthInBytes ~/ 4);
      final data = ByteData.sublistView(event);
      for (int i = 0; i < values.length; i++) {
        values[i] = data.getFloat32(i * 4, Endian.little);
      }
      return values;
    }
    if (event is List) {
      final values = <double>[];
      for (final item in event) {
        if (item is num) {
          values.add(item.toDouble());
        }
      }
      if (values.isEmpty) return null;
      return Float32List.fromList(values);
    }
    if (event is Map) {
      final rawValues = event['values'];
      if (rawValues is Float32List) return rawValues;
      if (rawValues is Uint8List) return _parseDepthFrame(rawValues);
      if (rawValues is List) return _parseDepthFrame(rawValues);
    }
    return null;
  }
}

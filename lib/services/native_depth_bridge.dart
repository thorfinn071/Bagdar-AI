import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';

typedef _PreprocessNative =
    Int32 Function(
      Pointer<Uint8> yBytes,
      Int32 srcWidth,
      Int32 srcHeight,
      Int32 rowStride,
      Float cropTopFrac,
      Pointer<Float> outBuffer,
      Int32 outLength,
    );

typedef _PreprocessDart =
    int Function(
      Pointer<Uint8> yBytes,
      int srcWidth,
      int srcHeight,
      int rowStride,
      double cropTopFrac,
      Pointer<Float> outBuffer,
      int outLength,
    );

class NativeDepthBridge {
  NativeDepthBridge._(DynamicLibrary library) {
    _preprocess = library.lookupFunction<_PreprocessNative, _PreprocessDart>(
      'vg_preprocess_y_plane_to_f32',
    );
  }

  static NativeDepthBridge? tryCreate() {
    if (!Platform.isAndroid) return null;
    try {
      return NativeDepthBridge._(DynamicLibrary.open('libbagdar_native.so'));
    } catch (e) {
      debugPrint('NativeDepthBridge: load failed ($e)');
      return null;
    }
  }

  late final _PreprocessDart _preprocess;
  Pointer<Uint8>? _scratch;
  int _scratchCapacity = 0;

  bool get isLoaded => _scratch != null;

  bool preprocess({
    required Uint8List yBytes,
    required int srcWidth,
    required int srcHeight,
    required int rowStride,
    required double cropTopFrac,
    required Pointer<Float> outBuffer,
    required int outLength,
  }) {
    if (outLength <= 0) return false;
    if (!_ensureScratch(yBytes.length)) return false;
    final scratchView = _scratch!.asTypedList(yBytes.length);
    scratchView.setAll(0, yBytes);
    final ok = _preprocess(
      _scratch!,
      srcWidth,
      srcHeight,
      rowStride,
      cropTopFrac,
      outBuffer,
      outLength,
    );
    return ok != 0;
  }

  bool _ensureScratch(int requiredLength) {
    if (requiredLength <= _scratchCapacity) return true;
    try {
      if (_scratch != null) {
        ffi.calloc.free(_scratch!);
      }
      _scratch = ffi.calloc<Uint8>(requiredLength);
      _scratchCapacity = requiredLength;
      return true;
    } catch (e) {
      debugPrint('NativeDepthBridge: scratch alloc failed ($e)');
      return false;
    }
  }

  void dispose() {
    if (_scratch != null) {
      ffi.calloc.free(_scratch!);
      _scratch = null;
      _scratchCapacity = 0;
    }
  }
}

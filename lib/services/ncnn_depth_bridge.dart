import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';

typedef _InitNative = Int32 Function(
    Pointer<ffi.Utf8>, Pointer<ffi.Utf8>, Int32, Int32);
typedef _InitDart = int Function(
    Pointer<ffi.Utf8>, Pointer<ffi.Utf8>, int, int);

typedef _IsVulkanNative = Int32 Function();
typedef _IsVulkanDart = int Function();

typedef _InferNative = Int32 Function(
    Pointer<Uint8>, Int32, Int32, Int32, Float, Pointer<Float>, Int32);
typedef _InferDart = int Function(
    Pointer<Uint8>, int, int, int, double, Pointer<Float>, int);

typedef _DisposeNative = Void Function();
typedef _DisposeDart = void Function();





class NcnnDepthBridge {
  static const int inputSize = 256;
  static const int outputLength = inputSize * inputSize;

  NcnnDepthBridge._(DynamicLibrary lib)
      : _init = lib
            .lookupFunction<_InitNative, _InitDart>('bagdar_ncnn_init'),
        _isVulkan = lib
            .lookupFunction<_IsVulkanNative, _IsVulkanDart>('bagdar_ncnn_is_vulkan'),
        _infer = lib
            .lookupFunction<_InferNative, _InferDart>('bagdar_ncnn_infer_yuv'),
        _disposeNative = lib
            .lookupFunction<_DisposeNative, _DisposeDart>('bagdar_ncnn_dispose');

  static NcnnDepthBridge? tryCreate() {
    if (!Platform.isAndroid) return null;
    try {
      final lib = DynamicLibrary.open('libbagdar_native.so');
      lib.lookup<NativeFunction<_InitNative>>('bagdar_ncnn_init');
      return NcnnDepthBridge._(lib);
    } catch (e) {
      debugPrint('NcnnDepthBridge: not available ($e)');
      return null;
    }
  }

  final _InitDart _init;
  final _IsVulkanDart _isVulkan;
  final _InferDart _infer;
  final _DisposeDart _disposeNative;

  bool _initialized = false;
  bool _vulkanActive = false;

  Pointer<Uint8>? _scratch;
  int _scratchCapacity = 0;

  late final Pointer<Float> _outputPtr =
      ffi.calloc<Float>(outputLength);
  late final Float32List _outputBuffer = _outputPtr.asTypedList(outputLength);

  bool get isInitialized => _initialized;
  bool get isVulkan => _vulkanActive;

  bool init({
    required String paramPath,
    required String binPath,
    required bool useVulkan,
    required int numThreads,
  }) {
    final paramP = paramPath.toNativeUtf8();
    final binP = binPath.toNativeUtf8();
    try {
      final ret = _init(paramP, binP, useVulkan ? 1 : 0, numThreads);
      if (ret != 0) {
        debugPrint('NcnnDepthBridge: init failed (ret=$ret)');
        _initialized = false;
        return false;
      }
      _initialized = true;
      _vulkanActive = _isVulkan() != 0;
      debugPrint('NcnnDepthBridge: ready (vulkan=$_vulkanActive)');
      return true;
    } finally {
      ffi.calloc.free(paramP);
      ffi.calloc.free(binP);
    }
  }

  
  
  
  Float32List? inferYuv({
    required Uint8List yBytes,
    required int srcWidth,
    required int srcHeight,
    required int rowStride,
    required double cropTopFrac,
  }) {
    if (!_initialized) return null;
    if (!_ensureScratch(yBytes.length)) return null;
    final view = _scratch!.asTypedList(yBytes.length);
    view.setAll(0, yBytes);

    final ret = _infer(
      _scratch!,
      srcWidth,
      srcHeight,
      rowStride,
      cropTopFrac,
      _outputPtr,
      outputLength,
    );
    if (ret != 0) {
      debugPrint('NcnnDepthBridge: infer failed (ret=$ret)');
      return null;
    }
    return _outputBuffer;
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
      debugPrint('NcnnDepthBridge: scratch alloc failed ($e)');
      _scratch = null;
      _scratchCapacity = 0;
      return false;
    }
  }

  void dispose() {
    if (_initialized) {
      try {
        _disposeNative();
      } catch (_) {}
      _initialized = false;
      _vulkanActive = false;
    }
    if (_scratch != null) {
      ffi.calloc.free(_scratch!);
      _scratch = null;
      _scratchCapacity = 0;
    }
    try {
      ffi.calloc.free(_outputPtr);
    } catch (_) {}
  }
}

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/foundation.dart';

typedef _InitNative =
    Int32 Function(Pointer<ffi.Utf8>, Pointer<ffi.Utf8>, Int32, Int32);
typedef _InitDart =
    int Function(Pointer<ffi.Utf8>, Pointer<ffi.Utf8>, int, int);

typedef _IsVulkanNative = Int32 Function();
typedef _IsVulkanDart = int Function();

typedef _InferYuv420Native =
    Int32 Function(
      Pointer<Uint8>,
      Int32,
      Pointer<Uint8>,
      Int32,
      Pointer<Uint8>,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Float,
      Pointer<Float>,
      Int32,
    );
typedef _InferYuv420Dart =
    int Function(
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      Pointer<Uint8>,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      int,
      double,
      Pointer<Float>,
      int,
    );

typedef _LastOutNative = Int32 Function();
typedef _LastOutDart = int Function();

typedef _DisposeNative = Void Function();
typedef _DisposeDart = void Function();

/// Thin FFI wrapper around the NCNN-based MiDaS inference functions exported
/// by `libbagdar_native.so`. The native side is optional — when the library
/// was built without NCNN (third_party libs absent), [tryCreate] returns null
/// and callers should fall back to TFLite or focal-length depth.
class NcnnDepthBridge {
  static const int inputSize = 256;
  static const int outputLength = inputSize * inputSize;

  NcnnDepthBridge._(DynamicLibrary lib)
    : _init = lib.lookupFunction<_InitNative, _InitDart>('bagdar_ncnn_init'),
      _isVulkan = lib.lookupFunction<_IsVulkanNative, _IsVulkanDart>(
        'bagdar_ncnn_is_vulkan',
      ),
      _inferYuv420 = lib.lookupFunction<_InferYuv420Native, _InferYuv420Dart>(
        'bagdar_ncnn_infer_yuv420',
      ),
      _lastOutW = lib.lookupFunction<_LastOutNative, _LastOutDart>(
        'bagdar_ncnn_last_out_w',
      ),
      _lastOutH = lib.lookupFunction<_LastOutNative, _LastOutDart>(
        'bagdar_ncnn_last_out_h',
      ),
      _disposeNative = lib.lookupFunction<_DisposeNative, _DisposeDart>(
        'bagdar_ncnn_dispose',
      );

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
  final _InferYuv420Dart _inferYuv420;
  final _LastOutDart _lastOutW;
  final _LastOutDart _lastOutH;
  final _DisposeDart _disposeNative;

  bool _initialized = false;
  bool _vulkanActive = false;

  Pointer<Uint8>? _scratch;
  int _scratchCapacity = 0;

  late final Pointer<Float> _outputPtr = ffi.calloc<Float>(outputLength);
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

  int get lastNativeOutWidth => _lastOutW();
  int get lastNativeOutHeight => _lastOutH();

  /// Runs MiDaS on a YUV_420_888 frame (RGB, not grayscale). Returns the
  /// 256x256 inverse-depth map (view into native memory; valid until next
  /// call). Invalid samples are NaN. Returns null on error.
  Float32List? inferYuv420({
    required Uint8List yBytes,
    required Uint8List uBytes,
    required Uint8List vBytes,
    required int srcWidth,
    required int srcHeight,
    required int yRowStride,
    required int uRowStride,
    required int vRowStride,
    int yPixelStride = 1,
    int uPixelStride = 1,
    int vPixelStride = 1,
    int rotationDegrees = 0,
    bool mirrored = false,
    required double cropTopFrac,
  }) {
    if (!_initialized) return null;
    final need = yBytes.length + uBytes.length + vBytes.length;
    if (!_ensureScratch(need)) return null;
    final view = _scratch!.asTypedList(need);
    view.setRange(0, yBytes.length, yBytes);
    view.setRange(yBytes.length, yBytes.length + uBytes.length, uBytes);
    view.setRange(yBytes.length + uBytes.length, need, vBytes);
    final yPtr = _scratch!;
    final uPtr = _scratch! + yBytes.length;
    final vPtr = _scratch! + yBytes.length + uBytes.length;

    final ret = _inferYuv420(
      yPtr,
      yBytes.length,
      uPtr,
      uBytes.length,
      vPtr,
      vBytes.length,
      srcWidth,
      srcHeight,
      yRowStride,
      yPixelStride <= 0 ? 1 : yPixelStride,
      uRowStride,
      uPixelStride <= 0 ? 1 : uPixelStride,
      vRowStride,
      vPixelStride <= 0 ? 1 : vPixelStride,
      rotationDegrees,
      mirrored ? 1 : 0,
      cropTopFrac,
      _outputPtr,
      outputLength,
    );
    if (ret != 0) {
      debugPrint('NcnnDepthBridge: infer_yuv420 failed (ret=$ret)');
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

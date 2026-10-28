import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'camera_fast_motion_types.dart';

final class _Frame extends Struct {
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Double()
  external double fx;
  @Double()
  external double fy;
  @Double()
  external double error;
  external Pointer<Double> pixels;
  external Pointer<Double> range;
  external Pointer<Double> lower;
  external Pointer<Double> upper;
  external Pointer<Double> nx;
  external Pointer<Double> ny;
  external Pointer<Double> x2;
  external Pointer<Double> y2;
  external Pointer<Double> axis;
  external Pointer<Uint8> valid;
  external Pointer<Uint8> status;
}

typedef _MatchNative =
    Int32 Function(
      Pointer<_Frame>,
      Pointer<Double>,
      Pointer<Double>,
      Double,
      Int32,
      Int32,
      Pointer<Double>,
      Pointer<Int32>,
      Pointer<Int32>,
    );
typedef _Match =
    int Function(
      Pointer<_Frame>,
      Pointer<Double>,
      Pointer<Double>,
      double,
      int,
      int,
      Pointer<Double>,
      Pointer<Int32>,
      Pointer<Int32>,
    );

class _OwnedFrame {
  final Pointer<_Frame> frame;
  final Pointer<Double> numbers;
  final Pointer<Uint8> masks;

  _OwnedFrame(
    FastMetricMotionInput input,
    Float64List pixels,
    Float64List nx,
    Float64List ny,
    Float64List x2,
    Float64List y2,
  ) : frame = calloc<_Frame>(),
      // Every numeric input is filled below. The lazily written axis plane
      // is read only after its calloc-initialized status marks it available.
      // Clearing all seven full-image planes first was redundant.
      numbers = malloc<Double>(
        7 * input.camera.depth.width * input.camera.depth.height +
            2 * (nx.length + ny.length),
      ),
      masks = calloc<Uint8>(
        2 * input.camera.depth.width * input.camera.depth.height,
      ) {
    final f = input.camera.depth, n = f.width * f.height;
    var offset = 0;
    Pointer<Double> store(List<double> values) {
      final pointer = numbers + offset;
      pointer.asTypedList(values.length).setRange(0, values.length, values);
      offset += values.length;
      return pointer;
    }

    frame.ref
      ..width = f.width
      ..height = f.height
      ..fx = f.fx
      ..fy = f.fy
      ..error = f.errorM
      ..pixels = store(pixels)
      ..range = store(f.rangeM)
      ..lower = store(f.freeZLowerM)
      ..upper = store(f.surfaceZUpperM)
      ..nx = store(nx)
      ..ny = store(ny)
      ..x2 = store(x2)
      ..y2 = store(y2)
      ..axis = numbers + offset
      ..valid = masks
      ..status = masks + n;
    final valid = masks.asTypedList(n);
    for (var k = 0; k < n; k++) {
      valid[k] = f.valid[k] ? 1 : 0;
    }
  }

  void dispose() {
    calloc.free(frame);
    malloc.free(numbers);
    calloc.free(masks);
  }
}

/// Opt-in desktop correspondence experiment. Owns copies of at most two
/// admitted frames; frame caches never grant risk or freshness authority.
/// FFI calls are non-leaf so a long search does not prevent Dart GC safepoints.
// Versioned copy transport correction. Typed setRange performs a bulk copy
// when the immutable transferred input is a Float64List. Arithmetic and C ABI
// remain identical to camera_fast_motion_native_match.dart.
class CameraFastMotionBulkNativeMatch {
  final _frames = <FastMetricMotionInput, _OwnedFrame>{};
  late final _Match _match;
  final _template = calloc<Double>(75), _basis = calloc<Double>(6);
  final _scores = calloc<Double>(4225);
  final _xs = calloc<Int32>(4225), _ys = calloc<Int32>(4225);
  bool _disposed = false;
  int matchComputeUs = 0, frameCopyUs = 0, matchingCalls = 0;
  int get cachedFrames => _frames.length;

  void resetStats() {
    matchComputeUs = 0;
    frameCopyUs = 0;
    matchingCalls = 0;
  }

  CameraFastMotionBulkNativeMatch(String libraryPath) {
    try {
      final library = DynamicLibrary.open(libraryPath);
      if (library.lookupFunction<Int32 Function(), int Function()>(
            'fast_motion_abi',
          )() !=
          1) {
        throw StateError('Native motion ABI mismatch');
      }
      _match = library.lookupFunction<_MatchNative, _Match>(
        'fast_motion_match',
      );
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  void retain(FastMetricMotionInput current, FastMetricMotionInput? previous) {
    _frames.removeWhere((key, owned) {
      if (identical(key, current) || identical(key, previous)) return false;
      owned.dispose();
      return true;
    });
  }

  void invalidate() {
    for (final frame in _frames.values) {
      frame.dispose();
    }
    _frames.clear();
  }

  List<int>? match(
    FastMetricMotionInput target,
    Float64List pixels,
    Float64List nx,
    Float64List ny,
    Float64List x2,
    Float64List y2,
    List<double> template,
    List<double> rx,
    List<double> ry,
    double za,
    List<int> around,
  ) {
    if (_disposed) throw StateError('Native matcher disposed');
    final frame = target.camera.depth;
    // Intersect the Dart-sized projected window before narrowing coordinates
    // to the native Int32 ABI. Out-of-image projections must not wrap back
    // into the image or overflow C's centre +/- radius arithmetic.
    if (around.length != 2 ||
        around[0] + 32 < 1 ||
        around[1] + 32 < 1 ||
        around[0] - 32 > frame.width - 2 ||
        around[1] - 32 > frame.height - 2) {
      return null;
    }
    prepare(target, pixels, nx, ny, x2, y2);
    final owned = _frames[target]!;
    _template.asTypedList(75).setAll(0, template);
    _basis.asTypedList(6)
      ..setAll(0, rx)
      ..setAll(3, ry);
    final timer = Stopwatch()..start();
    final index = _match(
      owned.frame,
      _template,
      _basis,
      za,
      around[0],
      around[1],
      _scores,
      _xs,
      _ys,
    );
    matchComputeUs += timer.elapsedMicroseconds;
    matchingCalls++;
    if (index < 0) return null;
    final width = target.camera.depth.width;
    return [index % width, index ~/ width];
  }

  void prepare(
    FastMetricMotionInput target,
    Float64List pixels,
    Float64List nx,
    Float64List ny,
    Float64List x2,
    Float64List y2,
  ) {
    if (_disposed) throw StateError('Native matcher disposed');
    final frame = target.camera.depth;
    if (!frame.structurallyValid ||
        pixels.length != frame.width * frame.height * 3 ||
        nx.length != frame.width ||
        x2.length != frame.width ||
        ny.length != frame.height ||
        y2.length != frame.height) {
      throw ArgumentError('Invalid admitted native frame buffers');
    }
    final timer = Stopwatch()..start();
    _frames.putIfAbsent(
      target,
      () => _OwnedFrame(target, pixels, nx, ny, x2, y2),
    );
    frameCopyUs += timer.elapsedMicroseconds;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    invalidate();
    calloc.free(_template);
    calloc.free(_basis);
    calloc.free(_scores);
    calloc.free(_xs);
    calloc.free(_ys);
  }
}

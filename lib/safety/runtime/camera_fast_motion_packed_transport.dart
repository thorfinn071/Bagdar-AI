import 'dart:isolate';
import 'dart:typed_data';

import '../perception/camera_fast_motion_types.dart';

/// Snapshot transport for an input already admitted by the worker.
/// Admission and freshness authority belong to the owner, not these bytes.
TransferableTypedData packFastMotionFrame(FastMetricMotionInput input) {
  final f = input.camera.depth;
  final n = f.width * f.height,
      rgbLength = input.rgb.length,
      padding = (8 - rgbLength % 8) % 8;
  // Construct a single owned packet. TransferableTypedData takes its own
  // snapshot; no caller buffer is sent, retained, or changed. This avoids
  // three temporary double arrays plus an intermediate boxed mask list.
  final depthStart = rgbLength + padding;
  final packet = Uint8List(depthStart + n * 25);
  packet.setRange(0, rgbLength, input.rgb);
  final doubles = Float64List.view(packet.buffer, depthStart, n * 3);
  doubles
    ..setRange(0, n, f.rangeM)
    ..setRange(n, n * 2, f.freeZLowerM)
    ..setRange(n * 2, n * 3, f.surfaceZUpperM);
  final maskStart = depthStart + n * 24;
  for (var i = 0; i < n; i++) {
    packet[maskStart + i] = f.valid[i] ? 1 : 0;
  }
  return TransferableTypedData.fromList([packet]);
}

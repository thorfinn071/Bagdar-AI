import 'package:bagdar/safety/perception/camera_typed_height_envelope_frame.dart';
import 'package:flutter_test/flutter_test.dart';

import 'camera_typed_height_envelope_frame_test.dart' show packet;
import 'harness/camera_visible_passage_fixture.dart' show copyVisibleFrame;
import 'single_camera_observability_test.dart' show opticalFrame;

void main() {
  for (final fault in [
    'frame',
    'capture',
    'session',
    'model',
    'transform',
    'reference',
    'origin',
    'rotation',
    'intrinsics',
  ]) {
    test('transferred optical payload rejects mismatched metadata: $fault', () {
      final original = packet();
      final metadata = fault == 'intrinsics'
          ? opticalFrame(focal: 3)
          : copyVisibleFrame(
              original.depth,
              frameId: fault == 'frame' ? 2 : null,
              timestamp: fault == 'capture'
                  ? original.depth.capturedAtUs + 100000
                  : null,
              session: fault == 'session' ? 2 : null,
              modelHash: fault == 'model' ? 'different-model' : null,
              transform: fault == 'transform' ? 'different-transform' : null,
              referenceFrame: fault == 'reference'
                  ? 'different-reference'
                  : null,
              origin: fault == 'origin' ? [0, 0, 1.2] : null,
              rotation: fault == 'rotation'
                  ? [1, 0, 0, 0, 1, 0, 0, 0, 1]
                  : null,
            );
      expect(
        () => CameraTypedHeightEnvelopeFrame.fromTransferable(
          metadata: metadata,
          storage: CameraTypedHeightEnvelopeFrame.pack(original),
        ),
        throwsFormatException,
      );
    });
  }
}

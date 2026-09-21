import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/camera_session.dart';
import 'package:bagdar/models/frame_packet.dart';
import 'package:bagdar/safety/perception/observation_header.dart';

void main() {
  group('CameraSession', () {
    test('new session rejects packets from the previous generation', () {
      final session = CameraSession();
      final first = session.beginNewSession();
      expect(session.accepts(first), isTrue);
      final second = session.beginNewSession();
      expect(session.accepts(first), isFalse);
      expect(session.accepts(second), isTrue);
    });

    test('frame ids are monotonic inside a session and reset on restart', () {
      final session = CameraSession();
      session.beginNewSession();
      expect(session.nextFrameId(), 1);
      expect(session.nextFrameId(), 2);
      session.beginNewSession();
      expect(session.nextFrameId(), 1);
    });

    test('latest-frame-wins rejects an older observation', () {
      final session = CameraSession();
      final generation = session.beginNewSession();
      final first = session.nextFrameId();
      final second = session.nextFrameId();
      final header = ObservationHeader(
        providerId: 'test-provider',
        modelId: 'test-model',
        modelHash: 'sha256:test',
        preprocessId: 'test-preprocess-v1',
        sessionGeneration: generation,
        frameId: first,
        sourceTimestampUs: 1_000_000,
        producedAtUs: 1_010_000,
        transformId: 'transform-v1',
        confidence: 1,
        health: ObservationHealth.healthy,
      );
      expect(first, 1);
      expect(second, 2);
      expect(session.acceptsObservation(header), isFalse);
    });

    test('rejects image/depth timestamp delta above 150 ms', () {
      expect(
        CameraSession.timestampsAligned(
          imageTimestampUs: 1_000_000,
          depthTimestampUs: 1_000_000,
        ),
        isTrue,
      );
      expect(
        CameraSession.timestampsAligned(
          imageTimestampUs: 1_000_000,
          depthTimestampUs: 1_200_000,
        ),
        isFalse,
      );
    });
  });

  group('upright geometry contract', () {
    test('rotation 0/90/180/270 matches the NCNN upright contract', () {
      const source = FrameSize(4, 6);
      const point = Offset(0.1, 0.2);
      Offset mapped(int rotation) => FrameTransform.forSensor(
        sensorRotationDeg: rotation,
        mirrored: false,
        sourceSize: source,
      ).mapSourcePointToUpright(point);

      expect(mapped(0), const Offset(0.1, 0.2));
      expect(mapped(90), const Offset(0.8, 0.1));
      expect(mapped(180), const Offset(0.9, 0.8));
      expect(mapped(270), const Offset(0.2, 0.9));

      expect(
        FrameTransform.forSensor(
          sensorRotationDeg: 90,
          mirrored: false,
          sourceSize: source,
        ).uprightSize.toDiagnosticMap(),
        <String, int>{'width': 6, 'height': 4},
      );
    });

    test('front-camera mirror is applied after upright rotation', () {
      final transform = FrameTransform.forSensor(
        sensorRotationDeg: 90,
        mirrored: true,
        sourceSize: const FrameSize(4, 6),
      );
      final mapped = transform.mapSourcePointToUpright(const Offset(0.1, 0.2));
      expect(mapped.dx, closeTo(0.2, 1e-9));
      expect(mapped.dy, closeTo(0.1, 1e-9));
    });

    test('crop is applied after rotation and mirror in normalized space', () {
      final transform = FrameTransform.forSensor(
        sensorRotationDeg: 0,
        mirrored: true,
        sourceSize: const FrameSize(100, 200),
        crop: const CropTransform(topFraction: 0.25),
      );
      final cropped = transform.mapSourceRectToCroppedUpright(
        const Rect.fromLTRB(0.2, 0.25, 0.4, 0.75),
      );
      expect(cropped.left, closeTo(0.6, 1e-9));
      expect(cropped.right, closeTo(0.8, 1e-9));
      expect(cropped.top, closeTo(0, 1e-9));
      expect(cropped.bottom, closeTo(2 / 3, 1e-9));
      expect(transform.id, contains('r0:m1:c0.000000,0.250000'));
    });
  });
}

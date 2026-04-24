import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/camera/frame_quality_guard.dart';
import 'package:bagdar/services/weather_gate.dart';

Uint8List _makeUniform(int w, int h, int value) {
  final bytes = Uint8List(w * h);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = value;
  }
  return bytes;
}

Uint8List _makeVaried(int w, int h, int seed) {
  final rng = Random(seed);
  final bytes = Uint8List(w * h);
  for (int i = 0; i < bytes.length; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return bytes;
}

Uint8List _makeGridPlane(int w, int h, List<bool> dirtyMask) {
  assert(dirtyMask.length == 9);
  final bytes = Uint8List(w * h);
  final cellW = w ~/ 3;
  final cellH = h ~/ 3;
  for (int y = 0; y < h; y++) {
    final gy = (y ~/ cellH).clamp(0, 2);
    for (int x = 0; x < w; x++) {
      final gx = (x ~/ cellW).clamp(0, 2);
      final gi = gy * 3 + gx;
      if (dirtyMask[gi]) {
        bytes[y * w + x] = 100;
      } else {
        bytes[y * w + x] = ((x % 3) * 127) & 0xFF;
      }
    }
  }
  return bytes;
}

void main() {
  group('FrameQualityGuard AE transition', () {
    test('emits aeStarted on first bright uniform frame, aeTransitioning after 2', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final plane = _makeUniform(64, 64, 220);

      final rep1 = guard.evaluate(
        yPlane: plane,
        bytesPerRow: 64,
        width: 64,
        height: 64,
        now: DateTime(2024),
      );
      expect(
        rep1.events.any((e) =>
            e.type == FrameQualityEventType.aeTransitionStarted),
        isTrue,
      );
      expect(guard.aeTransitionFrames, 1);
      expect(guard.aeTransitioning, isFalse);
      expect(rep1.aePipelineFrozen, isFalse);

      final rep2 = guard.evaluate(
        yPlane: plane,
        bytesPerRow: 64,
        width: 64,
        height: 64,
        now: DateTime(2024).add(const Duration(milliseconds: 50)),
      );
      expect(guard.aeTransitionFrames, 2);
      expect(guard.aeTransitioning, isTrue);
      expect(rep2.aePipelineFrozen, isTrue);
      expect(
        rep2.events.any((e) =>
            e.type == FrameQualityEventType.aeTransitionStarted),
        isFalse,
      );
    });

    test('emits aeEnded event and stays frozen within 3-second guard window', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final bright = _makeUniform(64, 64, 220);
      final varied = _makeVaried(64, 64, 42);

      for (int i = 0; i < 5; i++) {
        guard.evaluate(
          yPlane: bright,
          bytesPerRow: 64,
          width: 64,
          height: 64,
          now: DateTime(2024).add(Duration(milliseconds: i * 30)),
        );
      }
      expect(guard.aeTransitionFrames, 5);

      final endTime = DateTime(2024).add(const Duration(milliseconds: 200));
      final rep = guard.evaluate(
        yPlane: varied,
        bytesPerRow: 64,
        width: 64,
        height: 64,
        now: endTime,
      );
      final ended = rep.events.firstWhere(
        (e) => e.type == FrameQualityEventType.aeTransitionEnded,
        orElse: () => fail('no aeEnded event'),
      );
      expect(ended.frames, 5);
      expect(guard.aeTransitionFrames, 0);
      expect(rep.aePipelineFrozen, isTrue);

      expect(
        guard.aePipelineFrozen(endTime.add(const Duration(seconds: 2))),
        isTrue,
      );
      expect(
        guard.aePipelineFrozen(endTime.add(const Duration(seconds: 4))),
        isFalse,
      );
    });
  });

  group('FrameQualityGuard camera blocked', () {
    test('emits cameraBlocked after 45 consecutive dark frames', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final dark = _makeUniform(64, 64, 5);

      FrameQualityReport? rep;
      for (int i = 0; i < 45; i++) {
        rep = guard.evaluate(
          yPlane: dark,
          bytesPerRow: 64,
          width: 64,
          height: 64,
          now: DateTime(2024).add(Duration(milliseconds: i)),
        );
      }
      expect(
        rep!.events.any((e) =>
            e.type == FrameQualityEventType.cameraBlocked),
        isTrue,
      );
      expect(guard.cameraBlockedWarned, isTrue);
      expect(guard.lowLuminosityFrames, 45);
    });

    test('recovers (reset flag) after first bright frame', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final dark = _makeUniform(64, 64, 5);
      final bright = _makeVaried(64, 64, 7);

      for (int i = 0; i < 45; i++) {
        guard.evaluate(
          yPlane: dark,
          bytesPerRow: 64,
          width: 64,
          height: 64,
          now: DateTime(2024).add(Duration(milliseconds: i)),
        );
      }
      expect(guard.cameraBlockedWarned, isTrue);

      guard.evaluate(
        yPlane: bright,
        bytesPerRow: 64,
        width: 64,
        height: 64,
        now: DateTime(2024).add(const Duration(milliseconds: 60)),
      );
      expect(guard.cameraBlockedWarned, isFalse);
      expect(guard.lowLuminosityFrames, 0);
    });
  });

  group('FrameQualityGuard droplet detection', () {
    test('emits dropletDetected after sustained low-variance grid cells', () {
      const w = 96;
      const h = 96;
      final plane = _makeGridPlane(w, h, const [
        true, true, false,
        false, false, false,
        false, false, false,
      ]);

      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      bool dropletEmitted = false;
      for (int i = 0; i < 65; i++) {
        final rep = guard.evaluate(
          yPlane: plane,
          bytesPerRow: w,
          width: w,
          height: h,
          now: DateTime(2024).add(Duration(milliseconds: i * 50)),
        );
        if (rep.events
            .any((e) => e.type == FrameQualityEventType.dropletDetected)) {
          dropletEmitted = true;
        }
      }
      expect(
        dropletEmitted,
        isTrue,
        reason: 'streaks=${guard.debugDropletStreaks}',
      );
      expect(guard.dropletSuspected, isTrue);
    });
  });

  group('FrameQualityGuard frozen frame', () {
    test('emits cameraFrozen when hash unchanged for > 5 seconds', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final varied = _makeVaried(96, 96, 77);

      guard.evaluate(
        yPlane: varied,
        bytesPerRow: 96,
        width: 96,
        height: 96,
        now: DateTime(2024),
      );
      final rep = guard.evaluate(
        yPlane: varied,
        bytesPerRow: 96,
        width: 96,
        height: 96,
        now: DateTime(2024).add(const Duration(seconds: 6)),
      );
      expect(
        rep.events.any((e) => e.type == FrameQualityEventType.cameraFrozen),
        isTrue,
      );
      expect(guard.cameraFrozenWarned, isTrue);
    });

    test('does not re-emit frozen event while still frozen', () {
      final guard = FrameQualityGuard(
        weatherGate: WeatherGate(),
        initialTime: DateTime(2024),
      );
      final varied = _makeVaried(96, 96, 77);

      guard.evaluate(
        yPlane: varied,
        bytesPerRow: 96,
        width: 96,
        height: 96,
        now: DateTime(2024),
      );
      guard.evaluate(
        yPlane: varied,
        bytesPerRow: 96,
        width: 96,
        height: 96,
        now: DateTime(2024).add(const Duration(seconds: 6)),
      );
      final rep = guard.evaluate(
        yPlane: varied,
        bytesPerRow: 96,
        width: 96,
        height: 96,
        now: DateTime(2024).add(const Duration(seconds: 7)),
      );
      expect(
        rep.events.any((e) => e.type == FrameQualityEventType.cameraFrozen),
        isFalse,
      );
    });
  });
}

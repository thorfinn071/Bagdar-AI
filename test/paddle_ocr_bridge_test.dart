import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/paddle_ocr_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    PaddleOcrBridge.debugResetInstance();
  });

  group('OcrTextLine.fromMap', () {
    test('parses a fully-populated payload', () {
      final line = OcrTextLine.fromMap(const {
        'text': 'Қазақстан',
        'confidence': 0.92,
        'box': [10, 20, 100, 30],
      });
      expect(line.text, 'Қазақстан');
      expect(line.confidence, closeTo(0.92, 1e-9));
      expect(line.box, [10, 20, 100, 30]);
    });

    test('returns confidence=0 when the payload omits it', () {
      final line = OcrTextLine.fromMap(const {'text': 'hello'});
      expect(line.text, 'hello');
      expect(line.confidence, 0.0);
      expect(line.box, isEmpty);
    });

    test('defends against non-list box values', () {
      final line = OcrTextLine.fromMap(const {
        'text': 'x',
        'confidence': 0.5,
        'box': 'garbage',
      });
      expect(line.box, isEmpty);
    });
  });

  group('PaddleOcrCapability.fromMap', () {
    test('parses available + version', () {
      final cap = PaddleOcrCapability.fromMap(const {
        'available': true,
        'version': '2.13',
      });
      expect(cap.available, isTrue);
      expect(cap.version, '2.13');
      expect(cap.unavailableReason, isEmpty);
    });

    test('records the unavailableReason for diagnostics', () {
      final cap = PaddleOcrCapability.fromMap(const {
        'available': false,
        'unavailableReason': 'models_missing',
      });
      expect(cap.available, isFalse);
      expect(cap.unavailableReason, 'models_missing');
    });
  });

  group('PaddleOcrBridge — channel plumbing', () {
    test(
      'availableEngine round-trips capability through the platform channel',
      () async {
        const channel = MethodChannel('bagdar/paddle_ocr');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'availableEngine') {
            return {
              'available': true,
              'version': '2.13',
            };
          }
          return null;
        });

        final bridge = PaddleOcrBridge.forTesting(methodChannel: channel);
        await bridge.init();
        expect(bridge.isAvailable, isTrue);
        expect(bridge.capability.version, '2.13');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );

    test(
      'recognize returns parsed OcrTextLine list when channel responds',
      () async {
        const channel = MethodChannel('bagdar/paddle_ocr');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'recognize') {
            return [
              {
                'text': 'Қазақстан',
                'confidence': 0.91,
                'box': [0, 0, 100, 30],
              },
              {
                'text': 'Астана',
                'confidence': 0.74,
                'box': [0, 40, 80, 30],
              },
            ];
          }
          return null;
        });

        final bridge = PaddleOcrBridge.forTesting(methodChannel: channel);
        bridge.debugSetCapability(const PaddleOcrCapability(available: true));

        final lines = await bridge.recognize(
          yuvBytes: Uint8List.fromList(const [0, 1, 2, 3]),
          width: 100,
          height: 100,
          bytesPerRow: 100,
          rotationDeg: 90,
        );
        expect(lines, hasLength(2));
        expect(lines[0].text, 'Қазақстан');
        expect(lines[1].text, 'Астана');
        expect(lines.map((l) => l.confidence),
            everyElement(greaterThan(0)));

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );

    test(
      'recognize short-circuits to empty list when engine is unavailable',
      () async {
        const channel = MethodChannel('bagdar/paddle_ocr');
        var channelHits = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          channelHits++;
          return null;
        });

        final bridge = PaddleOcrBridge.forTesting(methodChannel: channel);
        
        final lines = await bridge.recognize(
          yuvBytes: Uint8List.fromList(const [0, 1, 2, 3]),
          width: 100,
          height: 100,
          bytesPerRow: 100,
          rotationDeg: 90,
        );
        expect(lines, isEmpty);
        expect(channelHits, 0,
            reason: 'unavailable engine must not hit the platform channel');

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );

    test(
      'recognize swallows PlatformException and returns empty list',
      () async {
        const channel = MethodChannel('bagdar/paddle_ocr');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'recognize') {
            throw PlatformException(code: 'RECOGNIZE_FAILED');
          }
          return null;
        });

        final bridge = PaddleOcrBridge.forTesting(methodChannel: channel);
        bridge.debugSetCapability(const PaddleOcrCapability(available: true));

        final lines = await bridge.recognize(
          yuvBytes: Uint8List.fromList(const [0, 1, 2, 3]),
          width: 100,
          height: 100,
          bytesPerRow: 100,
          rotationDeg: 90,
        );
        expect(lines, isEmpty);

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      },
    );

    test('init flagged as unavailable when plugin is missing', () async {
      
      
      final bridge = PaddleOcrBridge.forTesting(
        methodChannel: const MethodChannel('bagdar/paddle_ocr_unmocked'),
      );
      await bridge.init();
      expect(bridge.isAvailable, isFalse);
      expect(bridge.capability.unavailableReason, 'plugin_missing');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/vosk_kk_recognizer.dart';

void main() {
  group('VoskKkRecognizer.testExtractText', () {
    test('extracts text field from Vosk-style JSON', () {
      final result = VoskKkRecognizer.testExtractText(
        '{"text": "айналада не бар"}',
        'text',
      );
      expect(result, 'айналада не бар');
    });

    test('extracts partial field from partial JSON', () {
      final result = VoskKkRecognizer.testExtractText(
        '{"partial": "айналада"}',
        'partial',
      );
      expect(result, 'айналада');
    });

    test('returns empty string for empty final result', () {
      final result = VoskKkRecognizer.testExtractText(
        '{"text": ""}',
        'text',
      );
      expect(result, '');
    });

    test('returns empty string when key is missing', () {
      final result = VoskKkRecognizer.testExtractText(
        '{"text": "айналада"}',
        'partial',
      );
      expect(result, '');
    });

    test('returns empty string for empty input', () {
      expect(VoskKkRecognizer.testExtractText('', 'text'), '');
    });

    test('falls through to bare-string mode for non-JSON payloads', () {
      
      
      expect(
        VoskKkRecognizer.testExtractText('тура', 'text'),
        'тура',
      );
    });

    test('trims whitespace from extracted text', () {
      expect(
        VoskKkRecognizer.testExtractText(
          '{"text": "   айналада не бар   "}',
          'text',
        ),
        'айналада не бар',
      );
    });

    test('malformed JSON does not throw, returns empty', () {
      expect(
        VoskKkRecognizer.testExtractText('{"text": ', 'text'),
        '',
      );
    });
  });

  group('VoskKkRecognizer.unknownToken', () {
    test('matches Vosk\'s [unk] sentinel verbatim', () {
      
      
      expect(VoskKkRecognizer.unknownToken, '[unk]');
    });
  });

  group('VoskKkRecognizer.sampleRateHz', () {
    test('vosk-kk small model expects 16 kHz', () {
      
      
      expect(VoskKkRecognizer.sampleRateHz, 16000);
    });
  });

  group('VoskKkRecognizer instance lifecycle (without native model)', () {
    test('singleton instance is stable', () {
      final a = VoskKkRecognizer.instance;
      final b = VoskKkRecognizer.instance;
      expect(identical(a, b), true);
    });

    test('debugInjectFinalResult fires onResult callback', () {
      final rec = VoskKkRecognizer.instance;
      String? captured;
      rec.onResult = (text) => captured = text;
      rec.debugInjectFinalResult('{"text": "көмек"}');
      expect(captured, 'көмек');
      expect(rec.lastFinalText, 'көмек');
    });

    test('debugInjectPartial fires onPartial callback', () {
      final rec = VoskKkRecognizer.instance;
      String? captured;
      rec.onPartial = (text) => captured = text;
      rec.debugInjectPartial('{"partial": "көме"}');
      expect(captured, 'көме');
    });

    test('debugInjectPartial with empty partial does not fire callback', () {
      final rec = VoskKkRecognizer.instance;
      String? captured;
      rec.onPartial = (text) => captured = text;
      rec.debugInjectPartial('{"partial": ""}');
      expect(captured, isNull);
    });
  });
}

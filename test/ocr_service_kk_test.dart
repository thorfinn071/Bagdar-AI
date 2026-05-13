import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/models/strings.dart';
import 'package:bagdar/services/kk_dictionary.dart';
import 'package:bagdar/services/ocr_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    KkDictionary.instance.debugReset();
    AppStrings.setLanguage(AppLanguage.kk);
  });

  tearDown(() {
    AppStrings.setLanguage(AppLanguage.ru);
  });

  group('OcrService — Phase 3 Kazakh post-correction', () {
    test('passes text through unchanged when language is not kk', () {
      AppStrings.setLanguage(AppLanguage.ru);
      KkDictionary.instance.debugSeed(const ['қазақстан']);
      final svc = OcrService();
      const input = 'казакстан';
      // Same OCR output that would get corrected if language were kk,
      // but the ru path must leave it untouched.
      expect(
        svc.debugApplyKkCorrection(input),
        input,
        reason: 'only kk language activates post-correction',
      );
      svc.dispose();
    });

    test('returns input unchanged when the dictionary has not loaded', () {
      // Dictionary is reset in setUp → isLoaded == false → no-op.
      final svc = OcrService();
      const input = 'казакстан';
      expect(svc.debugApplyKkCorrection(input), input);
      svc.dispose();
    });

    test('applies kk confusion-pair correction when dict is loaded', () {
      // Single-edit example matching KkDictionary's spec (К → Қ only).
      KkDictionary.instance.debugSeed(const ['қазахстан']);
      final svc = OcrService();
      final corrected = svc.debugApplyKkCorrection('казахстан');
      expect(corrected, 'қазахстан');
      svc.dispose();
    });
  });

  group('OcrService — stabilizer semantics', () {
    test(
      'requires two identical consecutive reads before emitting',
      () {
        final svc = OcrService();
        // First read fills the buffer; expect no emission yet.
        final first = svc.debugFinalizeForTesting('exit', stabilize: true);
        expect(first, isNull);
        expect(svc.debugStabilizeBufferLength(), 1);

        // Second identical read should release the text.
        final second = svc.debugFinalizeForTesting('exit', stabilize: true);
        expect(second, 'exit');
        expect(svc.debugStabilizeBufferLength(), 0,
            reason: 'buffer clears once stabilized output is emitted');
        svc.dispose();
      },
    );

    test(
      'non-matching second read suppresses emission and rotates the buffer',
      () {
        final svc = OcrService();
        svc.debugFinalizeForTesting('exit', stabilize: true);
        final divergent =
            svc.debugFinalizeForTesting('entrance', stabilize: true);
        expect(divergent, isNull,
            reason: 'stabilizer must require two identical reads');
        // Buffer should keep the last two values, rotating the older one out.
        expect(svc.debugStabilizeBufferLength(), 2);
        svc.dispose();
      },
    );

    test(
      'stabilize=false passes the text through immediately and clears buffer',
      () {
        final svc = OcrService();
        svc.debugFinalizeForTesting('one', stabilize: true);
        expect(svc.debugStabilizeBufferLength(), 1);

        final direct = svc.debugFinalizeForTesting('two', stabilize: false);
        expect(direct, 'two');
        expect(svc.debugStabilizeBufferLength(), 0,
            reason: 'non-stabilized reads must reset the buffer');
        svc.dispose();
      },
    );
  });
}

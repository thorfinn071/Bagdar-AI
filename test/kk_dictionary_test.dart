import 'package:flutter_test/flutter_test.dart';

import 'package:bagdar/services/kk_dictionary.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    KkDictionary.instance.debugReset();
  });

  group('KkDictionary — confusion-pair correction', () {
    test('returns input unchanged when the dictionary is not loaded', () {
      const input = 'қазахстан астанасы';
      expect(KkDictionary.instance.correctSentence(input), input);
    });

    test('does not mutate words that are already correct', () {
      KkDictionary.instance.debugSeed(const ['қазахстан', 'астанасы']);
      const input = 'қазахстан астанасы';
      expect(KkDictionary.instance.correctSentence(input), input);
    });

    test('fixes К→Қ confusion when only the Kazakh variant is in dict', () {
      KkDictionary.instance.debugSeed(const ['қазахстан']);
      expect(KkDictionary.instance.correctSentence('казахстан'), 'қазахстан');
    });

    test('fixes Н→Ң confusion at the end of a word', () {
      KkDictionary.instance.debugSeed(const ['жоғарың']);
      expect(KkDictionary.instance.correctSentence('жоғарын'), 'жоғарың');
    });

    test('preserves Russian loanwords that have no Kazakh variant', () {
      KkDictionary.instance.debugSeed(const ['қазақстан']);
      const loan = 'телефон';
      expect(KkDictionary.instance.correctSentence(loan), loan);
    });

    test('preserves digits and punctuation between words', () {
      KkDictionary.instance.debugSeed(const ['қазахстан']);
      const input = 'казахстан, 2024 жыл.';
      final corrected = KkDictionary.instance.correctSentence(input);
      expect(corrected, 'қазахстан, 2024 жыл.');
    });

    test('returns first matching candidate deterministically when multiple '
        'variants exist', () {
      KkDictionary.instance.debugSeed(const ['суы', 'сүй']);

      expect(KkDictionary.instance.correctWordForTesting('суй'), 'сүй');
    });

    test('lower / upper case handling is symmetric', () {
      KkDictionary.instance.debugSeed(const ['ұлы']);

      expect(KkDictionary.instance.correctWordForTesting('Улы'), 'Ұлы');
    });
  });

  group('KkDictionary — performance', () {
    test(
      'post-corrects 200-char input in well under 50 ms with a small dict',
      () {
        KkDictionary.instance.debugSeed(const [
          'қазахстан',
          'астанасы',
          'мемлекеттік',
          'университеті',
          'ұлттық',
          'кітапханасы',
          'жоғары',
          'мектеп',
          'өмір',
          'әке',
          'ұлы',
          'сүрет',
        ]);

        const input =
            'казахстан астанасы мемлекеттік '
            'университеті ұлттық кітапханасы жоғары '
            'мектеп өмір әке ұлы сүрет казахстан астанасы '
            'мемлекеттік университеті ұлттық кітапханасы';
        expect(input.length, greaterThan(150));

        final sw = Stopwatch()..start();
        KkDictionary.instance.correctSentence(input);
        sw.stop();
        expect(
          sw.elapsedMilliseconds,
          lessThan(50),
          reason:
              'Phase 3 acceptance: post-correction must stay under '
              '50 ms for a 200-char input on the test host',
        );
      },
    );
  });

  group('KkDictionary — bookkeeping', () {
    test('debugSeed marks the dictionary as loaded', () {
      expect(KkDictionary.instance.isLoaded, isFalse);
      KkDictionary.instance.debugSeed(const ['жалпы']);
      expect(KkDictionary.instance.isLoaded, isTrue);
      expect(KkDictionary.instance.wordCount, 1);
    });

    test('contains is case-insensitive', () {
      KkDictionary.instance.debugSeed(const ['Қазақстан']);
      expect(KkDictionary.instance.contains('қазақстан'), isTrue);
      expect(KkDictionary.instance.contains('ҚАЗАҚСТАН'), isTrue);
      expect(KkDictionary.instance.contains('Russia'), isFalse);
    });

    test('debugReset clears state', () {
      KkDictionary.instance.debugSeed(const ['жалпы']);
      expect(KkDictionary.instance.isLoaded, isTrue);
      KkDictionary.instance.debugReset();
      expect(KkDictionary.instance.isLoaded, isFalse);
      expect(KkDictionary.instance.wordCount, 0);
    });
  });
}

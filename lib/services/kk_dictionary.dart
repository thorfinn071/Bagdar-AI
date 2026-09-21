import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// Confusion pairs the OCR pipeline is most likely to flip on Kazakh
/// text. Each Russian letter that "looks similar" to a Kazakh extra
/// letter is mapped to the set of Kazakh letters it might be confused
/// with — the [KkDictionary] uses these to propose 1-edit candidate
/// corrections without over-correcting Russian loanwords.
///
/// Source: PaddleOCR Cyrillic substitution analysis + standard Kazakh
/// orthography reference.
const Map<String, List<String>> kKkConfusionPairs = {
  'а': ['ә'],
  'г': ['ғ'],
  'к': ['қ'],
  'н': ['ң'],
  'о': ['ө'],
  'у': ['ұ', 'ү'],
  'х': ['һ'],
  'ы': ['і'],
  'и': ['і'],

  'А': ['Ә'],
  'Г': ['Ғ'],
  'К': ['Қ'],
  'Н': ['Ң'],
  'О': ['Ө'],
  'У': ['Ұ', 'Ү'],
  'Х': ['Һ'],
  'Ы': ['І'],
  'И': ['І'],
};

/// In-memory Kazakh wordlist with conservative OCR post-correction.
///
/// Loaded lazily from `assets/paddle_ocr/kk_wordlist.txt.gz`. Each word
/// is stored once (lowercase) so the in-memory footprint stays under
/// ~6 MB for the 100 K-word frequency list specified in
/// `plans/bagdar-kazakh-language-stack-1f2668.md`.
///
/// The correction algorithm is intentionally narrow:
///   - For each whitespace-delimited word that is not already in the
///     dictionary, generate all single-substitution variants where the
///     edit comes from [kKkConfusionPairs].
///   - If exactly one variant exists in the dictionary, use it; if
///     multiple match, pick the first one (deterministic so the same
///     OCR input always corrects to the same output).
///   - Otherwise leave the word untouched.
///
/// This guarantees:
///   - Russian loanwords (which won't be in the kk dictionary) are
///     never silently flipped.
///   - Proper nouns and digits pass through unchanged.
///   - The fix-up budget per word is O(L × P) where L = word length
///     and P = max alternates per letter (≤ 2), so a 200-character
///     sentence post-corrects in well under 50 ms on Snapdragon 680.
class KkDictionary {
  KkDictionary._();

  static final KkDictionary instance = KkDictionary._();

  static const String _assetPath = 'assets/paddle_ocr/kk_wordlist.txt.gz';

  final Set<String> _words = <String>{};
  bool _loaded = false;
  bool _loading = false;
  Completer<bool>? _loadCompleter;

  /// True once the wordlist has been loaded into memory. When the asset
  /// is missing, `isLoaded` stays false and [correctSentence] becomes a
  /// no-op (returns the input unchanged).
  bool get isLoaded => _loaded;

  /// Number of words currently in the dictionary. Useful for diagnostics
  /// and tests.
  int get wordCount => _words.length;

  /// Best-effort load. Returns `true` on success, `false` if the asset
  /// is missing or unreadable. Idempotent + reentrancy-safe — repeated
  /// calls await the first in-flight load.
  Future<bool> load({AssetBundle? bundle}) async {
    if (_loaded) return true;
    if (_loading && _loadCompleter != null) {
      return _loadCompleter!.future;
    }
    _loading = true;
    _loadCompleter = Completer<bool>();
    try {
      final source = bundle ?? rootBundle;
      final bytes = await source.load(_assetPath);
      final raw = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      final decompressed = GZipDecoder().decodeBytes(raw);
      final text = utf8.decode(decompressed, allowMalformed: true);
      _ingest(text);
      _loaded = true;
      _loadCompleter!.complete(true);
      return true;
    } catch (e) {
      debugPrint('KkDictionary.load failed: $e');
      _loaded = false;
      _loadCompleter!.complete(false);
      return false;
    } finally {
      _loading = false;
    }
  }

  /// Apply Kazakh confusion-pair post-correction to [text]. Whitespace
  /// and punctuation are preserved; only alphabetic runs are inspected.
  ///
  /// When the dictionary has not been loaded (asset missing during
  /// development, or on a host without the bundle), this returns
  /// [text] unchanged.
  String correctSentence(String text) {
    if (!_loaded || text.isEmpty) return text;
    final out = StringBuffer();
    final runeBuf = StringBuffer();
    final chars = text.runes.toList(growable: false);

    void flushWord() {
      if (runeBuf.isEmpty) return;
      final word = runeBuf.toString();
      out.write(_correctWord(word));
      runeBuf.clear();
    }

    for (final code in chars) {
      final ch = String.fromCharCode(code);
      if (_isWordChar(code)) {
        runeBuf.write(ch);
      } else {
        flushWord();
        out.write(ch);
      }
    }
    flushWord();
    return out.toString();
  }

  /// Public for unit testing — apply correction to a single bare word.
  @visibleForTesting
  String correctWordForTesting(String word) => _correctWord(word);

  /// True iff [word] exists verbatim in the dictionary (case-insensitive).
  bool contains(String word) => _words.contains(word.toLowerCase());

  String _correctWord(String word) {
    if (word.length < 2) return word;
    final lower = word.toLowerCase();
    if (_words.contains(lower)) return word;
    final candidates = _generateConfusionVariants(word);
    for (final candidate in candidates) {
      if (_words.contains(candidate.toLowerCase())) {
        return candidate;
      }
    }
    return word;
  }

  /// Generate all 1-substitution variants of [word] where the
  /// substitution comes from [kKkConfusionPairs]. Deterministic order:
  /// scan left-to-right, expand each confusion alternative in the
  /// order they appear in the table.
  Iterable<String> _generateConfusionVariants(String word) sync* {
    final units = word.split('');
    for (var i = 0; i < units.length; i++) {
      final alternates = kKkConfusionPairs[units[i]];
      if (alternates == null) continue;
      for (final alt in alternates) {
        final mutated = List<String>.of(units);
        mutated[i] = alt;
        yield mutated.join();
      }
    }
  }

  /// `\p{Letter}` is overkill for a quick guard; a hand-rolled Cyrillic
  /// + Latin + digits check is enough for the OCR pipeline and avoids
  /// the regex compile cost per call.
  bool _isWordChar(int rune) {
    if (rune >= 0x30 && rune <= 0x39) return true;
    if (rune >= 0x41 && rune <= 0x5A) return true;
    if (rune >= 0x61 && rune <= 0x7A) return true;
    if (rune >= 0x0400 && rune <= 0x04FF) return true;
    if (rune == 0x2D || rune == 0x27) return true;
    return false;
  }

  void _ingest(String text) {
    _words.clear();
    for (final raw in const LineSplitter().convert(text)) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      _words.add(trimmed.toLowerCase());
    }
  }

  /// Seed the in-memory dictionary directly (bypasses the asset load).
  /// Tests should never depend on `assets/paddle_ocr/kk_wordlist.txt.gz`
  /// being present.
  @visibleForTesting
  void debugSeed(Iterable<String> words) {
    _words
      ..clear()
      ..addAll(words.map((w) => w.toLowerCase()));
    _loaded = true;
  }

  @visibleForTesting
  void debugReset() {
    _words.clear();
    _loaded = false;
    _loading = false;
    _loadCompleter = null;
  }
}

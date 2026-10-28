/// Short sequential utterances keep long instructions within the existing TTS
/// engine's per-utterance timeout. Paragraph order and every word are preserved.
Iterable<String> onboardingSpeechSegments(String text) sync* {
  for (final paragraph in text.split('\n')) {
    var chunk = '';
    for (final word in paragraph.trim().split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      if (chunk.isNotEmpty && chunk.length + 1 + word.length > 160) {
        yield chunk;
        chunk = '';
      }
      chunk = chunk.isEmpty ? word : '$chunk $word';
    }
    if (chunk.isNotEmpty) yield chunk;
  }
}

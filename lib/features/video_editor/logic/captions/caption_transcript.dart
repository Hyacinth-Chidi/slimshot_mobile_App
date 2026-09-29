/// A word as the server reports it, in seconds from the start of the uploaded
/// audio — which starts at timeline 0, so these are timeline seconds.
class TranscriptWord {
  const TranscriptWord({
    required this.text,
    required this.start,
    required this.end,
  });

  final String text;
  final double start;
  final double end;
}

/// A finished caption job's result.
class CaptionTranscript {
  const CaptionTranscript({
    required this.text,
    required this.words,
    this.language,
  });

  /// The whole transcript, with the provider's own spacing.
  final String text;
  final List<TranscriptWord> words;
  final String? language;

  /// Defensive, like every read here: a word with no text, or a start that is
  /// not a finite, non-negative number, is dropped; an end before its start is
  /// pulled up to it.
  factory CaptionTranscript.fromJson(Map<String, dynamic> json) {
    double? number(Object? value) => value is num ? value.toDouble() : null;

    final words = <TranscriptWord>[];
    final raw = json['words'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        final text = entry['text'];
        final start = number(entry['start']);
        final end = number(entry['end']);
        if (text is! String || text.trim().isEmpty) continue;
        if (start == null || !start.isFinite || start < 0) continue;
        words.add(
          TranscriptWord(
            text: text.trim(),
            start: start,
            end: end == null || !end.isFinite || end < start ? start : end,
          ),
        );
      }
    }
    final text = json['text'];
    final language = json['language'];
    return CaptionTranscript(
      text: text is String ? text : '',
      words: words,
      language: language is String ? language : null,
    );
  }
}

/// A transcript word and the separator written before it.
class SpacedWord {
  const SpacedWord(this.separator, this.word);

  /// `' '` or `''` — never anything else.
  final String separator;
  final TranscriptWord word;
}

final RegExp _whitespace = RegExp(r'\s');

/// Each word's leading separator, recovered from the transcript [text].
///
/// The server drops the provider's spacing tokens, so words arrive without the
/// spaces between them — and joining them with a space would put spaces
/// through Chinese and Japanese, which are written without any. The whole
/// transcript still has the true spacing: each word is found in it, in order,
/// and whatever lies between two words is the separator — one space if it
/// holds any whitespace, nothing otherwise. A word the transcript does not
/// contain falls back to one space.
List<SpacedWord> rebuildTranscriptSpacing(
  String text,
  List<TranscriptWord> words,
) {
  final spaced = <SpacedWord>[];
  var cursor = 0;
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    final at = text.indexOf(word.text, cursor);
    var separator = ' ';
    if (at >= 0) {
      separator = text.substring(cursor, at).contains(_whitespace) ? ' ' : '';
      cursor = at + word.text.length;
    }
    spaced.add(SpacedWord(i == 0 ? '' : separator, word));
  }
  return spaced;
}

import 'dart:math' as math;

import 'caption_word.dart';

/// One word of a caption's text: where it sits, and what it is once case and
/// punctuation are set aside.
class CaptionToken {
  const CaptionToken(this.start, this.end, this.normalised);

  /// UTF-16 offsets into the text, `[start, end)`.
  final int start;
  final int end;

  /// Lower case, letters and digits only — what two spellings of one word
  /// share. Empty for a token with neither (a dash, an emoji).
  final String normalised;
}

final RegExp _space = RegExp(r'\s');
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final RegExp _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}]', unicode: true);

/// Han and kana: scripts written without spaces between words. Hangul is not
/// here — Korean spaces its words.
bool isUnspacedScript(int rune) =>
    (rune >= 0x3040 && rune <= 0x30FF) ||
    (rune >= 0x3400 && rune <= 0x4DBF) ||
    (rune >= 0x4E00 && rune <= 0x9FFF) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0x20000 && rune <= 0x2FA1F);

String _normalise(String word) =>
    word.toLowerCase().replaceAll(_notLetterOrDigit, '');

/// The words of [text], as the transcript counts them: separated by
/// whitespace, except that each character of a script written without spaces
/// is a word of its own — which is how a provider returns those languages.
/// Punctuation stays with the word it follows.
List<CaptionToken> captionTokens(String text) {
  final tokens = <CaptionToken>[];
  var start = -1;
  var lastLetterUnspaced = false;
  var at = 0;

  void close(int end) {
    if (start < 0) return;
    tokens.add(
      CaptionToken(start, end, _normalise(text.substring(start, end))),
    );
    start = -1;
  }

  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (_space.hasMatch(char)) {
      close(at);
      lastLetterUnspaced = false;
    } else {
      final unspaced = isUnspacedScript(rune);
      final letter = unspaced || _letterOrDigit.hasMatch(char);
      if (unspaced || (lastLetterUnspaced && letter)) close(at);
      if (start < 0) start = at;
      if (letter) lastLetterUnspaced = unspaced;
    }
    at += rune > 0xFFFF ? 2 : 1;
  }
  close(at);
  return tokens;
}

/// The words of [newText], timed from what [oldText]'s words were.
///
/// Fixing a misheard word must not move the words around it. Old and new
/// words are aligned by their longest common subsequence — case and
/// punctuation set aside, so `hello` and `Hello,` are one word — and **a word
/// that matched keeps its times exactly**. A run of words that did not match
/// shares the room between its matched neighbours (or the caption's edges,
/// [span] being its length), each in proportion to its length. With nothing
/// matched at all — a rewrite, or a caption that carried no words — they
/// share the whole caption.
///
/// Times are relative to the caption's start, like [CaptionWord]'s.
List<CaptionWord> retimeCaptionWords({
  required String oldText,
  required List<CaptionWord> oldWords,
  required String newText,
  required Duration span,
}) {
  final tokens = captionTokens(newText);
  if (tokens.isEmpty) return const [];

  final old = [
    for (final w in oldWords)
      if (w.textStart >= 0 &&
          w.textEnd <= oldText.length &&
          w.textStart < w.textEnd)
        w,
  ];
  final oldNorm = [
    for (final w in old) _normalise(oldText.substring(w.textStart, w.textEnd)),
  ];
  final matched = _align(oldNorm, [for (final t in tokens) t.normalised]);

  final spanMs = math.max(0, span.inMilliseconds);
  final starts = List<int?>.filled(tokens.length, null);
  final ends = List<int?>.filled(tokens.length, null);
  matched.forEach((token, word) {
    starts[token] = old[word].start.inMilliseconds;
    ends[token] = old[word].end.inMilliseconds;
  });

  var i = 0;
  while (i < tokens.length) {
    if (starts[i] != null) {
      i++;
      continue;
    }
    var j = i;
    while (j < tokens.length && starts[j] == null) {
      j++;
    }
    // The room: from the matched word before the run to the one after it.
    final from = i == 0 ? 0 : ends[i - 1]!;
    final to = math.max(from, j == tokens.length ? spanMs : starts[j]!);
    final lengths = [for (var k = i; k < j; k++) tokens[k].end - tokens[k].start];
    final total = lengths.fold<int>(0, (a, b) => a + b);
    var before = 0;
    for (var k = i; k < j; k++) {
      starts[k] = from + ((to - from) * before / total).round();
      before += lengths[k - i];
      ends[k] = from + ((to - from) * before / total).round();
    }
    i = j;
  }

  return [
    for (var k = 0; k < tokens.length; k++)
      CaptionWord(
        textStart: tokens[k].start,
        textEnd: tokens[k].end,
        start: Duration(milliseconds: starts[k]!),
        end: Duration(milliseconds: math.max(starts[k]!, ends[k]!)),
      ),
  ];
}

/// New-word index → old-word index, for the longest run of words the two
/// lists share in order.
Map<int, int> _align(List<String> old, List<String> fresh) {
  final n = old.length;
  final m = fresh.length;
  final length = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var a = n - 1; a >= 0; a--) {
    for (var b = m - 1; b >= 0; b--) {
      length[a][b] = old[a] == fresh[b]
          ? length[a + 1][b + 1] + 1
          : math.max(length[a + 1][b], length[a][b + 1]);
    }
  }
  final pairs = <int, int>{};
  var a = 0;
  var b = 0;
  while (a < n && b < m) {
    if (old[a] == fresh[b]) {
      pairs[b] = a;
      a++;
      b++;
    } else if (length[a + 1][b] >= length[a][b + 1]) {
      a++;
    } else {
      b++;
    }
  }
  return pairs;
}

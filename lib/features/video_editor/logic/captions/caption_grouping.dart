import 'dart:math' as math;

import 'package:characters/characters.dart';

import 'caption_settings.dart';
import 'caption_transcript.dart';
import 'caption_word.dart';

/// A silence at least this long starts a new caption.
const double kCaptionPauseBreakSeconds = 0.6;

/// How long a caption stays after its last word, so it does not flicker off
/// between two phrases — never past the next caption's start. This also keeps
/// every caption at least 0.4s long wherever there is room for it.
const double kCaptionHoldSeconds = 0.4;

/// One caption before it becomes a text overlay.
class CaptionDraft {
  const CaptionDraft({
    required this.text,
    required this.start,
    required this.end,
    required this.words,
  });

  final String text;

  /// Timeline instants.
  final Duration start;
  final Duration end;

  /// Relative to [start].
  final List<CaptionWord> words;
}

// A sentence may end inside a quote or a bracket: `done."`, `done.)`.
final RegExp _sentenceEnd = RegExp(r'''[.!?…。！？]["'”’)\]»」』]*$''');
final RegExp _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// Groups [words] into captions of [length] and times them.
///
/// A caption breaks after sentence-ending punctuation, before a word that
/// follows a pause of [kCaptionPauseBreakSeconds], and where the next word
/// would pass the length's word or character limit. A word longer than the
/// limit stands alone rather than being split or dropped. A token with no
/// letter or digit — a dash, a stray quote — never starts a caption of its own:
/// it joins the one before.
///
/// Every caption starts no earlier than the previous one ends and has a
/// length, whatever order or overlap the provider's times arrive in, so a set
/// always fits on one lane.
///
/// [endLimitSeconds] is where the sound ends. The hold never runs past it:
/// speech that reaches the end of the video is the ordinary case, and a hold
/// beyond it would make the project — and the exported file — longer than the
/// video, with a tail of bare background. A word that itself outlasts the
/// limit is kept whole.
List<CaptionDraft> groupCaptionWords(
  List<SpacedWord> words,
  CaptionLength length, {
  double? endLimitSeconds,
}) {
  final groups = <List<SpacedWord>>[];
  var current = <SpacedWord>[];
  var chars = 0;
  var wordCount = 0;

  void close() {
    if (current.isEmpty) return;
    groups.add(current);
    current = [];
    chars = 0;
    wordCount = 0;
  }

  for (final w in words) {
    final isWord = _letterOrDigit.hasMatch(w.word.text);
    if (!isWord && current.isEmpty && groups.isNotEmpty) {
      groups.last.add(w);
      continue;
    }
    final size = w.word.text.characters.length;
    if (isWord && current.isNotEmpty) {
      final pause =
          w.word.start - current.last.word.end >= kCaptionPauseBreakSeconds;
      final tooLong = wordCount + 1 > length.maxWords ||
          chars + w.separator.characters.length + size > length.maxChars;
      if (pause || tooLong) close();
    }
    chars += (current.isEmpty ? 0 : w.separator.characters.length) + size;
    if (isWord) wordCount++;
    current.add(w);
    if (_sentenceEnd.hasMatch(w.word.text)) close();
  }
  close();

  int ms(double seconds) => (seconds * 1000).round();
  final drafts = <CaptionDraft>[];
  var floor = 0;
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i];
    final start = math.max(ms(group.first.word.start), floor);
    final lastEnd = math.max(
      group.map((x) => ms(x.word.end)).reduce(math.max),
      start,
    );
    var end = lastEnd + ms(kCaptionHoldSeconds);
    if (endLimitSeconds != null) {
      end = math.min(end, math.max(lastEnd, ms(endLimitSeconds)));
    }
    if (i + 1 < groups.length) {
      final next = ms(groups[i + 1].first.word.start);
      if (next > start) end = math.min(end, next);
    }
    // Every caption has a length, even one whose only word has none and
    // which the sound's end leaves no room to hold.
    if (end <= start) end = start + 1;

    final text = StringBuffer();
    final captionWords = <CaptionWord>[];
    for (var j = 0; j < group.length; j++) {
      if (j > 0) text.write(group[j].separator);
      final from = text.length;
      text.write(group[j].word.text);
      final wordStart = math.max(0, ms(group[j].word.start) - start);
      captionWords.add(
        CaptionWord(
          textStart: from,
          textEnd: text.length,
          start: Duration(milliseconds: wordStart),
          end: Duration(
            milliseconds: math.max(wordStart, ms(group[j].word.end) - start),
          ),
        ),
      );
    }

    drafts.add(
      CaptionDraft(
        text: text.toString(),
        start: Duration(milliseconds: start),
        end: Duration(milliseconds: end),
        words: captionWords,
      ),
    );
    floor = end;
  }
  return drafts;
}

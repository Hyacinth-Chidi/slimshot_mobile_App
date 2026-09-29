import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_retime.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';

/// Fixing a caption's words keeps the timing of the words that did not change.
void main() {
  CaptionWord w(int from, int to, int startMs, int endMs) => CaptionWord(
        textStart: from,
        textEnd: to,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
      );

  // "the quick brown fox", a word every 300ms, each 250ms long.
  const oldText = 'the quick brown fox';
  final oldWords = [
    w(0, 3, 0, 250),
    w(4, 9, 300, 550),
    w(10, 15, 600, 850),
    w(16, 19, 900, 1150),
  ];
  const span = Duration(milliseconds: 1500);

  List<CaptionWord> retime(String newText, {List<CaptionWord>? from}) =>
      retimeCaptionWords(
        oldText: oldText,
        oldWords: from ?? oldWords,
        newText: newText,
        span: span,
      );

  List<String> textsOf(String text, List<CaptionWord> words) =>
      [for (final x in words) text.substring(x.textStart, x.textEnd)];

  test('the same text keeps every word as it was', () {
    expect(retime(oldText), oldWords);
  });

  test('fixing one word leaves every other word untouched', () {
    const fixed = 'the quick brawn fox';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['the', 'quick', 'brawn', 'fox']);
    expect(words[0], oldWords[0]);
    expect(words[1], oldWords[1]);
    expect(words[3], oldWords[3]);
    // The new word takes the room between its neighbours.
    expect(words[2].start, const Duration(milliseconds: 550));
    expect(words[2].end, const Duration(milliseconds: 900));
  });

  test('a longer replacement moves the offsets after it, not the times', () {
    const fixed = 'the quickest brown fox';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['the', 'quickest', 'brown', 'fox']);
    expect((words[2].start, words[2].end), (oldWords[2].start, oldWords[2].end));
    expect((words[3].start, words[3].end), (oldWords[3].start, oldWords[3].end));
  });

  test('case and punctuation are not a different word', () {
    const fixed = 'The quick, brown fox!';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['The', 'quick,', 'brown', 'fox!']);
    for (var i = 0; i < 4; i++) {
      expect(
        (words[i].start, words[i].end),
        (oldWords[i].start, oldWords[i].end),
        reason: 'word $i',
      );
    }
  });

  test('an added word sits between its neighbours', () {
    const fixed = 'the very quick brown fox';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['the', 'very', 'quick', 'brown', 'fox']);
    expect(words[1].start, const Duration(milliseconds: 250));
    expect(words[1].end, const Duration(milliseconds: 300));
    expect(words[2], w(9, 14, 300, 550));
  });

  test('several new words share the room by their length', () {
    const fixed = 'the quick a lovely fox';
    final words = retime(fixed);
    // 'a' and 'lovely' share 550–900, one part to six.
    expect(words[2].start, const Duration(milliseconds: 550));
    expect(words[2].end, const Duration(milliseconds: 600));
    expect(words[3].start, const Duration(milliseconds: 600));
    expect(words[3].end, const Duration(milliseconds: 900));
  });

  test('a removed word takes its time with it', () {
    const fixed = 'the brown fox';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['the', 'brown', 'fox']);
    expect(
      [for (final x in words) x.start.inMilliseconds],
      [0, 600, 900],
    );
  });

  test('new words at either end reach to the caption edges', () {
    const fixed = 'and the quick brown fox jumps';
    final words = retime(fixed);
    expect(words.first.start, Duration.zero);
    expect(words.first.end, Duration.zero);
    expect(words.last.start, const Duration(milliseconds: 1150));
    expect(words.last.end, span);
  });

  test('a rewrite shares the whole caption, in order, inside it', () {
    const fixed = 'something else entirely';
    final words = retime(fixed);
    expect(textsOf(fixed, words), ['something', 'else', 'entirely']);
    expect(words.first.start, Duration.zero);
    expect(words.last.end, span);
    for (var i = 0; i < words.length; i++) {
      expect(words[i].end >= words[i].start, isTrue);
      if (i > 0) expect(words[i].start >= words[i - 1].end, isTrue);
    }
  });

  test('no text, no words; and a caption that had none gets them', () {
    expect(retime(''), isEmpty);
    expect(retime('   '), isEmpty);
    final fresh = retime('two words', from: const []);
    expect(textsOf('two words', fresh), ['two', 'words']);
    expect(fresh.first.start, Duration.zero);
    expect(fresh.last.end, span);
  });

  test('a script written without spaces is a word a character', () {
    const text = '你好。世界';
    final words = retimeCaptionWords(
      oldText: '',
      oldWords: const [],
      newText: text,
      span: span,
    );
    // Punctuation stays with the character it follows.
    expect(textsOf(text, words), ['你', '好。', '世', '界']);
  });

  test('offsets count UTF-16 units, so an emoji does not shift the next word',
      () {
    const text = 'hi 👍 there';
    final words = retimeCaptionWords(
      oldText: '',
      oldWords: const [],
      newText: text,
      span: span,
    );
    expect(textsOf(text, words), ['hi', '👍', 'there']);
  });

  test('old words whose offsets no longer fit the old text are ignored', () {
    final words = retime('the quick', from: [w(0, 3, 0, 250), w(40, 50, 300, 550)]);
    expect(textsOf('the quick', words), ['the', 'quick']);
    expect(words.first, w(0, 3, 0, 250));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';

void main() {
  TranscriptWord w(String text, double start, double end) =>
      TranscriptWord(text: text, start: start, end: end);

  group('CaptionTranscript.fromJson', () {
    test('reads the server result', () {
      final t = CaptionTranscript.fromJson({
        'provider': 'elevenlabs',
        'language': 'en',
        'durationSeconds': 6.2,
        'text': 'Welcome back.',
        'words': [
          {'text': 'Welcome', 'start': 0.18, 'end': 0.5, 'confidence': 1},
          {'text': 'back.', 'start': 0.6, 'end': 0.8, 'confidence': 0.97},
        ],
      });
      expect(t.text, 'Welcome back.');
      expect(t.language, 'en');
      expect(t.words.map((x) => (x.text, x.start, x.end)), [
        ('Welcome', 0.18, 0.5),
        ('back.', 0.6, 0.8),
      ]);
    });

    test(
        'drops words with no text or no usable time; a backwards end is pulled up',
        () {
      final t = CaptionTranscript.fromJson({
        'text': 'a b c d',
        'words': [
          {'text': 'a', 'start': 0.1, 'end': 0.2},
          {'text': '  ', 'start': 0.3, 'end': 0.4},
          {'text': 'b', 'start': 'soon', 'end': 0.5},
          {'text': 'c', 'start': -1, 'end': 0.5},
          {'text': 'd', 'start': 0.9, 'end': 0.6},
          'junk',
        ],
      });
      expect(t.words.map((x) => x.text), ['a', 'd']);
      expect(t.words.last.end, 0.9);
    });

    test('an empty result is an empty transcript', () {
      final t = CaptionTranscript.fromJson(const {});
      expect(t.text, '');
      expect(t.words, isEmpty);
      expect(t.language, isNull);
    });
  });

  group('rebuildTranscriptSpacing', () {
    List<String> separators(String text, List<String> words) =>
        rebuildTranscriptSpacing(text, [for (final x in words) w(x, 0, 0)])
            .map((s) => s.separator)
            .toList();

    test('spaced languages keep one space between words', () {
      expect(
        separators(
          'Welcome back to the channel.',
          ['Welcome', 'back', 'to', 'the', 'channel.'],
        ),
        ['', ' ', ' ', ' ', ' '],
      );
    });

    test('a script written without spaces gets none', () {
      expect(separators('你好世界', ['你', '好', '世', '界']), ['', '', '', '']);
    });

    test('mixed scripts follow the transcript', () {
      expect(separators('Hello 世界', ['Hello', '世', '界']), ['', ' ', '']);
    });

    test('a run of whitespace or a line break is one space', () {
      expect(separators('one  \n two', ['one', 'two']), ['', ' ']);
    });

    test('a repeated word is found in order', () {
      expect(separators('the the end', ['the', 'the', 'end']), ['', ' ', ' ']);
    });

    test('a word the transcript lacks falls back to one space', () {
      expect(
        separators('alpha gamma', ['alpha', 'beta', 'gamma']),
        ['', ' ', ' '],
      );
    });

    test('the first word never carries a separator', () {
      expect(separators('  lead', ['lead']), ['']);
    });
  });
}

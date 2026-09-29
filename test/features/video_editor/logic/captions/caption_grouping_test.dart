import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_transcript.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';

void main() {
  SpacedWord sw(String text, double start, double end, {String sep = ' '}) =>
      SpacedWord(sep, TranscriptWord(text: text, start: start, end: end));

  /// Words 0.3s apart, 0.25s long: no pauses, no punctuation.
  List<SpacedWord> steady(List<String> texts) => [
        for (var i = 0; i < texts.length; i++)
          sw(texts[i], i * 0.3, i * 0.3 + 0.25, sep: i == 0 ? '' : ' '),
      ];

  List<String> texts(List<CaptionDraft> d) => d.map((c) => c.text).toList();

  group('where a caption breaks', () {
    test('a phrase holds at most three words', () {
      expect(
        texts(groupCaptionWords(
          steady(['one', 'two', 'three', 'four', 'five', 'six', 'seven']),
          CaptionLength.phrase,
        )),
        ['one two three', 'four five six', 'seven'],
      );
    });

    test('a phrase holds at most twenty characters', () {
      expect(
        texts(groupCaptionWords(
          steady(['extraordinary', 'people', 'wonderful']),
          CaptionLength.phrase,
        )),
        ['extraordinary people', 'wonderful'],
      );
    });

    test('Word is one word per caption', () {
      expect(
        texts(groupCaptionWords(steady(['a', 'b', 'c']), CaptionLength.word)),
        ['a', 'b', 'c'],
      );
    });

    test('a line holds at most seven words', () {
      expect(
        texts(groupCaptionWords(
          steady(['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i']),
          CaptionLength.line,
        )),
        ['a b c d e f g', 'h i'],
      );
    });

    test('a sentence ends a caption whatever the length', () {
      expect(
        texts(groupCaptionWords(
          steady(['Hi.', 'there', 'friend']),
          CaptionLength.line,
        )),
        ['Hi.', 'there friend'],
      );
      expect(
        texts(groupCaptionWords([
          sw('你', 0, 0.2, sep: ''),
          sw('好。', 0.3, 0.5, sep: ''),
          sw('世', 0.6, 0.8, sep: ''),
          sw('界', 0.9, 1.1, sep: ''),
        ], CaptionLength.line)),
        ['你好。', '世界'],
      );
    });

    test('a sentence that ends inside a quote or a bracket still ends', () {
      for (final last in ['done."', 'done.”', "done.'", 'done.)', 'done?」']) {
        expect(
          texts(groupCaptionWords(
            steady(['He', last, 'Then', 'more']),
            CaptionLength.line,
          )),
          ['He $last', 'Then more'],
          reason: last,
        );
      }
    });

    test('a pause of 0.6s ends a caption; a shorter one does not', () {
      expect(
        texts(groupCaptionWords([
          sw('one', 0, 0.2, sep: ''),
          sw('two', 0.8, 1.0),
          sw('three', 1.59, 1.8),
        ], CaptionLength.line)),
        ['one', 'two three'],
      );
    });

    test('a word longer than the limit is a caption of its own, never dropped',
        () {
      expect(
        texts(groupCaptionWords(
          steady(['see', 'https://slimshot.example/very/long/path', 'now']),
          CaptionLength.phrase,
        )),
        ['see', 'https://slimshot.example/very/long/path', 'now'],
      );
    });

    test('a punctuation-only token joins the caption before it', () {
      expect(
        texts(groupCaptionWords([
          sw('Wait', 0, 0.3, sep: ''),
          sw('—', 0.3, 0.35),
          sw('what', 1.2, 1.5),
        ], CaptionLength.phrase)),
        ['Wait —', 'what'],
      );
    });

    test('…even straight after a sentence has ended', () {
      expect(
        texts(groupCaptionWords([
          sw('Stop.', 0, 0.3, sep: ''),
          sw('"', 0.3, 0.3, sep: ''),
          sw('Go', 1.0, 1.2),
        ], CaptionLength.line)),
        ['Stop."', 'Go'],
      );
    });

    test('no words, no captions', () {
      expect(groupCaptionWords(const [], CaptionLength.phrase), isEmpty);
    });
  });

  group('when a caption shows', () {
    test('it shows a moment before its first word is spoken', () {
      // Text that arrives with the word reads as late: the eye needs the
      // caption there when the sound starts, and a preview frame is not free.
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 3.0, 3.2)],
        CaptionLength.line,
      );
      expect(kCaptionLeadSeconds, 0.06);
      expect(d[0].start, const Duration(milliseconds: 940));
      expect(d[1].start, const Duration(milliseconds: 2940));
    });

    test('a caption at the very start cannot begin before zero', () {
      final d = groupCaptionWords(
        [sw('Hi.', 0.02, 0.3, sep: '')],
        CaptionLength.line,
      );
      expect(d.single.start, Duration.zero);
      expect(d.single.words.single.start, const Duration(milliseconds: 20));
    });

    test('it holds 0.4s past its last word when nothing follows soon', () {
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 3.0, 3.2)],
        CaptionLength.line,
      );
      expect(d[0].end, const Duration(milliseconds: 1700));
      expect(d[1].end, const Duration(milliseconds: 3600));
    });

    test('the hold stops at the next caption', () {
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 1.5, 1.7)],
        CaptionLength.line,
      );
      // …which itself begins a moment before its word.
      expect(d[0].end, const Duration(milliseconds: 1440));
      expect(d[1].start, const Duration(milliseconds: 1440));
    });

    test('the last hold stops where the sound ends', () {
      // Speech that runs to the end of the video is the ordinary case. A hold
      // past it would make the project — and the exported file — longer than
      // the video, with a tail of bare background nobody asked for.
      final d = groupCaptionWords(
        [sw('Hi.', 1.0, 1.3, sep: ''), sw('Bye.', 3.0, 3.2)],
        CaptionLength.line,
        endLimitSeconds: 3.3,
      );
      expect(d[0].end, const Duration(milliseconds: 1700));
      expect(d[1].end, const Duration(milliseconds: 3300));
    });

    test('a word that itself outlasts the sound is kept whole', () {
      final d = groupCaptionWords(
        [sw('Bye.', 3.0, 3.4, sep: '')],
        CaptionLength.line,
        endLimitSeconds: 3.2,
      );
      expect(d.single.end, const Duration(milliseconds: 3400));
    });

    test('a caption has a length even where the sound ends on its word', () {
      final d = groupCaptionWords(
        [sw('Bye.', 3.0, 3.0, sep: '')],
        CaptionLength.line,
        endLimitSeconds: 3.0,
      );
      expect(d.single.end > d.single.start, isTrue);
    });

    test('provider times that overlap or run backwards never overlap captions',
        () {
      final d = groupCaptionWords([
        sw('One.', 1.0, 1.6, sep: ''),
        sw('Two.', 1.2, 1.4),
        sw('Three.', 0.9, 1.1),
      ], CaptionLength.line);
      expect(d, hasLength(3));
      for (var i = 0; i < d.length; i++) {
        expect(d[i].end > d[i].start, isTrue, reason: 'caption $i has length');
        if (i > 0) {
          expect(
            d[i].start >= d[i - 1].end,
            isTrue,
            reason: 'caption $i starts after caption ${i - 1} ends',
          );
        }
      }
    });
  });

  group('what a caption holds', () {
    test('UTF-16 offsets, and word times that stay on the spoken word', () {
      // The caption starts early; its words do not. A word's time is measured
      // from the caption's start, so the lead is added back to each.
      final d = groupCaptionWords(
        [sw('Hello,', 2.0, 2.4, sep: ''), sw('world', 2.5, 2.9)],
        CaptionLength.phrase,
      );
      expect(d.single.text, 'Hello, world');
      expect(d.single.words, const [
        CaptionWord(
          textStart: 0,
          textEnd: 6,
          start: Duration(milliseconds: 60),
          end: Duration(milliseconds: 460),
        ),
        CaptionWord(
          textStart: 7,
          textEnd: 12,
          start: Duration(milliseconds: 560),
          end: Duration(milliseconds: 960),
        ),
      ]);
    });

    test('a script without spaces joins with nothing', () {
      final d = groupCaptionWords(
        [sw('你', 0, 0.2, sep: ''), sw('好', 0.3, 0.5, sep: '')],
        CaptionLength.phrase,
      );
      expect(d.single.text, '你好');
      expect(
        d.single.words.map((w) => (w.textStart, w.textEnd)),
        [(0, 1), (1, 2)],
      );
    });
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_edits.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_grouping.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

void main() {
  CaptionWord w(int from, int to, int startMs, int endMs) => CaptionWord(
        textStart: from,
        textEnd: to,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
      );

  // Shown from 2.0s to 4.0s; its first word is spoken 60ms in.
  TextOverlayModel caption() => TextOverlayModel(
        id: 'c',
        text: 'the quick brown fox',
        startTime: const Duration(seconds: 2),
        endTime: const Duration(seconds: 4),
        captionSetId: 's',
        captionWords: [
          w(0, 3, 60, 300),
          w(4, 9, 400, 700),
          w(10, 15, 800, 1100),
          w(16, 19, 1200, 1500),
        ],
      );

  List<String> wordsOf(TextOverlayModel c) => [
        for (final x in c.captionWords!) c.text.substring(x.textStart, x.textEnd),
      ];

  /// A word's instant on the timeline, in ms.
  List<int> instants(TextOverlayModel c) => [
        for (final x in c.captionWords!)
          c.startTime.inMilliseconds + x.start.inMilliseconds,
      ];

  group('splitCaption', () {
    test('cuts at the word boundary nearest the cursor', () {
      // The cursor sits inside "brown"; its start is the nearest boundary.
      final cut = splitCaption(caption(), 11, rightId: 'r')!;
      expect(cut.left.text, 'the quick');
      expect(cut.right.text, 'brown fox');
      expect(cut.left.id, 'c');
      expect(cut.right.id, 'r');
      expect(wordsOf(cut.left), ['the', 'quick']);
      expect(wordsOf(cut.right), ['brown', 'fox']);
    });

    test('every word stays on the instant it was spoken', () {
      final whole = caption();
      final cut = splitCaption(whole, 11, rightId: 'r')!;
      expect([...instants(cut.left), ...instants(cut.right)], instants(whole));
    });

    test('the halves abut, and the right one leads its first word', () {
      final cut = splitCaption(caption(), 11, rightId: 'r')!;
      expect(cut.left.startTime, const Duration(seconds: 2));
      expect(cut.left.endTime, cut.right.startTime);
      expect(cut.right.endTime, const Duration(seconds: 4));
      // "brown" is spoken at 2.8s.
      expect(
        cut.right.startTime,
        Duration(milliseconds: 2800 - (kCaptionLeadSeconds * 1000).round()),
      );
    });

    test('both halves stay in the set, on the lane, in the look', () {
      final styled = caption().copyWith(
        laneIndex: 3,
        fontFamily: 'Montserrat Bold',
        scale: 1.4,
      );
      final cut = splitCaption(styled, 11, rightId: 'r')!;
      for (final half in [cut.left, cut.right]) {
        expect(half.captionSetId, 's');
        expect(half.laneIndex, 3);
        expect(half.fontFamily, 'Montserrat Bold');
        expect(half.scale, 1.4);
      }
    });

    test('at the very start or the very end there is nothing to split', () {
      expect(splitCaption(caption(), 0, rightId: 'r'), isNull);
      expect(splitCaption(caption(), 19, rightId: 'r'), isNull);
      expect(splitCaption(caption(), 99, rightId: 'r'), isNull);
    });

    test('a caption of one word cannot be split', () {
      final one = caption().copyWith(text: 'fox', captionWords: [w(0, 3, 60, 300)]);
      expect(splitCaption(one, 1, rightId: 'r'), isNull);
    });
  });

  group('mergeCaptions', () {
    TextOverlayModel next() => TextOverlayModel(
          id: 'n',
          text: 'jumps over',
          startTime: const Duration(milliseconds: 4200),
          endTime: const Duration(milliseconds: 5200),
          captionSetId: 's',
          captionWords: [w(0, 5, 60, 400), w(6, 10, 500, 800)],
        );

    test('joins the words, and spans both captions', () {
      final merged = mergeCaptions(caption(), next());
      expect(merged.id, 'c');
      expect(merged.text, 'the quick brown fox jumps over');
      expect(merged.startTime, const Duration(seconds: 2));
      expect(merged.endTime, const Duration(milliseconds: 5200));
      expect(
        wordsOf(merged),
        ['the', 'quick', 'brown', 'fox', 'jumps', 'over'],
      );
    });

    test('every word stays on the instant it was spoken', () {
      final merged = mergeCaptions(caption(), next());
      expect(instants(merged), [...instants(caption()), ...instants(next())]);
    });

    test('a script without spaces joins with nothing', () {
      TextOverlayModel zh(String id, String text, int startMs) =>
          TextOverlayModel(
            id: id,
            text: text,
            startTime: Duration(milliseconds: startMs),
            endTime: Duration(milliseconds: startMs + 500),
            captionSetId: 's',
            captionWords: [w(0, 1, 0, 200), w(1, 2, 250, 450)],
          );
      final merged = mergeCaptions(zh('a', '你好', 0), zh('b', '世界', 600));
      expect(merged.text, '你好世界');
      expect(wordsOf(merged), ['你', '好', '世', '界']);
    });

    test('a split, merged back, is the caption it was', () {
      final whole = caption();
      final cut = splitCaption(whole, 11, rightId: 'r')!;
      final back = mergeCaptions(cut.left, cut.right);
      expect(back.text, whole.text);
      expect(back.startTime, whole.startTime);
      expect(back.endTime, whole.endTime);
      expect(back.captionWords, whole.captionWords);
    });
  });

  group('shiftCaptionStart', () {
    test('a later start keeps each word on its instant', () {
      final trimmed = shiftCaptionStart(
        caption(),
        const Duration(milliseconds: 2300),
      );
      expect(trimmed.startTime, const Duration(milliseconds: 2300));
      expect(trimmed.endTime, const Duration(seconds: 4));
      expect(instants(trimmed).sublist(1), instants(caption()).sublist(1));
    });

    test('a word the trim passed starts with the caption, never before it',
        () {
      final trimmed = shiftCaptionStart(
        caption(),
        const Duration(milliseconds: 2300),
      );
      final first = trimmed.captionWords!.first;
      expect(first.start, Duration.zero);
      expect(first.end, Duration.zero);
    });

    test('an earlier start keeps each word on its instant too', () {
      final grown = shiftCaptionStart(
        caption(),
        const Duration(milliseconds: 1500),
      );
      expect(instants(grown), instants(caption()));
    });

    test('ordinary text is only moved', () {
      final text = TextOverlayModel(id: 't', text: 'hi');
      final moved = shiftCaptionStart(text, const Duration(seconds: 1));
      expect(moved.startTime, const Duration(seconds: 1));
      expect(moved.captionWords, isNull);
    });
  });

  group('re-cutting a set', () {
    List<TextOverlayModel> set() => [
          caption(),
          TextOverlayModel(
            id: 'n',
            text: 'jumps over',
            startTime: const Duration(milliseconds: 4200),
            endTime: const Duration(milliseconds: 5200),
            captionSetId: 's',
            captionWords: [w(0, 5, 60, 400), w(6, 10, 500, 800)],
          ),
        ];

    test('the words come back in order with their instants and spacing', () {
      final words = captionSpacedWords(set().reversed.toList());
      expect(
        [for (final x in words) x.word.text],
        ['the', 'quick', 'brown', 'fox', 'jumps', 'over'],
      );
      expect([for (final x in words) x.separator], ['', ' ', ' ', ' ', ' ', ' ']);
      expect(words.first.word.start, closeTo(2.06, 1e-9));
      expect(words.last.word.end, closeTo(5.0, 1e-9));
    });

    test('one word a caption when re-cut to Word, fixes and all', () {
      final fixed = set()
        ..[0] = caption().copyWith(
          text: 'the quick brawn fox',
        );
      final drafts = recutCaptionDrafts(fixed, CaptionLength.word);
      expect(
        [for (final d in drafts) d.text],
        ['the', 'quick', 'brawn', 'fox', 'jumps', 'over'],
      );
      // "quick" is spoken at 2.4s and shows a moment before.
      expect(
        drafts[1].start,
        Duration(milliseconds: 2400 - (kCaptionLeadSeconds * 1000).round()),
      );
    });

    test('nothing past the end of the set', () {
      final drafts = recutCaptionDrafts(set(), CaptionLength.line);
      expect(drafts.last.end <= const Duration(milliseconds: 5200), isTrue);
    });
  });

  group('followCaptionMotion', () {
    const before = OverlayMotion(
      position: Offset(0, 100),
      scale: 1,
      rotation: 0,
      opacity: 1,
    );
    const after = OverlayMotion(
      position: Offset(10, 80),
      scale: 1.5,
      rotation: 0.2,
      opacity: 0.5,
    );

    test('takes the same change, from wherever it was', () {
      const other = OverlayMotion(
        position: Offset(5, 120),
        scale: 2,
        rotation: 0.1,
        opacity: 1,
      );
      final moved = followCaptionMotion(other, before: before, after: after);
      expect(moved.position, const Offset(15, 100));
      expect(moved.scale, 3.0);
      expect(moved.rotation, closeTo(0.3, 1e-9));
      expect(moved.opacity, 0.5);
    });

    test('moves a keyframed caption along its whole path', () {
      final other = OverlayMotion.fromParams({
        ...const OverlayMotion(
          position: Offset(0, 0),
          scale: 1,
          rotation: 0,
          opacity: 1,
        ).params,
        OverlayProperty.x: AnimatableDouble.sorted(
          baseValue: 0,
          keyframes: const [
            Keyframe(progress: 0, value: 0),
            Keyframe(progress: 1, value: 50),
          ],
        ),
      });
      final moved = followCaptionMotion(other, before: before, after: after);
      expect(
        [for (final k in moved.keyframes.of(OverlayProperty.x)) k.value],
        [10, 60],
      );
    });

    test('no change is no change', () {
      const other = OverlayMotion(
        position: Offset(5, 120),
        scale: 2,
        rotation: 0.1,
        opacity: 0.8,
      );
      final same = followCaptionMotion(other, before: before, after: before);
      expect(same.position, other.position);
      expect(same.scale, other.scale);
      expect(same.rotation, other.rotation);
      expect(same.opacity, other.opacity);
    });

    test('stays inside the sizes and opacity a text may have', () {
      const big = OverlayMotion(
        position: Offset.zero,
        scale: 4.5,
        rotation: 0,
        opacity: 0.2,
      );
      final moved = followCaptionMotion(big, before: before, after: after);
      expect(moved.scale, 5.0);
      expect(moved.opacity, 0.0);
    });
  });
}

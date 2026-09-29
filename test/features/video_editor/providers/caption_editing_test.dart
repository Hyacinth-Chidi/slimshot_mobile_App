import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_settings.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Editing a caption set through the notifier: every way in keeps the words
/// on their instants, and one action is one undo step.
void main() {
  CaptionWord w(int from, int to, int startMs, int endMs) => CaptionWord(
        textStart: from,
        textEnd: to,
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
      );

  TextOverlayModel caption(String id, String text, int startMs, int endMs) {
    final words = <CaptionWord>[];
    var at = 0;
    var t = 60;
    for (final word in text.split(' ')) {
      words.add(w(at, at + word.length, t, t + 200));
      at += word.length + 1;
      t += 300;
    }
    return TextOverlayModel(
      id: id,
      text: text,
      startTime: Duration(milliseconds: startMs),
      endTime: Duration(milliseconds: endMs),
      laneIndex: 1,
      position: const Offset(0, 100),
      captionSetId: 'set',
      captionWords: words,
    );
  }

  final plain = TextOverlayModel(
    id: 'title',
    text: 'Title',
    startTime: Duration.zero,
    endTime: const Duration(seconds: 9),
    position: const Offset(3, 4),
  );

  VideoEditorNotifier editor({String? selected, double playhead = 1.5}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          textOverlays: [
            plain,
            caption('a', 'the quick brown', 1000, 2000),
            caption('b', 'fox jumps', 2000, 3000),
            caption('c', 'over it', 3000, 4000),
          ],
          captionSettings: const CaptionSettings(setId: 'set'),
          selectedTextId: selected,
          currentPlaybackPosition: playhead,
          currentMenuId: selected == null ? 'root' : 'text_overlay',
        );

  TextOverlayModel textOf(VideoEditorNotifier n, String id) =>
      n.state.textOverlays.firstWhere((t) => t.id == id);

  List<TextOverlayModel> captionsOf(VideoEditorNotifier n) =>
      n.state.textOverlays.where((t) => t.isCaption).toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));

  List<int> instants(TextOverlayModel c) => [
        for (final x in c.captionWords!)
          c.startTime.inMilliseconds + x.start.inMilliseconds,
      ];

  group('fixing words', () {
    test('any text change to a caption keeps the other words where they were',
        () {
      final n = editor();
      final before = textOf(n, 'a').captionWords!;
      n.updateTextOverlay('a', (o) => o.copyWith(text: 'the quack brown'));
      final after = textOf(n, 'a').captionWords!;
      expect(after[0], before[0]);
      expect(after[2], before[2]);
      expect(
        textOf(n, 'a').text.substring(after[1].textStart, after[1].textEnd),
        'quack',
      );
    });

    test('the live write retimes too, and takes no undo step', () {
      final n = editor();
      n.updateTextOverlayLive('a', (o) => o.copyWith(text: 'the quick brown cat'));
      expect(textOf(n, 'a').captionWords, hasLength(4));
      expect(n.state.canUndo, isFalse);
    });

    test('ordinary text gains no words', () {
      final n = editor();
      n.updateTextOverlay('title', (o) => o.copyWith(text: 'New title'));
      expect(textOf(n, 'title').captionWords, isNull);
    });

    test('a change that is not to the text leaves the words alone', () {
      final n = editor();
      final before = textOf(n, 'a').captionWords;
      n.updateTextOverlay('a', (o) => o.copyWith(fontFamily: 'Inter'));
      expect(identical(textOf(n, 'a').captionWords, before), isTrue);
    });
  });

  group('copying a caption', () {
    test('the copy is ordinary text, not a second member of the set', () {
      // A copy that stayed in the set fed its words into a re-cut a second
      // time ("hello world hello world") and was laid on its original's lane.
      final n = editor(selected: 'a');
      n.duplicateTextOverlay('a');
      final copy = textOf(n, n.state.selectedTextId!);
      expect(copy.text, 'the quick brown');
      expect(copy.isCaption, isFalse);
      expect(copy.captionWords, isNull);
      expect(captionsOf(n), hasLength(3));

      n.recutCaptions(CaptionLength.word);
      expect(
        captionsOf(n).map((c) => c.text),
        ['the', 'quick', 'brown', 'fox', 'jumps', 'over', 'it'],
      );
    });
  });

  group('trimming on the timeline', () {
    test('a drag past a word and back leaves the word where it was', () {
      // Each frame of the drag used to trim the frame before it, so a word
      // the edge had passed was pinned to the edge and stayed there.
      final n = editor();
      final before = textOf(n, 'c').captionWords;
      n.beginTimelineGesture();
      n.trimLaneItem('c', start: 3.5, end: 4.0);
      n.trimLaneItem('c', start: 3.2, end: 4.0);
      n.trimLaneItem('c', start: 3.0, end: 4.0);
      n.endTimelineGesture();
      expect(textOf(n, 'c').startTime, const Duration(seconds: 3));
      expect(textOf(n, 'c').captionWords, before);
    });

    test('a later start keeps the words on their instants', () {
      final n = editor();
      final before = instants(textOf(n, 'c'));
      n.trimLaneItem('c', start: 3.2, end: 4.0);
      final trimmed = textOf(n, 'c');
      expect(trimmed.startTime, const Duration(milliseconds: 3200));
      // "over" (3.06s) is behind the new start; "it" (3.36s) is not.
      expect(instants(trimmed).last, before.last);
    });

    test('moving only the end changes no word', () {
      final n = editor();
      final before = textOf(n, 'c').captionWords;
      n.trimLaneItem('c', start: 3.0, end: 3.8);
      expect(textOf(n, 'c').captionWords, before);
    });
  });

  group('the set moves as one', () {
    test('dragging one caption moves every caption, and nothing else', () {
      final n = editor(selected: 'a');
      n.beginOverlayEdit();
      n.setOverlayMotionLive(id: 'a', position: const Offset(10, 60));
      for (final c in captionsOf(n)) {
        expect(c.position, const Offset(10, 60), reason: c.id);
      }
      expect(textOf(n, 'title').position, const Offset(3, 4));
    });

    test('pinching one resizes and turns them all', () {
      final n = editor(selected: 'a');
      n.beginOverlayEdit();
      n.setOverlayMotionLive(id: 'a', scale: 1.5, rotation: 0.25);
      for (final c in captionsOf(n)) {
        expect(c.scale, 1.5, reason: c.id);
        expect(c.rotation, 0.25, reason: c.id);
      }
      expect(textOf(n, 'title').scale, 1.0);
    });

    test('one Undo puts the whole set back', () {
      final n = editor(selected: 'a');
      n.beginOverlayEdit();
      n.setOverlayMotionLive(id: 'a', position: const Offset(10, 60));
      n.setOverlayMotionLive(id: 'a', position: const Offset(20, 40));
      n.undo();
      for (final c in captionsOf(n)) {
        expect(c.position, const Offset(0, 100), reason: c.id);
      }
      expect(n.state.canUndo, isFalse);
    });

    test('the box width is the set\'s too', () {
      final n = editor(selected: 'a');
      n.updateTextOverlayLive('a', (o) => o.copyWith(boxWidth: 210));
      for (final c in captionsOf(n)) {
        expect(c.boxWidth, 210, reason: c.id);
      }
      expect(textOf(n, 'title').boxWidth, isNull);
    });

    test('✕ on a tool that changed the set puts the whole set back', () {
      final n = editor(selected: 'a');
      n.openRevertibleTool('opacity');
      n.setOverlayOpacity(0.3);
      for (final c in captionsOf(n)) {
        expect(c.opacity, closeTo(0.3, 1e-9), reason: c.id);
      }
      n.discardActiveTool();
      for (final c in captionsOf(n)) {
        expect(c.opacity, 1.0, reason: c.id);
      }
      expect(n.state.canUndo, isFalse);
    });

    test('ordinary text still moves alone', () {
      final n = editor(selected: 'title');
      n.beginOverlayEdit();
      n.setOverlayMotionLive(id: 'title', position: const Offset(50, 50));
      expect(textOf(n, 'title').position, const Offset(50, 50));
      for (final c in captionsOf(n)) {
        expect(c.position, const Offset(0, 100), reason: c.id);
      }
    });
  });

  group('splitting', () {
    test('one caption becomes two, as one undo step', () {
      final n = editor();
      n.splitCaptionAt('a', 10);
      expect(
        captionsOf(n).map((c) => c.text),
        ['the quick', 'brown', 'fox jumps', 'over it'],
      );
      expect(captionsOf(n).every((c) => c.laneIndex == 1), isTrue);
      n.undo();
      expect(captionsOf(n).map((c) => c.text).first, 'the quick brown');
      expect(n.state.canUndo, isFalse);
    });

    test('at either end of the text nothing happens, and nothing to undo', () {
      final n = editor();
      n.splitCaptionAt('a', 0);
      n.splitCaptionAt('a', 15);
      n.splitCaptionAt('title', 2);
      n.splitCaptionAt('nobody', 2);
      expect(captionsOf(n), hasLength(3));
      expect(n.state.canUndo, isFalse);
    });
  });

  group('merging', () {
    test('a caption takes the next one in, as one undo step', () {
      final n = editor(selected: 'b');
      n.mergeCaptionWithNext('a');
      expect(
        captionsOf(n).map((c) => c.text),
        ['the quick brown fox jumps', 'over it'],
      );
      expect(captionsOf(n).first.endTime, const Duration(seconds: 3));
      // The caption that was selected is gone; the one it joined is selected.
      expect(n.state.selectedTextId, 'a');
      n.undo();
      expect(captionsOf(n), hasLength(3));
    });

    test('the last caption has nothing to take in', () {
      final n = editor();
      n.mergeCaptionWithNext('c');
      n.mergeCaptionWithNext('title');
      expect(captionsOf(n), hasLength(3));
      expect(n.state.canUndo, isFalse);
    });
  });

  group('deleting them all', () {
    test('removes the set and its settings, keeps plain text, one undo step',
        () {
      final n = editor(selected: 'b');
      n.deleteAllCaptions();
      expect(n.state.textOverlays.map((t) => t.id), ['title']);
      expect(n.state.captionSettings, isNull);
      expect(n.state.selectedTextId, isNull);
      expect(n.state.currentMenuId, 'root');
      n.undo();
      expect(captionsOf(n), hasLength(3));
      expect(n.state.captionSettings, isNotNull);
    });

    test('with no captions there is nothing to undo', () {
      final n = VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(textOverlays: [plain]);
      n.deleteAllCaptions();
      expect(n.state.canUndo, isFalse);
    });
  });

  group('re-cutting', () {
    test('the set is cut again to the new length, fixes and all', () {
      final n = editor(selected: 'a');
      n.updateTextOverlayLive('a', (o) => o.copyWith(text: 'the quack brown'));
      n.recutCaptions(CaptionLength.word);
      expect(
        captionsOf(n).map((c) => c.text),
        ['the', 'quack', 'brown', 'fox', 'jumps', 'over', 'it'],
      );
      expect(n.state.captionSettings?.length, CaptionLength.word);
      expect(textOf(n, 'title').text, 'Title');
    });

    test('keeps the look, the place, the lane and the set', () {
      final n = editor();
      n.updateTextOverlayLive(
        'a',
        (o) => o.copyWith(fontFamily: 'Montserrat Bold', scale: 1.3),
      );
      n.recutCaptions(CaptionLength.line);
      for (final c in captionsOf(n)) {
        expect(c.fontFamily, 'Montserrat Bold');
        expect(c.scale, 1.3);
        expect(c.position, const Offset(0, 100));
        expect(c.laneIndex, 1);
        expect(c.captionSetId, 'set');
      }
      expect(captionsOf(n).map((c) => c.id).toSet(), hasLength(captionsOf(n).length));
    });

    test('to the length it already has changes nothing', () {
      // It would take an undo step, issue new ids and throw away every
      // split and merge made by hand, to arrive where it started.
      final n = editor();
      n.splitCaptionAt('a', 10);
      n.undo();
      n.splitCaptionAt('a', 10);
      final before = n.state.textOverlays;
      // The set was made at Phrase, the default.
      n.recutCaptions(CaptionLength.phrase);
      expect(identical(n.state.textOverlays, before), isTrue);
      n.undo();
      expect(captionsOf(n), hasLength(3), reason: 'the one step was the split');
      expect(n.state.canUndo, isFalse);
    });

    test('is one undo step, and leaves no caption selected', () {
      final n = editor(selected: 'a');
      n.recutCaptions(CaptionLength.word);
      expect(n.state.selectedTextId, isNull);
      expect(n.state.currentMenuId, 'root');
      n.undo();
      expect(captionsOf(n).map((c) => c.id), ['a', 'b', 'c']);
      expect(n.state.canUndo, isFalse);
    });
  });

  group('emptied captions', () {
    test('are removed without an undo step of their own', () {
      final n = editor();
      n.updateTextOverlayLive('b', (o) => o.copyWith(text: '  '));
      n.removeEmptyCaptions();
      expect(captionsOf(n).map((c) => c.id), ['a', 'c']);
      expect(n.state.canUndo, isFalse);
      expect(textOf(n, 'title').text, 'Title');
    });
  });
}

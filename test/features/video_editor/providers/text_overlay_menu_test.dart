import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A selected text has a menu of its own.
///
/// It used not to: `selectTextOverlay` sent the editor to the **root** menu,
/// so a selected text showed the tools for making a project — Crop, Filters,
/// Background — and nothing for the text itself. Image overlays, video
/// overlays, clips and audio each had a menu; text was the odd one out, and
/// its whole editor was reachable only by tapping the already-selected text.
///
/// The menu follows the selection through every door a text can be selected
/// by — select, add, duplicate, split — and leaves by every door it can stop
/// being selected by, including the canvas frame's ✕, which deletes without
/// deselecting.
void main() {
  TextOverlayModel caption({
    String id = 't1',
    int startSeconds = 2,
    int endSeconds = 6,
  }) =>
      TextOverlayModel(
        id: id,
        text: 'Hello',
        startTime: Duration(seconds: startSeconds),
        endTime: Duration(seconds: endSeconds),
        inAnimation: 'fade_in',
        outAnimation: 'fade_out',
        loopAnimation: 'wave_loop',
        laneIndex: 1,
      );

  VideoEditorNotifier notifierWith({
    List<TextOverlayModel> texts = const [],
    List<ImageOverlayModel> images = const [],
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10)],
        textOverlays: texts,
        imageOverlays: images,
      );
  }

  group('the text menu follows the selection', () {
    test('selecting a text opens its menu', () {
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');

      expect(n.state.selectedTextId, 't1');
      expect(n.state.currentMenuId, 'text_overlay');
    });

    test('deselecting returns to the root menu', () {
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');
      n.selectTextOverlay(null);

      expect(n.state.selectedTextId, isNull);
      expect(n.state.currentMenuId, 'root');
    });

    test('adding a text opens its menu, as the only selection', () {
      // The Text tool and the emoji picker both arrive here. An image selected
      // beforehand must not survive: two selections would leave the delete
      // handler — which checks text first — acting on a thing the menu is
      // not about.
      final n = notifierWith(
        images: [ImageOverlayModel(id: 'i1', imagePath: '/x.png')],
      );
      n.selectImageOverlay('i1');
      n.addTextOverlay(caption());

      expect(n.state.selectedTextId, 't1');
      expect(n.state.selectedImageId, isNull);
      expect(n.state.currentMenuId, 'text_overlay');
    });

    test('deleting the selected text alone returns to the root menu', () {
      // The canvas frame's ✕ calls `deleteTextOverlay` and nothing else. If
      // only deselecting left the menu, this path would strand the text menu
      // on screen with nothing selected — every tool a silent no-op.
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');
      n.deleteTextOverlay('t1');

      expect(n.state.selectedTextId, isNull);
      expect(n.state.currentMenuId, 'root');
    });

    test('deleting a different text leaves the menu alone', () {
      final n = notifierWith(texts: [caption(), caption(id: 't2')]);
      n.selectTextOverlay('t1');
      n.deleteTextOverlay('t2');

      expect(n.state.selectedTextId, 't1');
      expect(n.state.currentMenuId, 'text_overlay');
    });

    test('duplicating keeps the text menu, on the copy', () {
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');
      n.duplicateTextOverlay('t1');

      expect(n.state.selectedTextId, isNot('t1'));
      expect(n.state.currentMenuId, 'text_overlay');
    });
  });

  group('splitting a text at the playhead', () {
    VideoEditorNotifier selected() {
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');
      return n;
    }

    test('cuts it into two abutting halves with the same content', () {
      final n = selected();
      n.splitTextOverlay(4.0);

      final texts = n.state.textOverlays;
      expect(texts, hasLength(2));
      final left = texts.firstWhere((t) => t.id == 't1');
      final right = texts.firstWhere((t) => t.id != 't1');

      expect(left.startTime, const Duration(seconds: 2));
      expect(left.endTime, const Duration(seconds: 4));
      expect(right.startTime, const Duration(seconds: 4));
      expect(right.endTime, const Duration(seconds: 6));
      // Same words, same place, same lane — the right half continues the
      // text rather than starting a new one somewhere else.
      expect(right.text, left.text);
      expect(right.position, left.position);
      expect(right.laneIndex, left.laneIndex);
    });

    test('the entrance stays on the left half and the exit on the right', () {
      // Copied verbatim, each half would carry both: the text would play its
      // exit before the cut and its entrance again after it — a fade out and
      // back in at a seam the user meant to be invisible.
      final n = selected();
      n.splitTextOverlay(4.0);

      final left = n.state.textOverlays.firstWhere((t) => t.id == 't1');
      final right = n.state.textOverlays.firstWhere((t) => t.id != 't1');

      expect(left.inAnimation, 'fade_in');
      expect(left.outAnimation, 'none');
      expect(right.inAnimation, 'none');
      expect(right.outAnimation, 'fade_out');
      // A loop runs under the whole span, so both halves keep it.
      expect(left.loopAnimation, 'wave_loop');
      expect(right.loopAnimation, 'wave_loop');
    });

    test('selects the right half and stays on the text menu', () {
      final n = selected();
      n.splitTextOverlay(4.0);

      final right = n.state.textOverlays.firstWhere((t) => t.id != 't1');
      expect(n.state.selectedTextId, right.id);
      expect(n.state.currentMenuId, 'text_overlay');
    });

    test('is one undo step', () {
      final n = selected();
      n.splitTextOverlay(4.0);
      n.undo();

      expect(n.state.textOverlays, hasLength(1));
      expect(n.state.textOverlays.single.id, 't1');
      expect(n.state.textOverlays.single.endTime, const Duration(seconds: 6));
    });

    test('refuses a cut that would leave a sliver or miss the text', () {
      // The minimum is the timeline's own trim minimum, so a split cannot
      // make a piece the trim handles could not.
      for (final playhead in [2.1, 5.9, 1.0, 7.0]) {
        final n = selected();
        expect(
          () => n.splitTextOverlay(playhead),
          throwsException,
          reason: 'a cut at ${playhead}s should be refused',
        );
        expect(n.state.textOverlays, hasLength(1));
        expect(n.state.canUndo, isFalse, reason: 'a refusal is not an edit');
      }
    });

    test('does nothing with no text selected', () {
      final n = notifierWith(texts: [caption()]);
      n.splitTextOverlay(4.0);

      expect(n.state.textOverlays, hasLength(1));
      expect(n.state.canUndo, isFalse);
    });
  });

  group('the Split tool, with a text selected', () {
    bool splitOffered(VideoEditorNotifier n) {
      final container = ProviderContainer(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
      );
      addTearDown(container.dispose);
      return container.listen(isSplitToolEnabledProvider, (_, _) {}).read();
    }

    VideoEditorNotifier selectedAt(double playhead) {
      final n = notifierWith(texts: [caption()]);
      n.selectTextOverlay('t1');
      n.state = n.state.copyWith(currentPlaybackPosition: playhead);
      return n;
    }

    test('is offered while the playhead is inside the text', () {
      // The gate used to know only clips: it required `isClipSelected`, which
      // selecting a text clears, so a text's Split could never have shown.
      expect(splitOffered(selectedAt(4.0)), isTrue);
    });

    test('is withheld where the cut would leave a sliver, or miss', () {
      expect(splitOffered(selectedAt(2.1)), isFalse);
      expect(splitOffered(selectedAt(1.0)), isFalse);
      expect(splitOffered(selectedAt(6.5)), isFalse);
    });

    test('is offered exactly where the split succeeds', () {
      // One rule, two consumers: a button that shows where the split refuses
      // is a dead tap, and one that hides where it would work is a missing
      // tool. Swept across both edges, including the exact minimum.
      for (final playhead in [
        1.0, 2.0, 2.1, 2.2, 2.25, 4.0, 5.75, 5.8, 5.85, 6.0, 7.0,
      ]) {
        final offered = splitOffered(selectedAt(playhead));
        var succeeded = true;
        try {
          selectedAt(playhead).splitTextOverlay(playhead);
        } on Exception {
          succeeded = false;
        }
        expect(offered, succeeded, reason: 'at ${playhead}s');
      }
    });
  });
}

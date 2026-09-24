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
/// by — select, add, duplicate — and leaves by every door it can stop
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
}

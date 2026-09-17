import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/chroma/chroma_key.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// An overlay can be keyed on colour, with the clip's own `ChromaKey`.
///
/// The model is shared on purpose: a green screen means one thing everywhere,
/// and one coverage function keeps the preview and the export agreeing. The
/// reason it could not be built until now is that the preview drew overlays as
/// Flutter widgets, which cannot make a per-pixel colour decision — so the
/// export would have dropped the green while the canvas still showed it. With
/// overlays drawn in GL both sides run the same shader.
void main() {
  const key = ChromaKey(enabled: true, similarity: 0.5, smoothness: 0.2);

  group('the model', () {
    test('an overlay carries no key until one is set', () {
      expect(ImageOverlayModel(id: 'i', imagePath: '/p.png').chromaKey,
          ChromaKey.none);
      expect(VideoOverlayModel(id: 'v', videoPath: '/v.mp4').chromaKey,
          ChromaKey.none);
    });

    test('a key survives a round trip through JSON', () {
      final video = VideoOverlayModel(id: 'v', videoPath: '/v.mp4')
          .copyWith(chromaKey: key);
      expect(VideoOverlayModel.fromJson(video.toJson()).chromaKey, key);

      final image = ImageOverlayModel(id: 'i', imagePath: '/p.png')
          .copyWith(chromaKey: key);
      expect(ImageOverlayModel.fromJson(image.toJson()).chromaKey, key);
    });

    test('an unkeyed overlay writes nothing, so old drafts are unchanged', () {
      expect(
        VideoOverlayModel(id: 'v', videoPath: '/v.mp4').toJson(),
        isNot(contains('chromaKey')),
      );
      // And a draft written before keys existed reads as unkeyed.
      expect(
        VideoOverlayModel.fromJson({'id': 'v', 'videoPath': '/v.mp4'}).chromaKey,
        ChromaKey.none,
      );
    });
  });

  group('the editor', () {
    VideoEditorNotifier notifier({String? image, String? video}) =>
        VideoEditorNotifier(VideoEditorService())
          ..state = VideoEditorState(
            segments: [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)],
            imageOverlays: [ImageOverlayModel(id: 'i', imagePath: '/p.png')],
            videoOverlays: [VideoOverlayModel(id: 'v', videoPath: '/v.mp4')],
            selectedImageId: image,
            selectedVideoOverlayId: video,
          );

    test('one editor serves whichever overlay is selected', () {
      final onVideo = notifier(video: 'v');
      onVideo.setChromaKeyOnSelection(key);
      expect(onVideo.state.videoOverlays.single.chromaKey, key);
      expect(onVideo.state.imageOverlays.single.chromaKey, ChromaKey.none);

      final onImage = notifier(image: 'i');
      onImage.setChromaKeyOnSelection(key);
      expect(onImage.state.imageOverlays.single.chromaKey, key);
    });

    test('it reads back what the panel should show', () {
      final n = notifier(video: 'v');
      expect(n.chromaKeyOnSelection, ChromaKey.none);
      n.setChromaKeyOnSelection(key);
      expect(n.chromaKeyOnSelection, key);
    });

    test('a clip wins when a clip is selected', () {
      final n = notifier(video: 'v')
        ..state = notifier(video: 'v').state.copyWith(
              selectedSegmentId: 'c',
              isClipSelected: true,
            );
      n.setChromaKeyOnSelection(key);
      expect(n.state.segments.single.chromaKey, key);
      expect(n.state.videoOverlays.single.chromaKey, ChromaKey.none);
    });

    test('with nothing selected it writes nothing and takes no snapshot', () {
      // An undo entry that undoes nothing is a lie, and the screen's opener
      // only borrows a clip when there is no target at all — so an overlay
      // selection must never be written over by the clip under the playhead.
      final n = notifier();
      n.setChromaKeyOnSelection(key);
      expect(n.state.segments.single.chromaKey, ChromaKey.none);
      expect(n.state.imageOverlays.single.chromaKey, ChromaKey.none);
      expect(n.state.videoOverlays.single.chromaKey, ChromaKey.none);
      expect(n.state.canUndo, isFalse);
    });

    test('a write is one undo step, and a live write is none', () {
      final n = notifier(video: 'v');
      n.setChromaKeyOnSelection(key);
      expect(n.state.canUndo, isTrue);
      n.undo();
      expect(n.state.videoOverlays.single.chromaKey, ChromaKey.none);

      // A slider drag: one snapshot at the start, live writes between.
      n.beginChromaKeyOnSelection();
      for (var i = 1; i <= 10; i++) {
        n.setChromaKeyOnSelection(
          key.copyWith(similarity: i / 10),
          live: true,
        );
      }
      expect(n.state.videoOverlays.single.chromaKey.similarity, 1.0);
      n.undo();
      expect(n.state.videoOverlays.single.chromaKey, ChromaKey.none);
    });
  });
}

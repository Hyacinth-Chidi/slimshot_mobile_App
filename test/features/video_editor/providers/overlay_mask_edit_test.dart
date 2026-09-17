import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// One mask editor serves whatever is selected — a clip, a photo overlay or a
/// video overlay — so there is no second editor to drift from the first.
void main() {
  const circle = ClipMask(shape: ClipMaskShape.circle, width: 0.7, height: 0.7);
  const rounded = ClipMask(
    shape: ClipMaskShape.roundedRectangle,
    width: 0.9,
    height: 0.5,
    cornerRadius: 0.2,
  );

  VideoEditorNotifier notifier({
    String? clip,
    String? image,
    String? video,
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: [
            VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10),
          ],
          imageOverlays: [ImageOverlayModel(id: 'i', imagePath: '/p.png')],
          videoOverlays: [VideoOverlayModel(id: 'v', videoPath: '/v.mp4')],
          selectedSegmentId: clip,
          isClipSelected: clip != null,
          selectedImageId: image,
          selectedVideoOverlayId: video,
        );

  test('with a clip selected it still writes the clip', () {
    final n = notifier(clip: 'c');
    n.setMaskOnSelection(circle);
    expect(n.state.segments.single.mask, circle);
    expect(n.state.imageOverlays.single.mask, ClipMask.none);
  });

  test('with a photo overlay selected it writes that overlay', () {
    final n = notifier(image: 'i');
    n.setMaskOnSelection(rounded);
    expect(n.state.imageOverlays.single.mask, rounded);
    expect(n.state.segments.single.mask, ClipMask.none);
    expect(n.state.videoOverlays.single.mask, ClipMask.none);
  });

  test('with a video overlay selected it writes that overlay', () {
    final n = notifier(video: 'v');
    n.setMaskOnSelection(circle);
    expect(n.state.videoOverlays.single.mask, circle);
    expect(n.state.imageOverlays.single.mask, ClipMask.none);
  });

  test('a write is one undo step, and undo restores the shape', () {
    final n = notifier(image: 'i');
    n.setMaskOnSelection(circle);
    n.setMaskOnSelection(rounded);
    expect(n.state.imageOverlays.single.mask, rounded);
    n.undo();
    expect(n.state.imageOverlays.single.mask, circle);
    n.undo();
    expect(n.state.imageOverlays.single.mask, ClipMask.none);
  });

  test('a live write takes no undo step of its own', () {
    final n = notifier(video: 'v');
    n.setMaskOnSelection(circle);
    n.setMaskOnSelection(
      circle.copyWith(feather: 0.2),
      takeUndoSnapshot: false,
    );
    expect(n.state.videoOverlays.single.mask.feather, closeTo(0.2, 1e-9));
    // One snapshot for the pair, so undo clears the whole gesture.
    n.undo();
    expect(n.state.videoOverlays.single.mask, ClipMask.none);
  });

  test('with nothing selected it writes nothing and takes no snapshot', () {
    final n = notifier();
    n.setMaskOnSelection(circle);
    expect(n.state.segments.single.mask, ClipMask.none);
    expect(n.state.imageOverlays.single.mask, ClipMask.none);
    expect(n.state.videoOverlays.single.mask, ClipMask.none);
    expect(n.state.canUndo, isFalse);
  });

  test('maskOnSelection reports what the editor should show', () {
    expect(notifier().maskOnSelection, ClipMask.none);

    final img = notifier(image: 'i');
    img.setMaskOnSelection(rounded);
    expect(img.maskOnSelection, rounded);

    final clip = notifier(clip: 'c');
    clip.setMaskOnSelection(circle);
    expect(clip.maskOnSelection, circle);
  });
}

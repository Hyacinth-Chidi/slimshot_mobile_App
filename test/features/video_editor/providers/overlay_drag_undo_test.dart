import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Dragging an overlay on the canvas is one undo step.
///
/// Device-reported as the overlay crawling behind the finger: every frame of a
/// move went through `updateImageOverlay`, which snapshots the whole editor
/// state for undo — sixty snapshots a second, and an Undo that walked the drag
/// back a pixel at a time. The text layer already had the rule; the photo and
/// video layers never got it.
void main() {
  VideoEditorNotifier notifier() => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      segments: [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)],
      imageOverlays: [ImageOverlayModel(id: 'i', imagePath: '/p.png')],
      videoOverlays: [VideoOverlayModel(id: 'v', videoPath: '/v.mp4')],
    );

  test('a photo overlay drag undoes in one step', () {
    final n = notifier();
    final start = n.state.imageOverlays.single.position;

    n.saveStateForUndo();
    for (var i = 1; i <= 30; i++) {
      n.updateImageOverlayLive(
        'i',
        (o) => o.copyWith(position: Offset(i * 2.0, i * 1.0)),
      );
    }
    expect(n.state.imageOverlays.single.position, const Offset(60, 30));

    n.undo();
    expect(n.state.imageOverlays.single.position, start);
    expect(n.state.canUndo, isFalse);
  });

  test('a video overlay drag undoes in one step', () {
    final n = notifier();
    final start = n.state.videoOverlays.single.position;

    n.saveStateForUndo();
    for (var i = 1; i <= 30; i++) {
      n.updateVideoOverlayLive(
        'v',
        (o) => o.copyWith(position: Offset(i * 2.0, i * 1.0)),
      );
    }
    expect(n.state.videoOverlays.single.position, const Offset(60, 30));

    n.undo();
    expect(n.state.videoOverlays.single.position, start);
    expect(n.state.canUndo, isFalse);
  });

  test('a live update to an overlay that is gone is ignored', () {
    final n = notifier();
    n.updateImageOverlayLive('nope', (o) => o.copyWith(scale: 3));
    n.updateVideoOverlayLive('nope', (o) => o.copyWith(scale: 3));
    expect(n.state.imageOverlays.single.scale, 1.0);
    expect(n.state.videoOverlays.single.scale, 1.0);
  });
}

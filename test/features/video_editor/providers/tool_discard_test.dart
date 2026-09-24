import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// ✕ on a slider panel discards what the slider did.
///
/// A clip's Volume held its drag as a preview and ✕ dropped it; everything
/// else under the Volume and Opacity panels — a video overlay's volume, any
/// overlay's opacity, a clip's opacity — wrote the model as the slider moved,
/// so ✕ closed the panel and **kept** the change. ✕ is the one explicit
/// discard (`tool_dismissal.dart`); it has to discard whatever the panel
/// edits.
void main() {
  VideoEditorNotifier notifier({
    String? selectedClip,
    String? selectedImage,
    String? selectedVideo,
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: [
            VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10),
            VideoSegment(id: 'd', sourceStart: 10, sourceEnd: 20),
          ],
          imageOverlays: [ImageOverlayModel(id: 'i', imagePath: '/p.png')],
          videoOverlays: [VideoOverlayModel(id: 'v', videoPath: '/v.mp4')],
          selectedSegmentId: selectedClip,
          isClipSelected: selectedClip != null,
          selectedImageId: selectedImage,
          selectedVideoOverlayId: selectedVideo,
          currentPlaybackPosition: 5,
        );

  /// A slider drag as the panels make it: one snapshot, then live writes.
  void dragVideoVolume(VideoEditorNotifier n, double to) {
    n.saveStateForUndo();
    for (final v in [0.8, 0.5, to]) {
      n.updateVideoOverlayLive('v', (o) => o.copyWith(volume: v));
    }
  }

  group('✕ discards', () {
    test("a video overlay's volume", () {
      final n = notifier(selectedVideo: 'v')..openRevertibleTool('volume');
      dragVideoVolume(n, 0.2);
      expect(n.state.videoOverlays.single.volume, 0.2);

      n.discardActiveTool();

      expect(n.state.videoOverlays.single.volume, 1.0);
      expect(n.state.activeToolId, isNull);
    });

    test("an overlay's opacity", () {
      final n = notifier(selectedImage: 'i')..openRevertibleTool('opacity');
      n.saveStateForUndo();
      n.setOverlayOpacity(0.3, takeUndoSnapshot: false);

      n.discardActiveTool();

      expect(n.state.imageOverlays.single.opacity, 1.0);
    });

    test("a clip's opacity, keyframe and all", () {
      // On a keyframed clip the slider writes a diamond — possibly a new one.
      // Discarding puts the clip back whole, so the diamond goes too.
      final n = notifier(selectedClip: 'c')..addKeyframeAtPlayhead();
      final before = n.state.segments.first;
      n.state = n.state.copyWith(currentPlaybackPosition: 8);
      n.openRevertibleTool('opacity');
      n.saveStateForUndo();
      n.setClipProperty(ClipProperty.opacity, 0.1, takeUndoSnapshot: false);
      expect(n.state.segments.first, isNot(same(before)));

      n.discardActiveTool();

      expect(n.state.segments.first.toJson(), before.toJson());
    });

    test('leaves no undo entry behind, and keeps the ones before it', () {
      // An undo that undoes nothing is a lie; an edit made before the tool
      // opened must still be undoable after the discard.
      final n = notifier(selectedVideo: 'v');
      n.updateVideoOverlay('v', (o) => o.copyWith(speed: 2));
      n.openRevertibleTool('volume');
      dragVideoVolume(n, 0.2);

      n.discardActiveTool();
      expect(n.state.canUndo, isTrue);
      n.undo();

      expect(n.state.videoOverlays.single.speed, 1.0);
      expect(n.state.canUndo, isFalse);
    });

    test('leaves the playhead where it is', () {
      // The target is put back, not the whole editor: restoring a snapshot
      // would also move the playhead back to where the drag began.
      final n = notifier(selectedVideo: 'v')..openRevertibleTool('volume');
      dragVideoVolume(n, 0.2);
      n.state = n.state.copyWith(currentPlaybackPosition: 7);

      n.discardActiveTool();

      expect(n.state.currentPlaybackPosition, 7);
    });
  });

  group('✓ keeps', () {
    test('the value, as one undo step', () {
      final n = notifier(selectedVideo: 'v')..openRevertibleTool('volume');
      dragVideoVolume(n, 0.2);

      n.closeActiveTool();
      expect(n.state.videoOverlays.single.volume, 0.2);

      n.undo();
      expect(n.state.videoOverlays.single.volume, 1.0);
      expect(n.state.canUndo, isFalse);
    });

    test('and a later ✕ has nothing left to discard', () {
      final n = notifier(selectedVideo: 'v')..openRevertibleTool('volume');
      dragVideoVolume(n, 0.2);
      n.closeActiveTool();

      n.setActiveTool('volume');
      n.discardActiveTool();

      expect(n.state.videoOverlays.single.volume, 0.2);
    });
  });

  test('✕ on a tool opened without a record only closes it', () {
    final n = notifier(selectedVideo: 'v')..setActiveTool('mask');
    n.updateVideoOverlay('v', (o) => o.copyWith(volume: 0.4));

    n.discardActiveTool();

    expect(n.state.activeToolId, isNull);
    expect(n.state.videoOverlays.single.volume, 0.4);
  });

  test('a record does not outlive its tool', () {
    // Selecting audio closes a tool without going through ✓ or ✕. A record
    // left behind would let the next tool's ✕ restore a stale overlay.
    final n = notifier(selectedVideo: 'v')..openRevertibleTool('volume');
    n.selectAudioTrack('a');
    n.selectVideoOverlay('v');
    n.setActiveTool('mask');
    n.updateVideoOverlay('v', (o) => o.copyWith(volume: 0.4));

    n.discardActiveTool();

    expect(n.state.videoOverlays.single.volume, 0.4);
  });

  test('the screen opens Volume and Opacity with a record, and ✕ discards',
      () {
    final screen =
        File('lib/screens/video_editor_screen.dart').readAsStringSync();
    expect(screen, contains("notifier.openRevertibleTool('opacity')"));
    expect(screen, contains("notifier.openRevertibleTool('volume')"));
    expect(screen, contains('notifier.discardActiveTool()'));
    expect(screen, isNot(contains("setActiveTool('opacity')")));
  });

  test("an overlay's opacity drag is one undo step", () {
    // Every frame of the slider went through `updateImageOverlay`, which
    // snapshots: Undo walked the drag back a step at a time.
    final n = notifier(selectedImage: 'i');
    n.saveStateForUndo();
    for (final v in [0.9, 0.7, 0.5, 0.3]) {
      n.setOverlayOpacity(v, takeUndoSnapshot: false);
    }
    n.undo();

    expect(n.state.imageOverlays.single.opacity, 1.0);
    expect(n.state.canUndo, isFalse);
  });
}

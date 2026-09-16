import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Two guards around the clip gestures, both found in review.
///
/// A clip stays selected while the playhead moves onto its neighbour, so every
/// gesture has to cope with "there is no instant of this clip under the
/// playhead". And every gesture runs while the timeline may be playing, so a
/// moving playhead must not turn one drag into a trail of diamonds.
void main() {
  /// Clip `b` selected, 10s long, so a position under 10 is on clip `a`.
  VideoEditorNotifier notifierWith({
    required double position,
    bool isPlaying = false,
    List<Keyframe> scaleKeyframes = const [],
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10),
          VideoSegment(
            id: 'b',
            sourceStart: 10,
            sourceEnd: 20,
            canvasScale: AnimatableDouble(
              baseValue: 1.0,
              keyframes: scaleKeyframes,
            ),
          ),
        ],
        selectedSegmentId: 'b',
        isClipSelected: true,
        currentPlaybackPosition: position,
        isPlaying: isPlaying,
      );
  }

  VideoSegment b(VideoEditorNotifier n) => n.state.segments[1];

  group('with the playhead on another clip', () {
    test('the plus button places nothing', () {
      // The old clamp resolved this as progress 0 and pinned a diamond at the
      // start of a clip the user was not looking at.
      final n = notifierWith(position: 3.0);
      n.addKeyframeAtPlayhead();
      expect(b(n).hasKeyframes, isFalse);
    });

    test('a transform write goes to the base and adds no diamond', () {
      final n = notifierWith(
        position: 3.0,
        scaleKeyframes: const [Keyframe(progress: 0.5, value: 2.0)],
      );
      n.beginClipCanvasTransform();
      n.updateClipCanvasTransform(scale: 3.0, offsetX: 0.0, offsetY: 0.0);
      n.endClipCanvasTransform();

      expect(b(n).canvasScale.keyframes, hasLength(1));
      expect(b(n).canvasScale.baseValue, 3.0);
    });
  });

  test('starting a transform gesture pauses playback', () {
    // Dragging a ruler or pinching on a keyframed clip while it plays would
    // otherwise write into a moving playhead — many diamonds from one drag.
    final n = notifierWith(position: 12.0, isPlaying: true);
    n.beginClipCanvasTransform();
    expect(n.state.isPlaying, isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// The Volume control on a video layer. On a layer with a volume track (a
/// reaction's) it writes through the edit rule, as a clip's Volume does; on
/// every other video layer it is exactly what it was.
void main() {
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 6);

  OverlayKeyframes ducked() => const OverlayKeyframes({
        OverlayProperty.x: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.y: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.scale: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 1), Keyframe(progress: 1, value: 1)],
        OverlayProperty.rotation: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.opacity: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 1), Keyframe(progress: 1, value: 1)],
        OverlayProperty.volume: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 0.25), Keyframe(progress: 1, value: 1)],
      });

  VideoEditorNotifier project({OverlayKeyframes keyframes = OverlayKeyframes.none}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          segments: [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)],
          videoOverlays: [
            VideoOverlayModel(
              id: 'v',
              videoPath: '/v.mp4',
              timelineStart: start,
              timelineEnd: end,
              sourceStart: 0,
              sourceEnd: 20,
              keyframes: keyframes,
            ),
          ],
        )
        ..selectVideoOverlay('v');

  void seek(VideoEditorNotifier n, double seconds) => n.state = n.state.copyWith(currentPlaybackPosition: seconds);
  VideoOverlayModel layer(VideoEditorNotifier n) => n.state.videoOverlays.single;
  List<double> volumes(VideoEditorNotifier n) =>
      [for (final k in layer(n).keyframes.of(OverlayProperty.volume)) k.value];

  group('a video layer made in the editor', () {
    test('a diamond placed on it pins no volume', () {
      final n = project();
      seek(n, 4);
      n.addKeyframeAtPlayhead();
      expect(layer(n).keyframes.of(OverlayProperty.x), isNotEmpty);
      expect(layer(n).keyframes.of(OverlayProperty.volume), isEmpty);
    });

    test('the edit rule has no volume to write: its Volume control writes the base, as before', () {
      final n = project();
      seek(n, 4);
      n.addKeyframeAtPlayhead();
      final before = layer(n);
      n.setOverlayMotionLive(id: 'v', volume: 0.3);
      expect(identical(layer(n), before), isTrue);
    });
  });

  group('a layer with a volume track', () {
    test('its Volume shows the value at the playhead', () {
      final n = project(keyframes: ducked());
      seek(n, 4);
      expect(n.state.overlayEditValue(OverlayProperty.volume), moreOrLessEquals(0.25));
    });

    test('on a diamond, Volume writes that diamond and leaves the base', () {
      final n = project(keyframes: ducked());
      seek(n, 4);
      n.setOverlayMotionLive(id: 'v', volume: 0.1);
      expect(volumes(n), [1, 0.1, 1]);
      expect(layer(n).volume, 1);
    });

    test('between diamonds, Volume places one that pins every property, then writes it', () {
      final n = project(keyframes: ducked());
      seek(n, 3);
      n.setOverlayMotionLive(id: 'v', volume: 0.5);
      expect(volumes(n), [1, 0.5, 0.25, 1]);
      for (final p in OverlayProperty.values) {
        expect(layer(n).keyframes.of(p), hasLength(4), reason: '$p carries the new diamond too');
      }
    });

    test('a volume outside 0..1 is held to it', () {
      final n = project(keyframes: ducked());
      seek(n, 4);
      n.setOverlayMotionLive(id: 'v', volume: 3);
      expect(volumes(n), [1, 1, 1]);
    });

    test('split, each half keeps its part of the track', () {
      final n = project(keyframes: ducked());
      n.splitVideoOverlay(3);
      final halves = n.state.videoOverlays;
      expect(halves, hasLength(2));
      for (final half in halves) {
        expect(half.keyframes.of(OverlayProperty.volume), isNotEmpty);
      }
      expect(halves.first.shownAt(3).volume, moreOrLessEquals(0.625, epsilon: 1e-6));
      expect(halves.last.shownAt(3).volume, moreOrLessEquals(0.625, epsilon: 1e-6));
    });
  });
}

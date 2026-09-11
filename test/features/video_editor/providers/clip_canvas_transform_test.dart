import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

void main() {
  VideoSegment clip(String id, {double scale = 1.0, double dx = 0.0}) {
    return VideoSegment(
      id: id,
      sourceStart: 0,
      sourceEnd: 5,
      canvasScale: scale,
      canvasOffsetX: dx,
    );
  }

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selectedSegmentId,
      );
  }

  group('clip canvas transform', () {
    test('update writes only the selected clip, clamped', () {
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        selectedSegmentId: 'b',
      );

      notifier.updateClipCanvasTransform(
        scale: 99.0,
        offsetX: 0.25,
        offsetY: -0.1,
      );

      expect(notifier.state.segments[0].canvasScale, 1.0);
      expect(notifier.state.segments[1].canvasScale, kMaxClipCanvasScale);
      expect(notifier.state.segments[1].canvasOffsetX, 0.25);
      expect(notifier.state.segments[1].canvasOffsetY, -0.1);
    });

    test('a whole gesture undoes as one step', () {
      final notifier = notifierWith([clip('a')], selectedSegmentId: 'a');

      notifier.beginClipCanvasTransform();
      notifier.updateClipCanvasTransform(scale: 2.0, offsetX: 0.1, offsetY: 0.0);
      notifier.updateClipCanvasTransform(scale: 2.5, offsetX: 0.2, offsetY: 0.0);
      notifier.endClipCanvasTransform();

      expect(notifier.state.segments[0].canvasScale, 2.5);
      notifier.undo();
      expect(notifier.state.segments[0].canvasScale, 1.0);
      expect(notifier.state.segments[0].canvasOffsetX, 0.0);
    });

    test('reset returns the clip to the plain fit, undoably', () {
      final notifier = notifierWith(
        [clip('a', scale: 3.0, dx: 0.4)],
        selectedSegmentId: 'a',
      );

      notifier.resetClipCanvasTransform();
      expect(notifier.state.segments[0].canvasScale, 1.0);
      expect(notifier.state.segments[0].canvasOffsetX, 0.0);

      notifier.undo();
      expect(notifier.state.segments[0].canvasScale, 3.0);
    });

    test('a split carries the transform to both halves', () {
      final notifier = notifierWith(
        [clip('a', scale: 2.0, dx: 0.3)],
        selectedSegmentId: 'a',
      );

      notifier.splitAtPosition(2.5);

      expect(notifier.state.segments.length, 2);
      for (final half in notifier.state.segments) {
        expect(half.canvasScale, 2.0);
        expect(half.canvasOffsetX, 0.3);
      }
    });

    test('the transform survives a draft round-trip', () {
      final original = clip('a', scale: 1.7, dx: -0.2);
      final restored = VideoSegment.fromJson(original.toJson());

      expect(restored.canvasScale, 1.7);
      expect(restored.canvasOffsetX, -0.2);
    });

    test('clips with different transforms are not merged for playback', () {
      const composer = VideoEditorTimelineComposer();
      final state = VideoEditorState(
        assets: [
          MediaAsset(
            id: 'asset',
            path: '/media/one.mp4',
            type: MediaAssetType.video,
            durationSeconds: 10,
            width: 1080,
            height: 1920,
            hasAudio: true,
          ),
        ],
        segments: [
          VideoSegment(
            id: 'a',
            assetId: 'asset',
            sourceStart: 0,
            sourceEnd: 5,
            canvasScale: 2.0,
          ),
          VideoSegment(
            id: 'b',
            assetId: 'asset',
            sourceStart: 5,
            sourceEnd: 10,
          ),
        ],
      );

      final timeline = composer.compose(state);
      // Same file, adjacent ranges — mergeable but for the transform. Merged,
      // the second clip would inherit the first clip's zoom.
      expect(timeline.playbackClips.length, 2);
    });
  });
}

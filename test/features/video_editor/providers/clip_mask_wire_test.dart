import 'dart:ui';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A clip's mask from the model to the wire.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  VideoSegment clip(String id, {double start = 0, double end = 10}) =>
      VideoSegment(id: id, assetId: 'a', sourceStart: start, sourceEnd: end);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
      {String? selected, double position = 0}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [asset],
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: selected != null,
        currentPlaybackPosition: position,
      );
  }

  const circle = ClipMask(shape: ClipMaskShape.circle, width: 0.5, height: 0.5);

  group('the model', () {
    test('defaults to none and writes nothing for it', () {
      final s = clip('a');
      expect(s.mask, ClipMask.none);
      expect(s.toJson().containsKey('mask'), isFalse);
    });

    test('round-trips through json', () {
      final s = clip('a').copyWith(mask: circle);
      final restored = VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.mask, circle);
    });
  });

  group('the notifier', () {
    test('sets the selected clip\'s mask as one undo step', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.setClipMask(circle);
      expect(n.state.segments.single.mask, circle);
      n.undo();
      expect(n.state.segments.single.mask, ClipMask.none);
    });

    test('a live write can skip the snapshot', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.saveStateForUndo();
      n.setClipMask(circle, takeUndoSnapshot: false);
      n.setClipMask(circle.copyWith(centerX: 0.2), takeUndoSnapshot: false);
      n.undo();
      expect(n.state.segments.single.mask, ClipMask.none);
    });

    test('a split carries the mask to both halves', () {
      final n = notifierWith([clip('a')], selected: 'a', position: 5.0);
      n.setClipMask(circle);
      n.splitAtPosition(5.0);
      for (final s in n.state.segments) {
        expect(s.mask, circle, reason: s.id);
      }
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    test('carries the mask as a map, and omits none', () {
      final masked = composer
          .compose(notifierWith([clip('a').copyWith(mask: circle)]).state)
          .toJson();
      final json = (masked['videoClips'] as List).single as Map<String, dynamic>;
      expect(json['mask'], isA<Map>());
      expect((json['mask'] as Map)['shape'], 'circle');

      final plain = composer.compose(notifierWith([clip('a')]).state).toJson();
      final plainJson = (plain['videoClips'] as List).single as Map<String, dynamic>;
      expect(plainJson.containsKey('mask'), isFalse);
    });

    test('differently masked neighbours are not merged', () {
      final timeline = composer.compose(notifierWith([
        clip('a', start: 0, end: 4).copyWith(mask: circle),
        clip('b', start: 4, end: 8),
      ]).state);
      expect(timeline.playbackClips, hasLength(2));
    });

    test('while the mask tool is open on a clip, it shows unplaced but cropped',
        () {
      // The mask is authored on the picture as it will play minus its
      // placement: the crop stays (the window is over the cropped picture),
      // scale/pan/rotation are suspended so the canvas maps a drag through the
      // fit alone — the clip-crop tool's rule, one step gentler.
      final timeline = composer.compose(
        notifierWith([
          clip('a').copyWith(
            canvasScale: const AnimatableDouble(baseValue: 2.0),
            canvasRotation: const AnimatableDouble(baseValue: 30.0),
            cropRect: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
          ),
        ], selected: 'a')
            .state
            .copyWith(activeToolId: 'mask'),
      );
      final c = timeline.videoClips.single;
      expect(c.canvasScaleAt(0.5), 1.0);
      expect(c.canvasRotationAt(0.5), 0.0);
      expect(c.contentRect, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
    });
  });
}

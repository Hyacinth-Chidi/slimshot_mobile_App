import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Clip opacity: the seventh keyframable property.
///
/// Overlays had an opacity; the clip under them did not. In the engine it is
/// a **mix toward the letterbox fill**, never alpha — the clip pass has no
/// blending and the fill is already what shows around a clip — applied after
/// the clip's own grade and before the effect chain. On this side it is one
/// more `AnimatableDouble` that every keyframe control already knows how to
/// pin, so a fade in or out is two diamonds.
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

  group('the model', () {
    test('defaults to fully present and writes a bare number', () {
      final s = clip('a');
      expect(s.opacityAt(0.5), 1.0);
      expect(s.toJson()['opacity'], 1.0);
      expect(s.toJson()['opacity'], isA<num>());
    });

    test('a draft without it loads fully present', () {
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
      });
      expect(s.opacityAt(0.0), 1.0);
    });

    test('is a keyframable property like the other six', () {
      final s = clip('a');
      final faded = withClipParameter(
        s,
        ClipProperty.opacity,
        const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 0.0),
          Keyframe(progress: 1.0, value: 1.0),
        ]),
      );
      expect(clipParameter(faded, ClipProperty.opacity).keyframes, hasLength(2));
      expect(faded.opacityAt(0.5), closeTo(0.5, 1e-9));
      expect(faded.hasKeyframes, isTrue);

      // A diamond pins it with everything else.
      final pinned = captureKeyframe(clip('a'), 0.3);
      expect(clipParameter(pinned, ClipProperty.opacity).keyframes, hasLength(1));
    });

    test('resolves clamped to 0..1, because a keyframe can overshoot', () {
      final s = clip('a').copyWith(
        opacity: const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 1.5),
          Keyframe(progress: 1.0, value: -0.5),
        ]),
      );
      expect(s.opacityAt(0.0), 1.0);
      expect(s.opacityAt(1.0), 0.0);
    });

    test('round-trips keyframes through json', () {
      final s = clip('a').copyWith(
        opacity: const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 0.0),
          Keyframe(progress: 1.0, value: 1.0),
        ]),
      );
      final restored = VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.opacityAt(0.25), closeTo(0.25, 1e-9));
    });
  });

  group('the notifier', () {
    test('writes the base on an unkeyframed clip', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.setClipProperty(ClipProperty.opacity, 0.4);
      expect(n.state.segments.single.opacity.baseValue, 0.4);
      expect(n.state.segments.single.hasKeyframes, isFalse);
    });

    test('writes the diamond on a keyframed clip', () {
      final n = notifierWith([clip('a')], selected: 'a', position: 5.0);
      n.addKeyframeAtPlayhead();
      n.setClipProperty(ClipProperty.opacity, 0.2);
      final s = n.state.segments.single;
      expect(s.opacity.keyframes.single.value, 0.2);
      expect(s.opacity.baseValue, 1.0);
    });

    test('a split carries the opacity to both halves', () {
      final n = notifierWith([clip('a')], selected: 'a', position: 5.0);
      n.setClipProperty(ClipProperty.opacity, 0.6);
      n.splitAtPosition(5.0);
      for (final s in n.state.segments) {
        expect(s.opacity.baseValue, 0.6, reason: s.id);
      }
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    test('carries the opacity, flat as a number and animated as a map', () {
      final flat = composer.compose(notifierWith([clip('a')]).state).toJson();
      final flatClip =
          (flat['videoClips'] as List).single as Map<String, dynamic>;
      expect(flatClip['opacity'], 1.0);

      final animated = composer
          .compose(notifierWith([
            clip('a').copyWith(
              opacity: const AnimatableDouble(baseValue: 1.0, keyframes: [
                Keyframe(progress: 0.0, value: 0.0),
                Keyframe(progress: 1.0, value: 1.0),
              ]),
            ),
          ]).state)
          .toJson();
      final animatedClip =
          (animated['videoClips'] as List).single as Map<String, dynamic>;
      expect(animatedClip['opacity'], isA<Map>());
    });

    test('differently faded neighbours are not merged for playback', () {
      final timeline = composer.compose(notifierWith([
        clip('a', start: 0, end: 4)
            .copyWith(opacity: const AnimatableDouble(baseValue: 0.5)),
        clip('b', start: 4, end: 8),
      ]).state);
      expect(timeline.playbackClips, hasLength(2));
    });
  });
}

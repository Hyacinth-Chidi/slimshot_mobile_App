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

/// The edges: split, merge, round-trip, and the promise that an unkeyframed
/// project is untouched.
void main() {
  const asset = MediaAsset(
    id: 'asset_main',
    path: '/source/video.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
    double position = 0.0,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [asset],
        segments:
            segments.map((s) => s.copyWith(assetId: asset.id)).toList(),
        selectedSegmentId: selectedSegmentId,
        isClipSelected: selectedSegmentId != null,
        currentPlaybackPosition: position,
      );
  }

  group('a Ken Burns move', () {
    test('survives a draft round-trip', () {
      var s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10);
      s = s.copyWith(
        canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 1.0),
          Keyframe(progress: 1.0, value: 1.8),
        ]),
      );

      final restored =
          VideoSegment.fromJson(jsonDecode(jsonEncode(s.toJson())));
      expect(restored.canvasScaleAt(0.5), closeTo(1.4, 1e-9));
      expect(restored.canvasScaleAt(0.0), closeTo(1.0, 1e-9));
      expect(restored.canvasScaleAt(1.0), closeTo(1.8, 1e-9));
    });

    test('reaches the composed timeline and resolves the same there', () {
      const composer = VideoEditorTimelineComposer();
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10).copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(progress: 0.0, value: 1.0),
            Keyframe(progress: 1.0, value: 1.8),
          ]),
        ),
      ], selectedSegmentId: 'a');

      final clip = composer.compose(n.state).videoClips.single;
      // The engines resolve through the *clip*, so this is the number the
      // preview and the export will each land on at the halfway frame.
      expect(clip.canvasScaleAt(clip.clipProgressAt(5.0)), closeTo(1.4, 1e-9));
    });
  });

  group('splitting a keyframed clip', () {
    test('both halves meet at the seam with the same value', () {
      // scale 1.0 -> 3.0 across a 10s clip, cut at 5s: the unsplit clip is at
      // 2.0 there, so both halves must be too or the picture jumps at the cut.
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10).copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(
              progress: 0.0,
              value: 1.0,
              interpolation: KeyframeInterpolation.linear,
            ),
            Keyframe(progress: 1.0, value: 3.0),
          ]),
        ),
      ], selectedSegmentId: 'a');

      n.splitAtPosition(5.0);

      expect(n.state.segments, hasLength(2));
      final left = n.state.segments[0];
      final right = n.state.segments[1];
      expect(left.canvasScaleAt(1.0), closeTo(2.0, 1e-6));
      expect(right.canvasScaleAt(0.0), closeTo(2.0, 1e-6));
    });

    test('every keyframe lands inside its own half', () {
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10).copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(progress: 0.0, value: 1.0),
            Keyframe(progress: 0.25, value: 1.5),
            Keyframe(progress: 0.8, value: 2.5),
            Keyframe(progress: 1.0, value: 3.0),
          ]),
        ),
      ], selectedSegmentId: 'a');

      n.splitAtPosition(5.0);

      for (final half in n.state.segments) {
        for (final property in ClipProperty.values) {
          for (final k in clipParameter(half, property).keyframes) {
            expect(k.progress, inInclusiveRange(0.0, 1.0),
                reason: '${property.name} on ${half.id}');
          }
        }
      }
    });

    test('the halves keep the ends the whole clip had', () {
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10).copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(
              progress: 0.0,
              value: 1.0,
              interpolation: KeyframeInterpolation.linear,
            ),
            Keyframe(progress: 1.0, value: 3.0),
          ]),
        ),
      ], selectedSegmentId: 'a');

      n.splitAtPosition(2.5); // a quarter in

      expect(n.state.segments[0].canvasScaleAt(0.0), closeTo(1.0, 1e-6));
      expect(n.state.segments[1].canvasScaleAt(1.0), closeTo(3.0, 1e-6));
    });

    test('an unkeyframed clip splits exactly as it always did', () {
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10).copyWith(
          canvasScale: const AnimatableDouble(baseValue: 1.6),
        ),
      ], selectedSegmentId: 'a');

      n.splitAtPosition(5.0);

      for (final half in n.state.segments) {
        expect(half.hasKeyframes, isFalse);
        expect(half.canvasScale.baseValue, 1.6);
      }
    });
  });

  group('the promise that nothing changed', () {
    test('an unkeyframed project composes bare numbers on the wire', () {
      const composer = VideoEditorTimelineComposer();
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4),
      ]);

      final wire =
          composer.compose(n.state).videoClips.single.toJson();
      expect(wire['volume'], isA<num>());
      expect(wire['canvasScale'], isA<num>());
      expect(wire['canvasOffsetX'], isA<num>());
      expect(wire['canvasOffsetY'], isA<num>());
    });

    test('an unkeyframed clip round-trips byte for byte', () {
      final s = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4);
      final once = jsonEncode(s.toJson());
      expect(
        jsonEncode(VideoSegment.fromJson(jsonDecode(once)).toJson()),
        once,
      );
    });
  });
}

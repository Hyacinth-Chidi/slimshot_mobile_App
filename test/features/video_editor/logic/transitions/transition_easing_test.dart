import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Easing on a transition: the seam's own curve for the picture's travel,
/// carried by the clip that transitions out, the way its type and duration are.
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

  VideoSegment clip(String id, {String? transition, KeyframeInterpolation? easing}) =>
      VideoSegment(
        id: id,
        assetId: asset.id,
        sourceStart: 0,
        sourceEnd: 10,
        transitionType: transition,
        transitionDuration: transition == null ? null : 1.0,
        transitionEasing: easing,
      );

  group('the model', () {
    test('a seam with no easing writes nothing new', () {
      final json = clip('a', transition: 'dissolve').toJson();
      expect(json.containsKey('transitionEasing'), isFalse);
    });

    test('an easing survives a draft', () {
      final json = clip(
        'a',
        transition: 'dissolve',
        easing: KeyframeInterpolation.cubicInOut,
      ).toJson();
      expect(json['transitionEasing'], 'cubicInOut');
      expect(
        VideoSegment.fromJson(json).transitionEasing,
        KeyframeInterpolation.cubicInOut,
      );
    });

    test('linear, or a name this build does not know, reads as none', () {
      final json = clip('a', transition: 'dissolve').toJson();
      expect(
        VideoSegment.fromJson({...json, 'transitionEasing': 'linear'}).transitionEasing,
        isNull,
      );
      expect(
        VideoSegment.fromJson({...json, 'transitionEasing': 'warp9'}).transitionEasing,
        isNull,
      );
    });

    test('taking the transition off takes its easing with it', () {
      final eased = clip('a', transition: 'dissolve', easing: KeyframeInterpolation.quadOut);
      expect(eased.copyWith(clearTransitionType: true).transitionEasing, isNull);
      // Anything else keeps it.
      expect(
        eased.copyWith(transitionType: 'wipe').transitionEasing,
        KeyframeInterpolation.quadOut,
      );
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    test('a seam with no easing sends what it always sent', () {
      final timeline = composer.compose(VideoEditorState(
        assets: const [asset],
        segments: [clip('a', transition: 'dissolve'), clip('b')],
      ));
      final wire = timeline.transitions.single.toJson();
      expect(wire.containsKey('easing'), isFalse);
    });

    test('an eased seam sends its curve by name', () {
      final timeline = composer.compose(VideoEditorState(
        assets: const [asset],
        segments: [
          clip('a', transition: 'dissolve', easing: KeyframeInterpolation.sineInOut),
          clip('b'),
        ],
      ));
      expect(timeline.transitions.single.toJson()['easing'], 'sineInOut');
    });
  });

  group('editing it', () {
    VideoEditorNotifier notifierWith(List<VideoSegment> segments) =>
        VideoEditorNotifier(VideoEditorService())
          ..state = VideoEditorState(assets: const [asset], segments: segments);

    test('eases the selected seam, one undo step', () {
      final n = notifierWith([clip('a', transition: 'dissolve'), clip('b')]);
      n.selectTransition('a');
      n.setSegmentTransitionEasing(KeyframeInterpolation.cubicInOut);
      expect(n.state.segments.first.transitionEasing, KeyframeInterpolation.cubicInOut);
      n.undo();
      expect(n.state.segments.first.transitionEasing, isNull);
    });

    test('choosing None stores nothing, and re-choosing the curve takes no step', () {
      final n = notifierWith([clip('a', transition: 'dissolve'), clip('b')]);
      n.selectTransition('a');
      n.setSegmentTransitionEasing(KeyframeInterpolation.linear);
      expect(n.state.segments.first.transitionEasing, isNull);
      expect(n.state.canUndo, isFalse);
    });

    test('a cut has nothing to ease', () {
      final n = notifierWith([clip('a'), clip('b')]);
      n.selectTransition('a');
      n.setSegmentTransitionEasing(KeyframeInterpolation.quadIn);
      expect(n.state.segments.first.transitionEasing, isNull);
      expect(n.state.canUndo, isFalse);
    });

    test('with Apply to all, every seam takes it and the last clip none', () {
      final n = notifierWith([
        clip('a', transition: 'dissolve'),
        clip('b', transition: 'wipe'),
        clip('c'),
      ]);
      n.selectTransition('a');
      n.setTransitionAppliesToAll(true);
      n.setSegmentTransitionEasing(KeyframeInterpolation.quadOut);
      expect(
        n.state.segments.map((s) => s.transitionEasing).toList(),
        [KeyframeInterpolation.quadOut, KeyframeInterpolation.quadOut, null],
      );
    });

    test('turning Apply to all on spreads the easing with the transition', () {
      final n = notifierWith([
        clip('a', transition: 'dissolve', easing: KeyframeInterpolation.sineIn),
        clip('b'),
        clip('c'),
      ]);
      n.selectTransition('a');
      n.setTransitionAppliesToAll(true);
      expect(n.state.segments[1].transitionEasing, KeyframeInterpolation.sineIn);
      expect(n.state.segments[2].transitionEasing, isNull);
    });

    test('a new type keeps the seam’s easing; None drops it', () {
      final n = notifierWith([
        clip('a', transition: 'dissolve', easing: KeyframeInterpolation.cubicIn),
        clip('b'),
      ]);
      n.selectTransition('a');
      n.setSegmentTransition('wipe', 1.0);
      expect(n.state.segments.first.transitionEasing, KeyframeInterpolation.cubicIn);
      n.setSegmentTransition(null, 1.0);
      expect(n.state.segments.first.transitionEasing, isNull);
    });

    test('a split carries the easing to the half that keeps the transition', () {
      final n = notifierWith([
        clip('a', transition: 'dissolve', easing: KeyframeInterpolation.quadInOut),
        clip('b'),
      ]);
      n.splitAtPosition(4);
      final segments = n.state.segments;
      expect(segments, hasLength(3));
      expect(segments[0].transitionEasing, isNull);
      expect(segments[1].transitionType, 'dissolve');
      expect(segments[1].transitionEasing, KeyframeInterpolation.quadInOut);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// The edit rule: whether an edit writes a base value or a keyframe.
///
/// **This is the whole reason no control has a keyframe UI of its own.** Every
/// existing slider and gesture routes through `setClipProperty` and inherits
/// keyframing without knowing the feature exists, so what is pinned here is the
/// behaviour every one of them gets.
void main() {
  /// A 10s clip, so [kKeyframeHitSeconds] (0.05s) is progress 0.005 — small
  /// enough that the tests can sit a playhead "between" diamonds deliberately.
  VideoSegment clip(String id) =>
      VideoSegment(id: id, sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
    double position = 0.0,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selectedSegmentId,
        isClipSelected: selectedSegmentId != null,
        currentPlaybackPosition: position,
      );
  }

  VideoSegment only(VideoEditorNotifier n) => n.state.segments.first;

  group('with no diamonds, an edit writes the base value', () {
    test('the transform gesture writes the base', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.beginClipCanvasTransform();
      n.updateClipCanvasTransform(scale: 2.0, offsetX: 0.1, offsetY: -0.1);
      n.endClipCanvasTransform();

      final s = only(n);
      expect(s.canvasScale.baseValue, 2.0);
      expect(s.canvasScale.keyframes, isEmpty);
      expect(s.hasKeyframes, isFalse);
    });

    test('setClipProperty writes the base', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.setClipProperty(ClipProperty.volume, 0.3);

      expect(only(n).volume.baseValue, 0.3);
      expect(only(n).volume.keyframes, isEmpty);
    });

    test('a clip with an envelope but no diamonds still writes the base', () {
      // `hasKeyframes` deliberately ignores envelopes: a catalog envelope is not
      // the user placing anything, so the rule must treat the clip as untouched.
      final n = notifierWith([
        clip('a').copyWith(
          effectIntensity:
              const AnimatableDouble(baseValue: 0.8, envelope: 'throb'),
        ),
      ], selectedSegmentId: 'a');
      n.setClipProperty(ClipProperty.effectIntensity, 0.4);

      expect(only(n).effectIntensity.baseValue, 0.4);
      expect(only(n).effectIntensity.keyframes, isEmpty);
      // …and the envelope survives, so the preset still shapes the new strength.
      expect(only(n).effectIntensity.envelope, 'throb');
    });
  });

  group('with diamonds, an edit lands on a keyframe', () {
    test('the playhead on a diamond writes that keyframe, not the base', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead(); // at 0.0
      n.updatePlaybackPosition(10.0); // the clip's end, progress 1.0
      n.addKeyframeAtPlayhead();

      n.setClipProperty(ClipProperty.canvasScale, 3.0);

      final s = only(n);
      expect(s.canvasScale.keyframes.length, 2);
      expect(s.canvasScale.keyframes.last.value, 3.0);
      expect(s.canvasScale.keyframes.first.value, 1.0);
      // The base is untouched: the user is editing a moment, not the clip.
      expect(s.canvasScale.baseValue, 1.0);
    });

    test('the playhead between diamonds places one first', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      n.updatePlaybackPosition(10.0);
      n.addKeyframeAtPlayhead();

      n.updatePlaybackPosition(5.0); // halfway, nowhere near a diamond
      n.setClipProperty(ClipProperty.volume, 0.2);

      final s = only(n);
      expect(keyframeProgresses(s).length, 3);
      // Every property gained the new instant, not just the one edited.
      for (final p in ClipProperty.values) {
        expect(clipParameter(s, p).keyframes.length, 3, reason: p.name);
      }
      expect(s.volumeAt(0.5), closeTo(0.2, 1e-9));
    });

    test('placing a diamond changes nothing the renderer resolves', () {
      final n = notifierWith([
        clip('a').copyWith(canvasScale: const AnimatableDouble(baseValue: 1.7)),
      ], selectedSegmentId: 'a', position: 4.0);

      final before = only(n);
      n.addKeyframeAtPlayhead();
      final after = only(n);

      for (final t in [0.0, 0.25, 0.4, 0.75, 1.0]) {
        for (final p in ClipProperty.values) {
          expect(clipParameter(after, p).resolveAt(t),
              closeTo(clipParameter(before, p).resolveAt(t), 1e-9),
              reason: '${p.name} @ $t');
        }
      }
    });

    test('the transform gesture keyframes itself on a keyframed clip', () {
      // The gesture has no idea keyframes exist — that is the point of routing
      // every control through one rule.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      n.updatePlaybackPosition(10.0);
      n.addKeyframeAtPlayhead();

      n.beginClipCanvasTransform();
      n.updateClipCanvasTransform(scale: 2.5, offsetX: 0.0, offsetY: 0.0);
      n.endClipCanvasTransform();

      final s = only(n);
      expect(s.canvasScale.keyframes.last.value, 2.5);
      expect(s.canvasScaleAt(0.0), 1.0);
      expect(s.canvasScaleAt(1.0), 2.5);
    });
  });

  group('the playhead decides which diamond', () {
    test('within the tolerance counts as on it, outside does not', () {
      // A 10s clip: kKeyframeHitSeconds (0.05s) is progress 0.005.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a',
          position: 5.0);
      n.addKeyframeAtPlayhead();

      n.updatePlaybackPosition(5.03);
      expect(n.state.playheadIsOnKeyframe, isTrue);

      n.updatePlaybackPosition(5.2);
      expect(n.state.playheadIsOnKeyframe, isFalse);
    });

    test('the tolerance is seconds, so a short clip is not more forgiving', () {
      // The same 0.05s on a 1s clip is progress 0.05 — twenty times the window
      // it is on a 20s clip. A fixed *progress* tolerance would make diamonds
      // unhittable on long clips and impossible to step off on short ones.
      final short = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 1);
      final n = notifierWith([short], selectedSegmentId: 'a', position: 0.5);
      n.addKeyframeAtPlayhead();

      n.updatePlaybackPosition(0.53);
      expect(n.state.playheadIsOnKeyframe, isTrue);
      n.updatePlaybackPosition(0.7);
      expect(n.state.playheadIsOnKeyframe, isFalse);
    });

    test('with no clip selected there is no keyframe clip', () {
      final n = notifierWith([clip('a')]);
      expect(n.state.keyframeClipId, isNull);
      expect(n.state.playheadIsOnKeyframe, isFalse);
      expect(n.state.selectedClipKeyframes, isEmpty);
    });

    test('seeking to a keyframe puts the playhead exactly on it', () {
      final n = notifierWith([
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4),
        VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 8),
      ], selectedSegmentId: 'b');

      n.seekToKeyframe(0.25);
      // Clip b starts at 4.0s and runs 8s: a quarter in is 6.0s.
      expect(n.state.currentPlaybackPosition, closeTo(6.0, 1e-9));
      expect(n.state.selectedClipProgress, closeTo(0.25, 1e-9));
    });
  });

  group('removing and easing', () {
    test('removing the last diamond keeps the picture', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a',
          position: 5.0);
      n.addKeyframeAtPlayhead();
      n.setClipProperty(ClipProperty.canvasScale, 2.4);

      n.removeKeyframeAtPlayhead();

      final s = only(n);
      expect(s.hasKeyframes, isFalse);
      // The value the user was looking at is the one that stays.
      expect(s.canvasScale.baseValue, 2.4);
      expect(s.canvasScaleAt(0.1), 2.4);
    });

    test('the easing sheet writes the diamond under the playhead', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      n.updatePlaybackPosition(10.0);
      n.addKeyframeAtPlayhead();

      n.updatePlaybackPosition(0.0);
      n.setKeyframeEasingAtPlayhead(KeyframeInterpolation.bounceOut);

      final s = only(n);
      for (final p in ClipProperty.values) {
        final ks = clipParameter(s, p).keyframes;
        expect(ks.first.interpolation, KeyframeInterpolation.bounceOut,
            reason: p.name);
        expect(ks.last.interpolation, KeyframeInterpolation.linear,
            reason: p.name);
      }
      expect(n.state.playheadKeyframeEasing, KeyframeInterpolation.bounceOut);
    });

    test('choosing an easing between diamonds places one, like the sliders do',
        () {
      // The sheet and the sliders must agree about what "here" means, or the
      // two controls would disagree about which instant the user is on.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a',
          position: 3.0);
      n.setKeyframeEasingAtPlayhead(KeyframeInterpolation.quadIn);

      final s = only(n);
      expect(keyframeProgresses(s), hasLength(1));
      expect(clipParameter(s, ClipProperty.volume).keyframes.single.interpolation,
          KeyframeInterpolation.quadIn);
    });

    test('retuning a value keeps the easing the keyframe already carried', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a',
          position: 5.0);
      n.addKeyframeAtPlayhead();
      n.setKeyframeEasingAtPlayhead(KeyframeInterpolation.bounceOut);
      n.setClipProperty(ClipProperty.canvasScale, 2.0);

      // The slider moved the value; it must not silently straighten the curve.
      expect(
        clipParameter(only(n), ClipProperty.canvasScale)
            .keyframes
            .single
            .interpolation,
        KeyframeInterpolation.bounceOut,
      );
    });
  });

  group('undo', () {
    test('a whole gesture is one undo step even when it keyframes', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      n.updatePlaybackPosition(10.0);
      n.addKeyframeAtPlayhead();

      final beforeGesture = only(n).canvasScale;
      n.beginClipCanvasTransform();
      for (final scale in [1.5, 2.0, 2.5, 3.0]) {
        n.updateClipCanvasTransform(scale: scale, offsetX: 0, offsetY: 0);
      }
      n.endClipCanvasTransform();
      expect(only(n).canvasScaleAt(1.0), 3.0);

      n.undo();
      // One step back is the whole drag, not a frame of it.
      expect(only(n).canvasScale, beforeGesture);
    });

    test('placing a diamond is undoable', () {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      expect(only(n).hasKeyframes, isTrue);
      n.undo();
      expect(only(n).hasKeyframes, isFalse);
    });
  });

  group('ownership', () {
    test('clearing the effect leaves transform keyframes alone', () {
      // **Keyframes are the clip's, not the effect's.** The rejected design
      // took them down with the effect, which is the confusion of ownership
      // this rebuild exists to fix.
      final n = notifierWith([
        clip('a').copyWith(effectId: 'vignette'),
      ], selectedSegmentId: 'a', position: 5.0);
      n.addKeyframeAtPlayhead();
      n.setClipProperty(ClipProperty.canvasScale, 2.0);

      n.setClipEffect(null);

      final s = only(n);
      expect(s.effectId, isNull);
      expect(s.canvasScale.keyframes, isNotEmpty);
      expect(s.canvasScaleAt(0.5), 2.0);
    });
  });
}

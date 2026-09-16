import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  VideoSegment seg({double scale = 1.0, double volume = 1.0}) => VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 10,
        canvasScale: AnimatableDouble(baseValue: scale),
        volume: AnimatableDouble(baseValue: volume),
      );

  group('clip keyframes', () {
    test('a fresh clip has no diamonds', () {
      expect(keyframeProgresses(seg()), isEmpty);
    });

    test('capturing pins every property at its resolved value', () {
      final s = captureKeyframe(seg(scale: 1.6, volume: 0.4), 0.5);

      for (final p in ClipProperty.values) {
        final param = clipParameter(s, p);
        expect(param.keyframes.length, 1, reason: p.name);
        expect(param.keyframes.single.progress, 0.5, reason: p.name);
        expect(param.keyframes.single.value, param.baseValue, reason: p.name);
        expect(param.keyframes.single.interpolation,
            KeyframeInterpolation.linear,
            reason: p.name);
      }
      // One diamond, not five — the union collapses the shared instant.
      expect(keyframeProgresses(s), [0.5]);
    });

    test('capturing does not change what the clip resolves to anywhere', () {
      // **The property a future refactor would silently break.** Placing a
      // diamond marks a moment; it must not move the picture.
      final before = seg(scale: 1.6, volume: 0.4);
      final after = captureKeyframe(before, 0.5);
      for (final t in [0.0, 0.2, 0.5, 0.8, 1.0]) {
        for (final p in ClipProperty.values) {
          expect(clipParameter(after, p).resolveAt(t),
              closeTo(clipParameter(before, p).resolveAt(t), 1e-9),
              reason: '${p.name} @ $t');
        }
      }
    });

    test('capturing on an already-animated clip follows the existing curve', () {
      var s = seg();
      s = withClipParameter(
          s,
          ClipProperty.canvasScale,
          const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(progress: 0.0, value: 1.0),
            Keyframe(progress: 1.0, value: 3.0),
          ]));
      final captured = captureKeyframe(s, 0.5);

      // Linear between 1 and 3: the new diamond lands on the curve rather than
      // on the base, so the move is unbroken.
      expect(clipParameter(captured, ClipProperty.canvasScale).resolveAt(0.5),
          closeTo(2.0, 1e-9));
      expect(keyframeProgresses(captured), [0.0, 0.5, 1.0]);
    });

    test('capturing twice at one instant replaces rather than duplicates', () {
      final once = captureKeyframe(seg(), 0.5);
      final twice = captureKeyframe(once, 0.5);
      expect(keyframeProgresses(twice), [0.5]);
      for (final p in ClipProperty.values) {
        expect(clipParameter(twice, p).keyframes.length, 1, reason: p.name);
      }
    });

    test('an envelope survives capturing, though keyframes now win', () {
      // The envelope is not destroyed by keyframing — removing the last diamond
      // has to hand the clip back to it.
      var s = withClipParameter(seg(), ClipProperty.effectIntensity,
          const AnimatableDouble(baseValue: 0.8, envelope: 'throb'));
      s = captureKeyframe(s, 0.5);
      expect(clipParameter(s, ClipProperty.effectIntensity).envelope, 'throb');
    });

    test('the diamond set is the union, so a half-written draft still shows them',
        () {
      var s = seg();
      s = withClipParameter(
          s,
          ClipProperty.volume,
          const AnimatableDouble(
              baseValue: 1.0,
              keyframes: [Keyframe(progress: 0.25, value: 0.5)]));
      s = withClipParameter(
          s,
          ClipProperty.canvasScale,
          const AnimatableDouble(
              baseValue: 1.0,
              keyframes: [Keyframe(progress: 0.75, value: 2.0)]));
      expect(keyframeProgresses(s), [0.25, 0.75]);
    });

    test('the hit test finds a diamond within tolerance and rejects outside it',
        () {
      final s = captureKeyframe(seg(), 0.5);
      expect(keyframeProgressNear(s, 0.503, 0.01), 0.5);
      expect(keyframeProgressNear(s, 0.6, 0.01), isNull);
    });

    test('the hit test returns the nearest when two are in range', () {
      var s = captureKeyframe(seg(), 0.50);
      s = captureKeyframe(s, 0.52);
      expect(keyframeProgressNear(s, 0.519, 0.05), 0.52);
      expect(keyframeProgressNear(s, 0.505, 0.05), 0.50);
    });

    test('removing takes the diamond off every property', () {
      var s = captureKeyframe(seg(), 0.25);
      s = captureKeyframe(s, 0.75);
      s = removeKeyframe(s, 0.25, 0.01);

      expect(keyframeProgresses(s), [0.75]);
      for (final p in ClipProperty.values) {
        expect(clipParameter(s, p).keyframes.length, 1, reason: p.name);
      }
    });

    test('removing the last diamond keeps the picture', () {
      var s = seg();
      s = withClipParameter(
          s,
          ClipProperty.canvasScale,
          const AnimatableDouble(
              baseValue: 1.0,
              keyframes: [Keyframe(progress: 0.5, value: 2.4)]));

      final cleared = removeKeyframe(s, 0.5, 0.01);
      expect(keyframeProgresses(cleared), isEmpty);
      // The value the user was looking at becomes the base, rather than the
      // clip snapping back to a scale set minutes ago.
      expect(clipParameter(cleared, ClipProperty.canvasScale).baseValue, 2.4);
      expect(clipParameter(cleared, ClipProperty.canvasScale).resolveAt(0.3),
          2.4);
    });

    test('removing a non-final diamond leaves the base alone', () {
      var s = captureKeyframe(seg(scale: 1.0), 0.25);
      s = captureKeyframe(s, 0.75);
      final after = removeKeyframe(s, 0.25, 0.01);
      expect(clipParameter(after, ClipProperty.canvasScale).baseValue, 1.0);
    });

    test('removing a diamond that is not there changes nothing', () {
      final s = captureKeyframe(seg(), 0.5);
      expect(removeKeyframe(s, 0.1, 0.01), s);
    });

    test('easing is written to every property at that instant only', () {
      var s = captureKeyframe(seg(), 0.25);
      s = captureKeyframe(s, 0.75);
      s = setKeyframeEasing(s, 0.25, 0.01, KeyframeInterpolation.bounceOut);

      for (final p in ClipProperty.values) {
        final ks = clipParameter(s, p).keyframes;
        expect(ks.firstWhere((k) => k.progress == 0.25).interpolation,
            KeyframeInterpolation.bounceOut,
            reason: p.name);
        expect(ks.firstWhere((k) => k.progress == 0.75).interpolation,
            KeyframeInterpolation.linear,
            reason: p.name);
      }
    });

    test('easing a diamond that is not there changes nothing', () {
      final s = captureKeyframe(seg(), 0.5);
      expect(setKeyframeEasing(s, 0.1, 0.01, KeyframeInterpolation.quadIn), s);
    });

    test('easing keeps every value where it was', () {
      var s = seg();
      s = withClipParameter(
          s,
          ClipProperty.canvasScale,
          const AnimatableDouble(baseValue: 1.0, keyframes: [
            Keyframe(progress: 0.0, value: 1.0),
            Keyframe(progress: 1.0, value: 3.0),
          ]));
      final eased =
          setKeyframeEasing(s, 0.0, 0.01, KeyframeInterpolation.quadIn);

      // The curve between them changed; the points themselves did not.
      final ks = clipParameter(eased, ClipProperty.canvasScale).keyframes;
      expect(ks.map((k) => k.value).toList(), [1.0, 3.0]);
      expect(eased.canvasScaleAt(0.5), closeTo(1.5, 1e-9)); // quadIn(0.5)=0.25
    });

    test('every property is reachable through the accessors', () {
      // The switch statements are the only thing that has to be kept in step
      // with the enum, and a missed case would silently exclude a property from
      // every diamond.
      var s = seg();
      for (final p in ClipProperty.values) {
        s = withClipParameter(
            s, p, const AnimatableDouble(baseValue: 0.375));
        expect(clipParameter(s, p).baseValue, 0.375, reason: p.name);
      }
    });
  });

  group('the curve target — which segment the curve icon edits', () {
    // Sorted diamonds k0 < k1 < ...; the flag lives on the keyframe a segment
    // *starts* at. The icon edits the segment the playhead is inside, so it
    // must be inert wherever there is no travel to shape.
    VideoSegment twoDiamonds() {
      var s = captureKeyframe(seg(), 0.25);
      s = captureKeyframe(s, 0.75);
      return s;
    }

    test('no diamonds, no target', () {
      expect(keyframeCurveTarget(seg(), 0.5, 0.01), isNull);
    });

    test('one diamond alone has no segment, so no target anywhere', () {
      // A curve needs two points to run between. With one, the value holds on
      // both sides and a curve would change nothing — a control that lies.
      final s = captureKeyframe(seg(), 0.5);
      expect(keyframeCurveTarget(s, 0.2, 0.01), isNull);
      expect(keyframeCurveTarget(s, 0.5, 0.01), isNull);
      expect(keyframeCurveTarget(s, 0.8, 0.01), isNull);
    });

    test('between two diamonds the target is the one the segment starts at',
        () {
      expect(keyframeCurveTarget(twoDiamonds(), 0.5, 0.01), 0.25);
    });

    test('before the first diamond there is nothing to ease', () {
      expect(keyframeCurveTarget(twoDiamonds(), 0.1, 0.01), isNull);
    });

    test('after the last diamond there is nothing to ease', () {
      expect(keyframeCurveTarget(twoDiamonds(), 0.9, 0.01), isNull);
    });

    test('on the last diamond the target is the segment arriving at it', () {
      // The screenshot case: the playhead parked on the second diamond, the
      // sheet open, editing the curve the value travelled to get there.
      expect(keyframeCurveTarget(twoDiamonds(), 0.75, 0.01), 0.25);
    });

    test('on the first diamond the target is the segment leaving it', () {
      // Nothing arrives at the first diamond, so the only curve near the
      // playhead is the one leaving. Better than an inert icon on a diamond
      // the user just tapped.
      expect(keyframeCurveTarget(twoDiamonds(), 0.25, 0.01), 0.25);
    });

    test('on a middle diamond the outgoing segment wins', () {
      // Only the *last* diamond falls back to the segment arriving at it,
      // because nothing follows it. Anywhere else there is travel in both
      // directions, and the diamond's own flag is the one controlling the
      // segment that leaves it — so that is what the icon edits.
      var s = twoDiamonds();
      s = captureKeyframe(s, 0.5);
      expect(keyframeCurveTarget(s, 0.5, 0.01), 0.5);
    });

    test('within tolerance of a diamond counts as on it', () {
      expect(keyframeCurveTarget(twoDiamonds(), 0.753, 0.01), 0.25);
    });
  });

  group('setting a curve', () {
    test('writes the target segment on every property', () {
      var s = captureKeyframe(seg(), 0.25);
      s = captureKeyframe(s, 0.75);
      s = setKeyframeCurve(s, 0.5, 0.01, KeyframeInterpolation.bounceOut);

      for (final p in ClipProperty.values) {
        final ks = clipParameter(s, p).keyframes;
        expect(ks.first.interpolation, KeyframeInterpolation.bounceOut,
            reason: p.name);
        expect(ks.last.interpolation, KeyframeInterpolation.linear,
            reason: p.name);
      }
    });

    test('never places a diamond', () {
      // The curve icon shapes travel that already exists. The plus button is
      // the one control that creates instants; a curve picker that quietly
      // added one was the device-reported fault.
      final one = captureKeyframe(seg(), 0.5);
      final after = setKeyframeCurve(one, 0.2, 0.01, KeyframeInterpolation.quadIn);
      expect(after, one);
      expect(keyframeProgresses(after), [0.5]);
    });

    test('with no target it changes nothing', () {
      var s = captureKeyframe(seg(), 0.25);
      s = captureKeyframe(s, 0.75);
      expect(setKeyframeCurve(s, 0.9, 0.01, KeyframeInterpolation.quadIn), s);
    });
  });
}

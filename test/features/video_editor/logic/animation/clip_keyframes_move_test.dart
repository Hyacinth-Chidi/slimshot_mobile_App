import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

/// Moving a diamond: every property's keyframe at one instant slides to
/// another, keeping its value and its curve.
///
/// A diamond is an instant of the clip, so the move is of the instant — the
/// seven properties' keyframes at it travel together, or the filmstrip's one
/// mark would stop being an honest picture of the clip's state.
void main() {
  VideoSegment clip() => VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10);

  /// Diamonds at 0.2 and 0.6; scale keyframed 1→2 across them with a bounce.
  VideoSegment two() {
    var s = captureKeyframe(clip(), 0.2);
    s = captureKeyframe(s, 0.6);
    return withClipParameter(
      s,
      ClipProperty.canvasScale,
      const AnimatableDouble(baseValue: 1.0, keyframes: [
        Keyframe(progress: 0.2, value: 1.0, interpolation: KeyframeInterpolation.bounceOut),
        Keyframe(progress: 0.6, value: 2.0),
      ]),
    );
  }

  test('moves the instant on every property, value and curve intact', () {
    final moved = moveKeyframe(two(), 0.2, 0.35, 0.01);
    expect(keyframeProgresses(moved), [closeTo(0.35, 1e-9), closeTo(0.6, 1e-9)]);
    for (final p in ClipProperty.values) {
      final ks = clipParameter(moved, p).keyframes;
      expect(ks.map((k) => k.progress), [closeTo(0.35, 1e-9), closeTo(0.6, 1e-9)],
          reason: '$p');
    }
    final scale = clipParameter(moved, ClipProperty.canvasScale).keyframes;
    expect(scale.first.value, 1.0);
    expect(scale.first.interpolation, KeyframeInterpolation.bounceOut);
  });

  test('stays sorted when a diamond is dragged past its neighbour', () {
    final moved = moveKeyframe(two(), 0.2, 0.8, 0.01);
    expect(keyframeProgresses(moved), [closeTo(0.6, 1e-9), closeTo(0.8, 1e-9)]);
    // The moved one carries its own value with it; the neighbour keeps its own.
    final scale = clipParameter(moved, ClipProperty.canvasScale).keyframes;
    expect(scale.map((k) => k.value), [2.0, 1.0]);
  });

  test('clamps to the clip', () {
    expect(keyframeProgresses(moveKeyframe(two(), 0.6, 1.4, 0.01)),
        [closeTo(0.2, 1e-9), closeTo(1.0, 1e-9)]);
    expect(keyframeProgresses(moveKeyframe(two(), 0.2, -0.3, 0.01)),
        [closeTo(0.0, 1e-9), closeTo(0.6, 1e-9)]);
  });

  test('refuses to land on another diamond, so two never collapse into one',
      () {
    final s = two();
    final refused = moveKeyframe(s, 0.2, 0.6, 0.01);
    expect(identical(refused, s), isTrue);
    expect(identical(moveKeyframe(s, 0.2, 0.6 + kKeyframeMatchProgress / 2, 0.01), s),
        isTrue);
  });

  test('with no diamond near the origin, nothing happens', () {
    final s = two();
    expect(identical(moveKeyframe(s, 0.4, 0.5, 0.01), s), isTrue);
  });

  test('a move to where it already is is a no-op', () {
    final s = two();
    expect(identical(moveKeyframe(s, 0.2, 0.2, 0.01), s), isTrue);
  });
}

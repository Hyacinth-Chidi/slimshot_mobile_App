import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_stack.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';

/// Which effect bars are drawn at an instant, in what order, at what strength
/// and at what point in their animation. The Kotlin `EffectStack` follows the
/// same rule, pinned through `effect_stack_fixture.json`.
void main() {
  EffectBarModel bar(
    String id,
    String effect,
    double start,
    double end, {
    int lane = 0,
    AnimatableDouble intensity = const AnimatableDouble(baseValue: 0.7),
  }) =>
      EffectBarModel(
        id: id,
        effectId: effect,
        start: start,
        end: end,
        laneIndex: lane,
        intensity: intensity,
      );

  List<String> drawn(List<EffectBarModel> bars, double t) =>
      [for (final a in effectBarsDrawnAt(bars, t)) a.bar.id];

  test('bars under the instant draw in lane order', () {
    final bars = [bar('high', 'grain', 0, 5, lane: 2), bar('low', 'vignette', 0, 5)];
    expect(drawn(bars, 2), ['low', 'high']);
  });

  test('a bar is not drawn at its own end, so neighbours never double', () {
    final bars = [bar('a', 'grain', 0, 2), bar('b', 'vignette', 2, 4)];
    expect(drawn(bars, 2), ['b']);
    expect(drawn(bars, 1.999), ['a']);
    expect(drawn(bars, 4), isEmpty);
  });

  test('a bar that does not fit the budget is skipped whole', () {
    // Glow is the whole budget: nothing else fits beside it.
    expect(drawn([bar('g', 'glow', 0, 5), bar('v', 'vignette', 0, 5, lane: 1)], 1),
        ['g']);
  });

  test('a skipped bar does not stop a later one that fits', () {
    final bars = [
      bar('b', 'blur', 0, 5),
      bar('g', 'glow', 0, 5, lane: 1),
      bar('v', 'vignette', 0, 5, lane: 2),
    ];
    expect(drawn(bars, 1), ['b', 'v']);
  });

  test('an effect this build does not know is not drawn and costs nothing', () {
    final bars = [
      bar('x', 'from_the_future', 0, 5),
      bar('g', 'glow', 0, 5, lane: 1),
    ];
    expect(drawn(bars, 1), ['g']);
  });

  test('intensity resolves at the bar\'s own progress', () {
    final b = bar('k', 'vignette', 4, 8,
        intensity: const AnimatableDouble(baseValue: 0.5, keyframes: [
          Keyframe(progress: 0, value: 0),
          Keyframe(progress: 1, value: 1),
        ]));
    expect(effectBarsDrawnAt([b], 6).single.intensity, closeTo(0.5, 1e-9));
  });

  test('an envelope runs across the bar', () {
    const shaped = AnimatableDouble(baseValue: 0.8, envelope: 'ramp_out');
    final b = bar('e', 'blur', 2, 6, intensity: shaped);
    expect(effectBarsDrawnAt([b], 3).single.intensity,
        closeTo(shaped.resolveAt(0.25).clamp(0, 1), 1e-9));
  });

  test('a timed effect plays its intro from the bar\'s start and rests at 1', () {
    // cinema_zoom's intro is 1.2s.
    final b = bar('z', 'cinema_zoom', 10, 20);
    expect(effectBarShaderProgressAt(b, 10.6), closeTo(0.5, 1e-9));
    expect(effectBarShaderProgressAt(b, 15), 1.0);
  });

  test('a keyframed intro: the strength runs on the bar, the picture on the intro',
      () {
    // The mismatch this ends: the strength used to be read at the intro's
    // clock while the diamonds were placed on the clip's.
    final b = bar('z', 'cinema_zoom', 0, 10,
        intensity: const AnimatableDouble(baseValue: 0.5, keyframes: [
          Keyframe(progress: 0, value: 0),
          Keyframe(progress: 1, value: 1),
        ]));
    final active = effectBarsDrawnAt([b], 0.6).single;
    expect(active.progress, closeTo(0.5, 1e-9));
    expect(active.intensity, closeTo(0.06, 1e-9));
  });

  test('a static effect\'s shader clock is the whole bar', () {
    expect(effectBarShaderProgressAt(bar('v', 'vignette', 2, 6), 3), closeTo(0.25, 1e-9));
  });

  test('a zero-length bar is already over, never a division by zero', () {
    final b = bar('0', 'vignette', 3, 3);
    expect(effectBarProgressAt(b, 3), 1.0);
    expect(effectBarShaderProgressAt(b, 3), 1.0);
  });

  test('intensity is clamped to what a shader expects', () {
    final b = bar('k', 'vignette', 0, 4,
        intensity: const AnimatableDouble(baseValue: 1.7));
    expect(effectBarsDrawnAt([b], 1).single.intensity, 1.0);
  });

  group('skipping', () {
    test('a bar the budget skips somewhere is named', () {
      final bars = [bar('b', 'blur', 0, 5), bar('g', 'glow', 3, 8, lane: 1)];
      expect(skippedEffectBarIds(bars), {'g'});
    });

    test('a newly skipped bar is reported once, an old one never again', () {
      final before = [bar('b', 'blur', 0, 5)];
      final after = [...before, bar('g', 'glow', 3, 8, lane: 1)];
      expect(newlySkippedEffectBar(before, after)?.id, 'g');
      final later = [for (final b in after) b.id == 'b' ? b.copyWith(end: 6) : b];
      expect(newlySkippedEffectBar(after, later), isNull);
    });
  });
}

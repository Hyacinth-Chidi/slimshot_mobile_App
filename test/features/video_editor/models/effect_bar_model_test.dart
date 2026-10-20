import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

/// An effect bar: an effect over a stretch of the timeline, on a lane.
void main() {
  const keyframed = AnimatableDouble(
    baseValue: 0.6,
    keyframes: [
      Keyframe(progress: 0, value: 0.2),
      Keyframe(progress: 1, value: 0.9),
    ],
  );

  test('round-trips through JSON, a keyframed intensity included', () {
    const bar = EffectBarModel(
      id: 'e1',
      effectId: 'blur',
      start: 2,
      end: 5.5,
      laneIndex: 3,
      intensity: keyframed,
    );
    final back = EffectBarModel.fromJson(bar.toJson());
    expect(back.id, 'e1');
    expect(back.effectId, 'blur');
    expect(back.start, 2);
    expect(back.end, 5.5);
    expect(back.laneIndex, 3);
    expect(back.intensity, keyframed);
    expect(back.duration, 3.5);
  });

  test('keeps an effect id this build does not know, as written', () {
    final back = EffectBarModel.fromJson(const {
      'id': 'e',
      'effectId': 'from_a_newer_build',
      'start': 0,
      'end': 1,
    });
    expect(back.effectId, 'from_a_newer_build');
  });

  group('a hand-edited draft never throws and never yields a broken bar', () {
    void expectSane(EffectBarModel bar) {
      expect(bar.start.isFinite, isTrue);
      expect(bar.start, greaterThanOrEqualTo(0));
      expect(bar.end.isFinite, isTrue);
      expect(bar.end - bar.start,
          greaterThanOrEqualTo(kMinClipDurationSeconds - 1e-9));
    }

    test('an end before its start', () {
      expectSane(EffectBarModel.fromJson(
          const {'id': 'e', 'effectId': 'blur', 'start': 4, 'end': 2}));
    });

    test('a negative or missing start', () {
      expectSane(EffectBarModel.fromJson(
          const {'id': 'e', 'effectId': 'blur', 'start': -3, 'end': 2}));
      expectSane(EffectBarModel.fromJson(const {'id': 'e', 'effectId': 'blur'}));
    });

    test('NaN', () {
      expectSane(EffectBarModel.fromJson(
          {'id': 'e', 'effectId': 'blur', 'start': double.nan, 'end': double.nan}));
    });

    test('mistyped fields', () {
      final bar = EffectBarModel.fromJson(const {
        'id': 7,
        'effectId': ['blur'],
        'start': '2',
        'end': true,
        'laneIndex': 'x',
        'intensity': 'loud',
      });
      expectSane(bar);
      expect(bar.laneIndex, 0);
      expect(bar.intensity.baseValue.isFinite, isTrue);
    });
  });

  test('copyWith changes only what it is given', () {
    const bar = EffectBarModel(id: 'e', effectId: 'blur', start: 1, end: 4);
    final moved = bar.copyWith(start: 2, end: 5, laneIndex: 1);
    expect((moved.id, moved.effectId, moved.start, moved.end, moved.laneIndex),
        ('e', 'blur', 2.0, 5.0, 1));
    expect(moved.intensity, bar.intensity);
  });
}

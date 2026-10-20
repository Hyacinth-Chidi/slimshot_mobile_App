import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A selected bar is a keyframe target: its intensity takes the same
/// diamonds, plus button, easing and edit rule as a clip's or an overlay's.
void main() {
  VideoEditorNotifier notifier(
    EffectBarModel bar, {
    double playhead = 2,
    bool playing = false,
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [
            MediaAsset(
              id: 'asset',
              path: '/v.mp4',
              type: MediaAssetType.video,
              durationSeconds: 60,
              width: 1920,
              height: 1080,
              hasAudio: true,
            ),
          ],
          segments: [
            VideoSegment(id: 'c', assetId: 'asset', sourceStart: 0, sourceEnd: 20),
          ],
          currentPlaybackPosition: playhead,
          isPlaying: playing,
          effectBars: [bar],
          selectedEffectBarId: bar.id,
          currentMenuId: 'effect_bar',
        );

  const flat = EffectBarModel(
    id: 'e',
    effectId: 'vignette',
    start: 2,
    end: 6,
    intensity: AnimatableDouble(baseValue: 0.5),
  );

  final keyed = flat.copyWith(
    intensity: const AnimatableDouble(baseValue: 0.5, keyframes: [
      Keyframe(progress: 0, value: 0),
      Keyframe(progress: 1, value: 1),
    ]),
  );

  EffectBarModel barOf(VideoEditorNotifier n) => n.state.effectBars.single;

  test('a selected bar is the keyframe target, on its own clock', () {
    final n = notifier(flat, playhead: 3);
    expect(n.state.hasKeyframeTarget, isTrue);
    expect(n.state.keyframeTargetProgress, closeTo(0.25, 1e-9));
    n.updatePlaybackPosition(9);
    expect(n.state.keyframeTargetProgress, isNull, reason: 'off the bar');
  });

  test('without diamonds the slider writes the base', () {
    final n = notifier(flat)
      ..beginEffectBarIntensityEdit()
      ..setEffectBarIntensityLive(0.3);
    expect(barOf(n).intensity.baseValue, 0.3);
    expect(barOf(n).intensity.keyframes, isEmpty);
    expect(n.state.effectBarEditIntensity, 0.3);
  });

  test('the plus places a diamond carrying the value there', () {
    final n = notifier(flat, playhead: 4)..addKeyframeAtPlayhead();
    expect(n.state.keyframeDiamonds, [closeTo(0.5, 1e-9)]);
    expect(barOf(n).intensity.keyframes.single.value, 0.5);
    expect(n.state.playheadIsOnKeyframe, isTrue);
    n.removeKeyframeAtPlayhead();
    expect(n.state.keyframeDiamonds, isEmpty);
  });

  test('between two diamonds a write places a third, then writes it', () {
    final n = notifier(keyed, playhead: 4)
      ..beginEffectBarIntensityEdit()
      ..setEffectBarIntensityLive(0.9);
    expect(n.state.keyframeDiamonds.length, 3);
    expect(n.state.effectBarEditIntensity, closeTo(0.9, 1e-9));
    expect(barOf(n).intensity.baseValue, 0.5, reason: 'the base is untouched');
  });

  test('the slider is held to 0..1 and ignores what is not a number', () {
    final n = notifier(flat)
      ..beginEffectBarIntensityEdit()
      ..setEffectBarIntensityLive(1.4);
    expect(barOf(n).intensity.baseValue, 1.0);
    n.setEffectBarIntensityLive(double.nan);
    expect(barOf(n).intensity.baseValue, 1.0);
  });

  test('a drag of the slider is one undo step', () {
    final n = notifier(flat)
      ..beginEffectBarIntensityEdit()
      ..setEffectBarIntensityLive(0.2)
      ..setEffectBarIntensityLive(0.3)
      ..setEffectBarIntensityLive(0.4);
    n.undo();
    expect(barOf(n).intensity.baseValue, 0.5);
    expect(n.state.canUndo, isFalse);
  });

  test('a drag starts by pausing, so a playing bar collects no trail', () {
    final n = notifier(flat, playing: true)..beginEffectBarIntensityEdit();
    expect(n.state.isPlaying, isFalse);
  });

  test('trimming a bar stretches its curve with it', () {
    final quarterKeyed = flat.copyWith(
      intensity: const AnimatableDouble(baseValue: 0.5, keyframes: [
        Keyframe(progress: 0.25, value: 0),
        Keyframe(progress: 0.75, value: 1),
      ]),
    );
    final n = notifier(quarterKeyed)..trimLaneItem('e', start: 2, end: 10);
    expect(n.state.keyframeDiamonds, [0.25, 0.75]);
  });

  test('the curve control edits the segment leaving the diamond', () {
    final n = notifier(keyed, playhead: 2)
      ..setKeyframeCurve(KeyframeInterpolation.cubicInOut);
    expect(n.state.keyframeCurve, KeyframeInterpolation.cubicInOut);
  });
}

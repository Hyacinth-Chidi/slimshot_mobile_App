import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

/// A video layer's volume track. Only a reaction's video layer carries one —
/// the owner's call: a video layer made in the editor keeps its five keyframe
/// properties, its Volume control and its payload exactly as they were.
void main() {
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 6);
  const five = {
    OverlayProperty.x,
    OverlayProperty.y,
    OverlayProperty.scale,
    OverlayProperty.rotation,
    OverlayProperty.opacity,
  };

  /// Every property pinned at each diamond (the diamond rule), the volume
  /// going down to a quarter in the middle and back up.
  OverlayKeyframes ducked() => const OverlayKeyframes({
        OverlayProperty.x: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.y: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.scale: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 1), Keyframe(progress: 1, value: 1)],
        OverlayProperty.rotation: [Keyframe(progress: 0, value: 0), Keyframe(progress: 0.5, value: 0), Keyframe(progress: 1, value: 0)],
        OverlayProperty.opacity: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 1), Keyframe(progress: 1, value: 1)],
        OverlayProperty.volume: [Keyframe(progress: 0, value: 1), Keyframe(progress: 0.5, value: 0.25), Keyframe(progress: 1, value: 1)],
      });

  VideoOverlayModel layer({OverlayKeyframes keyframes = OverlayKeyframes.none, double volume = 1}) => VideoOverlayModel(
        id: 'v',
        videoPath: '/v.mp4',
        timelineStart: start,
        timelineEnd: end,
        sourceStart: 0,
        sourceEnd: 20,
        volume: volume,
        keyframes: keyframes,
      );

  Map<String, dynamic> wire(VideoOverlayModel overlay) => jsonDecode(jsonEncode(const VideoEditorTimelineComposer()
      .composeOverlays(VideoEditorState(videoOverlays: [overlay]), previewCanvasSize: const Size(360, 640))
      .single
      .toJson())) as Map<String, dynamic>;

  group('a video layer made in the editor has no volume track, and nothing about it changes', () {
    test('its keyframe properties are the five it always had, keyframed or not', () {
      expect(layer().motion.params.keys.toSet(), five);
      const moving = OverlayKeyframes({
        OverlayProperty.x: [Keyframe(progress: 0, value: 0), Keyframe(progress: 1, value: 40)],
      });
      expect(layer(keyframes: moving).motion.params.keys.toSet(), five);
    });

    test('it sends its volume as the bare number it always did', () {
      expect(wire(layer(volume: 0.4))['volume'], 0.4);
    });
  });

  group("a layer with a volume track — a reaction's", () {
    test('volume is one of its properties, and comes back through its motion', () {
      final ducking = layer(keyframes: ducked());
      expect(ducking.motion.params.keys.toSet(), {...five, OverlayProperty.volume});
      expect(ducking.motion.params[OverlayProperty.volume]!.keyframes.map((k) => k.value), [1, 0.25, 1]);
      final back = ducking.withMotion(ducking.motion);
      expect(back.keyframes.toJson(), ducking.keyframes.toJson());
      expect(back.volume, ducking.volume);
    });

    test('what it plays at an instant is its track there', () {
      expect(layer(keyframes: ducked()).shownAt(4).volume, moreOrLessEquals(0.25));
      expect(layer(keyframes: ducked()).shownAt(3).volume, moreOrLessEquals(0.625));
      expect(layer(keyframes: ducked()).volume, 1, reason: 'the base is untouched');
    });

    test('its draft keeps the track', () {
      final back = VideoOverlayModel.fromJson(layer(keyframes: ducked()).toJson());
      expect(back.keyframes.of(OverlayProperty.volume).map((k) => k.value), [1, 0.25, 1]);
    });

    test('it sends the track to the engine', () {
      final volume = wire(layer(keyframes: ducked()))['volume'] as Map<String, dynamic>;
      expect(volume['baseValue'], 1);
      expect((volume['keyframes'] as List).map((k) => (k as Map)['value']), [1, 0.25, 1]);
    });

    test('with every diamond gone it is a plain layer again', () {
      final ducking = layer(keyframes: ducked(), volume: 0.8);
      final cleared = ducking.withMotion(ducking.motion.copyWithKeyframes(OverlayKeyframes.none));
      expect(cleared.motion.params.keys.toSet(), five);
      expect(cleared.volume, 0.8);
      expect(wire(cleared)['volume'], 0.8);
    });
  });
}

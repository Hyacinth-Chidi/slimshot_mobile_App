import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

/// Overlay keyframes on the wire to the engine.
///
/// An overlay's centre, scale, rotation and opacity travel as
/// `AnimatableDouble`s: a bare number while nothing is keyframed — the payload
/// every engine build has always read — and a keyframe map once something is.
void main() {
  const canvas = Size(360, 640);
  const composer = VideoEditorTimelineComposer();

  ImageOverlayModel photo({OverlayKeyframes keyframes = OverlayKeyframes.none}) =>
      ImageOverlayModel(
        id: 'i',
        imagePath: '/p.png',
        position: const Offset(30, -40),
        scale: 1.5,
        rotation: 0.3,
        opacity: 0.8,
        startTime: const Duration(seconds: 1),
        endTime: const Duration(seconds: 4),
        keyframes: keyframes,
      );

  VideoOverlayModel video({OverlayKeyframes keyframes = OverlayKeyframes.none}) =>
      VideoOverlayModel(
        id: 'v',
        videoPath: '/v.mp4',
        position: const Offset(-12.5, 60),
        scale: 0.75,
        rotation: -0.2,
        opacity: 0.6,
        timelineStart: const Duration(milliseconds: 500),
        timelineEnd: const Duration(milliseconds: 3500),
        sourceStart: 1,
        sourceEnd: 9,
        keyframes: keyframes,
      );

  TextOverlayModel text({
    Offset position = const Offset(250, -33.25),
    OverlayKeyframes keyframes = OverlayKeyframes.none,
  }) =>
      TextOverlayModel(
        id: 't',
        text: 'Hi',
        position: position,
        scale: 1.25,
        rotation: 0.15,
        referenceCanvasSize: const Size(300, 600),
        keyframes: keyframes,
      );

  /// Every property moving: x and y along a curve, the rest linearly. The
  /// values stay inside the canvas, where a text's placement clamp is the
  /// identity.
  const moving = OverlayKeyframes({
    OverlayProperty.x: [
      Keyframe(
        progress: 0,
        value: -20,
        interpolation: KeyframeInterpolation.cubicInOut,
      ),
      Keyframe(progress: 1, value: 90),
    ],
    OverlayProperty.y: [
      Keyframe(progress: 0.2, value: 10),
      Keyframe(progress: 0.9, value: -50),
    ],
    OverlayProperty.scale: [
      Keyframe(progress: 0, value: 1),
      Keyframe(progress: 1, value: 2.5),
    ],
    OverlayProperty.rotation: [
      Keyframe(progress: 0, value: 0),
      Keyframe(progress: 1, value: 1.2),
    ],
    OverlayProperty.opacity: [
      Keyframe(progress: 0, value: 1),
      Keyframe(progress: 0.5, value: 0.25),
    ],
  });

  const samples = [0.0, 0.1, 0.25, 0.5, 0.75, 1.0];

  group('an overlay with no keyframes sends exactly what it always did', () {
    // Captured from the composer at 854b50b, before overlay keyframes existed.
    test('photo and video', () {
      const golden =
          '[{"id":"i","kind":"image","path":"/p.png","centerX":0.5833333333333334,"centerY":0.4375,"boxWidth":0.5555555555555556,"boxHeight":0.3125,"scale":1.5,"rotation":0.3,"opacity":0.8,"startSeconds":1.0,"endSeconds":4.0,"laneIndex":0,"slideOffsetX":0.5555555555555556,"slideOffsetY":0.3125,"animationIn":null,"animationOut":null,"animationLoop":null,"animationInSeconds":0.5,"animationOutSeconds":0.5,"speedIn":1.0,"speedOut":1.0,"speedLoop":1.0,"sourceStart":0.0,"sourceEnd":0.0,"speed":1.0,"volume":1.0,"isMuted":false,"glyphs":null,"backgroundLeft":0.0,"backgroundTop":0.0,"backgroundRight":0.0,"backgroundBottom":0.0,"backgroundRadius":0.0},'
          '{"id":"v","kind":"video","path":"/v.mp4","centerX":0.4652777777777778,"centerY":0.59375,"boxWidth":0.6666666666666666,"boxHeight":0.375,"scale":0.75,"rotation":-0.2,"opacity":0.6,"startSeconds":0.5,"endSeconds":3.5,"laneIndex":0,"slideOffsetX":0.5555555555555556,"slideOffsetY":0.3125,"animationIn":null,"animationOut":null,"animationLoop":null,"animationInSeconds":0.5,"animationOutSeconds":0.5,"speedIn":1.0,"speedOut":1.0,"speedLoop":1.0,"sourceStart":1.0,"sourceEnd":9.0,"speed":1.0,"volume":1.0,"isMuted":false,"glyphs":null,"backgroundLeft":0.0,"backgroundTop":0.0,"backgroundRight":0.0,"backgroundBottom":0.0,"backgroundRadius":0.0}]';
      final state = VideoEditorState(
        imageOverlays: [photo()],
        videoOverlays: [video()],
      );
      final wire = composer
          .composeOverlays(state, previewCanvasSize: canvas)
          .map((o) => o.toJson())
          .toList();
      expect(jsonEncode(wire), golden);
    });

    test('text', () {
      // x sits past the canvas edge here, so the golden also pins the clamp.
      const golden =
          '{"centerX":1.0,"centerY":0.4445833333333333,"scale":1.25,"rotation":0.15}';
      final wire = textOverlayWirePlacement(text(), canvas);
      expect(
        jsonEncode({
          'centerX': wire.centerX.toJson(),
          'centerY': wire.centerY.toJson(),
          'scale': wire.scale.toJson(),
          'rotation': wire.rotation.toJson(),
        }),
        golden,
      );
    });
  });

  group('a keyframed overlay', () {
    for (final (kind, state, motionOf) in [
      (
        'photo',
        VideoEditorState(imageOverlays: [photo(keyframes: moving)]),
        (VideoEditorState s) => s.imageOverlays.single.motion,
      ),
      (
        'video',
        VideoEditorState(videoOverlays: [video(keyframes: moving)]),
        (VideoEditorState s) => s.videoOverlays.single.motion,
      ),
    ]) {
      test('$kind: every property is a track that resolves where the model '
          'does', () {
        final wire = composer
            .composeOverlays(state, previewCanvasSize: canvas)
            .single;
        final json = wire.toJson();
        for (final key in ['centerX', 'centerY', 'scale', 'rotation', 'opacity']) {
          expect(json[key], isA<Map>(), reason: key);
        }
        final motion = motionOf(state);
        for (final p in samples) {
          final shown = motion.at(p);
          expect(wire.centerX.resolveAt(p),
              closeTo(0.5 + shown.position.dx / canvas.width, 1e-12),
              reason: 'centerX at $p');
          expect(wire.centerY.resolveAt(p),
              closeTo(0.5 + shown.position.dy / canvas.height, 1e-12),
              reason: 'centerY at $p');
          expect(wire.scale.resolveAt(p), closeTo(shown.scale, 1e-12));
          expect(wire.rotation.resolveAt(p), closeTo(shown.rotation, 1e-12));
          expect(wire.opacity.resolveAt(p), closeTo(shown.opacity, 1e-12));
        }
      });
    }

    test('text: its centre goes through the layer\'s own placement', () {
      final t = text(position: const Offset(10, 5), keyframes: moving);
      final wire = textOverlayWirePlacement(t, canvas);
      for (final p in samples) {
        final shown = t.withMotion(t.motion.at(p));
        final centre =
            textOverlayCenter(shown, canvas, textOverlayRenderScale(shown, canvas));
        expect(wire.centerX.resolveAt(p),
            closeTo(centre.dx / canvas.width, 1e-12),
            reason: 'centerX at $p');
        expect(wire.centerY.resolveAt(p),
            closeTo(centre.dy / canvas.height, 1e-12),
            reason: 'centerY at $p');
        expect(wire.scale.resolveAt(p), closeTo(shown.scale, 1e-12));
        expect(wire.rotation.resolveAt(p), closeTo(shown.rotation, 1e-12));
        expect(wire.opacity.resolveAt(p), closeTo(shown.opacity, 1e-12));
      }
    });
  });

  test('a text sends its own opacity — it used to be a constant 1.0', () {
    final wire = textOverlayWirePlacement(text().copyWith(opacity: 0.4), canvas);
    expect(wire.opacity.toJson(), 0.4);
  });

  group('a text is rasterised at the largest scale it reaches', () {
    // The export draws text into a PNG at a density that folds in its scale;
    // drawn at the base while a keyframe zooms it to 2.5×, the end of the zoom
    // would be an upscaled, soft raster next to a crisp preview.
    test('the base when nothing is keyframed', () {
      expect(textOverlayPeakScale(text()), 1.25);
    });

    test('the track\'s highest point when scale is keyframed', () {
      expect(textOverlayPeakScale(text(keyframes: moving)), 2.5);
      // A track that never reaches the base: the base is not drawn at all.
      const shrinking = OverlayKeyframes({
        OverlayProperty.scale: [
          Keyframe(progress: 0, value: 0.5),
          Keyframe(progress: 1, value: 0.8),
        ],
      });
      expect(textOverlayPeakScale(text(keyframes: shrinking)), 0.8);
    });
  });

  group('mapAnimatable', () {
    test('maps the base and every keyframe, keeping each curve', () {
      final a = AnimatableDouble.sorted(baseValue: 2, keyframes: const [
        Keyframe(
          progress: 0.25,
          value: 10,
          interpolation: KeyframeInterpolation.cubicInOut,
        ),
        Keyframe(progress: 0.75, value: 30),
      ]);
      double f(double v) => 0.5 + v / 360;
      final m = mapAnimatable(a, f);
      expect(m.baseValue, f(2));
      expect(m.keyframes.first.interpolation, KeyframeInterpolation.cubicInOut);
      // Interpolation commutes with an affine map.
      for (final p in samples) {
        expect(m.resolveAt(p), closeTo(f(a.resolveAt(p)), 1e-12), reason: '$p');
      }
    });

    test('an unkeyframed parameter stays a bare number', () {
      final m = mapAnimatable(const AnimatableDouble(baseValue: 3), (v) => v * 2);
      expect(m.toJson(), 6.0);
    });
  });
}

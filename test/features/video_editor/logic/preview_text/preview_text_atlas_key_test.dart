import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_word.dart';
import 'package:slimshotai/features/video_editor/logic/preview_text/preview_text_atlas_key.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

/// A preview atlas is made again only when what it draws changes: moving,
/// retiming or animating a text is drawn by placing the atlas it has.
void main() {
  /// Every field set to something other than its default.
  final rich = TextOverlayModel(
    id: 'rich',
    text: 'Styled',
    color: const Color(0xFFFF0000),
    fontFamily: 'Oswald',
    backgroundColor: const Color(0x80000000),
    strokeColor: const Color(0xFF00FF00),
    strokeWidth: 3,
    shadowColor: const Color(0xFF0000FF),
    shadowBlurRadius: 12,
    shadowOpacity: 0.4,
    shadowDistance: 9,
    shadowAngle: 200,
    borderRadius: 7,
    backgroundPadding: 21,
    textAlign: 'left',
    fontSize: 150,
    position: const Offset(10, 20),
    scale: 2,
    rotation: 0.3,
    boxWidth: 180,
    startTime: const Duration(seconds: 1),
    endTime: const Duration(seconds: 3),
    inAnimation: 'typing',
    outAnimation: 'fade_out',
    loopAnimation: 'wave_loop',
    animationInDuration: 1.5,
    animationOutDuration: 1.5,
    loopSpeed: 2,
    laneIndex: 2,
    referenceCanvasSize: const Size(400, 700),
    opacity: 0.8,
    captionSetId: 's',
    captionWords: const [
      CaptionWord(textStart: 0, textEnd: 6, start: Duration.zero, end: Duration(milliseconds: 400)),
    ],
    highlight: const CaptionHighlight(style: CaptionHighlightStyle.pop),
  );

  const texture = Size(720, 1280);

  String keyOf(TextOverlayModel t, {Size textureSize = texture, bool fontReady = true}) =>
      previewTextAtlasKey(t, textureSize: textureSize, fontReady: fontReady);

  /// The serialised fields that change what the atlas looks like.
  final drawn = <String, TextOverlayModel>{
    'text': rich.copyWith(text: 'Other'),
    'color': rich.copyWith(color: const Color(0xFF00FFFF)),
    'fontFamily': rich.copyWith(fontFamily: 'Inter'),
    'backgroundColor': rich.copyWith(backgroundColor: const Color(0x40FFFFFF)),
    'strokeColor': rich.copyWith(strokeColor: const Color(0xFF111111)),
    'strokeWidth': rich.copyWith(strokeWidth: 1),
    'shadowColor': rich.copyWith(shadowColor: const Color(0xFF222222)),
    'shadowBlurRadius': rich.copyWith(shadowBlurRadius: 5),
    'shadowOpacity': rich.copyWith(shadowOpacity: 0.9),
    'shadowDistance': rich.copyWith(shadowDistance: 4),
    'shadowAngle': rich.copyWith(shadowAngle: 90),
    'borderRadius': rich.copyWith(borderRadius: 2),
    'backgroundPadding': rich.copyWith(backgroundPadding: 10),
    'textAlign': rich.copyWith(textAlign: 'right'),
    'fontSize': rich.copyWith(fontSize: 200),
    'boxWidth': rich.copyWith(boxWidth: 250),
    'refWidth': rich.copyWith(referenceCanvasSize: const Size(500, 700)),
    'refHeight': rich.copyWith(referenceCanvasSize: const Size(400, 900)),
    'highlight': rich.copyWith(
      highlight: const CaptionHighlight(style: CaptionHighlightStyle.karaoke),
    ),
    'captionWords': rich.copyWith(captionWords: const [
      CaptionWord(textStart: 0, textEnd: 3, start: Duration.zero, end: Duration(milliseconds: 400)),
    ]),
  };

  /// The serialised fields that only place, time or move the atlas.
  final placement = <String, TextOverlayModel?>{
    'id': rich.copyWith(id: 'other'),
    'positionX': rich.copyWith(position: const Offset(99, 20)),
    'positionY': rich.copyWith(position: const Offset(10, 99)),
    'rotation': rich.copyWith(rotation: 1.2),
    'opacity': rich.copyWith(opacity: 0.3),
    'startTimeMs': rich.copyWith(startTime: const Duration(seconds: 2)),
    'endTimeMs': rich.copyWith(endTime: const Duration(seconds: 5)),
    'laneIndex': rich.copyWith(laneIndex: 4),
    'inAnimation': rich.copyWith(inAnimation: 'fade_in'),
    'outAnimation': rich.copyWith(outAnimation: 'none'),
    'loopAnimation': rich.copyWith(loopAnimation: 'none'),
    'animationInDuration': rich.copyWith(animationInDuration: 2.5),
    'animationOutDuration': rich.copyWith(animationOutDuration: 0.7),
    'loopSpeed': rich.copyWith(loopSpeed: 1),
    'captionSetId': rich.copyWith(captionSetId: 'another set'),
    // Written as a constant; there is nothing to vary.
    'animationSchema': null,
  };

  /// The serialised fields that matter only through the scale the atlas is
  /// drawn at — see the quarter-step test.
  const density = {'scale', 'keyframes'};

  test('every field a text serialises affects its atlas, its density, or neither', () {
    final keys = rich.toJson().keys.toSet();
    final classified = {...drawn.keys, ...placement.keys, ...density};
    expect(keys.difference(classified), isEmpty, reason: 'classify the new field');
    expect(drawn.keys.toSet().intersection(placement.keys.toSet()), isEmpty);
    expect(drawn.keys.toSet().intersection(density), isEmpty);
    expect(placement.keys.toSet().intersection(density), isEmpty);
  });

  test('anything drawn changes the key', () {
    final base = keyOf(rich);
    for (final entry in drawn.entries) {
      expect(keyOf(entry.value), isNot(base), reason: entry.key);
    }
    expect(keyOf(rich, textureSize: const Size(1080, 1920)), isNot(base),
        reason: 'the texture sets the density');
    expect(keyOf(rich, fontReady: false), isNot(base),
        reason: 'the fallback face is another drawing');
  });

  test('placement, timing and animation leave the key alone', () {
    final base = keyOf(rich);
    for (final entry in placement.entries) {
      final variant = entry.value;
      if (variant == null) continue;
      expect(keyOf(variant), base, reason: entry.key);
    }
    final movedByKeyframe = rich.copyWith(
      keyframes: const OverlayKeyframes({
        OverlayProperty.x: [Keyframe(progress: 0, value: 5), Keyframe(progress: 1, value: 50)],
      }),
    );
    expect(keyOf(movedByKeyframe), base, reason: 'a position keyframe');
    final retimedWords = rich.copyWith(captionWords: const [
      CaptionWord(
        textStart: 0,
        textEnd: 6,
        start: Duration(milliseconds: 100),
        end: Duration(milliseconds: 900),
      ),
    ]);
    expect(keyOf(retimedWords), base, reason: 'word times are not drawn');
  });

  test('the canvas size is not part of the key', () {
    // The atlas is drawn at canvas × (texture / canvas): the texture's own
    // pixels. An equal text is the same key, with nothing else consulted.
    expect(keyOf(rich.copyWith()), keyOf(rich));
  });

  test('the scale is drawn in quarter steps, never below the text\'s own', () {
    double atScale(double s) => previewAtlasScale(rich.copyWith(scale: s));
    expect(atScale(1.0), 1.0);
    expect(atScale(1.05), closeTo(math.pow(2, 0.25), 1e-12));
    expect(atScale(1.18), closeTo(math.pow(2, 0.25), 1e-12));
    expect(atScale(2.0), closeTo(2.0, 1e-12));
    for (var i = 0; i < 50; i++) {
      final s = 0.2 + i * (5.8 / 49);
      final t = rich.copyWith(scale: s);
      expect(previewAtlasScale(t), greaterThanOrEqualTo(textOverlayPeakScale(t)),
          reason: 'scale $s');
    }

    expect(keyOf(rich.copyWith(scale: 1.05)), keyOf(rich.copyWith(scale: 1.18)));
    expect(keyOf(rich.copyWith(scale: 1.0)), isNot(keyOf(rich.copyWith(scale: 1.05))));

    // A keyframed zoom is drawn at its peak, exactly as a text resting there.
    final zooming = rich.copyWith(
      scale: 1,
      keyframes: const OverlayKeyframes({
        OverlayProperty.scale: [Keyframe(progress: 0, value: 1), Keyframe(progress: 1, value: 2)],
      }),
    );
    expect(keyOf(zooming), keyOf(rich.copyWith(scale: 2)));
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/logic/overlay_box_fit.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';

const _frame = Size(360, 640);

VideoOverlayModel _placed({Size? reference = _frame, OverlayKeyframes keyframes = OverlayKeyframes.none}) =>
    VideoOverlayModel(
      id: 'o',
      videoPath: '/v.mp4',
      position: const Offset(0, -160),
      scale: 2.4,
      keyframes: keyframes,
      referenceCanvasSize: reference,
    );

/// Where an overlay sits and how wide its box is, as shares of [canvas] —
/// what the composer sends the engine.
({double x, double y, double box}) _shares(VideoOverlayModel overlay, Size canvas) => (
      x: 0.5 + overlay.position.dx / canvas.width,
      y: 0.5 + overlay.position.dy / canvas.height,
      box: kVideoOverlayBoxPx * overlay.scale / canvas.width,
    );

void main() {
  test('an overlay placed in the editor is left as it is', () {
    final overlay = _placed(reference: null);
    expect(identical(fitOverlayToCanvas(overlay, const Size(300, 533)), overlay), isTrue);
  });

  test('on the editor\'s canvas it covers the same share of the frame it was placed on', () {
    const canvas = Size(270, 480);
    final placed = _placed();
    final fitted = fitOverlayToCanvas(placed, canvas);
    final before = _shares(placed, _frame);
    final after = _shares(fitted, canvas);
    expect(after.x, moreOrLessEquals(before.x));
    expect(after.y, moreOrLessEquals(before.y));
    expect(after.box, moreOrLessEquals(before.box));
    expect(fitted.referenceCanvasSize, isNull, reason: 'converted once: from now on it is the editor\'s');
  });

  test('a keyframed path moves with it', () {
    const keyframes = OverlayKeyframes({
      OverlayProperty.x: [Keyframe(progress: 0, value: 0), Keyframe(progress: 1, value: 90)],
      OverlayProperty.scale: [Keyframe(progress: 0, value: 1), Keyframe(progress: 1, value: 2)],
    });
    final fitted = fitOverlayToCanvas(_placed(keyframes: keyframes), const Size(180, 320));
    expect(fitted.keyframes.of(OverlayProperty.x).map((k) => k.value), [0, 45]);
    expect(fitted.keyframes.of(OverlayProperty.scale).map((k) => k.value), [0.5, 1]);
  });

  test('a photo overlay placed on the frame converts the same way', () {
    final photo = ImageOverlayModel(
      id: 'p',
      imagePath: '/p.jpg',
      position: const Offset(0, -160),
      scale: 2,
      referenceCanvasSize: _frame,
    );
    final fitted = fitImageOverlayToCanvas(photo, const Size(180, 320));
    expect(fitted.position, const Offset(0, -80));
    expect(fitted.scale, 1);
    expect(fitted.referenceCanvasSize, isNull);
    expect(ImageOverlayModel.fromJson(photo.toJson()).referenceCanvasSize, _frame);
    expect(ImageOverlayModel(id: 'q', imagePath: '/q.jpg').toJson().containsKey('refWidth'), isFalse);
  });

  test('a canvas not laid out yet leaves it for the real one', () {
    final placed = _placed();
    expect(fitOverlayToCanvas(placed, Size.zero).referenceCanvasSize, _frame);
  });

  test('the reference survives a draft, and an overlay without one writes nothing new', () {
    final back = VideoOverlayModel.fromJson(_placed().toJson());
    expect(back.referenceCanvasSize, _frame);
    final plain = _placed(reference: null).toJson();
    expect(plain.containsKey('refWidth'), isFalse);
    expect(VideoOverlayModel.fromJson(plain).referenceCanvasSize, isNull);
  });
}

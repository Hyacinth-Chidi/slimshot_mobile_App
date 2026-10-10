import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';

/// A Circle is a circle on the picture.
///
/// Device-reported: the circle came out an oval. A window is stored as
/// fractions of the picture's width and height, and the default is 60% of
/// each — two different lengths on any picture that is not square — so the
/// "circle" was stretched to the picture's shape, and a pinch, which scales
/// both sides alike, kept it stretched. Choosing Circle now sizes the window
/// round in pixels.
void main() {
  const tall = 1080 / 1920;
  const wide = 1920 / 1080;

  /// The coverage a pixel-equal step from the centre gets, across and down:
  /// on a round window the two are the same.
  (double, double) acrossAndDown(ClipMask m, double aspect, double step) => (
        // [step] in units of the picture's height; across, that is step/aspect
        // of the picture's width.
        maskCoverage(m, m.centerX + step / aspect, m.centerY, aspect: aspect),
        maskCoverage(m, m.centerX, m.centerY + step, aspect: aspect),
      );

  group('choosing Circle', () {
    test('makes the window round on a tall picture', () {
      final m = maskWithShape(ClipMask.none, ClipMaskShape.circle, aspect: tall);
      expect(m.shape, ClipMaskShape.circle);
      expect(m.width * tall, closeTo(m.height, 1e-9));

      // Measured where it matters, at the soft edge: a step just past the
      // radius covers the same across as down.
      final radius = m.height / 2;
      final (across, down) = acrossAndDown(m, tall, radius * 1.01);
      expect(across, greaterThan(0.0));
      expect(across, lessThan(1.0));
      expect(across, closeTo(down, 1e-9));
    });

    test('makes the window round on a wide picture', () {
      final m = maskWithShape(ClipMask.none, ClipMaskShape.circle, aspect: wide);
      expect(m.width * wide, closeTo(m.height, 1e-9));
      final (across, down) = acrossAndDown(m, wide, m.height / 2 * 1.01);
      expect(across, closeTo(down, 1e-9));
    });

    test('fits inside the window it came from, about the same centre', () {
      // The diameter is the window's shorter side on screen, so the circle
      // never grows past what the user had drawn.
      const rect = ClipMask(
        shape: ClipMaskShape.rectangle,
        centerX: 0.3,
        centerY: 0.7,
        width: 0.5,
        height: 0.4,
      );
      final m = maskWithShape(rect, ClipMaskShape.circle, aspect: tall);
      expect(m.centerX, 0.3);
      expect(m.centerY, 0.7);
      expect(m.width, lessThanOrEqualTo(rect.width));
      expect(m.height, lessThanOrEqualTo(rect.height));
      expect(m.width * tall, closeTo(m.height, 1e-9));
      // 0.5 of a tall picture's width is 0.28 of its height, the shorter side.
      expect(m.height, closeTo(0.5 * tall, 1e-9));
    });

    test('keeps everything but the size', () {
      const tuned = ClipMask(
        shape: ClipMaskShape.rectangle,
        feather: 0.2,
        inverted: true,
        angle: 30,
        cornerRadius: 0.05,
      );
      final m = maskWithShape(tuned, ClipMaskShape.circle, aspect: tall);
      expect(m.feather, 0.2);
      expect(m.inverted, isTrue);
      expect(m.angle, 30);
      expect(m.cornerRadius, 0.05);
    });

    test('takes an unknown picture as square', () {
      // An asset not yet probed has no shape to be round on.
      final m = maskWithShape(ClipMask.none, ClipMaskShape.circle, aspect: null);
      expect(m.width, m.height);
    });

    test('stays round under a pinch and a twist', () {
      final m = maskWithShape(ClipMask.none, ClipMaskShape.circle, aspect: tall);
      final after = maskAfterGesture(m, scale: 1.7, rotationRadians: 0.6);
      expect(after.width * tall, closeTo(after.height, 1e-9));
    });
  });

  test('every other shape keeps the window exactly where and as it was', () {
    const placed = ClipMask(
      shape: ClipMaskShape.rectangle,
      centerX: 0.3,
      centerY: 0.2,
      width: 0.4,
      height: 0.3,
      angle: 20,
    );
    for (final shape in [
      ClipMaskShape.rectangle,
      ClipMaskShape.linear,
      ClipMaskShape.mirror,
      ClipMaskShape.roundedRectangle,
    ]) {
      expect(
        maskWithShape(placed, shape, aspect: tall),
        placed.copyWith(shape: shape),
        reason: shape.name,
      );
    }
  });

  test('a first shape places the default window', () {
    expect(
      maskWithShape(ClipMask.none, ClipMaskShape.rectangle, aspect: tall),
      const ClipMask(shape: ClipMaskShape.rectangle),
    );
  });

  test('None removes the mask', () {
    const placed = ClipMask(shape: ClipMaskShape.circle, centerX: 0.2);
    expect(maskWithShape(placed, ClipMaskShape.none, aspect: tall), ClipMask.none);
  });
}

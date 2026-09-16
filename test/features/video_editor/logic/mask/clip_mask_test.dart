import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';

/// The mask model and its coverage maths — the Dart twin of the shader's.
void main() {
  group('the model', () {
    test('none is the default and writes nothing meaningful', () {
      expect(ClipMask.none.isNone, isTrue);
      expect(const ClipMask().shape, ClipMaskShape.none);
    });

    test('round-trips, and reads junk or an unknown shape as none', () {
      const m = ClipMask(
        shape: ClipMaskShape.circle,
        centerX: 0.3,
        centerY: 0.7,
        width: 0.4,
        height: 0.5,
        feather: 0.1,
        inverted: true,
      );
      expect(ClipMask.fromJson(m.toJson()), m);
      expect(ClipMask.fromJson(null), ClipMask.none);
      expect(ClipMask.fromJson({'shape': 'hexagon'}), ClipMask.none);
      expect(ClipMask.fromJson({'shape': 'none', 'width': 0.2}), ClipMask.none);
    });

    test('malformed numbers take defaults and are clamped', () {
      final m = ClipMask.fromJson({
        'shape': 'rectangle',
        'centerX': 'left',
        'centerY': 4.0,
        'width': 0.0,
        'feather': -1.0,
      });
      expect(m.centerX, 0.5);
      expect(m.centerY, 1.0);
      expect(m.width, kMaskMinExtent);
      expect(m.feather, 0.0);
    });
  });

  group('coverage', () {
    const rect = ClipMask(
      shape: ClipMaskShape.rectangle,
      centerX: 0.5,
      centerY: 0.5,
      width: 0.5,
      height: 0.5,
      feather: 0.1,
    );

    test('no mask covers everything', () {
      expect(maskCoverage(ClipMask.none, 0.01, 0.99), 1.0);
    });

    test('a rectangle is solid inside, empty outside, soft across the feather',
        () {
      expect(maskCoverage(rect, 0.5, 0.5), 1.0);
      expect(maskCoverage(rect, 0.9, 0.9), 0.0);
      // Half way across the feather from the edge (0.75) is half covered.
      expect(maskCoverage(rect, 0.75 + 0.05, 0.5), closeTo(0.5, 1e-9));
    });

    test('a circle is measured along the ellipse of its size', () {
      const circle = ClipMask(
        shape: ClipMaskShape.circle,
        centerX: 0.5,
        centerY: 0.5,
        width: 0.8,
        height: 0.4,
        feather: 0.0,
      );
      expect(maskCoverage(circle, 0.5, 0.5), 1.0);
      // On the horizontal rim, inside; just past the vertical rim, outside.
      expect(maskCoverage(circle, 0.89, 0.5), 1.0);
      expect(maskCoverage(circle, 0.5, 0.71), 0.0);
    });

    test('linear keeps the left and fades over the feather', () {
      const linear = ClipMask(shape: ClipMaskShape.linear, centerX: 0.5, feather: 0.1);
      expect(maskCoverage(linear, 0.1, 0.5), 1.0);
      expect(maskCoverage(linear, 0.9, 0.5), 0.0);
      expect(maskCoverage(linear, 0.5, 0.5), closeTo(0.5, 1e-9));
    });

    test('inverted keeps the outside', () {
      final inv = rect.copyWith(inverted: true);
      expect(maskCoverage(inv, 0.5, 0.5), 0.0);
      expect(maskCoverage(inv, 0.9, 0.9), 1.0);
    });
  });

  test('the uniform encoding is two vec4s in a fixed order', () {
    const m = ClipMask(
      shape: ClipMaskShape.linear,
      centerX: 0.3,
      centerY: 0.6,
      width: 0.4,
      height: 0.5,
      feather: 0.02,
      inverted: true,
    );
    expect(maskUniforms(m), [3.0, 0.3, 0.6, 0.02, 0.4, 0.5, 1.0, 0.0]);
    expect(maskUniforms(ClipMask.none).first, 0.0);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';

/// The rounded rectangle, and the rules that let one mask model serve both
/// clips and overlays.
///
/// A rounded rectangle is what a picture-in-picture actually wants — a plain
/// rectangle reads as a screenshot pasted on, and a circle crops away the
/// corners of a 16:9 inset. It is a rectangle whose corners are an arc, which
/// is why it is one shape rather than a rectangle with a separate setting.
void main() {
  ClipMask rounded({double radius = 0.25, double feather = 0.0}) => ClipMask(
        shape: ClipMaskShape.roundedRectangle,
        width: 0.8,
        height: 0.8,
        cornerRadius: radius,
        feather: feather,
      );

  group('the shape enum', () {
    test('every existing shape keeps the index the wire already sends', () {
      // Both sides read the shape as a number (`a.x < 1.5` in the shader), so
      // inserting a shape rather than appending would silently turn every
      // saved circle into something else.
      expect(ClipMaskShape.values.indexOf(ClipMaskShape.none), 0);
      expect(ClipMaskShape.values.indexOf(ClipMaskShape.rectangle), 1);
      expect(ClipMaskShape.values.indexOf(ClipMaskShape.circle), 2);
      expect(ClipMaskShape.values.indexOf(ClipMaskShape.linear), 3);
      expect(ClipMaskShape.values.indexOf(ClipMaskShape.roundedRectangle), 4);
    });

    test('a draft naming a shape this build does not know reads as no mask',
        () {
      expect(ClipMask.fromJson({'shape': 'hexagon'}), ClipMask.none);
    });
  });

  group('rounded rectangle coverage', () {
    test('the centre is inside and far outside is outside', () {
      final m = rounded();
      expect(maskCoverage(m, 0.5, 0.5), 1.0);
      expect(maskCoverage(m, 0.0, 0.0), 0.0);
    });

    test('a corner is cut where a plain rectangle would keep it', () {
      // The near corner of the box: inside a rectangle, outside the arc.
      const m = ClipMask(
        shape: ClipMaskShape.roundedRectangle,
        width: 0.8,
        height: 0.8,
        cornerRadius: 0.3,
        feather: 0.0,
      );
      const sharp = ClipMask(
        shape: ClipMaskShape.rectangle,
        width: 0.8,
        height: 0.8,
        feather: 0.0,
      );
      // Just inside the box's own corner.
      const cx = 0.5 + 0.39;
      const cy = 0.5 + 0.39;
      expect(maskCoverage(sharp, cx, cy), 1.0);
      expect(maskCoverage(m, cx, cy), 0.0);
      // The middle of an edge stays, on both.
      expect(maskCoverage(m, 0.5 + 0.39, 0.5), 1.0);
      expect(maskCoverage(m, 0.5, 0.5 + 0.39), 1.0);
    });

    test('a zero radius is exactly the plain rectangle', () {
      const sharp = ClipMask(
        shape: ClipMaskShape.rectangle,
        width: 0.7,
        height: 0.5,
        feather: 0.02,
      );
      const zero = ClipMask(
        shape: ClipMaskShape.roundedRectangle,
        width: 0.7,
        height: 0.5,
        cornerRadius: 0.0,
        feather: 0.02,
      );
      for (var i = 0; i <= 12; i++) {
        for (var j = 0; j <= 12; j++) {
          final x = i / 12, y = j / 12;
          expect(maskCoverage(zero, x, y), closeTo(maskCoverage(sharp, x, y), 1e-9),
              reason: 'at $x,$y');
        }
      }
    });

    test('the radius cannot exceed the box, so it degrades to a stadium', () {
      // Asking for a radius larger than the half-extent must not fold the
      // shape inside out; it clamps to the largest arc that fits.
      const huge = ClipMask(
        shape: ClipMaskShape.roundedRectangle,
        width: 0.6,
        height: 0.4,
        cornerRadius: 5.0,
        feather: 0.0,
      );
      expect(maskCoverage(huge, 0.5, 0.5), 1.0);
      // Still a closed shape: far outside is still out.
      expect(maskCoverage(huge, 0.0, 0.0), 0.0);
      // And the edge midpoints survive, which is what "stadium" means.
      expect(maskCoverage(huge, 0.5 + 0.29, 0.5), 1.0);
    });

    test('coverage never leaves 0..1 anywhere on the canvas', () {
      final m = rounded(radius: 0.2, feather: 0.08);
      for (var i = 0; i <= 20; i++) {
        for (var j = 0; j <= 20; j++) {
          expect(maskCoverage(m, i / 20, j / 20), inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('feather softens the edge rather than moving the shape', () {
      final hard = rounded(radius: 0.2);
      final soft = rounded(radius: 0.2, feather: 0.1);
      expect(maskCoverage(hard, 0.5, 0.5), 1.0);
      expect(maskCoverage(soft, 0.5, 0.5), 1.0);
      var sawPartial = false;
      for (var i = 0; i <= 60; i++) {
        final v = maskCoverage(soft, 0.5 + i / 120, 0.5);
        if (v > 0.0 && v < 1.0) sawPartial = true;
      }
      expect(sawPartial, isTrue);
    });

    test('inverting swaps inside for outside', () {
      final m = rounded(radius: 0.2);
      final inv = m.copyWith(inverted: true);
      expect(maskCoverage(inv, 0.5, 0.5), 0.0);
      expect(maskCoverage(inv, 0.0, 0.0), 1.0);
    });
  });

  group('serialisation', () {
    test('the corner radius round-trips and is clamped on read', () {
      final back = ClipMask.fromJson(rounded(radius: 0.3).toJson());
      expect(back.shape, ClipMaskShape.roundedRectangle);
      expect(back.cornerRadius, closeTo(0.3, 1e-9));

      final wild = ClipMask.fromJson({
        ...rounded().toJson(),
        'cornerRadius': 99.0,
      });
      expect(wild.cornerRadius, lessThanOrEqualTo(2.0));
      final negative = ClipMask.fromJson({
        ...rounded().toJson(),
        'cornerRadius': -3.0,
      });
      expect(negative.cornerRadius, greaterThanOrEqualTo(0.0));
    });

    test('a mask saved before rounded corners existed still loads', () {
      // No cornerRadius key at all — every draft written until now.
      final legacy = ClipMask.fromJson({
        'shape': 'rectangle',
        'centerX': 0.5,
        'centerY': 0.5,
        'width': 0.6,
        'height': 0.6,
        'feather': 0.05,
        'inverted': false,
      });
      expect(legacy.shape, ClipMaskShape.rectangle);
      expect(legacy.isNone, isFalse);
    });
  });

  group('the uniform pair', () {
    test('carries the shape index and the corner radius the shader reads', () {
      final u = maskUniforms(rounded(radius: 0.25));
      expect(u.length, 8);
      // (shape, cx, cy, feather) then (w, h, inverted, cornerRadius).
      expect(u[0], ClipMaskShape.values.indexOf(ClipMaskShape.roundedRectangle).toDouble());
      expect(u[7], closeTo(0.25, 1e-9));
    });

    test('an unrounded shape leaves the radius slot at zero', () {
      const sharp = ClipMask(shape: ClipMaskShape.rectangle);
      expect(maskUniforms(sharp)[7], 0.0);
    });
  });
}

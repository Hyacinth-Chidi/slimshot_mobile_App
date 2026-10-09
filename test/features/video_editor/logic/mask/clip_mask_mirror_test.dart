import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';

/// The Mirror mask: CapCut's band between two parallel lines. It keeps a
/// strip of the picture — horizontal until it is twisted — whose thickness is
/// the window's height; along its length it runs edge to edge.
void main() {
  test('appended to the shapes, so every saved shape keeps its number', () {
    // Both sides read the shape as a number; inserting it anywhere but last
    // would turn saved shapes into other shapes.
    expect(ClipMaskShape.values.indexOf(ClipMaskShape.mirror), 5);
    expect(ClipMaskShape.values.last, ClipMaskShape.mirror);
  });

  test('it round-trips through a draft', () {
    const m = ClipMask(shape: ClipMaskShape.mirror, centerY: 0.3, height: 0.2, angle: 30);
    final back = ClipMask.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(back, m);
    expect(m.toJson()['shape'], 'mirror');
  });

  group('coverage', () {
    const band = ClipMask(
      shape: ClipMaskShape.mirror,
      centerX: 0.5,
      centerY: 0.5,
      width: 0.6,
      height: 0.4,
      feather: 0.1,
    );

    test('keeps the band from edge to edge', () {
      expect(maskCoverage(band, 0.5, 0.5), 1.0);
      expect(maskCoverage(band, 0.01, 0.5), 1.0, reason: 'its width plays no part');
      expect(maskCoverage(band, 0.99, 0.65), 1.0);
    });

    test('drops what is above and below it', () {
      expect(maskCoverage(band, 0.5, 0.05), 0.0);
      expect(maskCoverage(band, 0.5, 0.95), 0.0);
    });

    test('softens over the feather on both edges', () {
      expect(maskCoverage(band, 0.5, 0.7 + 0.05), closeTo(0.5, 1e-9));
      expect(maskCoverage(band, 0.5, 0.3 - 0.05), closeTo(0.5, 1e-9));
    });

    test('a quarter turn stands it upright', () {
      final upright = band.copyWith(angle: 90);
      expect(maskCoverage(upright, 0.5, 0.05), 1.0);
      expect(maskCoverage(upright, 0.05, 0.5), 0.0);
    });

    test('inverted keeps the outside', () {
      final inverted = band.copyWith(inverted: true);
      expect(maskCoverage(inverted, 0.5, 0.5), 0.0);
      expect(maskCoverage(inverted, 0.5, 0.05), 1.0);
    });
  });

  test('the uniforms carry its number, and never a corner radius', () {
    final u = maskUniforms(const ClipMask(shape: ClipMaskShape.mirror, cornerRadius: 0.3));
    expect(u[0], 5.0);
    expect(u[7], 0.0);
  });
}

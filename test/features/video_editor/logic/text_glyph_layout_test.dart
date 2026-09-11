import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_glyph_layout.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

import '../../../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A bundled font, not a Google one — see test/support/test_fonts.dart.
  // Metrics differ from any particular user font, so these tests assert on
  // relationships (ordering, containment, proportion), never on absolute
  // pixel widths.
  TextOverlayModel overlayWith(String text) => TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: const Size(400, 700),
      );

  group('layoutTextGlyphs', () {
    test('returns one box per character, in order', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 3);
      expect(glyphs.map((g) => g.charIndex), [0, 1, 2]);
    });

    test('lays characters out left to right without overlapping', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs[0].inkRect.left, lessThan(glyphs[1].inkRect.left));
      expect(glyphs[1].inkRect.left, lessThan(glyphs[2].inkRect.left));
      // Adjacent glyphs may touch but must not overlap.
      expect(glyphs[0].inkRect.right, lessThanOrEqualTo(glyphs[1].inkRect.left + 0.01));
    });

    test('skips whitespace, which has no ink to draw', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a b'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.map((g) => g.charIndex), [0, 2]);
    });

    test('a second line sits below the first', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a\nb'),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs.length, 2);
      expect(glyphs[1].inkRect.top, greaterThan(glyphs[0].inkRect.bottom - 0.01));
    });

    test('padded rect grows by the shadow padding on every side', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith('a'),
        canvasSize: const Size(400, 700),
        shadowPadding: 4,
      );
      final g = glyphs.single;
      expect(g.paddedRect.left, closeTo(g.inkRect.left - 4, 1e-9));
      expect(g.paddedRect.top, closeTo(g.inkRect.top - 4, 1e-9));
      expect(g.paddedRect.right, closeTo(g.inkRect.right + 4, 1e-9));
      expect(g.paddedRect.bottom, closeTo(g.inkRect.bottom + 4, 1e-9));
    });

    test('glyph boxes sit inside the measured text box', () {
      const canvas = Size(400, 700);
      final overlay = overlayWith('hello');
      final glyphs = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvas,
        shadowPadding: 0,
      );
      for (final g in glyphs) {
        expect(g.inkRect.left, greaterThanOrEqualTo(-0.01));
        expect(g.inkRect.top, greaterThanOrEqualTo(-0.01));
      }
    });

    test('empty text produces no glyphs', () {
      final glyphs = layoutTextGlyphs(
        overlay: overlayWith(''),
        canvasSize: const Size(400, 700),
        shadowPadding: 0,
      );
      expect(glyphs, isEmpty);
    });
  });
}

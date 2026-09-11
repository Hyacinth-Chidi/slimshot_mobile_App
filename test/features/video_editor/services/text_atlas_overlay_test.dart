import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/text_atlas_overlay.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('glyphsForAtlas', () {
    test('converts atlas and box pixels into fractions', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(200, 100),
        atlasPxSize: Size(400, 50),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 100, 25),
            boxRect: Rect.fromLTWH(20, 10, 40, 50),
            srcRect: Rect.fromLTWH(0, 0, 1, 1),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );

      final glyphs = glyphsForAtlas(atlas);
      expect(glyphs.length, 1);
      final g = glyphs.single;
      expect(g.atlasLeft, 0);
      expect(g.atlasRight, closeTo(0.25, 1e-9));
      expect(g.atlasBottom, closeTo(0.5, 1e-9));
      expect(g.boxLeft, closeTo(0.1, 1e-9));
      expect(g.boxTop, closeTo(0.1, 1e-9));
      expect(g.boxRight, closeTo(0.3, 1e-9));
      expect(g.boxBottom, closeTo(0.6, 1e-9));
    });

    // `srcRect` is the one rect on `RasterizedGlyph` that is **already** a
    // fraction — of its own cell, not of the atlas or of the box. Dividing it
    // by anything produces values that still look plausible (small, 0..1) and
    // would silently mis-sample every glyph's bleed, with nothing downstream
    // able to notice. Hence a test of its own.
    test('passes srcRect through unconverted — it is already a fraction', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(200, 100),
        atlasPxSize: Size(400, 50),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 100, 25),
            boxRect: Rect.fromLTWH(20, 10, 40, 50),
            srcRect: Rect.fromLTRB(0.2, 0.3, 0.8, 0.9),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );

      final g = glyphsForAtlas(atlas).single;
      expect(g.srcLeft, 0.2);
      expect(g.srcTop, 0.3);
      expect(g.srcRight, 0.8);
      expect(g.srcBottom, 0.9);
    });

    test('a zero-sized atlas yields no glyphs rather than infinities', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(200, 100),
        atlasPxSize: Size(0, 0),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 10, 10),
            boxRect: Rect.fromLTWH(0, 0, 10, 10),
            srcRect: Rect.fromLTWH(0, 0, 1, 1),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );
      expect(glyphsForAtlas(atlas), isEmpty);
    });

    test('a zero-sized box yields no glyphs rather than infinities', () {
      const atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: Size(0, 0),
        atlasPxSize: Size(400, 50),
        glyphs: [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 10, 10),
            boxRect: Rect.fromLTWH(0, 0, 10, 10),
            srcRect: Rect.fromLTWH(0, 0, 1, 1),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );
      expect(glyphsForAtlas(atlas), isEmpty);
    });
  });
}

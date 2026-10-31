import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/editor_timeline.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_atlas_overlay.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

/// `rasterizeAtlas` writes its PNG through `path_provider`, which has no
/// platform implementation under `flutter_test`.
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    final dir = await Directory.systemTemp.createTemp('text_atlas_entry_test_');
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

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

  group('textOverlayBoxPx', () {
    // A realistic one-line box: the shape that produced the 3.32x vertical
    // stretch on device.
    const textBox = Size(176, 53);
    const canvas = Size(400, 700);

    /// The vertical/horizontal half-extents `OverlayRenderer.writeCorners`
    /// computes for a glyph, replicated here so this test pins the
    /// **Dart/Kotlin contract** rather than only the Dart side.
    ///
    /// `halfW` is a fraction of the canvas *width* and `halfH` a fraction of
    /// the canvas *height*, so converting both to pixels is what yields the
    /// rect actually drawn.
    Size drawnGlyphPx({
      required Size boxPx,
      required EditorTimelineGlyph glyph,
    }) {
      final boxWidthFrac = boxPx.width / canvas.width;
      final boxHeightFrac = boxPx.height / canvas.height;
      final halfW = 0.5 * boxWidthFrac * (glyph.boxRight - glyph.boxLeft);
      final halfH = 0.5 * boxHeightFrac * (glyph.boxBottom - glyph.boxTop);
      return Size(2 * halfW * canvas.width, 2 * halfH * canvas.height);
    }

    test('the atlas path sends the true text box, not a square', () {
      expect(textOverlayBoxPx(textBox, usingAtlas: true), textBox);
    });

    test('the flat fallback still sends the pixel square', () {
      expect(
        textOverlayBoxPx(textBox, usingAtlas: false),
        textOverlayFitBox(textBox),
      );
      expect(textOverlayBoxPx(textBox, usingAtlas: false), const Size(176, 176));
    });

    // The bug, stated as the renderer sees it: a glyph spanning the whole text
    // box must be drawn with the *text box's* aspect. Under the square box the
    // same glyph came out 176x176 — 1:1 — which is the 3.32x vertical stretch.
    test('a full-box glyph is drawn with the text box aspect, not 1:1', () {
      final atlas = RasterizedTextAtlas(
        pngPath: '/tmp/a.png',
        canvasPxSize: textBox,
        atlasPxSize: const Size(256, 64),
        glyphs: [
          RasterizedGlyph(
            atlasRect: const Rect.fromLTWH(0, 0, 176, 53),
            // Spans the full text box.
            boxRect: Rect.fromLTWH(0, 0, textBox.width, textBox.height),
            srcRect: const Rect.fromLTWH(0, 0, 1, 1),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );
      final glyph = glyphsForAtlas(atlas).single;

      final drawn = drawnGlyphPx(
        boxPx: textOverlayBoxPx(textBox, usingAtlas: true),
        glyph: glyph,
      );
      expect(drawn.width / drawn.height,
          closeTo(textBox.width / textBox.height, 1e-9));
      expect(drawn.width, closeTo(textBox.width, 1e-9));
      expect(drawn.height, closeTo(textBox.height, 1e-9));

      // And the shape the bug produced, for contrast: the square box drew the
      // same glyph 1:1, stretching it vertically by the box's aspect.
      final stretched = drawnGlyphPx(
        boxPx: textOverlayFitBox(textBox),
        glyph: glyph,
      );
      expect(stretched.height / drawn.height,
          closeTo(textBox.width / textBox.height, 1e-9));
    });
  });

  group('textAtlasOverlayEntry', () {
    final text = TextOverlayModel(
      id: 'cap',
      text: 'Hello',
      fontFamily: kTestFontFamily,
      referenceCanvasSize: const Size(400, 700),
      laneIndex: 3,
      inAnimation: 'none',
      startTime: const Duration(seconds: 1),
      endTime: const Duration(seconds: 3),
    );

    Future<RasterizedTextAtlas> atlasAt(Size canvas, double rasterScale) async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: text,
        canvasSize: canvas,
        rasterScale: rasterScale,
      );
      expect(atlas, isNotNull);
      expect(atlas!.glyphs, isNotEmpty);
      return atlas;
    }

    test("the entry is the export's atlas entry", () async {
      const canvas = Size(360, 640);
      final atlas = await atlasAt(canvas, 2);
      final entry = textAtlasOverlayEntry(text, atlas, canvas);

      expect(entry.id, 'text_cap');
      expect(entry.kind, 'text');
      expect(entry.path, atlas.pngPath);
      expect(entry.glyphs!.length, atlas.glyphs.length);
      expect(entry.laneIndex, 1003);
      expect(entry.boxWidth,
          closeTo(textOverlayBoxPx(atlas.canvasPxSize, usingAtlas: true).width / 360, 1e-12));
      expect(entry.animationIn, isNull, reason: "'none' is sent as nothing");
      expect(entry.animationInSeconds, 0.5);
      expect(entry.startSeconds, 1.0);
      expect(entry.endSeconds, 3.0);
    });

    test('hidden keeps everything but opacity', () async {
      const canvas = Size(360, 640);
      final atlas = await atlasAt(canvas, 2);
      final shown = textAtlasOverlayEntry(text, atlas, canvas).toJson();
      final hidden = textAtlasOverlayEntry(text, atlas, canvas, hidden: true).toJson();

      expect(hidden['opacity'], 0.0);
      expect(shown['opacity'], isNot(0.0));
      expect({...hidden}..remove('opacity'), {...shown}..remove('opacity'));
    });

    test('an atlas made at another canvas size places the same box', () async {
      // The keyboard and the tool panels resize the canvas; an atlas made
      // before the resize must place exactly the box one made after would.
      const small = Size(270, 480);
      const large = Size(360, 640);
      final fromSmall = await atlasAt(small, 720 / 270);
      final fromLarge = await atlasAt(large, 720 / 360);

      final a = textAtlasOverlayEntry(text, fromSmall, large, atlasCanvasSize: small);
      final b = textAtlasOverlayEntry(text, fromLarge, large, atlasCanvasSize: large);

      // Within 2%: the text engine rounds each line's height at the size it
      // lays out at, which measures 0.7% on this box — under a pixel at the
      // texture's density. A box measured against the wrong canvas is off by
      // the canvases' ratio, 25% here.
      void same(double x, double y, String what) =>
          expect(x, closeTo(y, y.abs() * 0.02), reason: what);
      same(a.boxWidth, b.boxWidth, 'boxWidth');
      same(a.boxHeight, b.boxHeight, 'boxHeight');
      same(a.slideOffsetX, b.slideOffsetX, 'slideOffsetX');
      same(a.slideOffsetY, b.slideOffsetY, 'slideOffsetY');
    });
  });
}

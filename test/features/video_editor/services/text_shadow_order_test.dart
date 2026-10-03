import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_atlas_overlay.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async =>
      (await Directory.systemTemp.createTemp('text_shadow_order_test_')).path;
}

/// In the file, as on the canvas, every shadow lies under every letter.
///
/// The atlas baked each letter's shadow into the letter's own cell, and the
/// native pass draws cells in order — so on a two-line text, line 2's
/// shadows were drawn over line 1's letters: a grey smudge on every exported
/// multi-line text with a shadow. The alpha-only reassembly tests could not
/// see it; a shadow over an opaque letter changes its colour, not its alpha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  const canvas = Size(400, 700);
  const red = Color(0xFFFF0000);

  TextOverlayModel text({bool shadow = true}) => TextOverlayModel(
        id: 't',
        text: 'aaaa bbbb',
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        color: red,
        boxWidth: 200,
        shadowColor: shadow ? Colors.black : Colors.transparent,
        shadowOpacity: 0.6,
        shadowBlurRadius: 8,
        shadowDistance: 2,
        shadowAngle: 90,
      );

  Future<RasterizedTextAtlas> atlasOf(TextOverlayModel overlay) async =>
      (await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlay,
        canvasSize: canvas,
        rasterScale: 1,
      ))!;

  Future<ui.Image> decode(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  Future<({ByteData data, int width})> rgba(ui.Image image) async => (
        data: (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
        width: image.width,
      );

  int countIn(({ByteData data, int width}) img, Rect r, bool Function(int r, int g, int b, int a) test) {
    var n = 0;
    for (var y = r.top.ceil(); y < r.bottom.floor(); y++) {
      for (var x = r.left.ceil(); x < r.right.floor(); x++) {
        final o = (y * img.width + x) * 4;
        if (test(img.data.getUint8(o), img.data.getUint8(o + 1), img.data.getUint8(o + 2),
            img.data.getUint8(o + 3))) {
          n++;
        }
      }
    }
    return n;
  }

  bool isRed(int r, int g, int b, int a) => a > 200 && r > 200 && g < 80 && b < 80;
  bool isShadow(int r, int g, int b, int a) => a > 30 && r < 80 && g < 80 && b < 80;

  test("a shadowed letter keeps its shadow in a cell of its own", () async {
    final atlas = await atlasOf(text());
    final image = await decode(atlas.pngPath);
    final px = await rgba(image);
    image.dispose();
    for (final g in atlas.glyphs) {
      expect(g.shadowAtlasRect, isNotNull);
      expect(g.shadowAtlasRect!.size, g.atlasRect.size);
      // The letter's cell is the letter; its shadow cell is the shadow.
      expect(countIn(px, g.atlasRect, isShadow), 0);
      expect(countIn(px, g.atlasRect, isRed), greaterThan(50));
      expect(countIn(px, g.shadowAtlasRect!, isRed), 0);
      expect(countIn(px, g.shadowAtlasRect!, isShadow), greaterThan(50));
    }
  });

  test('a text without a shadow has no shadow cells, and sends what it always did', () async {
    final atlas = await atlasOf(text(shadow: false));
    expect(atlas.glyphs.every((g) => g.shadowAtlasRect == null), isTrue);
    for (final g in glyphsForAtlas(atlas)) {
      expect(g.toJson().keys.where((k) => k.startsWith('shadow')), isEmpty);
    }
  });

  test('on the wire, a shadow cell is in atlas fractions', () async {
    final atlas = await atlasOf(text());
    final glyph = atlas.glyphs.first;
    final json = glyphsForAtlas(atlas).first.toJson();
    expect(json['shadowAtlasLeft'], closeTo(glyph.shadowAtlasRect!.left / atlas.atlasPxSize.width, 1e-9));
    expect(json['shadowAtlasBottom'],
        closeTo(glyph.shadowAtlasRect!.bottom / atlas.atlasPxSize.height, 1e-9));
  });

  test("put back in the native pass's order, a two-line text's letters are the flat raster's",
      () async {
    final overlay = text();
    final atlas = await atlasOf(overlay);
    final flat = (await TextOverlayRasterizer.rasterize(
      overlay: overlay,
      canvasSize: canvas,
      rasterScale: 1,
    ))!;
    final margin = (flat.rasterPxSize.width - flat.canvasPxSize.width) / 2;

    // Every shadow cell, then every letter cell — whole cells, placed as the
    // quads place them.
    final atlasImage = await decode(atlas.pngPath);
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder)..translate(margin, margin);
    void place(Rect cell, RasterizedGlyph g) {
      final src = g.srcRect;
      final sx = g.boxRect.width / (src.width * cell.width);
      final sy = g.boxRect.height / (src.height * cell.height);
      c.drawImageRect(
        atlasImage,
        cell,
        Rect.fromLTWH(
          g.boxRect.left - src.left * cell.width * sx,
          g.boxRect.top - src.top * cell.height * sy,
          cell.width * sx,
          cell.height * sy,
        ),
        Paint(),
      );
    }

    for (final g in atlas.glyphs) {
      if (g.shadowAtlasRect != null) place(g.shadowAtlasRect!, g);
    }
    for (final g in atlas.glyphs) {
      place(g.atlasRect, g);
    }
    final rebuilt = await recorder
        .endRecording()
        .toImage(flat.rasterPxSize.width.ceil(), flat.rasterPxSize.height.ceil());
    atlasImage.dispose();
    final flatImage = await decode(flat.pngPath);
    final a = await rgba(rebuilt);
    final b = await rgba(flatImage);
    rebuilt.dispose();
    flatImage.dispose();

    // Every letter pixel of the flat raster, in the rebuilt file.
    var letters = 0;
    var darkened = 0;
    for (var y = 0; y < flat.rasterPxSize.height.floor(); y++) {
      for (var x = 0; x < flat.rasterPxSize.width.floor(); x++) {
        final o = (y * b.width + x) * 4;
        if (!isRed(b.data.getUint8(o), b.data.getUint8(o + 1), b.data.getUint8(o + 2),
            b.data.getUint8(o + 3))) {
          continue;
        }
        letters++;
        if ((a.data.getUint8(o) - b.data.getUint8(o)).abs() > 12) darkened++;
      }
    }
    expect(letters, greaterThan(500));
    expect(darkened, 0);
  });
}

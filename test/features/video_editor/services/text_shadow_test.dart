import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async =>
      (await Directory.systemTemp.createTemp('text_shadow_test_')).path;
}

/// A text's shadow reaches the file whole.
///
/// Device-reported as "the shadow is only on the left". Measured: the export
/// raster was exactly the text box, whose 8px outer padding is less than the
/// shadow's reach down and to the right (offset plus about three blur sigmas,
/// ~19px), so the shadow was cut off in a hard straight line on the right and
/// bottom while its soft left and top survived. The glyph atlas padded each
/// cell by 1.5 × blur (12px) — short in the same direction.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();
  const canvas = Size(400, 700);

  TextOverlayModel shadowed(String text, {bool stroke = false}) =>
      TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        color: Colors.white,
        shadowColor: Colors.black,
        shadowBlurRadius: kTextShadowBlurRadius,
        strokeColor: stroke ? Colors.red : Colors.transparent,
        strokeWidth: stroke ? 4 : 0,
      );

  /// The strongest alpha on each edge of [image]: anything above zero is ink
  /// the image was not big enough to hold.
  Future<({int left, int top, int right, int bottom})> edgeAlpha(
    ui.Image image,
    Rect within,
  ) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int a(int x, int y) => data.getUint8((y * image.width + x) * 4 + 3);
    int maxOf(Iterable<int> xs) => xs.fold(0, (m, v) => v > m ? v : m);
    final l = within.left.floor(), t = within.top.floor();
    final r = within.right.ceil() - 1, b = within.bottom.ceil() - 1;
    return (
      left: maxOf([for (var y = t; y <= b; y++) a(l, y)]),
      top: maxOf([for (var x = l; x <= r; x++) a(x, t)]),
      right: maxOf([for (var y = t; y <= b; y++) a(r, y)]),
      bottom: maxOf([for (var x = l; x <= r; x++) a(x, b)]),
    );
  }

  Future<ui.Image> decode(String path) async {
    final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
    return (await codec.getNextFrame()).image;
  }

  test('the flat export raster holds the whole shadow', () async {
    final raster = await TextOverlayRasterizer.rasterize(
      overlay: shadowed('Hello'),
      canvasSize: canvas,
      rasterScale: 1,
    );
    final image = await decode(raster!.pngPath);
    final edges = await edgeAlpha(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    );
    expect(edges, (left: 0, top: 0, right: 0, bottom: 0));
  });

  test('its margin is even, so the text keeps its centre', () async {
    final raster = await TextOverlayRasterizer.rasterize(
      overlay: shadowed('Hello'),
      canvasSize: canvas,
      rasterScale: 1,
    );
    final box = TextOverlayLayout.measure(shadowed('Hello'), canvas).boxSize;
    final marginX = raster!.rasterPxSize.width - box.width;
    final marginY = raster.rasterPxSize.height - box.height;
    expect(marginX, greaterThan(0));
    expect(marginX, closeTo(marginY, 1e-9));
    // The text box itself — what the slide travels and the layer lays out —
    // is unchanged.
    expect(raster.canvasPxSize, box);
  });

  test('every glyph cell of the atlas holds its whole shadow', () async {
    // One glyph, so a cell border can only carry its own bleed.
    final atlas = await TextOverlayRasterizer.rasterizeAtlas(
      overlay: shadowed('H'),
      canvasSize: canvas,
      rasterScale: 1,
    );
    final image = await decode(atlas!.pngPath);
    final edges = await edgeAlpha(image, atlas.glyphs.single.atlasRect);
    expect(edges, (left: 0, top: 0, right: 0, bottom: 0));
  });

  test('no text style carries a shadow — one painter casts it', () {
    // Styles used to carry it, and each layer brought its own: an outlined
    // text had two, and a `Shadow`'s blur ignores the canvas scale. See
    // `paintTextOverlayInk`.
    final o = shadowed('Hi', stroke: true);
    expect(TextOverlayLayout.fillStyleFor(o, 1).shadows ?? const [], isEmpty);
    expect(TextOverlayLayout.strokeStyleFor(o, 1).shadows ?? const [], isEmpty);
  });

  /// The rows of [image]'s middle column, as (r, g, a).
  Future<List<(int, int, int)>> middleColumn(ui.Image image) async {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final x = image.width ~/ 2;
    return [
      for (var y = 0; y < image.height; y++)
        (
          data.getUint8((y * image.width + x) * 4),
          data.getUint8((y * image.width + x) * 4 + 1),
          data.getUint8((y * image.width + x) * 4 + 3),
        ),
    ];
  }

  test('an outline is not darkened on the side its shadow falls', () async {
    // The fill's shadow was painted over the outline beneath it, so the
    // outline's lower edge — where the shadow falls — came out darker than
    // its upper edge. Red outline, white fill, black shadow: the reddest
    // opaque pixel above the fill and below it must be the same red.
    final raster = await TextOverlayRasterizer.rasterize(
      overlay: shadowed('H', stroke: true),
      canvasSize: canvas,
      rasterScale: 1,
    );
    final column = await middleColumn(await decode(raster!.pngPath));
    final fillRows = [
      for (var y = 0; y < column.length; y++)
        if (column[y].$2 > 240 && column[y].$3 > 240) y,
    ];
    // Opaque and not white: outline pixels, whose red is what a shadow
    // painted over them would take down.
    int reddest(Iterable<int> ys) => ys
        .where((y) => column[y].$3 > 240 && column[y].$2 < 100)
        .map((y) => column[y].$1)
        .fold(0, (m, v) => v > m ? v : m);
    final above = reddest([for (var y = 0; y < fillRows.first; y++) y]);
    final below = reddest(
      [for (var y = fillRows.last + 1; y < column.length; y++) y],
    );
    expect(above, greaterThan(200), reason: 'the outline is there at all');
    expect(below, closeTo(above, 4));
  });

  test('the shadow is as soft in the file as on the canvas', () async {
    // The export draws at 2–3× the canvas's density. A `Shadow`'s blur did
    // not scale with it: measured, it faded over 12 box px at 1× and 6.7 at
    // 3× — a shadow twice as sharp in the file as on the screen.
    Future<double> falloff(double density) async {
      final raster = await TextOverlayRasterizer.rasterize(
        overlay: shadowed('H'),
        canvasSize: canvas,
        rasterScale: density,
      );
      final image = await decode(raster!.pngPath);
      final column = await middleColumn(image);
      final inkEnd = column.lastIndexWhere((p) => p.$2 > 200 && p.$3 > 200);
      final faded = column.indexWhere((p) => p.$3 < 20, inkEnd + 1);
      return (faded - inkEnd) * raster.rasterPxSize.height / image.height;
    }

    final atOne = await falloff(1);
    final atThree = await falloff(3);
    expect(atThree, closeTo(atOne, 1.5));
  });
}

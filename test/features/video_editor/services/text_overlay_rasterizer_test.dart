import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

import '../../../support/test_fonts.dart';

/// `rasterizeAtlas` writes its PNG through `path_provider`, which has no
/// platform implementation under `flutter_test` — the plugin's method
/// channel throws `MissingPluginException` with no host to answer it. This
/// fake answers `getTemporaryPath()` with a real temp directory so the
/// rasteriser's file write succeeds exactly as it does on-device.
class _FakePathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    final dir = await Directory.systemTemp.createTemp('text_atlas_test_');
    return dir.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PathProviderPlatform.instance = _FakePathProviderPlatform();

  TextOverlayModel overlayWith(String text, {Color? background}) =>
      TextOverlayModel(
        id: 't',
        text: text,
        fontFamily: kTestFontFamily,
        backgroundColor: background ?? Colors.transparent,
        referenceCanvasSize: const Size(400, 700),
      );

  group('rasterizeAtlas', () {
    test('returns one glyph entry per inked character', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas, isNotNull);
      expect(atlas!.glyphs.length, 3);
    });

    test('atlas cells do not overlap', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abcdef'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      final rects = atlas!.glyphs.map((g) => g.atlasRect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: 'cell $i overlaps cell $j',
          );
        }
      }
    });

    test('every cell sits inside the atlas', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('hello world'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      final bounds = Offset.zero & atlas!.atlasPxSize;
      for (final g in atlas.glyphs) {
        expect(bounds.contains(g.atlasRect.topLeft), isTrue);
        expect(bounds.contains(g.atlasRect.bottomRight - const Offset(0.01, 0.01)), isTrue);
      }
    });

    test('a cell and its box rect have the same shape', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 2,
      );
      for (final g in atlas!.glyphs) {
        final atlasAspect = g.atlasRect.width / g.atlasRect.height;
        final boxAspect = g.boxRect.width / g.boxRect.height;
        expect(atlasAspect, closeTo(boxAspect, 0.02));
      }
    });

    test('carries the background rect when the overlay has one', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc', background: Colors.red),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas!.backgroundRect, isNotNull);
    });

    test('has no background rect when the overlay has none', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('abc'),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas!.backgroundRect, isNull);
    });

    test('empty text produces no atlas', () async {
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlayWith('   '),
        canvasSize: const Size(400, 700),
        rasterScale: 1,
      );
      expect(atlas, isNull);
    });
  });
}

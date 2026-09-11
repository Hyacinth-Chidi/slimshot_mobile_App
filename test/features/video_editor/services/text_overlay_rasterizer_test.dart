import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

  // C1's bug (padded rects used as placement) packs and reports perfectly —
  // every test above passes against it. The only test that can see the
  // symptom is one that actually draws the atlas back together and checks
  // the resulting pixels against the flat raster, which is what real
  // consumers (the native overlay pass) do. Anything that regresses this
  // reintroduces double-composited ink at every glyph seam.
  //
  // The assertion is split into two regions, because they have different
  // guarantees:
  //
  // - **Inside every glyph's `boxRect`** (the ink area) must match the flat
  //   raster almost exactly. `boxRect`s tile the box without overlapping, so
  //   nothing here is composited twice — this is the region C1 was about.
  //   Not a literal zero, though: `getBoxesForSelection` returns full
  //   line-height boxes, not tight ink bounds, so a `boxRect`'s edge can
  //   land on a fractional pixel mid-glyph, and clipping+resampling at that
  //   edge leaves one seam row/column of antialiasing noise per glyph —
  //   confirmed by measurement to be a thin, low-magnitude, glyph-count-
  //   linear effect (~32-50px per glyph, max delta ~50/255), unrelated to
  //   C1. The gate scales with glyph count for exactly that reason: it
  //   catches an *area*-scaling regression (what a real double-composite of
  //   ink would look like — max delta near 255, count scaling with ink
  //   *area* not perimeter) while tolerating the known seam noise.
  // - **Outside every `boxRect`** (the shadow/stroke bleed halo) can still
  //   differ from the flat raster where two glyphs sit close enough that
  //   their *padded* cells overlap on canvas: each cell already contains a
  //   fully-rendered (and already-correct) crop of the whole run — shadow
  //   blur included — so where two such crops overlap, reassembly composites
  //   the same already-correct pixels a second time. Rejected fixes (dead
  //   ends, not retried): masking a cell to only its own glyph's ink is
  //   impossible once rasterised (nothing distinguishes whose pixels are
  //   whose), and a max/coverage blend for the bleed would break legitimate
  //   alpha blending between overlapping glyphs elsewhere. So the halo is
  //   asserted with a looser, but still bounded, tolerance — it must not
  //   grow without limit as more glyphs are added, which would signal the
  //   double-composite compounding rather than staying a fixed per-seam cost.
  group('atlas reassembly matches the flat raster', () {
    Future<void> expectReassemblyMatches(
      TextOverlayModel overlay, {
      required String label,
      int maxHaloPixelsOverThreshold = 60,
    }) async {
      const canvasSize = Size(400, 700);
      final flat = await TextOverlayRasterizer.rasterize(
        overlay: overlay,
        canvasSize: canvasSize,
        rasterScale: 1,
      );
      final atlas = await TextOverlayRasterizer.rasterizeAtlas(
        overlay: overlay,
        canvasSize: canvasSize,
        rasterScale: 1,
      );
      expect(flat, isNotNull, reason: '$label: flat raster produced nothing');
      expect(atlas, isNotNull, reason: '$label: atlas produced nothing');

      final flatAlpha = await _decodeAlpha(flat!.pngPath);
      final reassembled = await _reassemble(atlas!);

      expect(
        reassembled.width,
        flatAlpha.width,
        reason: '$label: reassembled canvas width does not match the flat raster',
      );
      expect(
        reassembled.height,
        flatAlpha.height,
        reason: '$label: reassembled canvas height does not match the flat raster',
      );

      final split = _alphaDeltaSplitByBoxRects(
        flatAlpha,
        reassembled,
        atlas.glyphs.map((g) => g.boxRect).toList(),
      );

      // Hard-ish gate: the ink area is where C1 lived. A seam row per glyph
      // is tolerated (see comment above); a max delta anywhere near 255, or
      // a count that scales with ink *area* rather than glyph count, is not
      // — that is C1's signature, not antialiasing noise.
      final maxInkPixelsOverThreshold = 60 * atlas.glyphs.length;
      expect(
        split.inside.pixelsOverThreshold,
        lessThan(maxInkPixelsOverThreshold),
        reason:
            '$label: ${split.inside.pixelsOverThreshold} px inside a glyph\'s '
            'boxRect differ from the flat raster by more than 32/255 alpha '
            '(max delta ${split.inside.maxDelta}) across '
            '${atlas.glyphs.length} glyphs — boxRects are overlapping or '
            'misplaced, which is exactly what C1 was',
      );
      expect(
        split.inside.maxDelta,
        lessThan(80),
        reason:
            '$label: worst inside-boxRect delta was ${split.inside.maxDelta}/255 '
            '— a real double-composite of ink saturates near 255, this is '
            'far above the ~50 seen from seam antialiasing alone',
      );

      // Soft gate: bleed-halo overlap between adjacent glyphs' padded cells,
      // a known, bounded characteristic of this design (see the group
      // comment) — not zero, but must not blow up.
      expect(
        split.outside.pixelsOverThreshold,
        lessThan(maxHaloPixelsOverThreshold),
        reason:
            '$label: ${split.outside.pixelsOverThreshold} px in the bleed '
            'halo differ from the flat raster by more than 32/255 alpha '
            '(max delta ${split.outside.maxDelta}, mean delta '
            '${split.outside.meanDelta.toStringAsFixed(3)}) — more than the '
            'expected per-seam bleed overlap',
      );
    }

    // Halo tolerances below are measured, not guessed: with zero padding
    // (plain/stroked with no shadow) the "halo" is really the same seam
    // antialiasing noise as the ink gate tolerates, just landing just
    // outside a boxRect's fractional edge depending on where a pixel centre
    // falls — hence a per-glyph allowance similar in size to the ink gate's.

    test('plain text', () async {
      await expectReassemblyMatches(
        overlayWith('hello'),
        label: 'plain',
        maxHaloPixelsOverThreshold: 60 * 5, // 5 glyphs, seam noise only
      );
    });

    test('stroked text', () async {
      final overlay = overlayWith('hello')
        ..strokeColor = Colors.black
        ..strokeWidth = 6;
      await expectReassemblyMatches(
        overlay,
        label: 'stroked',
        maxHaloPixelsOverThreshold: 80 * 5,
      );
    });

    test('shadowed text', () async {
      // 8px matches the app's actual shadow preset (text_editor_dialog.dart:
      // shadowBlurRadius: 8.0) — a realistic bleed width relative to the
      // 32px font, not the 20px stress figure used to originally measure
      // C1's ink-area bug. The halo is wider here because real bleed
      // (not just seam noise) now overlaps between adjacent glyphs.
      final overlay = overlayWith('hello')
        ..shadowColor = Colors.black
        ..shadowBlurRadius = 8;
      await expectReassemblyMatches(
        overlay,
        label: 'shadowed',
        maxHaloPixelsOverThreshold: 250 * 5,
      );
    });

    test('multi-line text', () async {
      await expectReassemblyMatches(
        overlayWith('hello\nworld'),
        label: 'multi-line',
        maxHaloPixelsOverThreshold: 60 * 10,
      );
    });

    test(
      'a wide shadow blur overlaps neighbouring bleed but never the ink',
      () async {
        // Documents the halo's known bound rather than hiding it: at 20px
        // blur on a 32px font (bleed wider than the glyph itself), adjacent
        // cells' padding overlaps substantially and the halo delta is large
        // — but the ink area (boxRect) stays within the tight ink tolerance
        // regardless (see the ink gate above), which is the actual C1
        // guarantee: ink is never double-composited, only the soft bleed
        // that was already an approximation.
        final overlay = overlayWith('hello')
          ..shadowColor = Colors.black
          ..shadowBlurRadius = 20;
        await expectReassemblyMatches(
          overlay,
          label: 'wide shadow blur',
          maxHaloPixelsOverThreshold: 2200,
        );
      },
    );
  });
}

/// One decoded image's alpha channel, row-major, plus its dimensions.
class _AlphaBuffer {
  const _AlphaBuffer({required this.width, required this.height, required this.alpha});

  final int width;
  final int height;
  final Uint8List alpha;

  int at(int x, int y) => alpha[y * width + x];
}

Future<_AlphaBuffer> _decodeAlpha(String pngPath) async {
  final bytes = await File(pngPath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    return _alphaFromImage(image);
  } finally {
    image.dispose();
  }
}

Future<_AlphaBuffer> _alphaFromImage(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final rgba = data!.buffer.asUint8List();
  final alpha = Uint8List(image.width * image.height);
  for (var i = 0; i < alpha.length; i++) {
    alpha[i] = rgba[i * 4 + 3];
  }
  return _AlphaBuffer(width: image.width, height: image.height, alpha: alpha);
}

/// Draws [atlas]'s cells back onto a transparent canvas the size of the text
/// box — the same reassembly the native overlay pass performs, one quad per
/// glyph.
///
/// **The whole cell is drawn, not just its `srcRect` crop.** `srcRect` says
/// which part of the cell maps onto `boxRect`; the padding around it (the
/// shadow/stroke bleed) is real ink that must still land on the canvas, just
/// scaled and positioned by the same transform that takes `srcRect` to
/// `boxRect`, so it can spill onto whatever is drawn under or after it —
/// exactly as the flat raster's un-clipped shadow spills onto a neighbouring
/// glyph. Cropping to `srcRect` (drawing only the ink) is the mistake this
/// test exists to catch: it would make the fixed C1 pass by construction
/// without checking that the bleed is preserved.
Future<_AlphaBuffer> _reassemble(RasterizedTextAtlas atlas) async {
  final atlasBytes = await File(atlas.pngPath).readAsBytes();
  final atlasCodec = await ui.instantiateImageCodec(atlasBytes);
  final atlasImage = (await atlasCodec.getNextFrame()).image;

  final width = atlas.canvasPxSize.width.ceil();
  final height = atlas.canvasPxSize.height.ceil();

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (final glyph in atlas.glyphs) {
    final atlasRect = glyph.atlasRect;
    final src = glyph.srcRect;
    // Pixel size of the src crop within the cell.
    final srcPxWidth = src.width * atlasRect.width;
    final srcPxHeight = src.height * atlasRect.height;
    if (srcPxWidth <= 0 || srcPxHeight <= 0) continue;
    final scaleX = glyph.boxRect.width / srcPxWidth;
    final scaleY = glyph.boxRect.height / srcPxHeight;
    // Where the *whole* cell lands once srcRect's crop is scaled onto
    // boxRect — the padding extends proportionally beyond boxRect on every
    // side, exactly like the shader will map it.
    final destLeft = glyph.boxRect.left - src.left * atlasRect.width * scaleX;
    final destTop = glyph.boxRect.top - src.top * atlasRect.height * scaleY;
    final dest = Rect.fromLTWH(
      destLeft,
      destTop,
      atlasRect.width * scaleX,
      atlasRect.height * scaleY,
    );
    canvas.drawImageRect(atlasImage, atlasRect, dest, paint);
  }
  final picture = recorder.endRecording();
  ui.Image? composited;
  try {
    composited = await picture.toImage(width, height);
    return await _alphaFromImage(composited);
  } finally {
    composited?.dispose();
    atlasImage.dispose();
  }
}

class _AlphaDelta {
  const _AlphaDelta({
    required this.pixelsOverThreshold,
    required this.maxDelta,
    required this.meanDelta,
  });

  final int pixelsOverThreshold;
  final int maxDelta;
  final double meanDelta;
}

class _SplitAlphaDelta {
  const _SplitAlphaDelta({required this.inside, required this.outside});

  /// Delta restricted to pixels inside at least one glyph's `boxRect` — the
  /// tiled ink area, which must never overlap and so must match exactly.
  final _AlphaDelta inside;

  /// Delta restricted to pixels outside every `boxRect` — the shadow/stroke
  /// bleed halo, where adjacent glyphs' padded cells can legitimately
  /// overlap on canvas. See the `atlas reassembly` group comment.
  final _AlphaDelta outside;
}

/// Compares two same-size alpha buffers, splitting the result by whether
/// each pixel falls inside any of [boxRects]. Buffers of different size
/// (which should not happen — both paths measure through the same
/// [TextOverlayLayout]) count every pixel as maximally different in both
/// buckets so the caller's assertion still fails loudly rather than
/// throwing an index error.
_SplitAlphaDelta _alphaDeltaSplitByBoxRects(
  _AlphaBuffer a,
  _AlphaBuffer b,
  List<Rect> boxRects,
) {
  if (a.width != b.width || a.height != b.height) {
    const maxedOut = _AlphaDelta(pixelsOverThreshold: 1 << 30, maxDelta: 255, meanDelta: 255);
    return const _SplitAlphaDelta(inside: maxedOut, outside: maxedOut);
  }

  bool insideAnyBoxRect(int x, int y) {
    final point = Offset(x + 0.5, y + 0.5);
    for (final r in boxRects) {
      if (r.contains(point)) return true;
    }
    return false;
  }

  var insideOver = 0;
  var insideMax = 0;
  var insideSum = 0;
  var insideCount = 0;
  var outsideOver = 0;
  var outsideMax = 0;
  var outsideSum = 0;
  var outsideCount = 0;

  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final delta = (a.at(x, y) - b.at(x, y)).abs();
      if (insideAnyBoxRect(x, y)) {
        insideSum += delta;
        insideCount++;
        if (delta > insideMax) insideMax = delta;
        if (delta > 32) insideOver++;
      } else {
        outsideSum += delta;
        outsideCount++;
        if (delta > outsideMax) outsideMax = delta;
        if (delta > 32) outsideOver++;
      }
    }
  }

  return _SplitAlphaDelta(
    inside: _AlphaDelta(
      pixelsOverThreshold: insideOver,
      maxDelta: insideMax,
      meanDelta: insideCount == 0 ? 0 : insideSum / insideCount,
    ),
    outside: _AlphaDelta(
      pixelsOverThreshold: outsideOver,
      maxDelta: outsideMax,
      meanDelta: outsideCount == 0 ? 0 : outsideSum / outsideCount,
    ),
  );
}

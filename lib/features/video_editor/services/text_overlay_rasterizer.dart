import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/captions/caption_highlight.dart';
import '../logic/captions/caption_highlight_layout.dart';
import '../logic/text_glyph_layout.dart';
import '../logic/text_overlay_geometry.dart';
import '../models/text_overlay_model.dart';

/// The result of packing padded glyph cells into rows at one density —
/// private plumbing between [TextOverlayRasterizer._packGlyphs] and the
/// density-search loop in [TextOverlayRasterizer.rasterizeAtlas].
class _Packing {
  const _Packing({
    required this.cells,
    required this.atlasWidth,
    required this.atlasHeight,
  });

  final List<Rect> cells;
  final double atlasWidth;
  final double atlasHeight;
}

/// One text overlay rendered to pixels, ready for the native overlay pass.
class RasterizedTextOverlay {
  const RasterizedTextOverlay({
    required this.pngPath,
    required this.canvasPxSize,
    required this.rasterPxSize,
  });

  /// The PNG's extent in preview-canvas pixels: [canvasPxSize] plus an even
  /// margin wide enough for the shadow and outline, centred on the box. The
  /// box's own outer padding is 8px, and a shadow reaches further than that —
  /// a raster the size of the box cut it off on the right and bottom. Even,
  /// so the raster's centre is the box's and the text lands where it did.
  final Size rasterPxSize;

  /// Temp PNG holding the text exactly as the preview draws it.
  final String pngPath;

  /// The overlay's box in **preview-canvas pixels**, before the user's pinch
  /// scale — the same box `text_overlay_layer.dart` lays out.
  final Size canvasPxSize;
}

/// One glyph's cell in the atlas, and where it belongs on the canvas.
///
/// A glyph carries **three** rects, and conflating any two of them
/// reintroduces the double-composited-ink bug this shape fixes:
///
/// - [atlasRect] (atlas px) — the whole padded cell. The padding is real ink
///   (shadow blur, stroke) and must live in the texture.
/// - [boxRect] (box px) — where the glyph is **placed**. These tile the box
///   and must never overlap, or reassembling cells with source-over blending
///   composites the shared ink twice. This is the glyph's *ink* rect, not
///   its padded one.
/// - [srcRect] (cell fractions) — which sub-rectangle of the cell corresponds
///   to [boxRect]; the padding sits outside it. The renderer maps [srcRect]
///   onto [boxRect] and lets the padding bleed beyond, so a shadow still
///   spills over its neighbours without any pixel being drawn twice.
class RasterizedGlyph {
  const RasterizedGlyph({
    required this.atlasRect,
    required this.boxRect,
    required this.srcRect,
    this.litAtlasRect,
    this.shadowAtlasRect,
    this.word = -1,
  });

  /// This glyph's shadow alone, in **atlas pixels** — a cell the size of
  /// [atlasRect], so [srcRect] serves it too. Null for a text without a
  /// shadow. Kept apart from the letter so every shadow can be drawn before
  /// any letter: baked into the letter's own cell, line 2's shadows landed on
  /// line 1's letters when the cells were put back in order.
  final Rect? shadowAtlasRect;

  /// The same glyph drawn in the highlight colour, in **atlas pixels** — a
  /// cell exactly the size of [atlasRect], so [srcRect] serves both. Null
  /// unless the caption's highlight recolours a word (colour, pop, karaoke).
  final Rect? litAtlasRect;

  /// The caption word this glyph belongs to, or -1 — ordinary text, or a mark
  /// between words.
  final int word;

  /// The cell's rect in **atlas pixels**, padding included.
  final Rect atlasRect;

  /// Where the glyph's ink is drawn, in **box-local canvas pixels** (origin
  /// at the text box's top-left, before the user's pinch scale). Tiles the
  /// box with its neighbours; never overlaps them.
  final Rect boxRect;

  /// The sub-rectangle of the cell — in **fractions of [atlasRect], 0..1** —
  /// that maps onto [boxRect]. The rest of the cell is bleed.
  final Rect srcRect;
}

/// A cell that is not a glyph — a word's pill, the text's background box —
/// and where it is placed. Both rects are exact: these cells carry no bleed.
class RasterizedCell {
  const RasterizedCell({required this.atlasRect, required this.boxRect});

  /// In atlas pixels.
  final Rect atlasRect;

  /// In box-local canvas pixels.
  final Rect boxRect;
}

/// A text overlay rasterised as a sprite sheet of glyphs.
///
/// The constructor is `const` so tests can build a fixture atlas without
/// running a rasteriser.
class RasterizedTextAtlas {
  const RasterizedTextAtlas({
    required this.pngPath,
    required this.canvasPxSize,
    required this.atlasPxSize,
    required this.glyphs,
    required this.backgroundRect,
    required this.borderRadius,
    this.pills = const [],
    this.background,
    this.highlight,
  });

  final String pngPath;

  /// The whole text box in canvas pixels — the same box `rasterize` reports.
  final Size canvasPxSize;

  final Size atlasPxSize;
  final List<RasterizedGlyph> glyphs;

  /// The background box in box-local canvas pixels, or null for no background.
  final Rect? backgroundRect;

  /// Background corner radius in canvas pixels.
  final double borderRadius;

  /// Per caption word, its pill cell — only for the pill highlight, and null
  /// for a word with no glyph.
  final List<RasterizedCell?> pills;

  /// The background box as a cell of its own, drawn behind every glyph as one
  /// quad — so a boxed text keeps the glyph path, and animates per character.
  final RasterizedCell? background;

  /// The caption's word highlight, or null for ordinary text.
  final CaptionHighlightLayout? highlight;
}

/// Empty atlas pixels between neighbouring cells.
///
/// The GPU samples a cell's edge between two texels, so a cell packed flush
/// against another reads a little of it. That was harmless while every cell
/// was a glyph with a transparent margin; a pill or a background box is solid
/// to its edge, and flush against a glyph it would draw a faint line of its
/// colour along that letter.
const double kAtlasCellGapPx = 2.0;

/// Rasterises a text overlay with Flutter's own text engine.
///
/// **This is what lets text export natively.** Reimplementing Flutter's text
/// layout in Android `Canvas` will not match — font metrics, stroke and shadow
/// all drift — so the pixels are produced by the same engine that draws the
/// preview and handed to the native overlay pass as an image.
///
/// The box, insets and styles all come from [TextOverlayLayout], the same
/// measurement the preview layer lays its widget out from; nothing here has
/// its own idea of what a text box looks like.
class TextOverlayRasterizer {
  /// The largest PNG side the raster will be written at. Hardware texture
  /// limits start at 4096 on the oldest supported parts.
  static const int kMaxRasterSidePx = 4096;

  /// The density [overlay] is drawn at for an export of [rasterScale]
  /// export-pixels per canvas-pixel.
  ///
  /// The user's pinch scale is folded in: a text scaled 3× on the canvas is
  /// drawn 3× larger in the file, and rasterising it at canvas density then
  /// upscaling in GL is exactly what makes exported text look soft. The
  /// density is capped so the PNG's longest side stays under
  /// [kMaxRasterSidePx].
  static double effectiveRasterScale({
    required double rasterScale,
    required double overlayScale,
    required Size canvasPxSize,
  }) {
    final wanted = math.max(1.0, rasterScale * math.max(overlayScale, 0.0));
    final longest = math.max(canvasPxSize.width, canvasPxSize.height);
    if (longest <= 0) return wanted;
    final cap = kMaxRasterSidePx / longest;
    return math.max(1.0, math.min(wanted, cap));
  }

  static Future<RasterizedTextOverlay?> rasterize({
    required TextOverlayModel overlay,
    required Size canvasSize,
    required double rasterScale,
  }) async {
    if (overlay.text.trim().isEmpty ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return null;
    }

    try {
      final layout = TextOverlayLayout.measure(overlay, canvasSize);
      final size = layout.boxSize;
      if (size.width <= 0 || size.height <= 0) return null;
      final inkScale = layout.inkScale;

      final density = effectiveRasterScale(
        rasterScale: rasterScale,
        overlayScale: overlay.scale,
        canvasPxSize: size,
      );

      // Whatever the box's own padding cannot hold of the shadow and outline.
      final margin = math.max(
        0.0,
        textGlyphBleedPadding(overlay, inkScale) -
            kTextOverlayOuterPadding * inkScale,
      );
      final rasterSize =
          Size(size.width + margin * 2, size.height + margin * 2);

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(density);
      canvas.translate(margin, margin);

      if (layout.hasBackground) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            layout.backgroundRect,
            Radius.circular(overlay.borderRadius * inkScale),
          ),
          Paint()..color = overlay.backgroundColor,
        );
      }

      // The text is laid out at exactly the width the layer gives its `Text`
      // widget (tight when the box was dragged wider), so alignment inside a
      // widened box lands where the preview put it.
      final textOrigin = layout.textOrigin;

      // Shadow, outline, fill — exactly as the canvas draws them.
      final strokePainter =
          TextOverlayLayout.strokePainterFor(overlay, inkScale)
            ?..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      final fillPainter = TextOverlayLayout.textPainterFor(overlay, inkScale)
        ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      paintTextOverlayInk(
        canvas,
        overlay: overlay,
        inkScale: inkScale,
        fill: fillPainter,
        stroke: strokePainter,
        textOrigin: textOrigin,
      );
      strokePainter?.dispose();
      fillPainter.dispose();

      final image = await recorder.endRecording().toImage(
            (rasterSize.width * density).ceil().clamp(1, kMaxRasterSidePx),
            (rasterSize.height * density).ceil().clamp(1, kMaxRasterSidePx),
          );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/text_overlay_${overlay.id}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());

      return RasterizedTextOverlay(
        pngPath: file.path,
        canvasPxSize: size,
        rasterPxSize: rasterSize,
      );
    } catch (error) {
      debugPrint('[TextRaster] ${overlay.id} failed: $error');
      return null;
    }
  }

  /// Rasterises [overlay] as a sprite sheet: one cell per inked character.
  ///
  /// The cells are packed into rows rather than laid out as they appear on
  /// screen, so a wide single line does not force a wide, mostly-empty
  /// texture. Each cell is padded by the shadow blur plus the stroke width,
  /// because both extend past a glyph's ink and would otherwise bleed into
  /// the neighbouring cell — but the padded rect is only ever drawn *into*
  /// the atlas; a glyph's on-canvas placement ([RasterizedGlyph.boxRect])
  /// is its unpadded ink rect, because padded rects of neighbouring glyphs
  /// overlap in box space and reassembling them would composite the shared
  /// ink twice.
  ///
  /// Returns null when there is nothing to draw, or when even the smallest
  /// usable density still overflows the texture limit — the caller falls
  /// back to the flat raster. That should be rare: the density is reduced
  /// and the atlas repacked first.
  static Future<RasterizedTextAtlas?> rasterizeAtlas({
    required TextOverlayModel overlay,
    required Size canvasSize,
    required double rasterScale,
  }) async {
    if (overlay.text.trim().isEmpty ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return null;
    }

    try {
      final layout = TextOverlayLayout.measure(overlay, canvasSize);
      final boxSize = layout.boxSize;
      if (boxSize.width <= 0 || boxSize.height <= 0) return null;
      final inkScale = layout.inkScale;

      // The same padding `TextOverlayPainter` clips its preview glyphs to —
      // one definition, so the canvas shows exactly what this atlas stores.
      final shadowPadding = textGlyphBleedPadding(overlay, inkScale);
      final glyphBoxes = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvasSize,
        shadowPadding: shadowPadding,
      );
      if (glyphBoxes.isEmpty) return null;

      var density = effectiveRasterScale(
        rasterScale: rasterScale,
        overlayScale: overlay.scale,
        canvasPxSize: boxSize,
      );

      // Beyond one cell per glyph: the glyphs again in the highlight colour,
      // a pill per word, and the background box — packed into the one sheet.
      final highlight = CaptionHighlightLayout.of(overlay, glyphBoxes);
      final style = highlight?.highlight.style;
      final needsLit = style == CaptionHighlightStyle.colour ||
          style == CaptionHighlightStyle.pop ||
          style == CaptionHighlightStyle.karaoke;
      final pillRects = style == CaptionHighlightStyle.pill
          ? [for (var w = 0; w < highlight!.wordBoxes.length; w++) highlight.pillRect(w)]
          : const <Rect?>[];
      final sizes = <Size>[for (final g in glyphBoxes) g.paddedRect.size];
      final litFrom = sizes.length;
      if (needsLit) sizes.addAll([for (final g in glyphBoxes) g.paddedRect.size]);
      // Each letter's shadow in a cell of its own, so the native pass can draw
      // every shadow before any letter, as the canvas does.
      final shadowed = TextOverlayLayout.hasShadow(overlay);
      final shadowFrom = sizes.length;
      if (shadowed) sizes.addAll([for (final g in glyphBoxes) g.paddedRect.size]);
      final pillCell = <int, int>{};
      for (var w = 0; w < pillRects.length; w++) {
        final rect = pillRects[w];
        if (rect == null) continue;
        pillCell[w] = sizes.length;
        sizes.add(rect.size);
      }
      final backgroundCell = layout.hasBackground ? sizes.length : -1;
      if (layout.hasBackground) sizes.add(layout.backgroundRect.size);

      // The 4096 cap must bind the *atlas* (the packed cells), not the box —
      // packed into rows, the atlas can be far larger than the box the
      // flat raster measures against. Pack at the wanted density; if it
      // overflows, shrink density by exactly the overflow ratio and repack.
      // Shrinking can itself change where rows wrap, so this is iterated
      // (converges in a couple of steps in practice) rather than assumed to
      // land in one shot, and bounded so a pathological case cannot loop.
      _Packing packing = _packCells(sizes, density);
      var attempts = 0;
      while ((packing.atlasWidth > kMaxRasterSidePx ||
              packing.atlasHeight > kMaxRasterSidePx) &&
          attempts < 6) {
        final overflow = math.max(
          packing.atlasWidth / kMaxRasterSidePx,
          packing.atlasHeight / kMaxRasterSidePx,
        );
        if (overflow <= 1.0) break;
        density = density / overflow;
        if (density < 1.0) {
          density = 1.0;
        }
        packing = _packCells(sizes, density);
        attempts++;
      }

      final atlasWidth = packing.atlasWidth;
      final atlasHeight = packing.atlasHeight;
      if (atlasWidth <= 0 ||
          atlasHeight <= 0 ||
          atlasWidth > kMaxRasterSidePx ||
          atlasHeight > kMaxRasterSidePx) {
        debugPrint(
          '[TextAtlas] ${overlay.id} atlas would not fit even at floor '
          'density: ${atlasWidth}x$atlasHeight vs cap $kMaxRasterSidePx',
        );
        return null;
      }
      final cells = packing.cells;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final fillPainter = TextOverlayLayout.textPainterFor(overlay, inkScale)
        ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      final strokePainter =
          TextOverlayLayout.strokePainterFor(overlay, inkScale)
            ?..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      final litPainter = needsLit
          ? (TextOverlayLayout.textPainterFor(
              overlay.copyWith(color: highlight!.highlight.color),
              inkScale,
            )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth))
          : null;
      ui.Image? image;
      try {
        // Each cell draws the *whole* text translated so that this glyph's
        // padded rect lands on the cell, clipped to the cell. Drawing the
        // whole run keeps kerning, ligatures and alignment identical to the
        // flat raster; the clip is what isolates one character. The shadow
        // is this glyph's alone — see [paintTextOverlayInk].
        // The same ink regions the canvas painter draws each glyph within, so
        // a cell holds its own letter and never a neighbour's or the other
        // line's — the export put cells back together that, at caption size,
        // each carried bits of the line next to them.
        final regions = glyphInkRegions(glyphBoxes);
        for (var i = 0; i < glyphBoxes.length; i++) {
          final glyph = glyphBoxes[i];
          final cell = cells[i];
          canvas.save();
          canvas.clipRect(cell);
          canvas.translate(cell.left, cell.top);
          canvas.scale(density);
          canvas.translate(-glyph.paddedRect.left, -glyph.paddedRect.top);
          paintTextOverlayInk(
            canvas,
            overlay: overlay,
            inkScale: inkScale,
            fill: fillPainter,
            stroke: strokePainter,
            textOrigin: layout.textOrigin,
            shadowFrom: glyph.inkRect,
            inkWithin: regions[i],
            shadow: !shadowed,
          );
          canvas.restore();
        }

        // The shadow cells: each letter's shadow, cast from its own tile,
        // and nothing else.
        if (shadowed) {
          for (var i = 0; i < glyphBoxes.length; i++) {
            final glyph = glyphBoxes[i];
            final cell = cells[shadowFrom + i];
            canvas.save();
            canvas.clipRect(cell);
            canvas.translate(cell.left, cell.top);
            canvas.scale(density);
            canvas.translate(-glyph.paddedRect.left, -glyph.paddedRect.top);
            paintTextOverlayInk(
              canvas,
              overlay: overlay,
              inkScale: inkScale,
              fill: fillPainter,
              stroke: strokePainter,
              textOrigin: layout.textOrigin,
              shadowFrom: glyph.inkRect,
              ink: false,
            );
            canvas.restore();
          }
        }

        // The lit cells: the same glyph, the same outline and shadow, the
        // fill in the highlight colour — what the preview paints with its
        // lit painter.
        if (litPainter != null) {
          for (var i = 0; i < glyphBoxes.length; i++) {
            final glyph = glyphBoxes[i];
            final cell = cells[litFrom + i];
            canvas.save();
            canvas.clipRect(cell);
            canvas.translate(cell.left, cell.top);
            canvas.scale(density);
            canvas.translate(-glyph.paddedRect.left, -glyph.paddedRect.top);
            paintTextOverlayInk(
              canvas,
              overlay: overlay,
              inkScale: inkScale,
              fill: litPainter,
              stroke: strokePainter,
              textOrigin: layout.textOrigin,
              shadowFrom: glyph.inkRect,
              inkWithin: regions[i],
              shadow: !shadowed,
            );
            canvas.restore();
          }
        }

        // A rounded box drawn whole into its cell.
        void box(Rect cell, Rect rect, double radius, Color colour) {
          canvas.save();
          canvas.clipRect(cell);
          canvas.translate(cell.left, cell.top);
          canvas.scale(density);
          canvas.translate(-rect.left, -rect.top);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(radius)),
            Paint()..color = colour,
          );
          canvas.restore();
        }

        pillCell.forEach((w, index) {
          box(cells[index], pillRects[w]!, highlight!.pillRadius(w), highlight.highlight.color);
        });
        if (backgroundCell >= 0) {
          box(
            cells[backgroundCell],
            layout.backgroundRect,
            overlay.borderRadius * inkScale,
            overlay.backgroundColor,
          );
        }

        image = await recorder.endRecording().toImage(
              atlasWidth.ceil().clamp(1, kMaxRasterSidePx),
              atlasHeight.ceil().clamp(1, kMaxRasterSidePx),
            );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) return null;

        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/text_atlas_${overlay.id}_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes.buffer.asUint8List());

        return RasterizedTextAtlas(
          pngPath: file.path,
          canvasPxSize: boxSize,
          atlasPxSize: Size(atlasWidth, atlasHeight),
          glyphs: [
            for (var i = 0; i < glyphBoxes.length; i++)
              _glyphFor(
                glyphBoxes[i],
                cells[i],
                lit: needsLit ? cells[litFrom + i] : null,
                shadow: shadowed ? cells[shadowFrom + i] : null,
                word: highlight?.glyphWord[i] ?? -1,
              ),
          ],
          backgroundRect: layout.hasBackground ? layout.backgroundRect : null,
          borderRadius: overlay.borderRadius * inkScale,
          pills: [
            for (var w = 0; w < pillRects.length; w++)
              pillCell[w] == null
                  ? null
                  : RasterizedCell(atlasRect: cells[pillCell[w]!], boxRect: pillRects[w]!),
          ],
          background: backgroundCell >= 0
              ? RasterizedCell(
                  atlasRect: cells[backgroundCell],
                  boxRect: layout.backgroundRect,
                )
              : null,
          highlight: highlight,
        );
      } finally {
        fillPainter.dispose();
        strokePainter?.dispose();
        litPainter?.dispose();
        image?.dispose();
      }
    } catch (error) {
      debugPrint('[TextAtlas] ${overlay.id} failed: $error');
      return null;
    }
  }

  /// Builds the placement rect for one glyph: [cell] in atlas pixels, and
  /// [srcRect] as the fraction of [cell] that the glyph's own ink occupies
  /// — derived from where [TextGlyphBox.inkRect] sits inside its
  /// [TextGlyphBox.paddedRect], so it stays correct even if padding is not
  /// symmetric on every side.
  static RasterizedGlyph _glyphFor(
    TextGlyphBox glyph,
    Rect cell, {
    Rect? lit,
    Rect? shadow,
    int word = -1,
  }) {
    final padded = glyph.paddedRect;
    final ink = glyph.inkRect;
    final srcRect = padded.width > 0 && padded.height > 0
        ? Rect.fromLTRB(
            (ink.left - padded.left) / padded.width,
            (ink.top - padded.top) / padded.height,
            (ink.right - padded.left) / padded.width,
            (ink.bottom - padded.top) / padded.height,
          )
        : const Rect.fromLTWH(0, 0, 1, 1);
    return RasterizedGlyph(
      atlasRect: cell,
      boxRect: ink,
      srcRect: srcRect,
      litAtlasRect: lit,
      shadowAtlasRect: shadow,
      word: word,
    );
  }

  /// Packs cells of [sizes] (canvas pixels), scaled by [density], into rows
  /// no wider than [kMaxRasterSidePx] — a pure function of density so
  /// [rasterizeAtlas] can call it repeatedly while narrowing down to a
  /// density whose atlas actually fits.
  static _Packing _packCells(List<Size> sizes, double density) {
    final cells = <Rect>[];
    var penX = 0.0;
    var penY = 0.0;
    var rowHeight = 0.0;
    var atlasWidth = 0.0;
    for (final size in sizes) {
      final w = size.width * density;
      final h = size.height * density;
      if (penX > 0 && penX + w > kMaxRasterSidePx) {
        penX = 0;
        penY += rowHeight + kAtlasCellGapPx;
        rowHeight = 0;
      }
      cells.add(Rect.fromLTWH(penX, penY, w, h));
      atlasWidth = math.max(atlasWidth, penX + w);
      penX += w + kAtlasCellGapPx;
      rowHeight = math.max(rowHeight, h);
    }
    return _Packing(cells: cells, atlasWidth: atlasWidth, atlasHeight: penY + rowHeight);
  }

}

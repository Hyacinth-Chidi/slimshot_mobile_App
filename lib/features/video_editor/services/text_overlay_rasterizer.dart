import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../logic/text_glyph_layout.dart';
import '../logic/text_overlay_geometry.dart';
import '../models/text_overlay_model.dart';

/// One text overlay rendered to pixels, ready for the native overlay pass.
class RasterizedTextOverlay {
  const RasterizedTextOverlay({
    required this.pngPath,
    required this.canvasPxSize,
  });

  /// Temp PNG holding the text exactly as the preview draws it.
  final String pngPath;

  /// The overlay's box in **preview-canvas pixels**, before the user's pinch
  /// scale — the same box `text_overlay_layer.dart` lays out.
  final Size canvasPxSize;
}

/// One glyph's cell in the atlas, and where it belongs on the canvas.
class RasterizedGlyph {
  const RasterizedGlyph({required this.atlasRect, required this.boxRect});

  /// The cell's rect in **atlas pixels**.
  final Rect atlasRect;

  /// Where the cell is drawn, in **box-local canvas pixels** (origin at the
  /// text box's top-left, before the user's pinch scale).
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
}

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
      final renderScale = layout.renderScale;

      final density = effectiveRasterScale(
        rasterScale: rasterScale,
        overlayScale: overlay.scale,
        canvasPxSize: size,
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(density);

      if (layout.hasBackground) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            layout.backgroundRect,
            Radius.circular(overlay.borderRadius * renderScale),
          ),
          Paint()..color = overlay.backgroundColor,
        );
      }

      // The text is laid out at exactly the width the layer gives its `Text`
      // widget (tight when the box was dragged wider), so alignment inside a
      // widened box lands where the preview put it.
      final textOrigin = layout.textOrigin;
      final textAlign = TextOverlayLayout.textAlignFor(overlay);

      // Stroke under fill, exactly as the layer stacks its two Text widgets.
      if (TextOverlayLayout.hasStroke(overlay)) {
        final strokePainter = TextPainter(
          text: TextSpan(
            text: overlay.text,
            style: TextOverlayLayout.strokeStyleFor(overlay, renderScale),
          ),
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: TextScaler.noScaling,
        )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
        strokePainter.paint(canvas, textOrigin);
        strokePainter.dispose();
      }
      final fillPainter = TextOverlayLayout.textPainterFor(overlay, renderScale)
        ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      fillPainter.paint(canvas, textOrigin);
      fillPainter.dispose();

      final image = await recorder.endRecording().toImage(
            (size.width * density).ceil().clamp(1, kMaxRasterSidePx),
            (size.height * density).ceil().clamp(1, kMaxRasterSidePx),
          );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) return null;

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/text_overlay_${overlay.id}_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());

      return RasterizedTextOverlay(pngPath: file.path, canvasPxSize: size);
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
  /// the neighbouring cell.
  ///
  /// Returns null when there is nothing to draw, or when the atlas would
  /// exceed the texture limit — the caller falls back to the flat raster.
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
      final renderScale = layout.renderScale;

      final shadowPadding = _bleedPadding(overlay, renderScale);
      final glyphBoxes = layoutTextGlyphs(
        overlay: overlay,
        canvasSize: canvasSize,
        shadowPadding: shadowPadding,
      );
      if (glyphBoxes.isEmpty) return null;

      final density = effectiveRasterScale(
        rasterScale: rasterScale,
        overlayScale: overlay.scale,
        canvasPxSize: boxSize,
      );

      // Pack cells into rows no wider than the texture limit.
      final cells = <Rect>[];
      var penX = 0.0;
      var penY = 0.0;
      var rowHeight = 0.0;
      var atlasWidth = 0.0;
      for (final glyph in glyphBoxes) {
        final w = glyph.paddedRect.width * density;
        final h = glyph.paddedRect.height * density;
        if (penX > 0 && penX + w > kMaxRasterSidePx) {
          penX = 0;
          penY += rowHeight;
          rowHeight = 0;
        }
        cells.add(Rect.fromLTWH(penX, penY, w, h));
        penX += w;
        rowHeight = math.max(rowHeight, h);
        atlasWidth = math.max(atlasWidth, penX);
      }
      final atlasHeight = penY + rowHeight;
      if (atlasWidth <= 0 ||
          atlasHeight <= 0 ||
          atlasWidth > kMaxRasterSidePx ||
          atlasHeight > kMaxRasterSidePx) {
        return null;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final textAlign = TextOverlayLayout.textAlignFor(overlay);
      final fillPainter = TextOverlayLayout.textPainterFor(overlay, renderScale)
        ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      TextPainter? strokePainter;
      if (TextOverlayLayout.hasStroke(overlay)) {
        strokePainter = TextPainter(
          text: TextSpan(
            text: overlay.text,
            style: TextOverlayLayout.strokeStyleFor(overlay, renderScale),
          ),
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: TextScaler.noScaling,
        )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      }

      // Each cell draws the *whole* text translated so that this glyph's
      // padded rect lands on the cell, clipped to the cell. Drawing the whole
      // run keeps kerning, ligatures and alignment identical to the flat
      // raster; the clip is what isolates one character.
      for (var i = 0; i < glyphBoxes.length; i++) {
        final glyph = glyphBoxes[i];
        final cell = cells[i];
        canvas.save();
        canvas.clipRect(cell);
        canvas.translate(cell.left, cell.top);
        canvas.scale(density);
        canvas.translate(-glyph.paddedRect.left, -glyph.paddedRect.top);
        strokePainter?.paint(canvas, layout.textOrigin);
        fillPainter.paint(canvas, layout.textOrigin);
        canvas.restore();
      }

      fillPainter.dispose();
      strokePainter?.dispose();

      final image = await recorder.endRecording().toImage(
            atlasWidth.ceil().clamp(1, kMaxRasterSidePx),
            atlasHeight.ceil().clamp(1, kMaxRasterSidePx),
          );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
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
            RasterizedGlyph(
              atlasRect: cells[i],
              boxRect: glyphBoxes[i].paddedRect,
            ),
        ],
        backgroundRect: layout.hasBackground ? layout.backgroundRect : null,
        borderRadius: overlay.borderRadius * renderScale,
      );
    } catch (error) {
      debugPrint('[TextAtlas] ${overlay.id} failed: $error');
      return null;
    }
  }

  /// How far ink can extend past a glyph's box: the shadow's blur and its
  /// offset, plus half the stroke width, which straddles the glyph's edge.
  static double _bleedPadding(TextOverlayModel overlay, double renderScale) {
    var padding = 0.0;
    if (overlay.shadowColor != Colors.transparent &&
        overlay.shadowBlurRadius > 0) {
      final blur = overlay.shadowBlurRadius * renderScale;
      padding = math.max(padding, blur + blur / 2);
    }
    if (TextOverlayLayout.hasStroke(overlay)) {
      padding = math.max(padding, overlay.strokeWidth * renderScale / 2);
    }
    return padding;
  }
}

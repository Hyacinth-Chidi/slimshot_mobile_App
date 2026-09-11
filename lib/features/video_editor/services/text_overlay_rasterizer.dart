import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

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
}

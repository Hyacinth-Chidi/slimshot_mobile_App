import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';
import '../utils/font_utils.dart';

/// The one definition of a text overlay's box.
///
/// `text_overlay_layer.dart` lays the preview widget out from this, and
/// `TextOverlayRasterizer` paints the export raster from this, so the two can
/// only disagree if one of them stops calling it. Every constant that shapes
/// the box lives here for the same reason — the layer and the rasteriser used
/// to carry their own copies and drifted the moment one was edited.
///
/// Units: the overlay stores its geometry in **reference-canvas pixels** (the
/// preview canvas it was created on) and the layout converts to whatever
/// canvas is being drawn through [renderScale]. `position` is the box centre's
/// offset from the canvas centre; `boxWidth` is the *outer* box width the user
/// dragged the edge handles to, or null for "as wide as the text".
const double kTextOverlayFontSize = 32.0;
const double kTextOverlayLineHeight = 1.15;

/// Clear space between the text (or its background) and the box edge.
const double kTextOverlayOuterPadding = 8.0;

/// The narrowest a user can drag a box. Flutter breaks words at character
/// level below their width, so nothing hangs outside the box at any width.
const double kMinTextBoxWidth = 60.0;

/// How far a text box can be widened, in reference pixels — generous rather
/// than tied to the canvas, because a box wider than the canvas is a legitimate
/// way to force a single line that then gets scaled down.
const double kMaxTextBoxWidth = 4000.0;

/// A box with no dragged width wraps at the reference canvas width minus this,
/// so a long line breaks with a margin on either side instead of at the edge.
const double kDefaultTextBoxMargin = 32.0;

const double kMinTextScale = 0.2;
const double kMaxTextScale = 5.0;

/// The scale an emoji dropped from the picker starts at.
///
/// An emoji is inserted as a text overlay, and at the caption size every other
/// text starts at it reads as punctuation rather than as a sticker. This is
/// only a starting *value* — the pinch gesture, the Transform sheet and
/// keyframes all treat it as any other scale, so nothing downstream knows an
/// emoji from a word. Inside [kMinTextScale]..[kMaxTextScale] by construction.
const double kEmojiOverlayScale = 2.5;

/// Reference → render pixel factor for [overlay] on [canvasSize].
double textOverlayRenderScale(TextOverlayModel overlay, Size canvasSize) {
  final refSize = overlay.referenceCanvasSize;
  final scaleX =
      refSize != null && refSize.width > 0 ? canvasSize.width / refSize.width : 1.0;
  final scaleY = refSize != null && refSize.height > 0
      ? canvasSize.height / refSize.height
      : 1.0;
  return math.min(scaleX, scaleY);
}

/// A text overlay measured for one canvas, in **render pixels** of that canvas.
class TextOverlayLayout {
  const TextOverlayLayout({
    required this.renderScale,
    required this.boxSize,
    required this.textWidth,
    required this.textHeight,
    required this.hasBackground,
    required this.outerPadding,
    required this.backgroundPaddingH,
    required this.backgroundPaddingV,
  });

  final double renderScale;

  /// The whole box: text, background insets and outer padding.
  final Size boxSize;

  /// The width the text is laid out at. With a dragged [TextOverlayModel.boxWidth]
  /// this is the box's inner width and the text aligns within it; otherwise it
  /// is the text's own width.
  final double textWidth;
  final double textHeight;

  final bool hasBackground;
  final double outerPadding;
  final double backgroundPaddingH;
  final double backgroundPaddingV;

  /// Where the text's top-left sits inside the box.
  Offset get textOrigin => Offset(
        outerPadding + backgroundPaddingH,
        outerPadding + backgroundPaddingV,
      );

  /// The background's rectangle inside the box.
  Rect get backgroundRect => Rect.fromLTWH(
        outerPadding,
        outerPadding,
        boxSize.width - outerPadding * 2,
        boxSize.height - outerPadding * 2,
      );

  /// Measures [overlay] on [canvasSize].
  static TextOverlayLayout measure(TextOverlayModel overlay, Size canvasSize) {
    final renderScale = textOverlayRenderScale(overlay, canvasSize);
    final hasBackground = overlay.backgroundColor != Colors.transparent;
    final outerPadding = kTextOverlayOuterPadding * renderScale;
    final backgroundPaddingH =
        hasBackground ? overlay.backgroundPadding * renderScale : 0.0;
    final backgroundPaddingV =
        hasBackground ? (overlay.backgroundPadding / 2) * renderScale : 0.0;
    final horizontalInsets = (outerPadding + backgroundPaddingH) * 2;
    final verticalInsets = (outerPadding + backgroundPaddingV) * 2;

    // Unset: wrap at the canvas the text was created on, minus a margin, so
    // a long line wraps rather than running off both edges. Set: the box is
    // exactly that wide and the text aligns inside it.
    final refWidth = overlay.referenceCanvasSize?.width ?? canvasSize.width;
    final outerWidth = overlay.boxWidth == null
        ? math.max(kMinTextBoxWidth, refWidth - kDefaultTextBoxMargin) * renderScale
        : overlay.boxWidth!.clamp(kMinTextBoxWidth, kMaxTextBoxWidth) *
            renderScale;
    final innerMaxWidth = math.max(0.0, outerWidth - horizontalInsets);
    final innerMinWidth = overlay.boxWidth == null ? 0.0 : innerMaxWidth;

    final painter = textPainterFor(overlay, renderScale)
      ..layout(minWidth: innerMinWidth, maxWidth: innerMaxWidth);
    final textWidth = painter.width;
    final textHeight = painter.height;
    painter.dispose();

    return TextOverlayLayout(
      renderScale: renderScale,
      boxSize: Size(textWidth + horizontalInsets, textHeight + verticalInsets),
      textWidth: textWidth,
      textHeight: textHeight,
      hasBackground: hasBackground,
      outerPadding: outerPadding,
      backgroundPaddingH: backgroundPaddingH,
      backgroundPaddingV: backgroundPaddingV,
    );
  }

  /// The fill painter for [overlay], unlaid. Stroke painters take the same
  /// span with a stroking `foreground` — see [strokeStyleFor].
  static TextPainter textPainterFor(TextOverlayModel overlay, double renderScale) {
    return TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: fillStyleFor(overlay, renderScale),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlignFor(overlay),
      // The preview `Text` widgets opt out of the system font scale for the
      // same reason: a phone set to "large text" must not grow the preview
      // while the export stays put.
      textScaler: TextScaler.noScaling,
    );
  }

  static TextAlign textAlignFor(TextOverlayModel overlay) {
    return switch (overlay.textAlign) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.center,
    };
  }

  static List<Shadow> shadowsFor(TextOverlayModel overlay, double renderScale) {
    if (overlay.shadowColor == Colors.transparent ||
        overlay.shadowBlurRadius <= 0) {
      return const <Shadow>[];
    }
    final blur = overlay.shadowBlurRadius * renderScale;
    return [
      Shadow(color: overlay.shadowColor, blurRadius: blur, offset: Offset(blur / 2, blur / 2)),
    ];
  }

  static TextStyle fillStyleFor(TextOverlayModel overlay, double renderScale) {
    return getFontStyle(
      overlay.fontFamily,
      fontSize: kTextOverlayFontSize * renderScale,
      color: overlay.color,
      height: kTextOverlayLineHeight,
      shadows: shadowsFor(overlay, renderScale),
    );
  }

  static bool hasStroke(TextOverlayModel overlay) {
    return overlay.strokeColor != Colors.transparent && overlay.strokeWidth > 0;
  }

  static TextStyle strokeStyleFor(TextOverlayModel overlay, double renderScale) {
    return getFontStyle(
      overlay.fontFamily,
      fontSize: kTextOverlayFontSize * renderScale,
      height: kTextOverlayLineHeight,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlay.strokeWidth * renderScale
        ..color = overlay.strokeColor,
      shadows: shadowsFor(overlay, renderScale),
    );
  }
}

/// The box's centre on the canvas, in render pixels.
Offset textOverlayCenter(
  TextOverlayModel overlay,
  Size canvasSize,
  double renderScale,
) {
  final clamped = clampTextOverlayPosition(overlay.position, canvasSize, renderScale);
  return Offset(
    canvasSize.width / 2 + clamped.dx * renderScale,
    canvasSize.height / 2 + clamped.dy * renderScale,
  );
}

/// Keeps the box's centre on the canvas. [position] is in reference pixels
/// and so is the result.
Offset clampTextOverlayPosition(Offset position, Size canvasSize, double renderScale) {
  if (renderScale <= 0) return position;
  final maxDx = canvasSize.width / 2;
  final maxDy = canvasSize.height / 2;
  final render = position * renderScale;
  return Offset(
        render.dx.clamp(-maxDx, maxDx).toDouble(),
        render.dy.clamp(-maxDy, maxDy).toDouble(),
      ) /
      renderScale;
}

/// The native overlay pass contain-fits content inside a box that is a
/// **square in pixels** — that is the image overlays' contract (200×200), and
/// `OverlayRenderer.writeCorners` derives the fit from the content's aspect
/// on that assumption. Handing it a box that already has the raster's shape
/// applied the aspect twice, which squashed every exported text: one-liners
/// lost most of their height, tall blocks most of their width. So a raster is
/// sent in the smallest square that contains it, and the fit lands on the
/// raster's exact size.
Size textOverlayFitBox(Size rasterCanvasPx) {
  final side = math.max(rasterCanvasPx.width, rasterCanvasPx.height);
  return Size(side, side);
}

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';
import 'animation/animatable_double.dart';
import 'animation/overlay_keyframes.dart';
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
/// canvas is being drawn — through [TextOverlayLayout.canvasScale] for where
/// the box sits and how wide it wraps, and [TextOverlayLayout.inkScale] for
/// what the text draws, which also carries its Size. `position` is the box centre's
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

/// Reference → render pixel factor for [overlay] on [canvasSize] — the
/// **geometry** scale: where a text sits and how wide its box is.
double textOverlayRenderScale(TextOverlayModel overlay, Size canvasSize) {
  final refSize = overlay.referenceCanvasSize;
  final scaleX =
      refSize != null && refSize.width > 0 ? canvasSize.width / refSize.width : 1.0;
  final scaleY = refSize != null && refSize.height > 0
      ? canvasSize.height / refSize.height
      : 1.0;
  return math.min(scaleX, scaleY);
}

/// The letters' em size in **reference** pixels: the text's Size against its
/// frame's short side, or — for a text made before sizes existed — the 32
/// pixels every text used to be.
double textEmSize(TextOverlayModel overlay, Size canvasSize) {
  final size = overlay.fontSize;
  if (size == null) return kTextOverlayFontSize;
  final side = (overlay.referenceCanvasSize ?? canvasSize).shortestSide;
  return side > 0 ? size / 1000 * side : kTextOverlayFontSize;
}

/// The Size a text shows on the ruler: its own, or — for a text made before
/// sizes existed — the one its letters have, so moving the ruler starts from
/// where the letters already are.
double textSizeOf(TextOverlayModel overlay, Size canvasSize) {
  final size = overlay.fontSize;
  if (size != null) return size;
  final side = (overlay.referenceCanvasSize ?? canvasSize).shortestSide;
  return side > 0 ? kTextOverlayFontSize / side * 1000 : kDefaultTextSize;
}

/// Reference → render factor for what a text **draws** — letters, outline,
/// shadow, background padding and radius, the box's own padding: the canvas
/// scale times the text's Size. See [TextOverlayLayout.inkScale].
double textInkScale(TextOverlayModel overlay, Size canvasSize) =>
    textOverlayRenderScale(overlay, canvasSize) *
    textEmSize(overlay, canvasSize) /
    kTextOverlayFontSize;

/// A text overlay measured for one canvas, in **render pixels** of that canvas.
///
/// **Two scales, and every caller chooses which it means.** [canvasScale] is
/// geometry — where the box sits, how wide it may wrap. [inkScale] is what
/// the text draws — its letters and everything that keeps proportion with
/// them. They differ by the text's Size, and that difference *is* the Size:
/// bigger letters in the same width re-wrap, and a look keeps its proportions.
/// There used to be one `renderScale`; it was removed rather than kept beside
/// these, so no caller could go on using it without deciding.
class TextOverlayLayout {
  const TextOverlayLayout({
    required this.canvasScale,
    required this.inkScale,
    required this.boxSize,
    required this.textWidth,
    required this.textHeight,
    required this.hasBackground,
    required this.outerPadding,
    required this.backgroundPaddingH,
    required this.backgroundPaddingV,
    double? backgroundTextWidth,
    this.backgroundAlign = 0.5,
  }) : backgroundTextWidth = backgroundTextWidth ?? textWidth;

  /// Reference → render pixels for geometry: positions and the wrap width.
  final double canvasScale;

  /// Reference → render pixels for what the text draws: the canvas scale
  /// times its Size ([textInkScale]).
  final double inkScale;

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

  /// How much of [textWidth] the background wraps: all of it, except on a
  /// caption, where it is the longest line — see [backgroundRect].
  final double backgroundTextWidth;

  /// Where a narrower background sits across the text: 0 left, 0.5 centred,
  /// 1 right — the lines' own alignment.
  final double backgroundAlign;

  /// Where the text's top-left sits inside the box.
  Offset get textOrigin => Offset(
        outerPadding + backgroundPaddingH,
        outerPadding + backgroundPaddingV,
      );

  /// The background's rectangle inside the box.
  ///
  /// **A caption's hugs its words.** A caption carries its set's wrap width,
  /// one the user never chose, so a background spanning the box drew a band
  /// most of the canvas wide behind a single word. It wraps the longest line
  /// instead, placed by the lines' alignment; the box the user grabs keeps the
  /// set's width. Plain text with a width of its own keeps a background as
  /// wide as the box — a banner is what widening it made.
  Rect get backgroundRect => Rect.fromLTWH(
        outerPadding + (textWidth - backgroundTextWidth) * backgroundAlign,
        outerPadding,
        backgroundTextWidth + backgroundPaddingH * 2,
        boxSize.height - outerPadding * 2,
      );

  /// Measures [overlay] on [canvasSize].
  static TextOverlayLayout measure(TextOverlayModel overlay, Size canvasSize) {
    final canvasScale = textOverlayRenderScale(overlay, canvasSize);
    final inkScale = textInkScale(overlay, canvasSize);
    final hasBackground = overlay.backgroundColor != Colors.transparent;
    // The box's own padding and the background's grow with the letters, so a
    // look keeps its proportions at any Size.
    final outerPadding = kTextOverlayOuterPadding * inkScale;
    final backgroundPaddingH =
        hasBackground ? overlay.backgroundPadding * inkScale : 0.0;
    final backgroundPaddingV =
        hasBackground ? (overlay.backgroundPadding / 2) * inkScale : 0.0;
    final horizontalInsets = (outerPadding + backgroundPaddingH) * 2;
    final verticalInsets = (outerPadding + backgroundPaddingV) * 2;

    // Unset: wrap at the canvas the text was created on, minus a margin, so
    // a long line wraps rather than running off both edges. Set: the box is
    // exactly that wide and the text aligns inside it. **Geometry, not ink**:
    // the width does not grow with the Size, which is what makes bigger
    // letters re-wrap rather than run off the frame.
    final refWidth = overlay.referenceCanvasSize?.width ?? canvasSize.width;
    final outerWidth = overlay.boxWidth == null
        ? math.max(kMinTextBoxWidth, refWidth - kDefaultTextBoxMargin) * canvasScale
        : overlay.boxWidth!.clamp(kMinTextBoxWidth, kMaxTextBoxWidth) *
            canvasScale;
    final innerMaxWidth = math.max(0.0, outerWidth - horizontalInsets);
    final innerMinWidth = overlay.boxWidth == null ? 0.0 : innerMaxWidth;

    final painter = textPainterFor(overlay, inkScale)
      ..layout(minWidth: innerMinWidth, maxWidth: innerMaxWidth);
    final textWidth = painter.width;
    final textHeight = painter.height;
    final hugsWords = hasBackground && overlay.isCaption;
    final longestLine = hugsWords
        ? painter
            .computeLineMetrics()
            .fold<double>(0, (widest, line) => math.max(widest, line.width))
        : textWidth;
    painter.dispose();

    return TextOverlayLayout(
      canvasScale: canvasScale,
      inkScale: inkScale,
      boxSize: Size(textWidth + horizontalInsets, textHeight + verticalInsets),
      textWidth: textWidth,
      textHeight: textHeight,
      hasBackground: hasBackground,
      outerPadding: outerPadding,
      backgroundPaddingH: backgroundPaddingH,
      backgroundPaddingV: backgroundPaddingV,
      backgroundTextWidth: math.min(longestLine, textWidth),
      backgroundAlign: switch (overlay.textAlign) {
        'left' || 'start' || 'justify' => 0.0,
        'right' || 'end' => 1.0,
        _ => 0.5,
      },
    );
  }

  /// The fill painter for [overlay], unlaid. Stroke painters take the same
  /// span with a stroking `foreground` — see [strokePainterFor]. Neither
  /// carries the shadow: [paintTextOverlayInk] casts it.
  static TextPainter textPainterFor(
    TextOverlayModel overlay,
    double inkScale,
  ) {
    return TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: fillStyleFor(overlay, inkScale),
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

  /// Whether a shadow is drawn: a colour, some opacity, and somewhere to be
  /// seen — with no blur *and* no distance it would sit exactly under the
  /// letters. Blur 0 with a distance is the crisp, hard shadow.
  static bool hasShadow(TextOverlayModel overlay) =>
      overlay.shadowColor != Colors.transparent &&
      overlay.shadowOpacity > 0 &&
      (overlay.shadowBlurRadius > 0 || overlay.shadowDistance > 0);

  /// The colour the shadow is drawn in: [TextOverlayModel.shadowColor] with
  /// its opacity folded into the alpha.
  static Color shadowColorFor(TextOverlayModel overlay) =>
      overlay.shadowColor.withValues(
        alpha: overlay.shadowColor.a * overlay.shadowOpacity,
      );

  /// Where the shadow sits relative to the text, in render pixels: the
  /// distance along the angle, clockwise from pointing right.
  static Offset shadowOffsetFor(TextOverlayModel overlay, double inkScale) {
    final radians = overlay.shadowAngle * math.pi / 180;
    final distance = overlay.shadowDistance * inkScale;
    return Offset(math.cos(radians) * distance, math.sin(radians) * distance);
  }

  /// The shadow's blur, as the Gaussian sigma a `Shadow` of that radius
  /// would use, in render pixels.
  static double shadowSigmaFor(TextOverlayModel overlay, double inkScale) =>
      Shadow.convertRadiusToSigma(overlay.shadowBlurRadius * inkScale);

  /// How far the shadow reaches past the ink it is cast from, in render
  /// pixels, in its **farthest** direction: the offset plus three sigmas of
  /// Flutter's own blur, beyond which a Gaussian has nothing left to draw.
  ///
  /// Anything that stores a shadow — the export raster's margin, an atlas
  /// cell's padding — must be at least this big, or the shadow is cut off in
  /// a straight line. It used to be sized by 1.5 × the blur *radius*, which
  /// is short of this down and to the right, so the file kept the shadow's
  /// soft left and top and lost the rest: "the shadow is only on the left".
  static double shadowReachFor(TextOverlayModel overlay, double inkScale) {
    if (!hasShadow(overlay)) return 0;
    return shadowOffsetFor(overlay, inkScale).distance +
        3 * shadowSigmaFor(overlay, inkScale);
  }

  /// The fill's style. **No shadow**: see [paintTextOverlayInk].
  static TextStyle fillStyleFor(TextOverlayModel overlay, double inkScale) {
    return getFontStyle(
      overlay.fontFamily,
      fontSize: kTextOverlayFontSize * inkScale,
      color: overlay.color,
      height: kTextOverlayLineHeight,
    );
  }

  /// The outline, as a painter laid out like the fill — or null when the text
  /// has none. The one place an outline painter is built, so the canvas, the
  /// flat raster and the atlas stack the same layers.
  static TextPainter? strokePainterFor(
    TextOverlayModel overlay,
    double inkScale,
  ) {
    if (!hasStroke(overlay)) return null;
    return TextPainter(
      text: TextSpan(
        text: overlay.text,
        style: strokeStyleFor(overlay, inkScale),
      ),
      textDirection: TextDirection.ltr,
      textAlign: textAlignFor(overlay),
      textScaler: TextScaler.noScaling,
    );
  }

  static bool hasStroke(TextOverlayModel overlay) {
    return overlay.strokeColor != Colors.transparent && overlay.strokeWidth > 0;
  }

  /// The outline's style. **No shadow**: see [paintTextOverlayInk].
  static TextStyle strokeStyleFor(
    TextOverlayModel overlay,
    double inkScale,
  ) {
    return getFontStyle(
      overlay.fontFamily,
      fontSize: kTextOverlayFontSize * inkScale,
      height: kTextOverlayLineHeight,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = overlay.strokeWidth * inkScale
        ..color = overlay.strokeColor,
    );
  }
}

/// Paints a text's ink — its shadow, then the outline, then the fill — at
/// [textOrigin] in box-local pixels. **The only thing that draws a text's
/// shadow**: the canvas (still and animated), the flat export raster and the
/// glyph atlas all come here, so they cannot disagree about it.
///
/// [fill] and [stroke] come from [TextOverlayLayout.textPainterFor] and
/// [TextOverlayLayout.strokePainterFor], laid out; neither carries a shadow.
///
/// The shadow is the text's silhouette — outline included — in the shadow's
/// colour, blurred and offset, **once**, under everything. It used to ride on
/// the text styles instead, and that went wrong three ways, each measured:
/// both the outline's style and the fill's carried one, so an outlined text
/// had two and the fill's was painted over the outline; a `Shadow`'s blur
/// ignores the canvas scale, so the export — drawn at 2–3× — got a shadow
/// roughly twice as sharp as the preview; and a glyph-atlas cell carried the
/// whole run's shadow, composited twice wherever cells overlapped.
///
/// [shadowFrom], when given, casts the shadow from only that part of the
/// text: a glyph's own tile, so each atlas cell and each animated letter
/// carries its own letter's shadow and nothing else. Tiles never overlap, so
/// every letter's shadow is drawn exactly once, and a letter that moves takes
/// its shadow with it.
///
/// [shadow] and [ink] draw one half each, for a caller drawing letter by
/// letter in **two passes** — every letter's shadow, then every letter's ink —
/// so a shadow lies under every letter as it does when the text is drawn
/// whole. One pass per letter put line 2's shadow over line 1's letters.
///
/// [inkWithin], when given, bounds the outline and fill — a glyph's ink
/// region (`glyphInkRegions`). A cell draws the whole run for kerning's sake,
/// and without this bound a cell padded for its shadow drew its neighbours
/// too, including letters on the next line, in its own colour and motion.
void paintTextOverlayInk(
  Canvas canvas, {
  required TextOverlayModel overlay,
  required double inkScale,
  required TextPainter fill,
  required TextPainter? stroke,
  required Offset textOrigin,
  Rect? shadowFrom,
  Rect? inkWithin,
  bool shadow = true,
  bool ink = true,
}) {
  if (shadow && TextOverlayLayout.hasShadow(overlay)) {
    final sigma = TextOverlayLayout.shadowSigmaFor(overlay, inkScale);
    final offset = TextOverlayLayout.shadowOffsetFor(overlay, inkScale);
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    // The layer takes the silhouette in whatever colours the text has; the
    // colour filter turns it into the shadow's colour, alpha included, and
    // the blur softens it with the same sigma a `Shadow` of that radius uses
    // — in the canvas's own units, so it scales with the export's density.
    canvas.saveLayer(
      null,
      Paint()
        ..imageFilter = ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.decal,
        )
        ..colorFilter = ColorFilter.mode(
          TextOverlayLayout.shadowColorFor(overlay),
          BlendMode.srcIn,
        ),
    );
    // Not antialiased: each pixel belongs wholly to one glyph's tile. An
    // antialiased clip splits a boundary pixel between the two cells that
    // share it, and source-over puts the halves back together short of
    // whole — a hairline seam through a hard shadow at every letter
    // (measured: 198 px off the flat raster at a far hard shadow; 7 without).
    if (shadowFrom != null) canvas.clipRect(shadowFrom, doAntiAlias: false);
    stroke?.paint(canvas, textOrigin);
    fill.paint(canvas, textOrigin);
    canvas.restore();
    canvas.restore();
  }
  if (!ink) return;
  if (inkWithin != null) {
    canvas.save();
    // Not antialiased, for the shadow's reason: a boundary pixel split
    // between two regions would be put back short of whole.
    canvas.clipRect(inkWithin, doAntiAlias: false);
  }
  stroke?.paint(canvas, textOrigin);
  fill.paint(canvas, textOrigin);
  if (inkWithin != null) canvas.restore();
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

/// A text overlay's placement on the wire to the engine: its centre as canvas
/// fractions, its scale, rotation and opacity — each an [AnimatableDouble]
/// carrying the text's keyframes, and a bare number while it has none.
///
/// The centre goes through [textOverlayCenter], the layer's own placement,
/// **one axis at a time**: its clamp is per axis, so x never depends on y and
/// each track maps alone. Mapping keyframe values rather than resolved ones is
/// exact wherever the values sit inside the canvas — there the clamp is the
/// identity and the map affine, see [mapAnimatable] — which is everywhere the
/// layer lets a drag put a text.
({
  AnimatableDouble centerX,
  AnimatableDouble centerY,
  AnimatableDouble scale,
  AnimatableDouble rotation,
  AnimatableDouble opacity,
}) textOverlayWirePlacement(TextOverlayModel overlay, Size canvasSize) {
  final renderScale = textOverlayRenderScale(overlay, canvasSize);
  final params = overlay.motion.params;
  return (
    centerX: mapAnimatable(
      params[OverlayProperty.x]!,
      (v) =>
          textOverlayCenter(
            overlay.copyWith(position: Offset(v, overlay.position.dy)),
            canvasSize,
            renderScale,
          ).dx /
          canvasSize.width,
    ),
    centerY: mapAnimatable(
      params[OverlayProperty.y]!,
      (v) =>
          textOverlayCenter(
            overlay.copyWith(position: Offset(overlay.position.dx, v)),
            canvasSize,
            renderScale,
          ).dy /
          canvasSize.height,
    ),
    scale: params[OverlayProperty.scale]!,
    rotation: params[OverlayProperty.rotation]!,
    opacity: params[OverlayProperty.opacity]!,
  );
}

/// The largest scale [overlay] reaches: the highest point on its keyframed
/// scale track, else its base.
///
/// The export rasterises a text at a density that folds in its scale. Drawn
/// at the base while a keyframe zooms it past that, the end of the zoom would
/// be an upscaled raster — soft beside the crisp preview. Every easing curve
/// stays between its two keyframes, so the highest keyframe is the highest
/// point.
double textOverlayPeakScale(TextOverlayModel overlay) {
  final track = overlay.keyframes.of(OverlayProperty.scale);
  if (track.isEmpty) return overlay.scale;
  return track.map((k) => k.value).reduce(math.max);
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

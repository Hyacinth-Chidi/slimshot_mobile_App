import 'dart:ui';

import '../logic/text_overlay_geometry.dart';
import '../models/editor_timeline.dart';
import 'text_overlay_rasterizer.dart';

/// The box dimensions to send as an overlay's `boxWidth`/`boxHeight`, in
/// canvas pixels. The two raster paths need **different** boxes, and sending
/// the wrong one distorts the text:
///
/// - **Flat raster** ([usingAtlas] false): a pixel *square*. The native pass
///   contain-fits the PNG inside the box and derives the fit from the image's
///   own aspect, so a box that already carries the raster's shape applies the
///   aspect twice and squashes the text. See [textOverlayFitBox].
/// - **Glyph atlas** ([usingAtlas] true): the **true, non-square** text box.
///   A glyph's `boxRect` is a fraction of that real box, and the glyph branch
///   of `OverlayRenderer.writeCorners` multiplies by the box dimensions
///   *directly* with no contain-fit — a cell already has the right shape, so
///   fitting it again would letterbox a letter. Handing it the square made a
///   glyph spanning a 176x53 box draw 176px tall: a 3.3x vertical stretch.
///
/// Both branches leave the centre alone: `centerX`/`centerY` come from
/// `textOverlayCenter` and do not depend on the box dimensions.
Size textOverlayBoxPx(Size boxPxSize, {required bool usingAtlas}) {
  return usingAtlas ? boxPxSize : textOverlayFitBox(boxPxSize);
}

/// The atlas's glyph cells as timeline glyphs — pixels converted to fractions
/// at this boundary, so the renderer never sees a device resolution.
///
/// Three rects, three different denominators, and getting one wrong is the
/// easiest mistake here:
///
/// - `atlasRect` is **atlas pixels** → divided by the atlas size.
/// - `boxRect` is **box-local canvas pixels** → divided by the text box size.
/// - `srcRect` is **already a fraction of its own cell** → passed through
///   untouched. Dividing it by anything yields values that still look
///   plausible (small, 0..1) while silently mis-sampling every glyph's bleed,
///   and nothing downstream can tell.
///
/// A degenerate atlas or box would divide by zero and emit infinities, which
/// reach the renderer as nonsense geometry rather than as an error, so they
/// yield no glyphs — the caller falls back to the flat raster.
List<EditorTimelineGlyph> glyphsForAtlas(RasterizedTextAtlas atlas) {
  final aw = atlas.atlasPxSize.width;
  final ah = atlas.atlasPxSize.height;
  final bw = atlas.canvasPxSize.width;
  final bh = atlas.canvasPxSize.height;
  if (aw <= 0 || ah <= 0 || bw <= 0 || bh <= 0) return const [];

  return [
    for (final glyph in atlas.glyphs)
      EditorTimelineGlyph(
        atlasLeft: glyph.atlasRect.left / aw,
        atlasTop: glyph.atlasRect.top / ah,
        atlasRight: glyph.atlasRect.right / aw,
        atlasBottom: glyph.atlasRect.bottom / ah,
        boxLeft: glyph.boxRect.left / bw,
        boxTop: glyph.boxRect.top / bh,
        boxRight: glyph.boxRect.right / bw,
        boxBottom: glyph.boxRect.bottom / bh,
        // Already a fraction of the cell. Not divided by anything.
        srcLeft: glyph.srcRect.left,
        srcTop: glyph.srcRect.top,
        srcRight: glyph.srcRect.right,
        srcBottom: glyph.srcRect.bottom,
      ),
  ];
}

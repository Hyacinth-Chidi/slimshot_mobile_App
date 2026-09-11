import '../models/editor_timeline.dart';
import 'text_overlay_rasterizer.dart';

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

import 'dart:ui';

import '../logic/animation/animatable_double.dart';
import '../logic/preview_text/preview_text_rules.dart';
import '../logic/text_overlay_geometry.dart';
import '../models/editor_timeline.dart';
import '../models/text_overlay_model.dart';
import 'text_overlay_rasterizer.dart';

/// A text's overlay entry, drawn from its atlas — **the one builder**, for
/// the export and the preview alike, so the engine is handed the same entry
/// whichever of the two made the atlas.
///
/// [atlasCanvasSize] is the canvas the atlas was made at, when that is not
/// [canvasSize]. The box, its background and the slide travel are measured
/// against it, as fractions; the placement against [canvasSize]. Text is laid
/// out relative to the canvas, so the fractions are the same on any canvas,
/// and an atlas made before the keyboard resized the canvas places exactly
/// the box one made after would.
///
/// [hidden] sends the text at no opacity: the engine keeps the atlas loaded,
/// so the moment the text stops being edited it can draw it, and draws
/// nothing for it meanwhile.
EditorTimelineOverlay textAtlasOverlayEntry(
  TextOverlayModel text,
  RasterizedTextAtlas atlas,
  Size canvasSize, {
  Size? atlasCanvasSize,
  bool hidden = false,
}) {
  final measuredOn = atlasCanvasSize ?? canvasSize;
  final boxPxSize = atlas.canvasPxSize;

  // The layer's own placement, in canvas fractions, keyframes and all: the
  // box centre is the canvas centre plus the (clamped) offset — the same
  // helper the layer positions its widget with.
  final placement = textOverlayWirePlacement(text, canvasSize);

  // The glyph path multiplies each cell's fraction by the box directly and so
  // takes the true text box — see `textOverlayBoxPx`.
  final fitBox = textOverlayBoxPx(boxPxSize, usingAtlas: true);
  final boxDivW = boxPxSize.width == 0 ? 1.0 : boxPxSize.width;
  final boxDivH = boxPxSize.height == 0 ? 1.0 : boxPxSize.height;

  return EditorTimelineOverlay(
    id: previewTextEntryId(text.id),
    kind: 'text',
    path: atlas.atlasPath,
    glyphs: glyphsForAtlas(atlas),
    backgroundLeft: (atlas.backgroundRect?.left ?? 0) / boxDivW,
    backgroundTop: (atlas.backgroundRect?.top ?? 0) / boxDivH,
    backgroundRight: (atlas.backgroundRect?.right ?? 0) / boxDivW,
    backgroundBottom: (atlas.backgroundRect?.bottom ?? 0) / boxDivH,
    backgroundRadius: atlas.borderRadius / boxDivW,
    backgroundAtlas: backgroundAtlasFor(atlas),
    highlight: highlightForAtlas(atlas),
    centerX: placement.centerX,
    centerY: placement.centerY,
    boxWidth: fitBox.width / measuredOn.width,
    boxHeight: fitBox.height / measuredOn.height,
    scale: placement.scale,
    rotation: placement.rotation,
    // The text's own, where a constant 1.0 used to go: opacity is a placement
    // property now, keyframable like the rest.
    opacity: hidden ? const AnimatableDouble(baseValue: 0) : placement.opacity,
    startSeconds: text.startTime.inMilliseconds / 1000.0,
    endSeconds: text.endTime.inMilliseconds / 1000.0,
    // Above every image/video overlay, matching the preview's stacking where
    // the text layer sits on top.
    laneIndex: 1000 + text.laneIndex,
    // flutter_animate slides by the widget's own size, not the image
    // overlays' fixed 200px, so the travel is the raster's own box.
    slideOffsetX: boxPxSize.width / measuredOn.width,
    slideOffsetY: boxPxSize.height / measuredOn.height,
    // The glyph path resolves ids through the catalog
    // (`TextAnimationCurves.resolveAnimationId`), which knows the legacy names
    // and resolves them *by slot*; it must receive the id as the model stores
    // it. (The flat-raster fallback draws through the image overlay's own
    // `stateAt`, whose vocabulary differs — the export translates for it.)
    animationIn: _catalogTextAnimation(text.inAnimation),
    animationOut: _catalogTextAnimation(text.outAnimation),
    animationLoop: _catalogTextAnimation(text.loopAnimation),
    // Speeds, not durations. Native resolves the window lengths itself from
    // the catalog, the glyph count and the speed — a staggered animation's
    // length depends on how many characters there are, which the composer
    // would otherwise have to recompute and keep in step across the boundary.
    speedIn: text.animationInDuration,
    speedOut: text.animationOutDuration,
    speedLoop: text.loopSpeed,
    animationInSeconds: 0.5,
    animationOutSeconds: 0.5,
  );
}

/// A stored animation id on its way to the **glyph** path, which resolves it
/// through the catalog on the Kotlin side.
///
/// Deliberately no translation: `TextAnimationCurves.resolveAnimationId`
/// holds the legacy tables and applies them **by slot**, which is the only
/// place that mapping may live — a second copy here would be one more thing
/// to keep in step across a boundary nothing type-checks. All this does is
/// spell `'none'` as null, which is what the contract's nullable field means.
String? _catalogTextAnimation(String name) {
  if (name.isEmpty || name == 'none') return null;
  return name;
}

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
        litAtlasLeft: glyph.litAtlasRect == null ? null : glyph.litAtlasRect!.left / aw,
        litAtlasTop: glyph.litAtlasRect == null ? null : glyph.litAtlasRect!.top / ah,
        litAtlasRight: glyph.litAtlasRect == null ? null : glyph.litAtlasRect!.right / aw,
        litAtlasBottom: glyph.litAtlasRect == null ? null : glyph.litAtlasRect!.bottom / ah,
        shadowAtlasLeft: glyph.shadowAtlasRect == null ? null : glyph.shadowAtlasRect!.left / aw,
        shadowAtlasTop: glyph.shadowAtlasRect == null ? null : glyph.shadowAtlasRect!.top / ah,
        shadowAtlasRight: glyph.shadowAtlasRect == null ? null : glyph.shadowAtlasRect!.right / aw,
        shadowAtlasBottom: glyph.shadowAtlasRect == null ? null : glyph.shadowAtlasRect!.bottom / ah,
        word: glyph.word >= 0 ? glyph.word : null,
      ),
  ];
}

/// The caption's highlight as the timeline sends it — words in text-box
/// fractions, times in seconds from the caption's start, pills in atlas and
/// box fractions. Null for ordinary text, or a degenerate atlas.
EditorTimelineTextHighlight? highlightForAtlas(RasterizedTextAtlas atlas) {
  final highlight = atlas.highlight;
  final aw = atlas.atlasPxSize.width;
  final ah = atlas.atlasPxSize.height;
  final bw = atlas.canvasPxSize.width;
  final bh = atlas.canvasPxSize.height;
  if (highlight == null || aw <= 0 || ah <= 0 || bw <= 0 || bh <= 0) {
    return null;
  }
  List<double> atlasFractions(Rect r) => [r.left / aw, r.top / ah, r.right / aw, r.bottom / ah];
  List<double> boxFractions(Rect r) => [r.left / bw, r.top / bh, r.right / bw, r.bottom / bh];

  return EditorTimelineTextHighlight(
    style: highlight.highlight.style.name,
    words: [
      for (var w = 0; w < highlight.spans.length; w++)
        () {
          final box = highlight.wordBoxes[w] ?? Rect.zero;
          final pill = w < atlas.pills.length ? atlas.pills[w] : null;
          return EditorTimelineHighlightWord(
            start: highlight.spans[w].start,
            end: highlight.spans[w].end,
            left: box.left / bw,
            top: box.top / bh,
            right: box.right / bw,
            bottom: box.bottom / bh,
            rtl: highlight.wordRtl[w],
            pillAtlas: pill == null ? null : atlasFractions(pill.atlasRect),
            pillBox: pill == null ? null : boxFractions(pill.boxRect),
          );
        }(),
    ],
  );
}

/// The background box's cell in atlas fractions, or null with no box.
List<double>? backgroundAtlasFor(RasterizedTextAtlas atlas) {
  final cell = atlas.background;
  final aw = atlas.atlasPxSize.width;
  final ah = atlas.atlasPxSize.height;
  if (cell == null || aw <= 0 || ah <= 0) return null;
  return [
    cell.atlasRect.left / aw,
    cell.atlasRect.top / ah,
    cell.atlasRect.right / aw,
    cell.atlasRect.bottom / ah,
  ];
}

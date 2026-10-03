
// Explicit rather than leaning on `material.dart`'s re-export: cluster
// iteration is load-bearing here, not incidental.
// ignore: unnecessary_import
import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../models/text_overlay_model.dart';
import 'text_overlay_geometry.dart';

/// One character's place in a laid-out text box.
///
/// Rects are **box-local pixels** — origin at the text box's top-left, the
/// same space [TextOverlayLayout.textOrigin] lives in — so a glyph can be
/// placed without re-deriving the box.
class TextGlyphBox {
  const TextGlyphBox({
    required this.charIndex,
    required this.inkRect,
    required this.paddedRect,
  });

  /// The **UTF-16 offset** into [TextOverlayModel.text] of the first code unit
  /// of this glyph's grapheme cluster.
  ///
  /// These are cluster *starts*, so they are not contiguous, for two reasons:
  /// whitespace is skipped, and a cluster can span several code units — 👍 is a
  /// surrogate pair, 👍🏽 adds a skin-tone modifier, 🇬🇧 is two regional
  /// indicators, and a combining accent trails its base letter. An animation
  /// that staggers by character must use this, not the list index, or a space
  /// would not consume a beat of the stagger.
  final int charIndex;

  /// Where the glyph's own pixels land.
  final Rect inkRect;

  /// [inkRect] grown by the shadow/stroke bleed, which is the rect the atlas
  /// actually stores. Shadows extend past a glyph's ink and would otherwise
  /// contaminate the neighbouring atlas cell.
  final Rect paddedRect;
}

/// How far a glyph's ink can extend past its box: half the stroke width,
/// which straddles the glyph's edge, plus the shadow's reach beyond that —
/// the shadow is cast from the outline when there is one, so it starts where
/// the outline ends. Symmetric, sized for the shadow's farthest direction.
///
/// **One definition, two consumers, and they must not drift.**
/// `TextOverlayRasterizer` pads the atlas cells it *writes* by this, and
/// `TextOverlayPainter` clips the preview glyphs it *draws* to the same rect —
/// so the preview is showing exactly what the export samples. Two copies of
/// this arithmetic (which is what there were) desync silently: the file and the
/// canvas would clip a shadow differently with nothing failing anywhere.
double textGlyphBleedPadding(TextOverlayModel overlay, double inkScale) {
  final stroke = TextOverlayLayout.hasStroke(overlay)
      ? overlay.strokeWidth * inkScale / 2
      : 0.0;
  final shadow = TextOverlayLayout.shadowReachFor(overlay, inkScale);
  // A pixel of slack, rounded up: the blur's tail is sampled on whole pixels.
  return shadow > 0 ? (stroke + shadow + 1).ceilToDouble() : stroke;
}

/// Where every character of [overlay] sits, using Flutter's own text layout.
///
/// This asks `TextPainter` for each character's box rather than measuring
/// characters independently: kerning, ligatures and bidi mean the width of
/// "AV" is not the width of "A" plus the width of "V", and per-character
/// measurement would drift from what the flat raster draws.
List<TextGlyphBox> layoutTextGlyphs({
  required TextOverlayModel overlay,
  required Size canvasSize,
  required double shadowPadding,
}) {
  if (overlay.text.isEmpty) return const [];

  final layout = TextOverlayLayout.measure(overlay, canvasSize);
  final painter = TextOverlayLayout.textPainterFor(overlay, layout.inkScale)
    ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);

  final origin = layout.textOrigin;
  final glyphs = <TextGlyphBox>[];

  // Iterate **grapheme clusters**, not code units. A `TextSelection` of one
  // code unit selects half a surrogate pair, and `getBoxesForSelection`
  // returns nothing for half a character — so 👍 produced no box at all and
  // vanished from the atlas. Clusters cover the rest of the same family:
  // skin-tone modifiers, flags (two regional indicators) and combining
  // accents are all one glyph spanning several code units, which iterating
  // runes would still split.
  var offset = 0;
  for (final cluster in overlay.text.characters) {
    // `cluster.length` is in UTF-16 code units, which is what `TextSelection`
    // indexes by — so the running offset stays in the painter's own units.
    final start = offset;
    offset += cluster.length;

    // Whitespace has no ink; drawing a quad for it wastes a draw call and
    // gives an empty atlas cell.
    if (cluster.trim().isEmpty) continue;

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: offset),
    );
    if (boxes.isEmpty) continue;

    final box = boxes.first.toRect().shift(origin);
    if (box.width <= 0 || box.height <= 0) continue;

    glyphs.add(
      TextGlyphBox(
        charIndex: start,
        inkRect: box,
        paddedRect: box.inflate(shadowPadding),
      ),
    );
  }

  painter.dispose();
  return glyphs;
}

/// How far a glyph's ink region reaches past the boundary it shares with a
/// neighbour, in box-local pixels — so the two regions overlap by a sliver
/// and no seam can open between letters that touch, in the preview or once
/// the export's atlas cells are put back together.
const double kGlyphInkRegionOverlap = 1.0;

/// Per glyph, the region its **visible ink** may be drawn in — its outline
/// and fill — in box-local pixels, in the same order as [glyphs].
///
/// Each glyph is drawn on its own, as the whole text run clipped to its
/// padded cell (kerning and ligatures make that the only exact way), and the
/// padding — sized for the outline and shadow — is tall enough at caption
/// size to reach the next line. So a cell drew **other letters**: harmless
/// while every letter looks alike, wrong the moment they differ. On a
/// two-line caption a line-2 cell repainted line-1 letters in line 2's state
/// — a sweep left white holes in words already spoken, and Pop dragged a
/// scaled ghost of line 1 across it (device-reported).
///
/// A region is bounded halfway to the neighbouring glyph on its line and
/// halfway to the neighbouring line, plus [kGlyphInkRegionOverlap]; where
/// there is no neighbour it keeps the cell's padding, so an outline at the
/// edge of the text is never cut. Halfway into a space means two words never
/// share pixels. The shadow is not bound by this: it is cast from the glyph's
/// own tile (`paintTextOverlayInk`'s `shadowFrom`) and may spill as far as
/// the cell allows.
List<Rect> glyphInkRegions(List<TextGlyphBox> glyphs) {
  if (glyphs.isEmpty) return const [];

  // Lines, by where their glyphs' boxes sit: glyphs on one line share a top.
  final rows = <List<int>>[];
  final rowTops = <double>[];
  for (var i = 0; i < glyphs.length; i++) {
    final top = glyphs[i].inkRect.top;
    var row = rowTops.indexWhere((t) => (t - top).abs() < 0.5);
    if (row < 0) {
      rows.add(<int>[]);
      rowTops.add(top);
      row = rows.length - 1;
    }
    rows[row].add(i);
  }
  final order = List<int>.generate(rows.length, (r) => r)
    ..sort((a, b) => rowTops[a].compareTo(rowTops[b]));
  double rowTop(int r) =>
      rows[r].map((i) => glyphs[i].inkRect.top).reduce((a, b) => a < b ? a : b);
  double rowBottom(int r) =>
      rows[r].map((i) => glyphs[i].inkRect.bottom).reduce((a, b) => a > b ? a : b);

  final regions = List<Rect>.filled(glyphs.length, Rect.zero);
  for (var k = 0; k < order.length; k++) {
    final r = order[k];
    final above = k > 0 ? order[k - 1] : null;
    final below = k + 1 < order.length ? order[k + 1] : null;
    final line = [...rows[r]]
      ..sort((a, b) => glyphs[a].inkRect.left.compareTo(glyphs[b].inkRect.left));
    for (var j = 0; j < line.length; j++) {
      final g = glyphs[line[j]];
      final prev = j > 0 ? glyphs[line[j - 1]] : null;
      final next = j + 1 < line.length ? glyphs[line[j + 1]] : null;
      final region = Rect.fromLTRB(
        prev == null
            ? g.paddedRect.left
            : (prev.inkRect.right + g.inkRect.left) / 2 - kGlyphInkRegionOverlap,
        above == null
            ? g.paddedRect.top
            : (rowBottom(above) + rowTop(r)) / 2 - kGlyphInkRegionOverlap,
        next == null
            ? g.paddedRect.right
            : (g.inkRect.right + next.inkRect.left) / 2 + kGlyphInkRegionOverlap,
        below == null
            ? g.paddedRect.bottom
            : (rowBottom(r) + rowTop(below)) / 2 + kGlyphInkRegionOverlap,
      );
      // Never wider than the cell the glyph is drawn into anyway.
      regions[line[j]] = region.intersect(g.paddedRect);
    }
  }
  return regions;
}

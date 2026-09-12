import 'dart:math' as math;

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

/// How far a glyph's ink can extend past its box: the shadow's blur and its
/// offset, plus half the stroke width, which straddles the glyph's edge.
///
/// **One definition, two consumers, and they must not drift.**
/// `TextOverlayRasterizer` pads the atlas cells it *writes* by this, and
/// `TextOverlayPainter` clips the preview glyphs it *draws* to the same rect —
/// so the preview is showing exactly what the export samples. Two copies of
/// this arithmetic (which is what there were) desync silently: the file and the
/// canvas would clip a shadow differently with nothing failing anywhere.
double textGlyphBleedPadding(TextOverlayModel overlay, double renderScale) {
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
  final painter = TextOverlayLayout.textPainterFor(overlay, layout.renderScale)
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

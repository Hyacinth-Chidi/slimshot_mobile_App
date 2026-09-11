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

  /// Index into [TextOverlayModel.text]. Whitespace is skipped, so these are
  /// not contiguous — an animation that staggers by character must use this,
  /// not the list index, or a space would not consume a beat of the stagger.
  final int charIndex;

  /// Where the glyph's own pixels land.
  final Rect inkRect;

  /// [inkRect] grown by the shadow/stroke bleed, which is the rect the atlas
  /// actually stores. Shadows extend past a glyph's ink and would otherwise
  /// contaminate the neighbouring atlas cell.
  final Rect paddedRect;
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

  for (var i = 0; i < overlay.text.length; i++) {
    // Whitespace has no ink; drawing a quad for it wastes a draw call and
    // gives an empty atlas cell.
    if (overlay.text[i].trim().isEmpty) continue;

    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    if (boxes.isEmpty) continue;

    final box = boxes.first.toRect().shift(origin);
    if (box.width <= 0 || box.height <= 0) continue;

    glyphs.add(
      TextGlyphBox(
        charIndex: i,
        inkRect: box,
        paddedRect: box.inflate(shadowPadding),
      ),
    );
  }

  painter.dispose();
  return glyphs;
}

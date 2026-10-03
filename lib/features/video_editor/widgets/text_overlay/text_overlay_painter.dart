import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/captions/caption_highlight_catalog.dart';
import '../../logic/captions/caption_highlight_layout.dart';
import '../../logic/text_animation_catalog.dart';
import '../../logic/text_glyph_layout.dart';
import '../../logic/text_overlay_geometry.dart';
import '../../models/text_overlay_model.dart';

/// Paints one text overlay's box on the preview canvas, per character.
///
/// **This is the preview half of a pair.** `VideoExportEngine.textDraws` builds
/// one quad per glyph from exactly the same three inputs — the boxes
/// [layoutTextGlyphs] measures, the [TextAnimationTiming] windows, and the
/// catalog's own curves — and `OverlayRenderer.writeCorners` applies the same
/// transform to each. The preview used to animate the whole box through
/// `flutter_animate`'s fixed half-second chain, which is why a per-character
/// export and the canvas showed different pictures; the fix is not a second
/// implementation of the same motion but the *same* definition driving both.
///
/// Anything that changes here — the transform order, the units, which rect a
/// glyph is clipped to — has to change in `OverlayRenderer.writeCorners` with
/// it.
class TextOverlayPainter extends CustomPainter {
  TextOverlayPainter({
    required this.overlay,
    required this.layout,
    required this.canvasSize,
    required this.positionSeconds,
  });

  final TextOverlayModel overlay;
  final TextOverlayLayout layout;

  /// The preview canvas the overlay is measured against — [layoutTextGlyphs]
  /// needs it to re-derive the same render scale [layout] carries.
  final Size canvasSize;

  /// The playhead, in **timeline** seconds. The animation windows are anchored
  /// to the overlay's own start and end, so this is the one clock both the
  /// preview and the export read.
  final double positionSeconds;

  /// Measured lazily and kept, because both [paint] and [shouldRepaint] need
  /// it and measuring means running Flutter's text layout. A painter instance
  /// is rebuilt whenever the overlay or the canvas changes, so nothing here
  /// can go stale.
  List<TextGlyphBox>? _glyphs;
  TextAnimationTiming? _timing;
  bool _timingResolved = false;

  List<TextGlyphBox> get _glyphBoxes =>
      _glyphs ??= glyphBoxesFor(overlay, canvasSize);

  CaptionHighlightLayout? _highlight;
  bool _highlightResolved = false;

  /// The caption's word highlight, or null — measured lazily, like the
  /// glyphs, and only for a caption that has one.
  CaptionHighlightLayout? get _highlightLayout {
    if (!_highlightResolved) {
      _highlightResolved = true;
      _highlight = _hasHighlight
          ? CaptionHighlightLayout.of(overlay, _glyphBoxes)
          : null;
    }
    return _highlight;
  }

  /// Cheap: no measuring. A caption with a style and words to mark.
  bool get _hasHighlight =>
      !overlay.highlight.isNone && (overlay.captionWords?.isNotEmpty ?? false);

  /// Whether any word looks different at [then] than at [positionSeconds] —
  /// read from the words' times alone, with no layout, so asking is cheap.
  bool _wordStatesDiffer(double then) {
    final spans = wordSpansOf(overlay.captionWords!);
    final start = overlay.startTime.inMicroseconds / 1e6;
    final span = (overlay.endTime - overlay.startTime).inMicroseconds / 1e6;
    WordHighlightState at(int word, double seconds) => wordHighlightStateAt(
          style: overlay.highlight.style,
          t: seconds - start,
          words: spans,
          index: word,
          spanSeconds: span,
        );
    for (var w = 0; w < spans.length; w++) {
      if (at(w, then) != at(w, positionSeconds)) return true;
    }
    return false;
  }

  /// The animation windows, or null when the text has no inked glyph to
  /// stagger across.
  TextAnimationTiming? get _animationTiming {
    if (!_timingResolved) {
      _timingResolved = true;
      // Measuring the glyphs is a full text layout, and an overlay with every
      // animation field at 'none' cannot possibly need it — which is most of
      // them, on a layer that rebuilds at the position-event rate.
      _timing = !_mayAnimate || _glyphBoxes.isEmpty
          ? null
          : timingFor(overlay, _glyphBoxes.length);
    }
    return _timing;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (overlay.text.isEmpty) return;

    final inkScale = layout.inkScale;

    // The background is one rect behind every glyph and it **does not move
    // with the letters**: a box sliced per character would come apart the
    // moment a glyph is displaced. The export draws it as one quad of its own
    // for the same reason.
    if (layout.hasBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          layout.backgroundRect,
          Radius.circular(overlay.borderRadius * inkScale),
        ),
        Paint()..color = overlay.backgroundColor,
      );
    }

    final fillPainter = TextOverlayLayout.textPainterFor(overlay, inkScale)
      ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
    // Shadow, outline, fill — one painter for all three, shared with the
    // export (`paintTextOverlayInk`).
    final strokePainter =
        TextOverlayLayout.strokePainterFor(overlay, inkScale)
          ?..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
    TextPainter? litPainter;
    try {
      final timing = _animationTiming;
      final animating = timing != null && timing.isActive;
      final highlight = _highlightLayout;

      // No live window and no highlight means the text is drawn exactly as
      // static text: the run painted once, unclipped, with no per-glyph pass
      // at all. That is the regression bar — an unanimated overlay must render
      // as it did before — and it is also the cheaper path, which is what
      // most overlays take.
      if (!animating && highlight == null) {
        paintTextOverlayInk(
          canvas,
          overlay: overlay,
          inkScale: inkScale,
          fill: fillPainter,
          stroke: strokePainter,
          textOrigin: layout.textOrigin,
        );
        return;
      }

      // Pills sit behind every glyph and, like the background, do not travel
      // with a letter's own animation.
      if (highlight != null) _paintPills(canvas, highlight);

      TextPainter lit() => litPainter ??= TextOverlayLayout.textPainterFor(
            overlay.copyWith(color: highlight!.highlight.color),
            inkScale,
          )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);

      final glyphs = _glyphBoxes;
      final glyphCount = glyphs.length;
      for (var i = 0; i < glyphCount; i++) {
        final glyph = glyphs[i];
        final state = animating
            ? timing.stateAt(positionSeconds, i, glyphCount)
            : const TextGlyphState();
        final word = highlight?.glyphWord[i] ?? -1;
        final marked = word < 0
            ? WordHighlightState.resting
            : highlight!.wordState(word, positionSeconds);
        final opacity = state.opacity * marked.opacity;
        final scale = state.scale * marked.scale;
        // A glyph animated to nothing is skipped rather than drawn at zero —
        // the same rule `textDraws` applies, and a negative scale would turn
        // the letter inside out.
        if (opacity <= 0 || scale <= 0) continue;

        // **The padded rect, not the ink rect, is what gets clipped** — it is
        // the atlas cell, and the cell carries the shadow and stroke bleed that
        // would otherwise be cut off at the letter's edge.
        final cell = glyph.paddedRect;
        final centre = cell.center;

        // The catalog measures displacement in **glyph heights on both axes**,
        // the glyph's own ink height, which is what `textDraws` converts
        // through (`boxBottom - boxTop`).
        final metric = glyph.inkRect.height;

        // **A popped word swells about its own centre**, not each letter about
        // its own: every glyph is scaled in place and moved away from the
        // word's centre by as much, so the word grows as one piece.
        var pop = Offset.zero;
        if (marked.scale != 1) {
          final box = highlight!.wordBoxes[word];
          if (box != null) pop = (centre - box.center) * (marked.scale - 1);
        }

        canvas.save();
        // **The transform comes first and the clip travels with it** — in GL
        // the cell *is* the quad, so moving the quad moves what is drawn.
        // Clipping in the resting position while the letter moves through the
        // clip draws nothing at all once a slide carries it out. Scale and
        // rotation are about the cell's own centre; the displacement moves
        // that centre. `writeCorners` composes the same terms in the same
        // order.
        canvas.translate(
          centre.dx + state.offsetX * metric + pop.dx,
          centre.dy + state.offsetY * metric + pop.dy,
        );
        if (state.rotation != 0) canvas.rotate(state.rotation);
        if (scale != 1) canvas.scale(scale);
        canvas.translate(-centre.dx, -centre.dy);
        canvas.clipRect(cell);

        // Opacity multiplies the whole glyph — stroke, fill and shadow — so a
        // fading letter fades as one thing. Bounded by `cell`, read in the
        // already-transformed space, like the clip.
        final fading = opacity < 1;
        if (fading) {
          canvas.saveLayer(
            cell,
            Paint()..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
          );
        }

        // The whole run is painted and clipped to one glyph, never the
        // character on its own: kerning and ligatures mean the width of "AV"
        // is not the width of "A" plus "V". Only this letter's shadow is cast,
        // so it travels with the letter.
        void ink(TextPainter fill) => paintTextOverlayInk(
              canvas,
              overlay: overlay,
              inkScale: inkScale,
              fill: fill,
              stroke: strokePainter,
              textOrigin: layout.textOrigin,
              shadowFrom: glyph.inkRect,
            );

        if (marked.fill > 0 && marked.fill < 1) {
          // **Karaoke cuts the glyph at the sweep**: lit behind the line,
          // plain ahead of it, through two complementary clips — so the
          // glyph's shadow is still cast once. The export splits the quad at
          // the same line.
          final box = highlight!.wordBoxes[word]!;
          final rtl = highlight.wordRtl[word];
          final sweep = rtl
              ? box.right - box.width * marked.fill
              : box.left + box.width * marked.fill;
          final behind = rtl
              ? Rect.fromLTRB(math.min(sweep, cell.right), cell.top, cell.right, cell.bottom)
              : Rect.fromLTRB(cell.left, cell.top, math.max(sweep, cell.left), cell.bottom);
          final ahead = rtl
              ? Rect.fromLTRB(cell.left, cell.top, math.max(sweep, cell.left), cell.bottom)
              : Rect.fromLTRB(math.min(sweep, cell.right), cell.top, cell.right, cell.bottom);
          if (!behind.isEmpty) {
            canvas.save();
            canvas.clipRect(behind);
            ink(lit());
            canvas.restore();
          }
          if (!ahead.isEmpty) {
            canvas.save();
            canvas.clipRect(ahead);
            ink(fillPainter);
            canvas.restore();
          }
        } else {
          ink(marked.highlighted ? lit() : fillPainter);
        }

        if (fading) canvas.restore();
        canvas.restore();
      }
    } finally {
      fillPainter.dispose();
      strokePainter?.dispose();
      litPainter?.dispose();
    }
  }

  /// The box behind each word whose pill is showing, in the highlight colour.
  void _paintPills(Canvas canvas, CaptionHighlightLayout highlight) {
    final colour = highlight.highlight.color;
    for (var w = 0; w < highlight.wordBoxes.length; w++) {
      final pill = highlight.wordState(w, positionSeconds).pill;
      if (pill <= 0) continue;
      final rect = highlight.pillRect(w);
      if (rect == null) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(highlight.pillRadius(w))),
        Paint()..color = colour.withValues(alpha: colour.a * pill),
      );
    }
  }

  /// The glyph boxes for [overlay], padded by the same bleed the atlas pads
  /// its cells by, so the preview clips exactly what the export samples.
  static List<TextGlyphBox> glyphBoxesFor(
    TextOverlayModel overlay,
    Size canvasSize,
  ) {
    return layoutTextGlyphs(
      overlay: overlay,
      canvasSize: canvasSize,
      // The same padding the rasteriser pads its atlas cells by — one
      // definition, so the preview clips exactly what the export samples.
      shadowPadding: textGlyphBleedPadding(
        overlay,
        textInkScale(overlay, canvasSize),
      ),
    );
  }

  /// The animation windows for [overlay] across [glyphCount] characters.
  ///
  /// The count is part of the timing — a staggered animation's natural duration
  /// grows with the text — and it must be the **inked** glyph count, matching
  /// what the atlas packs and what `textDraws` passes as `n`. Counting
  /// `overlay.text.length` instead would make every space lengthen the
  /// preview's animation but not the export's.
  static TextAnimationTiming timingFor(
    TextOverlayModel overlay,
    int glyphCount,
  ) {
    return TextAnimationTiming.resolve(
      inAnimationId: overlay.inAnimation,
      outAnimationId: overlay.outAnimation,
      loopAnimationId: overlay.loopAnimation,
      startSeconds: overlay.startTime.inMilliseconds / 1000.0,
      endSeconds: overlay.endTime.inMilliseconds / 1000.0,
      glyphCount: glyphCount,
      // One speed drives both windows; the model carries two keys because that
      // is the shape of the persisted JSON, and the animation tab writes both
      // from a single slider. See `TextAnimationTiming.resolve`.
      speed: overlay.animationInDuration,
      loopSpeed: overlay.loopSpeed,
    );
  }

  @override
  bool shouldRepaint(covariant TextOverlayPainter oldDelegate) {
    // Compared field by field rather than by identity. `TextOverlayModel` has
    // non-final fields, so an identity check would miss an in-place edit
    // entirely — the text would keep drawing its old content with nothing to
    // explain it — and the list is short enough to be honest about.
    final old = oldDelegate.overlay;
    if (old.id != overlay.id ||
        old.text != overlay.text ||
        old.color != overlay.color ||
        old.fontFamily != overlay.fontFamily ||
        old.backgroundColor != overlay.backgroundColor ||
        old.strokeColor != overlay.strokeColor ||
        old.strokeWidth != overlay.strokeWidth ||
        old.shadowColor != overlay.shadowColor ||
        old.shadowBlurRadius != overlay.shadowBlurRadius ||
        old.shadowOpacity != overlay.shadowOpacity ||
        old.shadowDistance != overlay.shadowDistance ||
        old.shadowAngle != overlay.shadowAngle ||
        old.borderRadius != overlay.borderRadius ||
        old.backgroundPadding != overlay.backgroundPadding ||
        old.textAlign != overlay.textAlign ||
        old.boxWidth != overlay.boxWidth ||
        old.startTime != overlay.startTime ||
        old.endTime != overlay.endTime ||
        old.inAnimation != overlay.inAnimation ||
        old.outAnimation != overlay.outAnimation ||
        old.loopAnimation != overlay.loopAnimation ||
        old.animationInDuration != overlay.animationInDuration ||
        old.animationOutDuration != overlay.animationOutDuration ||
        old.loopSpeed != overlay.loopSpeed ||
        old.highlight != overlay.highlight ||
        !identical(old.captionWords, overlay.captionWords) ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.layout.inkScale != layout.inkScale ||
        oldDelegate.layout.boxSize != layout.boxSize) {
      return true;
    }
    // `scale`, `rotation` and `position` are deliberately absent: they are
    // applied by the transforms *around* this painter, so changing one moves
    // the box without changing a pixel of what is inside it.

    if (oldDelegate.positionSeconds == positionSeconds) return false;

    // The playhead only matters while something is actually animating. A
    // static text sits in a layer that rebuilds on every position event, and
    // repainting it ~30 times a second would re-run Flutter's text layout for
    // a picture that cannot have changed. `_animationTiming` short-circuits on
    // the animation fields before it measures anything, so the common case
    // costs three string comparisons rather than a layout.
    // A highlighted caption repaints when some word's look changes — at a
    // word boundary, through a ramp, along a sweep — and not in between: a
    // repaint casts a blurred shadow per letter, and paying that at every
    // position event for an unchanged picture cost a low-end phone a large
    // share of each frame for as long as the caption was on screen.
    if (_hasHighlight && _wordStatesDiffer(oldDelegate.positionSeconds)) {
      return true;
    }
    final timing = _animationTiming;
    return timing != null && timing.isActive;
  }

  /// Whether any animation field is set to something other than 'none'.
  ///
  /// A cheap over-approximation: it says yes for an id that slot resolution
  /// will later reject (a bare `slide_up` in the out-slot, an unknown id from
  /// an old draft), which costs one wasted measurement, not a wrong picture.
  /// It must never say **no** for something that animates.
  bool get _mayAnimate =>
      _isSet(overlay.inAnimation) ||
      _isSet(overlay.outAnimation) ||
      _isSet(overlay.loopAnimation);

  static bool _isSet(String id) => id.isNotEmpty && id != 'none';
}

import 'package:flutter/material.dart';

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

    final renderScale = layout.renderScale;

    // The background is one rect behind every glyph and it **does not move
    // with the letters**: a box sliced per character would come apart the
    // moment a glyph is displaced, and a background that travels with the text
    // is a different design from the one the tool offers. It is also why a
    // text with a background still exports through the flat raster — the
    // native glyph pass draws letters only.
    if (layout.hasBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          layout.backgroundRect,
          Radius.circular(overlay.borderRadius * renderScale),
        ),
        Paint()..color = overlay.backgroundColor,
      );
    }

    final textAlign = TextOverlayLayout.textAlignFor(overlay);
    final fillPainter = TextOverlayLayout.textPainterFor(overlay, renderScale)
      ..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
    TextPainter? strokePainter;
    try {
      // Stroke under fill, exactly as the rasteriser stacks them and as the
      // two `Text` widgets used to.
      if (TextOverlayLayout.hasStroke(overlay)) {
        strokePainter = TextPainter(
          text: TextSpan(
            text: overlay.text,
            style: TextOverlayLayout.strokeStyleFor(overlay, renderScale),
          ),
          textDirection: TextDirection.ltr,
          textAlign: textAlign,
          textScaler: TextScaler.noScaling,
        )..layout(minWidth: layout.textWidth, maxWidth: layout.textWidth);
      }

      final timing = _animationTiming;

      // No live window means the text is drawn exactly as static text: the run
      // painted once, unclipped, with no per-glyph pass at all. That is the
      // regression bar for per-character animation — an unanimated overlay must
      // render as it did before — and it is also the cheaper path, which is
      // what most overlays take.
      if (timing == null || !timing.isActive) {
        strokePainter?.paint(canvas, layout.textOrigin);
        fillPainter.paint(canvas, layout.textOrigin);
        return;
      }

      final glyphs = _glyphBoxes;
      final glyphCount = glyphs.length;
      for (var i = 0; i < glyphCount; i++) {
        final glyph = glyphs[i];
        final state = timing.stateAt(positionSeconds, i, glyphCount);
        // A glyph animated to nothing is skipped rather than drawn at zero —
        // the same rule `textDraws` applies, and a negative scale would turn
        // the letter inside out.
        if (state.opacity <= 0 || state.scale <= 0) continue;

        // **The padded rect, not the ink rect, is what gets clipped** — it is
        // the atlas cell, and the cell carries the shadow and stroke bleed that
        // would otherwise be cut off at the letter's edge. Neighbouring padded
        // cells overlap, so a little bleed re-composites; that is the same
        // accepted residual the atlas has, measured and documented there, and
        // matching it is the point.
        final cell = glyph.paddedRect;
        final centre = cell.center;

        // The catalog measures displacement in **glyph heights on both axes** —
        // that is what keeps a diagonal slide diagonal and makes the travel
        // scale with the type size rather than with the box. The metric is the
        // glyph's own *ink* height, which is what `textDraws` converts through
        // (`boxBottom - boxTop`). Using the glyph's width for x would make an
        // "i" slide a fraction of a "W"'s distance and the word would come
        // apart mid-animation.
        final metric = glyph.inkRect.height;

        canvas.save();
        // **The transform comes first and the clip travels with it.** In GL the
        // clip is not a separate thing: the cell *is* the quad, so moving the
        // quad moves what is drawn. Here they are two calls, and clipping in
        // the resting position while the letter moves through the clip is a
        // real, severe bug rather than a subtlety — a slide travels 1.5 glyph
        // heights against a few pixels of bleed padding, so the letter leaves
        // its own clip entirely and nothing is drawn at all. Ordering the calls
        // this way means the clip is expressed in the *glyph's* space, which is
        // the space the run is painted in, so the two move together.
        //
        // Scale and rotation are about the **cell's own centre**, so a bouncing
        // letter hops where it sits instead of swinging around the caption.
        // The displacement is applied after, moving that centre — scaling the
        // offset as well would push the letter away from the block rather than
        // swelling it in place. `writeCorners` composes the same three terms in
        // the same order.
        canvas.translate(
          centre.dx + state.offsetX * metric,
          centre.dy + state.offsetY * metric,
        );
        if (state.rotation != 0) canvas.rotate(state.rotation);
        if (state.scale != 1) canvas.scale(state.scale);
        canvas.translate(-centre.dx, -centre.dy);
        canvas.clipRect(cell);

        // Opacity multiplies the whole glyph — stroke, fill and shadow — so a
        // fading letter fades as one thing. A layer is what makes that true:
        // painting stroke and fill each at the same alpha would show the
        // stroke through the half-transparent fill.
        //
        // Its bounds are `cell` for the same reason the clip is: both are read
        // in the current (already transformed) space, so a layer bounded in
        // resting coordinates would re-clip precisely what the clip above no
        // longer does.
        final fading = state.opacity < 1;
        if (fading) {
          canvas.saveLayer(
            cell,
            Paint()
              ..color = Color.fromRGBO(0, 0, 0, state.opacity.clamp(0.0, 1.0)),
          );
        }
        // The whole run is painted and clipped to one glyph, never the
        // character on its own: kerning and ligatures mean the width of "AV" is
        // not the width of "A" plus "V", so a character painted alone is not
        // the pixels that character has in context. The atlas rasteriser draws
        // its cells the same way, for the same reason.
        strokePainter?.paint(canvas, layout.textOrigin);
        fillPainter.paint(canvas, layout.textOrigin);
        if (fading) canvas.restore();
        canvas.restore();
      }
    } finally {
      fillPainter.dispose();
      strokePainter?.dispose();
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
        textOverlayRenderScale(overlay, canvasSize),
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
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.layout.renderScale != layout.renderScale ||
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

import 'package:flutter/material.dart';

import '../../logic/text_animation_catalog.dart';
import '../../models/text_overlay_model.dart';
import 'text_overlay_painter.dart';
import 'text_preview_tile.dart';

/// How many grapheme clusters of the user's text a tile shows.
///
/// Enough characters to read a per-glyph stagger as a stagger, few enough that
/// twenty tiles laying text out on every frame stays cheap — and a caption can
/// legitimately be a whole paragraph.
const int kTextAnimationTileGlyphs = 8;

/// What a tile shows when the overlay has no text of its own.
///
/// Text overlays are **created empty** in this app (`showTextEditor` deletes
/// one that is still empty when the sheet closes), so the animation tab is
/// routinely opened on an overlay with nothing in it. A tile drawing nothing
/// teaches the user nothing about the animation it is offering.
const String kTextAnimationTileSampleText = 'Text';

/// A small, looping, live preview of one text animation, drawn with the user's
/// own text.
///
/// **A tile drives the canvas's own painter.** It builds a synthetic
/// [TextOverlayModel] — the user's styling, their text truncated, the
/// animation in the slot its own [TextAnimation.category] names — and hands
/// it to [TextPreviewTile], which measures it and sweeps
/// `TextOverlayPainter`'s `positionSeconds` from an injected clock. It does
/// **not** draw its own approximation of the motion: a tile that approximated
/// would promise the user an animation the export does not deliver, which is
/// the exact failure the preview / export / tiles split exists to prevent.
///
/// The clock is injected rather than owned. The animation tab shows around
/// twenty of these at once and drives them all from one `AnimationController`;
/// a `Ticker` per tile would be twenty tickers competing for the same frames.
/// A null clock renders the tile's first frame and holds it — which is what an
/// off-screen tile, and a widget test, want.
class TextAnimationTile extends StatelessWidget {
  const TextAnimationTile({
    super.key,
    required this.animation,
    required this.overlay,
    required this.isSelected,
    required this.onTap,
    this.clock,
  });

  /// The catalog entry this tile previews.
  final TextAnimation animation;

  /// The overlay being edited. Only its **styling** and its text are used —
  /// see [_syntheticOverlay] for what is deliberately dropped.
  final TextOverlayModel overlay;

  final bool isSelected;

  /// Fired **once per tap**, never per animation frame: the tab turns a tap
  /// into an undo entry, and a per-frame callback would push one per frame.
  final VoidCallback onTap;

  /// Drives the playhead — see [TextPreviewTile.clock].
  final Listenable? clock;

  // ------------------------------------------------------------ synthetic --

  /// The user's text, cut to [kTextAnimationTileGlyphs] **grapheme clusters**.
  ///
  /// By cluster and never by `substring`: an emoji is several code units and a
  /// family emoji several clusters' worth of them, so a code-unit cut leaves a
  /// broken surrogate that renders as nothing. That exact mistake made emoji
  /// disappear from exports at an earlier stage of this work.
  String get _tileText {
    final source = overlay.text.trim();
    if (source.isEmpty) return kTextAnimationTileSampleText;
    final clusters = source.characters;
    if (clusters.length <= kTextAnimationTileGlyphs) return source;
    return clusters.take(kTextAnimationTileGlyphs).toString();
  }

  /// The overlay the tile actually paints.
  ///
  /// Keeps the user's **look** — colour, font, stroke, background, shadow,
  /// alignment — so a tile previews *their* text rather than a generic sample.
  ///
  /// Drops their **placement**: `scale`, `rotation` and `position` are reset,
  /// and `boxWidth` cleared. A tile is a fixed box, and a 3×-scaled caption
  /// dragged into a corner would overflow it or leave it empty; those three
  /// are applied by the transforms *around* the painter on the canvas, so
  /// dropping them changes where the box sits, never what is inside it.
  ///
  /// The timing is synthetic too: the span is exactly long enough to hold this
  /// animation and a rest, so one loop of the clock walks it from its start
  /// through to its resting state.
  TextOverlayModel _syntheticOverlay(int glyphCount) {
    final text = _tileText;
    final o = overlay;
    return TextOverlayModel(
      id: 'tile-${animation.id}',
      text: text,
      color: o.color,
      fontFamily: o.fontFamily,
      backgroundColor: o.backgroundColor,
      strokeColor: o.strokeColor,
      strokeWidth: o.strokeWidth,
      shadowColor: o.shadowColor,
      shadowBlurRadius: o.shadowBlurRadius,
      borderRadius: o.borderRadius,
      backgroundPadding: o.backgroundPadding,
      textAlign: o.textAlign,
      // Placement is the tile's, not the user's — see above.
      position: Offset.zero,
      scale: 1.0,
      rotation: 0.0,
      startTime: Duration.zero,
      endTime: _durationFor(_spanSeconds(glyphCount)),
      // Exactly one slot carries the animation. Putting it in the wrong one
      // makes `resolveTextAnimation` refuse it by category and the tile would
      // preview a still frame with nothing explaining why.
      inAnimation: animation.category == TextAnimationCategory.inAnim
          ? animation.id
          : 'none',
      outAnimation: animation.category == TextAnimationCategory.outAnim
          ? animation.id
          : 'none',
      loopAnimation: animation.category == TextAnimationCategory.loop
          ? animation.id
          : 'none',
      // A tile always previews an animation at its natural pace. The tab's
      // Speed slider retimes the *project's* text; a tile retimed with it
      // would make the slider look like it changed which animation is which.
      animationInDuration: kTextAnimationNaturalSpeed,
      animationOutDuration: kTextAnimationNaturalSpeed,
      loopSpeed: kTextAnimationNaturalSpeed,
      referenceCanvasSize: kTextPreviewCanvas,
    );
  }

  /// How long the synthetic overlay lives, in seconds.
  ///
  /// The animation's own natural duration plus a rest.
  /// [resolveTextAnimationDurations] only compresses the in and out windows
  /// when they do not fit the span, and the rest is what keeps them fitting —
  /// so a tile plays the animation at exactly the length the catalog defines
  /// it at.
  ///
  /// A loop's natural duration is one *cycle* rather than a lifetime, but the
  /// same span works: the in and out slots are 'none' so neither window can be
  /// live, and the timing wraps the loop's phase by its own period regardless.
  /// The whole span is swept for every category, which is what makes one loop
  /// of the clock "start through to rest" in all three cases: an in-animation
  /// runs at the head of the span and rests for the tail, an out-animation
  /// rests for the head and runs at the tail, and a loop wraps by its own
  /// period underneath both.
  double _spanSeconds(int glyphCount) =>
      animation.naturalDuration(glyphCount) + kTextPreviewRestSeconds;

  static Duration _durationFor(double seconds) =>
      Duration(microseconds: (seconds * 1000000).round());

  // ----------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final probe = _syntheticOverlay(1);
    // The glyph count is part of a staggered animation's natural duration, so
    // it has to be measured before the span is known. Measuring it from the
    // painter's own helper means the tile counts exactly the glyphs the
    // painter will animate — inked characters, not `text.length`.
    final glyphCount =
        TextOverlayPainter.glyphBoxesFor(probe, kTextPreviewCanvas).length;

    return TextPreviewTile(
      overlay: _syntheticOverlay(glyphCount),
      spanSeconds: _spanSeconds(glyphCount),
      label: animation.label,
      isSelected: isSelected,
      onTap: onTap,
      clock: clock,
    );
  }
}

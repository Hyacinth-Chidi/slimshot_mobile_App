import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../logic/text_animation_catalog.dart';
import '../../logic/text_template_catalog.dart';
import '../../models/text_overlay_model.dart';
import 'text_overlay_painter.dart';
import 'text_preview_tile.dart';

/// A live preview of one text template: its sample words in its whole look,
/// playing its animations.
///
/// **Built by the template itself, painted by the canvas's painter.** The
/// synthetic overlay is `TextTemplate.apply` — the same call that makes the
/// real text — given the sample words, so what the tile shows is what the
/// template inserts, down to the shadow blur. It is handed to
/// [TextPreviewTile], the shell the animation tab's tiles share, and never
/// approximated.
///
/// Placement is dropped, as in every tile: the template's `placement` and
/// `scale` say where and how big the text sits on the *canvas*, and a tile is
/// a fixed box that fits whatever it holds.
class TextTemplateTile extends StatelessWidget {
  const TextTemplateTile({
    super.key,
    required this.template,
    required this.onTap,
    this.clock,
  });

  final TextTemplate template;

  /// Fired once per tap.
  final VoidCallback onTap;

  /// Drives the playhead — see [TextPreviewTile.clock].
  final Listenable? clock;

  /// The template on the tile canvas, with its sample words, unplaced.
  TextOverlayModel _synthetic(double spanSeconds) => template
      .apply(
        id: 'tile-${template.id}',
        startTime: Duration.zero,
        endTime: Duration(microseconds: (spanSeconds * 1e6).round()),
        canvasSize: kTextPreviewCanvas,
      )
      .copyWith(
        text: template.sampleText,
        position: Offset.zero,
        scale: 1.0,
      );

  /// One loop of the clock: the entrance, a hold, then the exit.
  ///
  /// The hold is at least the rest every tile gives a finished look, and at
  /// least one full cycle of the loop animation if there is one, so a loop is
  /// seen to loop before the exit takes the text away. In and out windows fit
  /// the span exactly, so neither is compressed and each plays at the length
  /// the catalog defines it at.
  double _spanSeconds(int glyphCount) {
    double natural(String id, TextAnimationCategory slot) =>
        resolveTextAnimation(id, slot)?.naturalDuration(glyphCount) ?? 0;
    final hold = math.max(
      kTextPreviewRestSeconds,
      natural(template.loopAnimation, TextAnimationCategory.loop),
    );
    return natural(template.inAnimation, TextAnimationCategory.inAnim) +
        hold +
        natural(template.outAnimation, TextAnimationCategory.outAnim);
  }

  @override
  Widget build(BuildContext context) {
    // The glyph count feeds staggered animations' durations, so it is measured
    // first — from the painter's own helper, which counts the glyphs it will
    // actually animate.
    final glyphCount = TextOverlayPainter.glyphBoxesFor(
      _synthetic(kTextPreviewRestSeconds),
      kTextPreviewCanvas,
    ).length;
    final span = _spanSeconds(glyphCount);

    return TextPreviewTile(
      overlay: _synthetic(span),
      spanSeconds: span,
      label: template.name,
      // A template makes a new text, so there is no current choice to show.
      isSelected: false,
      onTap: onTap,
      clock: clock,
    );
  }
}

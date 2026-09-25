import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../logic/text_glyph_layout.dart';
import '../../logic/text_overlay_geometry.dart';
import '../../models/text_overlay_model.dart';
import 'text_overlay_painter.dart';

/// The canvas a preview tile measures its synthetic overlay against.
///
/// It is also that overlay's `referenceCanvasSize`, so the render scale is
/// exactly 1 and the box comes out at the catalog's own font size whatever
/// device the sheet is opened on. The tile then scales the finished box to
/// fit its own bounds — one uniform scale on a measured box, rather than a
/// second definition of how big text is.
///
/// **Wide, so a tile's words never wrap.** Text wraps at the canvas width
/// less a margin, and at 240 that was ~208px: HEADLINE and BREAKING broke in
/// two, and Press Start 2P — a full em per letter — wrapped nearly anything.
/// At 640 a template's sample, or the eight graphemes of the user's own text
/// a tile shows, sits on one line; the fit then scales the line to the tile.
const Size kTextPreviewCanvas = Size(640, 240);

/// How many grapheme clusters of the user's text a tile shows.
///
/// Enough characters to read a per-glyph stagger as a stagger, few enough that
/// a grid laying text out on every frame stays cheap — and a caption can
/// legitimately be a whole paragraph.
const int kTextPreviewGlyphs = 8;

/// The words a tile shows: [source] cut to [kTextPreviewGlyphs] **grapheme
/// clusters**, or [fallback] when there are none.
///
/// By cluster and never by `substring`: an emoji is several code units and a
/// family emoji several clusters' worth of them, so a code-unit cut leaves a
/// broken surrogate that renders as nothing. Text is created empty in this
/// app, so a tile is routinely asked for words that do not exist yet — and a
/// tile drawing nothing teaches nothing about the look it offers.
String textPreviewWords(String? source, {required String fallback}) {
  final words = source?.trim() ?? '';
  if (words.isEmpty) return fallback;
  final clusters = words.characters;
  if (clusters.length <= kTextPreviewGlyphs) return words;
  return clusters.take(kTextPreviewGlyphs).toString();
}

/// How every grid of preview tiles is laid out — the animation tab's and the
/// templates' alike: three to a row, a little wider than tall.
///
/// One definition because they are the same kind of tile side by side in one
/// sheet. The animation tab used to run four to a row in taller tiles beside a
/// Templates tab of three, so switching tabs changed the size of everything.
const SliverGridDelegateWithFixedCrossAxisCount kTextPreviewGrid =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  childAspectRatio: 1.1,
  crossAxisSpacing: 10,
  mainAxisSpacing: 10,
);

/// Holds a preview grid's [clock] still while the grid scrolls, and lets it
/// run again once the scroll has come to rest — for the grid's
/// `NotificationListener<ScrollNotification>`. Returns false, so the
/// notification keeps bubbling.
///
/// **Every tile redoes its text layout, and casts its shadow into an
/// offscreen layer per letter, on each tick of the clock** — measured at
/// ~12ms a frame for the template catalog on a desktop CPU, several times
/// that on a phone, plus ~50 offscreen layers for the GPU. At rest that is the
/// animation; during a scroll it took the frames the scroll needed, and the
/// grid stuttered and felt heavy under the finger. Held still, a tile is a
/// picture the scroll only moves. Only the grid's own scrollable counts
/// (depth 0), and the clock resumes from where it stopped.
bool holdPreviewClockWhileScrolling(
  ScrollNotification notification,
  AnimationController clock,
) {
  if (notification.depth != 0) return false;
  if (notification is ScrollStartNotification) {
    clock.stop();
  } else if (notification is ScrollEndNotification && !clock.isAnimating) {
    clock.repeat();
  }
  return false;
}

/// How long a tile rests on the finished look before looping.
///
/// Without it an in-animation would restart the instant its last glyph
/// landed, and the user would never see the text the animation is animating
/// *to*.
const double kTextPreviewRestSeconds = 0.45;

/// The most a tile magnifies a look to fill itself. Without a ceiling a word
/// of two letters becomes two giant glyphs that no longer read as the style
/// on offer; with this one a short word still sits comfortably large.
const double kTextPreviewMaxUpscale = 1.5;

/// The breathing room between a look and its tile's edge, in logical pixels.
const double kTextPreviewMargin = 6.0;

/// The shell every text preview tile shares: a small, looping, live preview
/// painted by **the canvas's own painter**.
///
/// A tile hands it a synthetic [TextOverlayModel] — starting at zero, living
/// [spanSeconds], measured against [kTextPreviewCanvas] — and this sweeps
/// [TextOverlayPainter]'s `positionSeconds` through that span from an injected
/// clock. It never draws its own approximation of a look or a motion: a tile
/// that approximated would promise the user something the canvas and the
/// export do not deliver, which is the failure the preview / export / tiles
/// split exists to prevent.
///
/// `TextAnimationTile` (one animation, the user's own text) and
/// `TextTemplateTile` (one template, its sample words) are thin wrappers that
/// build their synthetic overlay and hand it here, so the two cannot drift
/// apart in how they measure, fit, clip, sweep or show selection.
///
/// The clock is injected rather than owned. A sheet shows many tiles at once
/// and drives them all from one `AnimationController`; a `Ticker` per tile
/// would be a ticker per tile competing for the same frames. A null clock
/// renders the first frame and holds it — which is what an off-screen tile,
/// and a widget test, want.
class TextPreviewTile extends StatefulWidget {
  const TextPreviewTile({
    super.key,
    required this.overlay,
    required this.spanSeconds,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.clock,
  });

  /// What is painted: starts at zero and lives [spanSeconds], with
  /// [kTextPreviewCanvas] as its reference canvas.
  final TextOverlayModel overlay;

  /// How far one loop of the clock walks the overlay's own timeline.
  final double spanSeconds;

  /// The words under the preview, and its semantics label.
  final String label;

  final bool isSelected;

  /// Fired **once per tap**, never per animation frame: a caller turning a
  /// tap into an undo entry would otherwise push one per frame.
  final VoidCallback onTap;

  /// Drives the playhead. A [ValueListenable] of a double is read as a 0..1
  /// phase through one loop; any other [Listenable] simply advances the phase
  /// by a frame's worth on each notification, so a bare `Listenable` still
  /// animates.
  final Listenable? clock;

  @override
  State<TextPreviewTile> createState() => _TextPreviewTileState();
}

class _TextPreviewTileState extends State<TextPreviewTile> {
  /// 0..1 through one loop.
  double _phase = 0;

  /// The fallback for a clock that carries no value: a phase advanced per
  /// notification. Assumes roughly 60Hz, which is only ever a pacing guess —
  /// the picture itself comes from the catalog either way.
  static const double _kBlindPhaseStep = 1 / 60;

  @override
  void initState() {
    super.initState();
    widget.clock?.addListener(_onClock);
    _phase = _phaseFrom(widget.clock) ?? 0;
  }

  @override
  void didUpdateWidget(TextPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clock, widget.clock)) {
      oldWidget.clock?.removeListener(_onClock);
      widget.clock?.addListener(_onClock);
    }
  }

  @override
  void dispose() {
    widget.clock?.removeListener(_onClock);
    super.dispose();
  }

  void _onClock() {
    if (!mounted) return;
    final value = _phaseFrom(widget.clock);
    setState(() {
      _phase = value ?? (_phase + _kBlindPhaseStep) % 1.0;
    });
  }

  /// The clock's own phase, or null if it carries no readable value.
  static double? _phaseFrom(Listenable? clock) {
    if (clock is ValueListenable<double>) {
      final v = clock.value;
      if (v.isNaN || v.isInfinite) return 0;
      // A controller that overshoots (a spring, or `repeat` past 1) still maps
      // onto one cycle rather than running off the end of the window.
      final wrapped = v % 1.0;
      return wrapped < 0 ? wrapped + 1.0 : wrapped;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final overlay = widget.overlay;
    final layout = TextOverlayLayout.measure(overlay, kTextPreviewCanvas);
    // The whole look, not just the text box: a shadow and an outline reach
    // past the box — a glow by thirty-odd pixels — and fitting the box alone
    // cut them off at the tile's edge. The reach is the one the export pads
    // by, so the tile holds exactly what the file does.
    final bleed = textGlyphBleedPadding(overlay, layout.renderScale);
    final extent = Size(
      layout.boxSize.width + bleed * 2,
      layout.boxSize.height + bleed * 2,
    );

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.label,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isSelected ? AppColors.highlight : AppColors.surface,
            border: Border.all(
              color: widget.isSelected
                  ? AppColors.primaryStart
                  : AppColors.border,
              width: widget.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                // The stage: a mid-grey screen inside the tile, so a white
                // fill and a black outline or shadow both read. On the tile's
                // own near-black surface a subtitle's outline and a comic's
                // drop simply vanished.
                child: Container(
                  margin: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.previewStage,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  // An animation moves glyphs well outside the resting look — a
                  // slide travels 1.5 glyph heights — which is what the clip is
                  // for; the resting look itself always fits.
                  child: ClipRect(
                    child: Padding(
                      padding: const EdgeInsets.all(kTextPreviewMargin),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // **Fills the tile, both ways.** A long text scales
                          // down to fit and a short one scales up to meet the
                          // margin — up to [kTextPreviewMaxUpscale] — so every
                          // tile in a grid carries its look at a similar
                          // presence instead of some sitting small in the
                          // middle.
                          final scale = [
                            constraints.maxWidth / extent.width,
                            constraints.maxHeight / extent.height,
                            kTextPreviewMaxUpscale,
                          ].reduce((a, b) => a < b ? a : b);
                          return Center(
                            child: SizedBox(
                              width: extent.width * scale,
                              height: extent.height * scale,
                              child: FittedBox(
                                fit: BoxFit.fill,
                                child: SizedBox.fromSize(
                                  size: extent,
                                  child: Padding(
                                    padding: EdgeInsets.all(bleed),
                                    child: CustomPaint(
                                      size: layout.boxSize,
                                      painter: TextOverlayPainter(
                                        overlay: overlay,
                                        layout: layout,
                                        canvasSize: kTextPreviewCanvas,
                                        positionSeconds:
                                            _phase * widget.spanSeconds,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: widget.isSelected
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

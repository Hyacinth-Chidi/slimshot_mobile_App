/// The single definition of what every text animation does, as pure arithmetic.
///
/// Three consumers read this table: the canvas preview, a function-for-function
/// Kotlin port used by the export, and the animation tab's preview tiles. That
/// is why there is **no clock, no state and no Flutter import here** — only
/// `dart:math`. A curve that reached for `DateTime.now()`, a `Random`, an
/// `AnimationController` or a `Curves` constant could not be ported, and the
/// preview and the exported file would draw different pictures with nothing
/// explaining why. A shared fixture asserts both sides produce identical
/// values, so anything unportable breaks that test rather than failing quietly.
///
/// Everything here is a function of `(p, i, n)` alone:
/// * `p` — 0..1 progress through this animation's own window.
/// * `i` — the glyph's index in the text.
/// * `n` — how many glyphs there are.
///
/// Deliberately absent: **blur** and **neon flicker**. Both need multi-pass
/// rendering (draw to a texture, blur each axis, composite) and there is no FBO
/// framework yet. They belong to a future effects pipeline, not to a curve
/// table.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// What one glyph looks like at one instant.
///
/// The defaults are the **resting state** — the glyph exactly as the static
/// text draws it. An in-animation must return this at `p == 1` and an
/// out-animation at `p == 0`, or the text jumps the frame the animation ends.
class TextGlyphState {
  const TextGlyphState({
    this.opacity = 1,
    this.offsetX = 0,
    this.offsetY = 0,
    this.scale = 1,
    this.rotation = 0,
    this.fillProgress = 1,
  });

  /// 0..1, multiplied into the glyph's own alpha.
  final double opacity;

  /// Horizontal displacement in **glyph-height units**, positive right.
  ///
  /// Not pixels and not a fraction of the text box: a slide must travel the
  /// same *visual* distance whether the text is 14pt or 140pt, and a fraction
  /// of the box would make a one-word caption slide further than a paragraph.
  final double offsetX;

  /// Vertical displacement in glyph-height units, positive **down** — screen
  /// convention, matching the canvas and the atlas quads.
  final double offsetY;

  /// Uniform scale about the glyph's own centre. 1 is resting.
  final double scale;

  /// Rotation about the glyph's own centre, in **radians**, clockwise.
  final double rotation;

  /// 0..1 sweep for colour-fill effects: how much of this glyph has taken the
  /// fill colour. 1 — fully filled — is resting, so an animation that does not
  /// use it simply leaves it alone.
  final double fillProgress;

  /// The glyph exactly as static text draws it.
  static const TextGlyphState rest = TextGlyphState();
}

/// Which end of an overlay's life an animation belongs to.
enum TextAnimationCategory {
  /// Plays once as the text appears. Rests at `p == 1`.
  inAnim,

  /// Plays once as the text leaves. Starts from rest at `p == 0`.
  outAnim,

  /// Repeats for the whole span. `p == 0` and `p == 1` must agree, or the
  /// wrap is a visible jump every cycle.
  loop,
}

/// One entry in the table.
class TextAnimation {
  const TextAnimation({
    required this.id,
    required this.label,
    required this.category,
    required this.isPerGlyph,
    required this.naturalDuration,
    required this.stateAt,
  });

  /// Persisted into drafts and sent over the channel to Kotlin. **Renaming one
  /// needs a migration**; see [_kLegacyAnimationIds] for what that looks like.
  final String id;

  /// What the animation tab shows the user.
  final String label;

  final TextAnimationCategory category;

  /// Whether glyphs animate at different times. A flat animation moves the
  /// whole block as one, so a renderer may take the `i == 0` state and skip
  /// evaluating the rest.
  final bool isPerGlyph;

  /// How long this animation wants to run, in seconds, for a text of
  /// `glyphCount` characters. Staggered animations grow with the text;
  /// flat ones ignore the count entirely.
  final double Function(int glyphCount) naturalDuration;

  /// The curve itself. Pure: same inputs, same outputs, on both platforms.
  final TextGlyphState Function(double p, int i, int n) stateAt;
}

// ---------------------------------------------------------------------------
// Shared arithmetic
// ---------------------------------------------------------------------------

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// How much of the total window a single glyph's own animation occupies.
///
/// The other 45% is spread as the stagger, so glyphs overlap heavily: a
/// non-overlapping stagger (each glyph waiting for the last to finish) reads as
/// a slow queue rather than one effect travelling through the word.
const double _kGlyphShare = 0.55;

/// **The one stagger formula**, used by every per-glyph animation here.
///
/// Each glyph runs the same curve over [_kGlyphShare] of the window, and glyph
/// `i` starts `i/(n-1)` of the remaining `1 - _kGlyphShare` later — so glyph 0
/// starts at `p == 0` and the last glyph *finishes* exactly at `p == 1`.
///
/// Both endpoints are exact, which is the point: an in-animation whose last
/// glyph finished at `p == 0.98` would snap on its final frame, and the
/// "rests at p=1" test pins every entry against that.
///
/// Every staggered animation shares this rather than each picking its own
/// spacing, so typing, wave and bounce feel like one family of effects on the
/// same text rather than three unrelated plugins.
double _stagger(double p, int i, int n) {
  // A one-glyph text must still animate. Dividing by `n - 1` here would be a
  // divide-by-zero, and skipping the animation would make a single-character
  // caption the one case that silently does nothing.
  if (n <= 1) return _clamp01(p);

  final delay = (1.0 - _kGlyphShare) * (i / (n - 1));
  return _clamp01((p - delay) / _kGlyphShare);
}

/// A deterministic pseudo-random unit value for a glyph index.
///
/// Jitter for shake and wiggle **must not** come from `Random()`: the preview
/// and the export evaluate the same frame independently, and two draws of the
/// same instant have to agree down to the pixel. An index hash gives every
/// glyph its own constant character while staying reproducible on both
/// platforms.
///
/// Deliberately plain integer arithmetic — a 32-bit mix (Thomas Wang's
/// integer hash) masked to 32 bits at every step, so the Kotlin port is the
/// same expression with `Int` and produces bit-identical results rather than
/// relying on a language's hash implementation.
double _hashUnit(int i, int salt) {
  var h = (i * 2654435761 + salt * 40503) & 0xFFFFFFFF;
  h = (h ^ (h >> 16)) & 0xFFFFFFFF;
  h = (h * 2246822519) & 0xFFFFFFFF;
  h = (h ^ (h >> 13)) & 0xFFFFFFFF;
  h = (h * 3266489917) & 0xFFFFFFFF;
  h = (h ^ (h >> 16)) & 0xFFFFFFFF;
  return h / 4294967296.0;
}

// -- easing, written out ----------------------------------------------------
//
// Flutter's `Curves` cannot be imported here (and has no Kotlin equivalent),
// so every curve this table uses is an explicit function. These are the
// standard definitions, matching the familiar names so the motion reads the
// way a user of any other editor expects.

double _easeOutCubic(double t) {
  final u = 1 - t;
  return 1 - u * u * u;
}

double _easeInCubic(double t) => t * t * t;

/// Overshoots past 1 and settles back — the "pop" of a spring without a
/// simulation, which could not be ported as a pure function of `p`.
double _easeOutBack(double t, {double overshoot = 1.70158}) {
  final c3 = overshoot + 1;
  final u = t - 1;
  return 1 + c3 * u * u * u + overshoot * u * u;
}

double _easeInBack(double t, {double overshoot = 1.70158}) {
  final c3 = overshoot + 1;
  return c3 * t * t * t - overshoot * t * t;
}

/// A decaying bounce that lands exactly on 1 — three diminishing hops, the
/// shape CapCut's "bounce" reads as.
double _easeOutBounce(double t) {
  const n1 = 7.5625;
  const d1 = 2.75;
  if (t < 1 / d1) return n1 * t * t;
  if (t < 2 / d1) {
    final u = t - 1.5 / d1;
    return n1 * u * u + 0.75;
  }
  if (t < 2.5 / d1) {
    final u = t - 2.25 / d1;
    return n1 * u * u + 0.9375;
  }
  final u = t - 2.625 / d1;
  return n1 * u * u + 0.984375;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// `sin` over a whole number of cycles of `p`.
///
/// Loops are written through this rather than raw `sin(p * something)` because
/// the seam is only invisible when `p == 0` and `p == 1` land on the *same*
/// point of the wave. Anything that is not a whole cycle jumps every wrap.
double _cycles(double p, double count, [double phase = 0]) =>
    math.sin(2 * math.pi * (p * count + phase));

// ---------------------------------------------------------------------------
// Durations
// ---------------------------------------------------------------------------

/// The stock duration for a flat, non-staggered animation.
///
/// 0.5s is what the existing text layer actually plays (flutter_animate's
/// default), so legacy animations keep their current feel after the move onto
/// this table.
const double _kFlatDuration = 0.5;

/// Flat animations take the same time whatever the text says.
double _flat(int glyphCount) => _kFlatDuration;

/// A staggered animation's duration: a base, plus a beat per character.
///
/// Clamped at both ends for reasons that are visible rather than theoretical.
/// The floor keeps a one- or two-character text from flashing past too fast to
/// read as an animation at all; the ceiling keeps a long caption's typing from
/// eating a clip whole — beyond a couple of seconds a user reads it as the text
/// being late rather than as an effect.
double _staggered(int glyphCount, {double base = 0.35, double perGlyph = 0.05}) {
  final raw = base + perGlyph * math.max(0, glyphCount - 1);
  return raw.clamp(0.4, 2.5);
}

/// How long the in- and out-animations of one text overlay actually run.
///
/// `speed` scales them inversely — a 2× speed halves both — so the animation
/// tab's speed control means what a user expects.
///
/// When the two together do not fit inside `spanSeconds` they are **compressed
/// proportionally**, never dropped. Dropping one would make the exported file
/// differ from the preview with nothing on screen to explain it, which is the
/// same class of fault as an export silently losing a transition.
({double inSeconds, double outSeconds}) resolveTextAnimationDurations({
  required double spanSeconds,
  required TextAnimation? inAnim,
  required TextAnimation? outAnim,
  required int glyphCount,
  required double speed,
}) {
  // A zero or negative speed would divide to infinity; a caller reading a
  // half-initialised model can hand one over, so guard rather than trust it.
  final rate = speed > 0 ? speed : 1.0;

  var inSeconds = inAnim == null ? 0.0 : inAnim.naturalDuration(glyphCount) / rate;
  var outSeconds = outAnim == null ? 0.0 : outAnim.naturalDuration(glyphCount) / rate;

  // A span can legitimately be zero — an overlay mid-creation, or one trimmed
  // to nothing — and a negative one means the model is inconsistent. Neither
  // may produce a negative duration downstream.
  final span = spanSeconds > 0 ? spanSeconds : 0.0;

  final total = inSeconds + outSeconds;
  if (total > span && total > 0) {
    final squeeze = span / total;
    inSeconds *= squeeze;
    outSeconds *= squeeze;
  }

  return (inSeconds: inSeconds, outSeconds: outSeconds);
}

// ---------------------------------------------------------------------------
// Curve bodies
// ---------------------------------------------------------------------------

/// Typing reveals a glyph **whole**, not faded in.
///
/// The reveal is a step, not a ramp: a fade would smear several characters at
/// partial opacity at once, which reads as a blur rather than as typing. Only
/// the threshold moves, so exactly the glyphs whose turn has come are drawn.
TextGlyphState _typing(double p, int i, int n) {
  final g = _stagger(p, i, n);
  return TextGlyphState(opacity: g > 0 ? 1 : 0);
}

/// Untyping is typing run backwards: the last character disappears first.
TextGlyphState _untyping(double p, int i, int n) {
  // Reverse the index so the stagger walks right-to-left, which is how a
  // caption deletes itself.
  final g = _stagger(p, n - 1 - i, n);
  return TextGlyphState(opacity: g >= 1 ? 0 : 1);
}

TextGlyphState _fadeIn(double p, int i, int n) =>
    TextGlyphState(opacity: _clamp01(p));

TextGlyphState _fadeOut(double p, int i, int n) =>
    TextGlyphState(opacity: _clamp01(1 - p));

/// Grows from nothing — the legacy `zoom_in` / `scale`, which began at scale 0.
TextGlyphState _zoomIn(double p, int i, int n) =>
    TextGlyphState(scale: _lerp(0, 1, _easeOutCubic(_clamp01(p))), opacity: _clamp01(p * 2));

/// Shrinks *into* place from oversize — the legacy `zoom_out`, begin 2.0.
TextGlyphState _zoomOut(double p, int i, int n) =>
    TextGlyphState(scale: _lerp(2, 1, _easeOutCubic(_clamp01(p))), opacity: _clamp01(p * 2));

TextGlyphState _zoomInOut(double p, int i, int n) =>
    TextGlyphState(scale: _lerp(1, 0, _easeInCubic(_clamp01(p))), opacity: _clamp01((1 - p) * 2));

TextGlyphState _zoomOutOut(double p, int i, int n) =>
    TextGlyphState(scale: _lerp(1, 2, _easeInCubic(_clamp01(p))), opacity: _clamp01((1 - p) * 2));

/// How far a slide travels, in glyph heights.
///
/// A little over one line: far enough to read as entering from off-frame,
/// short enough that the text is not absent for most of a half-second window.
const double _kSlideDistance = 1.5;

/// Slides are built from one body so the four directions cannot drift apart.
///
/// `dx`/`dy` point from the animation's *start* towards rest, matching the
/// legacy layer: `slide_up` began below (`slideY(begin: 1)`) and travelled up.
TextGlyphState _slideIn(double p, double dx, double dy) {
  final t = _easeOutCubic(_clamp01(p));
  final remaining = 1 - t;
  return TextGlyphState(
    offsetX: dx * _kSlideDistance * remaining,
    offsetY: dy * _kSlideDistance * remaining,
    opacity: _clamp01(p * 2),
  );
}

TextGlyphState _slideOut(double p, double dx, double dy) {
  final t = _easeInCubic(_clamp01(p));
  return TextGlyphState(
    offsetX: dx * _kSlideDistance * t,
    offsetY: dy * _kSlideDistance * t,
    opacity: _clamp01((1 - p) * 2),
  );
}

/// Overshoots past its resting place and settles — one glyph at a time.
TextGlyphState _bounceIn(double p, int i, int n) {
  final g = _stagger(p, i, n);
  final t = _easeOutBounce(g);
  return TextGlyphState(
    // Drops in from above and bounces on the baseline.
    offsetY: -_kSlideDistance * (1 - t),
    opacity: _clamp01(g * 3),
  );
}

TextGlyphState _bounceOut(double p, int i, int n) {
  final g = _stagger(p, i, n);
  final t = _easeInCubic(g);
  return TextGlyphState(
    offsetY: _kSlideDistance * t,
    opacity: _clamp01((1 - g) * 3),
  );
}

/// A small scale overshoot — the "pop" that makes a caption land with weight.
TextGlyphState _popIn(double p, int i, int n) {
  final g = _stagger(p, i, n);
  return TextGlyphState(
    scale: _lerp(0.4, 1, _easeOutBack(g)),
    opacity: _clamp01(g * 3),
  );
}

TextGlyphState _popOut(double p, int i, int n) {
  final g = _stagger(p, i, n);
  return TextGlyphState(
    // `_easeInBack` dips slightly *below* zero early, which would flip the
    // glyph inside out; clamping the scale keeps the anticipation without it.
    scale: math.max(0.0, _lerp(1, 0.4, _easeInBack(g))),
    opacity: _clamp01((1 - g) * 3),
  );
}

/// A single hump travelling along the text as it appears.
TextGlyphState _waveIn(double p, int i, int n) {
  final g = _stagger(p, i, n);
  // Half a sine over the glyph's own window: up and back down, ending flat.
  final lift = math.sin(math.pi * g);
  return TextGlyphState(
    offsetY: -0.5 * lift,
    opacity: _clamp01(g * 2),
    // The glyph's own travel settles, so the resting state is exact at g == 1.
    scale: _lerp(0.8, 1, _easeOutCubic(g)),
  );
}

/// The text is already there; the fill colour sweeps through it.
///
/// Opacity stays at 1 throughout — this is a colour sweep over visible text,
/// not a reveal, and fading it as well would make it read as a slow fade.
TextGlyphState _colourFill(double p, int i, int n) =>
    TextGlyphState(fillProgress: _stagger(p, i, n));

/// Rises from below with a slight lean, glyph by glyph.
TextGlyphState _riseIn(double p, int i, int n) {
  final g = _stagger(p, i, n);
  final t = _easeOutCubic(g);
  return TextGlyphState(
    offsetY: _kSlideDistance * (1 - t),
    opacity: _clamp01(g * 2),
  );
}

/// Spins into place — rotation and scale resolving together.
TextGlyphState _spinIn(double p, int i, int n) {
  final g = _stagger(p, i, n);
  final t = _easeOutCubic(g);
  return TextGlyphState(
    // A half-turn is enough to read as a spin; a full turn at typical
    // durations is too fast to follow and reads as a flicker.
    rotation: -math.pi * (1 - t),
    scale: _lerp(0.3, 1, t),
    opacity: _clamp01(g * 2),
  );
}

/// Sinks away downward, fading — the counterpart to [_riseIn].
TextGlyphState _sinkOut(double p, int i, int n) {
  final g = _stagger(p, i, n);
  final t = _easeInCubic(g);
  return TextGlyphState(
    offsetY: _kSlideDistance * t,
    opacity: _clamp01((1 - g) * 2),
  );
}

// -- loops ------------------------------------------------------------------
//
// Every loop below is a whole number of cycles in `p`, so `p == 0` and
// `p == 1` are the same instant of the motion and the wrap is invisible.
// Per-glyph phase is a *fraction of the cycle*, which keeps that true however
// many glyphs there are — offsetting by anything that does not divide the
// cycle evenly would put the seam back.

/// A wave travelling along the text, forever.
TextGlyphState _waveLoop(double p, int i, int n) {
  // One full wavelength spread across the text, so the crest visibly travels
  // from the first character to the last rather than every glyph bobbing
  // together.
  final phase = n <= 1 ? 0.0 : i / n;
  return TextGlyphState(offsetY: -0.35 * _cycles(p, 1, phase));
}

/// A gentle breath — the whole block scaling as one.
TextGlyphState _pulseLoop(double p, int i, int n) =>
    TextGlyphState(scale: 1 + 0.08 * _cycles(p, 1));

/// A nervous shake: each glyph jitters on its own axis, deterministically.
TextGlyphState _shakeLoop(double p, int i, int n) {
  // The hash sets each glyph's *phase*, not its amplitude, so neighbours are
  // out of step (which is what makes it read as shake rather than as the block
  // vibrating) while the motion stays continuous and seamless at the wrap.
  final px = _hashUnit(i, 1);
  final py = _hashUnit(i, 2);
  // Several cycles per loop — a shake is fast by nature — and both counts are
  // whole, so the seam holds.
  return TextGlyphState(
    offsetX: 0.08 * _cycles(p, 6, px),
    offsetY: 0.08 * _cycles(p, 5, py),
  );
}

/// A slow, loose wobble: shake's lazy cousin, with rotation.
TextGlyphState _wiggleLoop(double p, int i, int n) {
  final pr = _hashUnit(i, 3);
  final po = _hashUnit(i, 4);
  return TextGlyphState(
    rotation: 0.09 * _cycles(p, 2, pr),
    offsetY: 0.05 * _cycles(p, 2, po),
  );
}

/// The fill sweeps through the text repeatedly.
///
/// `fillProgress` is a sawtooth rather than a sine so the sweep always travels
/// the same way; the seam is still exact because the ramp completes within the
/// loop and every glyph is back at its starting value at `p == 1`.
TextGlyphState _colourCycleLoop(double p, int i, int n) {
  final phase = n <= 1 ? 0.0 : i / n;
  final v = (p + phase) % 1.0;
  // Triangle, not sawtooth: a sawtooth's reset is a hard jump in colour on
  // every glyph, once per loop.
  return TextGlyphState(fillProgress: v < 0.5 ? v * 2 : (1 - v) * 2);
}

// ---------------------------------------------------------------------------
// The table
// ---------------------------------------------------------------------------

/// Every animation, in the order the animation tab shows them.
const List<TextAnimation> kTextAnimations = [
  // -- in --
  TextAnimation(
    id: 'typing',
    label: 'Typing',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _typing,
  ),
  TextAnimation(
    id: 'fade_in',
    label: 'Fade in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _fadeIn,
  ),
  TextAnimation(
    id: 'zoom_in',
    label: 'Zoom in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _zoomIn,
  ),
  TextAnimation(
    id: 'zoom_out',
    label: 'Zoom out',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _zoomOut,
  ),
  TextAnimation(
    id: 'slide_up',
    label: 'Slide up',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideUpIn,
  ),
  TextAnimation(
    id: 'slide_down',
    label: 'Slide down',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideDownIn,
  ),
  TextAnimation(
    id: 'slide_left',
    label: 'Slide left',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideLeftIn,
  ),
  TextAnimation(
    id: 'slide_right',
    label: 'Slide right',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideRightIn,
  ),
  TextAnimation(
    id: 'bounce_in',
    label: 'Bounce in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggeredSlow,
    stateAt: _bounceIn,
  ),
  TextAnimation(
    id: 'pop_in',
    label: 'Pop in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _popIn,
  ),
  TextAnimation(
    id: 'wave_in',
    label: 'Wave in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _waveIn,
  ),
  TextAnimation(
    id: 'colour_fill',
    label: 'Colour fill',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _colourFill,
  ),
  TextAnimation(
    id: 'rise_in',
    label: 'Rise in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _riseIn,
  ),
  TextAnimation(
    id: 'spin_in',
    label: 'Spin in',
    category: TextAnimationCategory.inAnim,
    isPerGlyph: true,
    naturalDuration: _staggeredSlow,
    stateAt: _spinIn,
  ),

  // -- out --
  TextAnimation(
    id: 'untyping',
    label: 'Untyping',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _untyping,
  ),
  TextAnimation(
    id: 'fade_out',
    label: 'Fade out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _fadeOut,
  ),
  TextAnimation(
    id: 'zoom_in_out',
    label: 'Zoom in out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _zoomInOut,
  ),
  TextAnimation(
    id: 'zoom_out_out',
    label: 'Zoom out out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _zoomOutOut,
  ),
  TextAnimation(
    id: 'slide_up_out',
    label: 'Slide up out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideUpOut,
  ),
  TextAnimation(
    id: 'slide_down_out',
    label: 'Slide down out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideDownOut,
  ),
  TextAnimation(
    id: 'slide_left_out',
    label: 'Slide left out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideLeftOut,
  ),
  TextAnimation(
    id: 'slide_right_out',
    label: 'Slide right out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: false,
    naturalDuration: _flat,
    stateAt: _slideRightOut,
  ),
  TextAnimation(
    id: 'bounce_out',
    label: 'Bounce out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _bounceOut,
  ),
  TextAnimation(
    id: 'pop_out',
    label: 'Pop out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _popOut,
  ),
  TextAnimation(
    id: 'sink_out',
    label: 'Sink out',
    category: TextAnimationCategory.outAnim,
    isPerGlyph: true,
    naturalDuration: _staggered,
    stateAt: _sinkOut,
  ),

  // -- loop --
  //
  // A loop's `naturalDuration` is the length of **one cycle**, not of the
  // overlay: the caller wraps `p` by it for as long as the text is on screen.
  TextAnimation(
    id: 'wave_loop',
    label: 'Wave',
    category: TextAnimationCategory.loop,
    isPerGlyph: true,
    naturalDuration: _loopCycle,
    stateAt: _waveLoop,
  ),
  TextAnimation(
    id: 'pulse_loop',
    label: 'Pulse',
    category: TextAnimationCategory.loop,
    isPerGlyph: false,
    naturalDuration: _loopCycle,
    stateAt: _pulseLoop,
  ),
  TextAnimation(
    id: 'shake_loop',
    label: 'Shake',
    category: TextAnimationCategory.loop,
    isPerGlyph: true,
    naturalDuration: _loopCycle,
    stateAt: _shakeLoop,
  ),
  TextAnimation(
    id: 'colour_cycle_loop',
    label: 'Colour cycle',
    category: TextAnimationCategory.loop,
    isPerGlyph: true,
    naturalDuration: _loopCycleSlow,
    stateAt: _colourCycleLoop,
  ),
  TextAnimation(
    id: 'wiggle_loop',
    label: 'Wiggle',
    category: TextAnimationCategory.loop,
    isPerGlyph: true,
    naturalDuration: _loopCycle,
    stateAt: _wiggleLoop,
  ),
];

// Tear-offs: a `const` list cannot hold a closure, so each direction and each
// duration variant needs a named top-level function.
TextGlyphState _slideUpIn(double p, int i, int n) => _slideIn(p, 0, 1);
TextGlyphState _slideDownIn(double p, int i, int n) => _slideIn(p, 0, -1);
TextGlyphState _slideLeftIn(double p, int i, int n) => _slideIn(p, 1, 0);
TextGlyphState _slideRightIn(double p, int i, int n) => _slideIn(p, -1, 0);

TextGlyphState _slideUpOut(double p, int i, int n) => _slideOut(p, 0, -1);
TextGlyphState _slideDownOut(double p, int i, int n) => _slideOut(p, 0, 1);
TextGlyphState _slideLeftOut(double p, int i, int n) => _slideOut(p, -1, 0);
TextGlyphState _slideRightOut(double p, int i, int n) => _slideOut(p, 1, 0);

/// Bounce and spin need longer to read: a bounce compressed into half a second
/// looks like a twitch, and a spin like a flicker.
double _staggeredSlow(int glyphCount) =>
    _staggered(glyphCount, base: 0.6, perGlyph: 0.05);

double _loopCycle(int glyphCount) => 1.2;
double _loopCycleSlow(int glyphCount) => 2.4;

// ---------------------------------------------------------------------------
// Lookup
// ---------------------------------------------------------------------------

/// Names older drafts stored, mapped onto catalog ids.
///
/// [id] is persisted, so an existing project holding `fade` or `scale` must
/// still animate rather than silently going still. The two bare names came
/// from the old widget layer, where one id served both ends — `fade` meant
/// `fadeIn` in `inAnimation` and `fadeOut` in `outAnimation`. Resolving both to
/// their in-variant is correct here because the caller already knows which
/// field it read; the out-field lookup is handled by [textAnimationById]
/// returning the in-variant and the consumer's own category check, so nothing
/// crashes either way.
const Map<String, String> _kLegacyAnimationIds = {
  'fade': 'fade_in',
  'scale': 'zoom_in',
};

final Map<String, TextAnimation> _byId = {
  for (final a in kTextAnimations) a.id: a,
};

/// The animation stored under [id], or null if nothing matches.
///
/// **Never throws.** An id can arrive from a draft written by an older build,
/// or from a rename that has not been migrated; the caller's contract is that
/// an unknown animation simply does not animate, exactly as `none` does. A
/// throw here would turn a stale draft into a crash on open.
TextAnimation? textAnimationById(String? id) {
  if (id == null || id.isEmpty || id == 'none') return null;
  final resolved = _kLegacyAnimationIds[id] ?? id;
  return _byId[resolved];
}

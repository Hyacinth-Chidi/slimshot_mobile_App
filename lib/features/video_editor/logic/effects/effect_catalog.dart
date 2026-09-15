/// The single definition of what visual effects a clip may carry.
///
/// Like the transition catalog, this is the one table every consumer keys off:
/// the effects panel builds its tiles from it, the timeline composer validates
/// a clip's stored id against it, and the renderer's shader registry is written
/// to match it entry for entry. A second list anywhere is how the panel and the
/// renderer drift into offering an effect that draws nothing.
///
/// **An effect id is persisted into drafts and sent over the channel**, exactly
/// like `EditorTransition.name` and a text animation id. Renaming one is a
/// migration, not an edit — a project saved today must still resolve its
/// effects in a build shipped a year from now. The ids here were chosen to be
/// livable for that long: they name the *effect*, not the implementation, so a
/// shader rewrite never forces a rename. `blur` stays `blur` whether it is two
/// gaussian passes or one kawase pass.
///
/// **An unknown id degrades to no effect, never to a crash** ([videoEffectById]
/// returns null). A draft can arrive from a newer build, from a rename that was
/// not migrated, or from a hand-edited file; the same rule unknown transition
/// names already follow.
library;

/// Which shelf of the effects panel an entry belongs to.
enum EffectCategory {
  /// The absence of an effect. No catalog entry carries it — it exists so a
  /// caller can name "no effect" in the same type as a real choice, and so the
  /// panel's leading None tile is not a special case of its own.
  none,

  /// Tone and colour: the look of the picture without moving any pixel.
  grade,

  /// Analogue artefacts — tape, broadcast, damaged signal.
  retro,

  /// Geometry: the frame's pixels are resampled from somewhere else.
  distort,

  /// Light added to the frame rather than taken from it.
  light,

  /// Sampling that reads more than one texel per output pixel — sharpening and
  /// the multi-pass blurs. Named for what the shader *does* rather than the
  /// mood it produces, because the cost is what a user picking several of them
  /// on a low-end device will feel.
  motion,

  /// Plays once over the clip's opening and settles — a cinema zoom, a shutter,
  /// a fade up from black.
  ///
  /// The category exists because these are the only effects that are a function
  /// of *time* rather than of the pixel: everything else here renders the same
  /// picture whenever it is sampled, and an intro renders a different one every
  /// frame. That is also why [VideoEffect.introSeconds] exists — an intro
  /// occupies the clip's opening, not the whole clip.
  intro,

  /// The clip appears from black over its opening — a shutter parting, a circle
  /// opening, cells arriving in a grid.
  ///
  /// **These are not transitions, and keeping them apart is the point of the
  /// category.** A transition is an overlap between two clips: it needs two live
  /// decoders, a window the composer resolves, and by definition something to
  /// blend *from*, so it cannot exist on the first clip of a timeline. A reveal
  /// is a property of one clip and works there — which is exactly where a user
  /// opening a video wants one.
  ///
  /// Timed, like [intro], and settling the same way. Shelved separately because
  /// a person browsing knows whether they want the picture to *arrive* or to
  /// *move*, and mixing eighteen of both on one shelf makes neither findable.
  reveal,

  /// Runs for the whole clip and never settles — a drift, a handheld shake.
  ///
  /// The counterpart of [intro]: these declare **no** [VideoEffect.introSeconds],
  /// so `uProgress` is the clip's position across its whole length and the
  /// motion is still going at the last frame. A continuous look that settled
  /// would be an intro.
  motionLoop,
}

/// What a clip's effect intensity reads as when nothing has set one.
///
/// A clip with no effect still has to store *some* intensity, and this is that
/// resting value — including for a draft written before effects existed, which
/// has no field to read. It is deliberately the neutral full strength rather
/// than zero: the moment an effect is applied without an explicit intensity,
/// the user must see it. A zero default would apply an effect that draws
/// nothing and read as the feature being broken.
const double defaultEffectIntensity = 1.0;

/// One effect the user can apply to a clip.
class VideoEffect {
  const VideoEffect({
    required this.id,
    required this.label,
    required this.category,
    required this.defaultIntensity,
    this.passCount = 1,
    this.introSeconds,
  });

  /// Persisted into drafts and sent over the channel. **Renaming needs a
  /// migration**; see the library comment.
  final String id;

  /// What the panel shows the user — named the way a person describes the look
  /// ("Dreamy"), not the way the shader works ("Gaussian convolution"). These
  /// strings appear on tiles, so they are short enough to fit one.
  final String label;

  final EffectCategory category;

  /// Where the intensity slider rests when the effect is first applied, as a
  /// **normalised 0..1 value — never pixels, never a radius**.
  ///
  /// This is the rule most often broken in this codebase: a pixel parameter
  /// renders differently in a ~400px preview and a 1080p export, so the file
  /// does not match what the user approved on the canvas. A shader turns this
  /// fraction into whatever units it needs, scaled by the frame it is actually
  /// drawing into.
  ///
  /// Each default is picked to be *visibly the effect* while still looking like
  /// footage — a first application should read as a choice, not as damage.
  final double defaultIntensity;

  /// How many render passes the chain runs for this effect.
  ///
  /// Must never exceed 4: `MAX_EFFECT_PASSES` in the Kotlin pass chain
  /// truncates and warns past it, so a fifth pass would silently render a
  /// different picture than the one declared here.
  final int passCount;

  /// How long this effect's animation runs from the clip's first frame, in
  /// **seconds**, or null for a static look that has no animation at all.
  ///
  /// This is the *window the shader's progress is measured across*, and it is
  /// the whole reason the concept lives here rather than in each shader. A
  /// cinema zoom is 0.8s whether the clip is 2s or 90s long, so a shader
  /// hardcoding "the first 10% of the clip" would play a lazy drift on a long
  /// clip and a snap on a short one. Declaring the seconds once, in the table
  /// every consumer already reads, is how the renderer draws the same opening
  /// on both.
  ///
  /// Named after `TextAnimation.naturalDuration`, which solves the same problem
  /// for text and is the precedent this follows — a flat number here where that
  /// is a function of the glyph count, because an intro's length depends on
  /// nothing but itself.
  ///
  /// **Null and a number mean two different things to the renderer**, not one
  /// thing with a default:
  ///
  /// * **null** — a static look. `uProgress` still arrives, measured across the
  ///   whole clip, and the shader ignores it. This is every existing entry, and
  ///   it is why adding the clock changes nothing about how `vignette` and
  ///   `fisheye` draw.
  /// * **a number** — an intro. `uProgress` runs 0 to 1 across exactly this many
  ///   seconds from the clip's start and then **stays at 1** for the rest of
  ///   the clip, which is what "plays once and settles" means: the shader's
  ///   `p == 1` state is its resting state, so the clip is left looking
  ///   untouched without the effect having to be removed.
  ///
  /// A clip shorter than the window is not a special case — progress simply
  /// does not reach 1 before the clip ends, so the intro is cut off with the
  /// clip. Compressing it to fit would make the same effect play at a different
  /// speed on a short clip, which is the `TextAnimation` mistake the speed
  /// multiplier exists to avoid.
  final double? introSeconds;

  /// Whether this effect plays over a window at the clip's opening and then
  /// settles.
  ///
  /// Derived from [introSeconds] rather than stored beside it: two fields that
  /// can disagree is one field too many, and here the disagreement would be an
  /// effect declared as animated that never moves.
  ///
  /// **Not the same question as "does it move".** A [EffectCategory.motionLoop]
  /// entry animates for the whole clip and declares no window, so it is false
  /// here — which is correct, because what this actually answers is "does
  /// progress run out before the clip does". Both [EffectCategory.intro] and
  /// [EffectCategory.reveal] are true.
  bool get isTimed => introSeconds != null;

  /// Whether this effect needs the ping-pong chain rather than a single draw.
  ///
  /// Derived, not stored: two fields that can disagree is one field too many,
  /// and the disagreement would be invisible until a multi-pass effect was
  /// drawn in a single pass.
  bool get isMultiPass => passCount > 1;
}

/// Every effect, in panel order within each category.
const List<VideoEffect> kVideoEffects = [
  // -- grade ---------------------------------------------------------------
  VideoEffect(
    id: 'vignette',
    label: 'Vignette',
    category: EffectCategory.grade,
    defaultIntensity: 0.5,
  ),
  VideoEffect(
    id: 'duotone',
    label: 'Duotone',
    category: EffectCategory.grade,
    defaultIntensity: 0.8,
  ),
  VideoEffect(
    id: 'chromatic',
    label: 'Fringe',
    category: EffectCategory.grade,
    defaultIntensity: 0.35,
  ),

  // -- retro ---------------------------------------------------------------
  VideoEffect(
    id: 'grain',
    label: 'Film Grain',
    category: EffectCategory.retro,
    defaultIntensity: 0.4,
  ),
  VideoEffect(
    id: 'vhs',
    label: 'VHS Tape',
    category: EffectCategory.retro,
    defaultIntensity: 0.5,
  ),
  VideoEffect(
    id: 'scanlines',
    label: 'Retro TV',
    category: EffectCategory.retro,
    defaultIntensity: 0.45,
  ),
  VideoEffect(
    id: 'rgb_split',
    label: 'RGB Shift',
    category: EffectCategory.retro,
    defaultIntensity: 0.35,
  ),
  VideoEffect(
    id: 'glitch',
    label: 'Glitch',
    category: EffectCategory.retro,
    defaultIntensity: 0.4,
  ),

  // -- distort -------------------------------------------------------------
  VideoEffect(
    id: 'fisheye',
    label: 'Fisheye',
    category: EffectCategory.distort,
    defaultIntensity: 0.45,
  ),
  VideoEffect(
    id: 'ripple',
    label: 'Ripple',
    category: EffectCategory.distort,
    defaultIntensity: 0.4,
  ),
  VideoEffect(
    id: 'swirl',
    label: 'Swirl',
    category: EffectCategory.distort,
    defaultIntensity: 0.4,
  ),
  VideoEffect(
    id: 'mirror',
    label: 'Mirror',
    category: EffectCategory.distort,
    // A mirror is a fold, not a strength: at anything but full the seam sits
    // somewhere arbitrary in frame. The slider still moves it for anyone who
    // wants that, but the default is the symmetric picture people mean.
    defaultIntensity: 1.0,
  ),

  // -- light ---------------------------------------------------------------
  VideoEffect(
    id: 'light_leak',
    label: 'Light Leak',
    category: EffectCategory.light,
    defaultIntensity: 0.5,
  ),
  VideoEffect(
    id: 'glow',
    label: 'Dreamy',
    category: EffectCategory.light,
    // Bright-pass, blur, composite. Three passes is the most expensive entry
    // in the catalog and the reason the chain exists at all.
    passCount: 3,
    defaultIntensity: 0.5,
  ),

  // -- motion --------------------------------------------------------------
  VideoEffect(
    id: 'sharpen',
    label: 'Sharpen',
    category: EffectCategory.motion,
    defaultIntensity: 0.4,
  ),
  VideoEffect(
    id: 'blur',
    label: 'Soft Blur',
    category: EffectCategory.motion,
    // Separable gaussian: horizontal, then vertical. One combined pass would
    // be O(n²) samples per pixel for the same picture.
    passCount: 2,
    defaultIntensity: 0.4,
  ),

  // -- intro ---------------------------------------------------------------
  VideoEffect(
    id: 'fade_in',
    label: 'Fade In',
    category: EffectCategory.intro,
    // The simplest possible consumer of the clock, and deliberately so: one
    // multiply by `uProgress`, so a picture that rises from black and settles
    // is proof the progress reaching the shader is the clip's own position —
    // in a way no more elaborate intro could be, where a wrong clock and a
    // right one look alike for the first few frames.
    introSeconds: 0.8,
    // An intro's strength is how far down it starts, not how much of the
    // picture it occupies; full is the fade people mean — up from true black.
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'cinema_zoom',
    label: 'Cinema Zoom',
    category: EffectCategory.intro,
    // The longest window in the category, because the whole character of a
    // cinematic push is that the movement is barely perceptible until it
    // stops. A fast cinema zoom is just a zoom.
    introSeconds: 1.2,
    defaultIntensity: 0.6,
  ),
  VideoEffect(
    id: 'zoom_in',
    label: 'Zoom In',
    category: EffectCategory.intro,
    // Short, because a punch that takes a second is a drift.
    introSeconds: 0.5,
    defaultIntensity: 0.7,
  ),
  VideoEffect(
    id: 'super_zoom',
    label: 'Super Zoom',
    category: EffectCategory.intro,
    introSeconds: 0.5,
    // Lower than `zoom_in`'s despite being the harder effect: its own start
    // scale is far higher, so the same visual punch needs less of the slider —
    // and it leaves room to go further, which is the reason it is a separate
    // entry rather than `zoom_in` at maximum.
    defaultIntensity: 0.6,
  ),
  VideoEffect(
    id: 'pulse_zoom',
    label: 'Pulse Zoom',
    category: EffectCategory.intro,
    // Three pulses over a second — around 180bpm, fast for music but right for
    // a short-form opening where the pulse must be legible in under a second.
    introSeconds: 1.0,
    defaultIntensity: 0.6,
  ),
  VideoEffect(
    id: 'bounce',
    label: 'Bounce',
    category: EffectCategory.intro,
    introSeconds: 0.9,
    defaultIntensity: 0.6,
  ),
  VideoEffect(
    id: 'spin',
    label: 'Spin',
    category: EffectCategory.intro,
    introSeconds: 0.8,
    defaultIntensity: 0.7,
  ),
  VideoEffect(
    id: 'roll',
    label: 'Roll',
    category: EffectCategory.intro,
    introSeconds: 0.8,
    defaultIntensity: 0.7,
  ),
  VideoEffect(
    id: 'tilt',
    label: 'Tilt',
    category: EffectCategory.intro,
    introSeconds: 0.7,
    defaultIntensity: 0.7,
  ),
  VideoEffect(
    id: 'blur_in',
    label: 'Blur In',
    category: EffectCategory.intro,
    // Separable gaussian, like `blur`: horizontal then vertical.
    passCount: 2,
    introSeconds: 0.8,
    defaultIntensity: 0.8,
  ),
  VideoEffect(
    id: 'pixel_in',
    label: 'Pixel In',
    category: EffectCategory.intro,
    introSeconds: 0.8,
    defaultIntensity: 0.7,
  ),
  VideoEffect(
    id: 'hue_shift',
    label: 'Hue Sweep',
    category: EffectCategory.intro,
    introSeconds: 1.0,
    defaultIntensity: 0.8,
  ),
  VideoEffect(
    id: 'bw_fade',
    label: 'Colour In',
    category: EffectCategory.intro,
    introSeconds: 1.0,
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'steady_in',
    label: 'Steady In',
    category: EffectCategory.intro,
    introSeconds: 0.9,
    defaultIntensity: 0.6,
  ),

  // -- reveal --------------------------------------------------------------
  //
  // Timed like the intros and settling by the same rule, but the picture
  // *arrives* rather than moving. Every one works on the first clip of a
  // timeline, which is what separates them from transitions.
  VideoEffect(
    id: 'shutter',
    label: 'Shutter',
    category: EffectCategory.reveal,
    introSeconds: 0.8,
    // A reveal's strength is how much of the frame starts covered, so full is
    // the gesture people mean — the clip opens on black.
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'horizontal_open',
    label: 'Side Open',
    category: EffectCategory.reveal,
    introSeconds: 0.8,
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'circle_in',
    label: 'Circle Open',
    category: EffectCategory.reveal,
    introSeconds: 0.8,
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'grid',
    label: 'Grid',
    category: EffectCategory.reveal,
    introSeconds: 1.0,
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'grid_collage',
    label: 'Collage',
    category: EffectCategory.reveal,
    // Longer than `grid`: more cells over the same window would each get a
    // shorter slice and the stagger would stop being legible.
    introSeconds: 1.2,
    defaultIntensity: 1.0,
  ),
  VideoEffect(
    id: 'roulette',
    label: 'Roulette',
    category: EffectCategory.reveal,
    introSeconds: 0.9,
    defaultIntensity: 1.0,
  ),

  // -- continuous ----------------------------------------------------------
  //
  // **No `introSeconds` on any of these, deliberately.** `uProgress` then runs
  // across the whole clip and the motion is still going at the last frame,
  // which is what "continuous" means. One of them declaring a window would
  // settle part-way through and then stop dead.
  VideoEffect(
    id: 'camera_pan',
    label: 'Camera Pan',
    category: EffectCategory.motionLoop,
    defaultIntensity: 0.6,
  ),
  VideoEffect(
    id: 'handheld',
    label: 'Handheld',
    category: EffectCategory.motionLoop,
    defaultIntensity: 0.5,
  ),
  VideoEffect(
    id: 'super_shake',
    label: 'Super Shake',
    category: EffectCategory.motionLoop,
    defaultIntensity: 0.5,
  ),
];

/// How long [id]'s animation runs from its clip's first frame, or null when it
/// is a static look measured across the whole clip.
///
/// The one place a consumer asks the question, so the renderer, the composer
/// and the panel cannot each answer it differently. Returns null for an unknown
/// id for the same reason [videoEffectById] does: a draft from a newer build
/// must open.
double? effectIntroSecondsFor(String? id) => videoEffectById(id)?.introSeconds;

final Map<String, VideoEffect> _byId = {
  for (final effect in kVideoEffects) effect.id: effect,
};

/// The effect stored under [id], or null when there is none.
///
/// **Never throws.** Null covers three cases that all mean the same thing to a
/// renderer — no id, a cleared selection (`''` or `'none'`), and an id this
/// build does not know — and the caller's contract for all three is to draw the
/// clip unaffected. A stale draft must open, not crash.
VideoEffect? videoEffectById(String? id) {
  if (id == null || id.isEmpty || id == 'none') return null;
  return _byId[id];
}

/// Every effect in [category], in catalog order.
///
/// [EffectCategory.none] is always empty: it names the absence of an effect,
/// so an entry claiming it would put a tile that does nothing on the shelf.
List<VideoEffect> effectsInCategory(EffectCategory category) =>
    kVideoEffects.where((e) => e.category == category).toList(growable: false);

/// The intensity a clip should start at when [id] is applied, or 0 for no
/// effect.
///
/// Callers setting `VideoSegment.effectId` go through this rather than
/// hardcoding 1.0, so an effect's chosen default is honoured from the first
/// frame the user sees instead of only once they touch the slider.
double defaultIntensityFor(String? id) =>
    videoEffectById(id)?.defaultIntensity ?? 0.0;

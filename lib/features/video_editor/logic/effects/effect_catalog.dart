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
];

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

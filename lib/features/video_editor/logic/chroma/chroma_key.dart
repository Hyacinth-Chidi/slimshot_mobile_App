/// A clip's chroma key: which of its pixels are dropped so the background
/// shows through, decided by **colour** rather than by position.
///
/// Structurally this is the mask's sibling, and deliberately so. A mask is a
/// coverage keyed on where a pixel is; a key is a coverage keyed on what colour
/// it is. Both multiply into the same `mix(backgroundAt(), graded, …)` at the
/// end of the shader's sampling helpers, which is the only place in the
/// pipeline where a clip pixel can be replaced by what is behind it: the clip
/// pass has no GL blending and `glClear` uses an opaque background, so an alpha
/// here would be a value nothing reads. Living there also means every one of
/// the eleven transitions inherits the key for free, and a keyed clip that is
/// fading is a keyed clip, fading.
///
/// **It cannot be an effect pass.** The effect chain runs on the finished
/// composited frame — one texture in, one target out — by which point the
/// clip's green has already been drawn over the background and there is
/// nothing behind it to reveal.
///
/// [chromaCoverage] and [despill] are the Dart twins of the shader's
/// `chromaCoverage` and `despill`. They exist so the arithmetic can be tested
/// at all (GLSL only runs on a device) and so the picker can preview a key; if
/// one side changes the other must.
library;

import 'dart:math' as math;

/// The least similarity window the maths will accept, so an exact-match key
/// still has a gradient to work with rather than a division by zero.
const double kChromaMinWindow = 0.001;

class ChromaKey {
  const ChromaKey({
    this.enabled = false,
    this.keyR = 0.0,
    this.keyG = 1.0,
    this.keyB = 0.0,
    this.similarity = 0.4,
    this.smoothness = 0.1,
    this.spill = 0.0,
  });

  /// No key: the whole clip shows. What every clip carries until one is set.
  static const ChromaKey none = ChromaKey();

  /// Off by default, so a clip that has never been keyed writes nothing and
  /// costs the shader one compare.
  final bool enabled;

  /// The colour being keyed out, 0..1 per channel. Green by default because
  /// that is what a green screen is, but any colour works — a blue screen, or
  /// a colour picked off the frame.
  final double keyR;
  final double keyG;
  final double keyB;

  /// How far from the key colour still counts as the key, 0..1. Raising it
  /// drops more of the neighbouring colours.
  final double similarity;

  /// How soft the boundary is, 0..1. Zero is a hard cut-out, which shows every
  /// jagged edge of the source; a little softness is what makes a key look
  /// like footage rather than a sticker.
  final double smoothness;

  /// How much of the key colour to pull out of the pixels that are **kept**,
  /// 0..1. A green screen bounces green onto whatever is in front of it, and
  /// that fringe survives the key because those pixels are not green enough to
  /// drop — so it has to be removed separately or the subject wears a halo.
  final double spill;

  bool get isNone => !enabled;

  ChromaKey copyWith({
    bool? enabled,
    double? keyR,
    double? keyG,
    double? keyB,
    double? similarity,
    double? smoothness,
    double? spill,
  }) {
    return ChromaKey(
      enabled: enabled ?? this.enabled,
      keyR: keyR ?? this.keyR,
      keyG: keyG ?? this.keyG,
      keyB: keyB ?? this.keyB,
      similarity: similarity ?? this.similarity,
      smoothness: smoothness ?? this.smoothness,
      spill: spill ?? this.spill,
    );
  }

  /// The two vec4s the shader reads, in a fixed order the Kotlin side mirrors:
  /// `(r, g, b, similarity)` then `(smoothness, spill, enabled, 0)`.
  List<double> uniforms() => [
        keyR,
        keyG,
        keyB,
        similarity,
        smoothness,
        spill,
        enabled ? 1.0 : 0.0,
        0.0,
      ];

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'r': keyR,
        'g': keyG,
        'b': keyB,
        'similarity': similarity,
        'smoothness': smoothness,
        'spill': spill,
      };

  static double _read(Object? raw, double fallback) {
    if (raw is! num) return fallback;
    final v = raw.toDouble();
    if (!v.isFinite) return fallback;
    return v.clamp(0.0, 1.0).toDouble();
  }

  /// A key from its JSON, or [none] for anything that is not one. Every value
  /// is clamped on read: a hand-edited draft must not reach a shader with a
  /// similarity of 9.
  static ChromaKey fromJson(Object? raw) {
    if (raw is! Map) return none;
    final enabled = raw['enabled'];
    if (enabled is! bool || !enabled) return none;
    return ChromaKey(
      enabled: true,
      keyR: _read(raw['r'], 0.0),
      keyG: _read(raw['g'], 1.0),
      keyB: _read(raw['b'], 0.0),
      similarity: _read(raw['similarity'], 0.4),
      smoothness: _read(raw['smoothness'], 0.1),
      spill: _read(raw['spill'], 0.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChromaKey &&
      other.enabled == enabled &&
      other.keyR == keyR &&
      other.keyG == keyG &&
      other.keyB == keyB &&
      other.similarity == similarity &&
      other.smoothness == smoothness &&
      other.spill == spill;

  @override
  int get hashCode =>
      Object.hash(enabled, keyR, keyG, keyB, similarity, smoothness, spill);

  @override
  String toString() => enabled
      ? 'ChromaKey(rgb $keyR/$keyG/$keyB, sim $similarity, smooth $smoothness)'
      : 'ChromaKey.none';
}

/// The **direction** of a colour's chroma — its hue, with both brightness and
/// saturation divided out.
///
/// Rec. 601's Cb/Cr, the pair broadcast video has keyed on for decades, and
/// then normalised. Both halves of that matter:
///
/// - Keying on chroma rather than on RGB distance is what lets a green screen
///   be unevenly lit. A plain RGB distance calls a bright green and a shadowed
///   green two different colours and keys one while keeping the other, which is
///   the ragged result a naive key gives.
/// - **Normalising is what makes that actually true.** Cb/Cr still scale with
///   brightness, so a 45% green sits 0.46 away from a full green — as far as a
///   sensible similarity window reaches — and the shadowed parts of the screen
///   survive the key anyway. Measured, not assumed: that number is why this
///   function returns a unit vector.
///
/// The cost is that near-greys have no meaningful direction, so [_chromaLength]
/// is reported alongside and a pixel with almost no colour is never keyed —
/// which is right, because a white shirt is not a green screen however the
/// arithmetic rounds.
({double cb, double cr, double length}) _chroma(double r, double g, double b) {
  final y = 0.299 * r + 0.587 * g + 0.114 * b;
  final cb = b - y;
  final cr = r - y;
  final length = math.sqrt(cb * cb + cr * cr);
  if (length < _kGreyThreshold) return (cb: 0.0, cr: 0.0, length: length);
  return (cb: cb / length, cr: cr / length, length: length);
}

/// Below this a colour has no usable hue and is treated as grey.
const double _kGreyThreshold = 0.02;

/// The chroma length at which a colour counts as fully saturated for keying.
/// A pure green screen is well above it; the value sets how quickly a
/// desaturating pixel stops being treated as the key.
const double _kFullSaturation = 0.25;

/// How much of a pixel is **kept**: 1 shows the clip, 0 shows the background.
///
/// The twin of the shader's `chromaCoverage`.
double chromaCoverage(double r, double g, double b, ChromaKey key) {
  if (!key.enabled) return 1.0;

  final pixel = _chroma(r, g, b);
  final target = _chroma(key.keyR, key.keyG, key.keyB);
  // A key with no hue of its own cannot key anything by hue.
  if (target.length < _kGreyThreshold) return 1.0;

  // **Hue first, saturation second.** Distance is how far the pixel's hue is
  // from the key's, 0 (same) to 1 (opposite), which is what makes a shadowed
  // green screen key like a lit one.
  final dCb = pixel.cb - target.cb;
  final dCr = pixel.cr - target.cr;
  final hueDistance = math.sqrt(dCb * dCb + dCr * dCr) * 0.5;

  // But hue alone is binary along the desaturation axis: every step from a
  // green screen toward grey keeps pointing at green until it abruptly is not
  // green at all, so the whole soft edge — where a hair or a motion-blurred
  // arm lives — collapses to a hard cut and `smoothness` does nothing.
  // Measured: a full walk from green to grey gave 0.0 then 1.0 and no value
  // between. Weakly saturated pixels are therefore pulled toward "keep" in
  // proportion to how grey they are, which is what gives that edge its ramp.
  final saturation =
      (pixel.length / _kFullSaturation).clamp(0.0, 1.0).toDouble();
  final distance = hueDistance + (1.0 - saturation);

  // Inside `similarity` the pixel is the key and goes; beyond that plus the
  // smoothness it is kept; between the two it is a partial edge. A zero
  // smoothness collapses to a hard threshold, which is why the window has a
  // floor — the step would otherwise be a division by zero.
  final inner = key.similarity;
  final outer = inner + math.max(key.smoothness, kChromaMinWindow);
  if (distance <= inner) return 0.0;
  if (distance >= outer) return 1.0;
  final t = (distance - inner) / (outer - inner);
  // Smoothstep, matching the shader's own: a linear ramp shows a visible band
  // where the edge meets the kept picture.
  return t * t * (3.0 - 2.0 * t);
}

/// A kept pixel with the key colour's bounce pulled out of it — the twin of
/// the shader's `despill`.
///
/// Only the key's dominant channel is touched, and only where it exceeds the
/// other two: that excess *is* the spill. Pulling it down to their average
/// leaves a neutral edge, and a pixel that legitimately holds that colour (a
/// green jumper in front of a green screen is a lost cause anyway, but a green
/// road sign at the edge of frame is not) is left alone because its channel is
/// not in excess.
({double r, double g, double b}) despill(
  double r,
  double g,
  double b,
  ChromaKey key,
) {
  if (!key.enabled || key.spill <= 0) return (r: r, g: g, b: b);

  // Which channel the key leans on hardest.
  final maxKey = math.max(key.keyR, math.max(key.keyG, key.keyB));
  if (maxKey <= 0) return (r: r, g: g, b: b);

  if (key.keyG == maxKey) {
    final neutral = (r + b) * 0.5;
    if (g <= neutral) return (r: r, g: g, b: b);
    return (r: r, g: g + (neutral - g) * key.spill, b: b);
  }
  if (key.keyB == maxKey) {
    final neutral = (r + g) * 0.5;
    if (b <= neutral) return (r: r, g: g, b: b);
    return (r: r, g: g, b: b + (neutral - b) * key.spill);
  }
  final neutral = (g + b) * 0.5;
  if (r <= neutral) return (r: r, g: g, b: b);
  return (r: r + (neutral - r) * key.spill, g: g, b: b);
}

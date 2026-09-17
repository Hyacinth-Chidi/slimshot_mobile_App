/// A clip's mask: a window over the picture, outside which the letterbox fill
/// shows through.
///
/// **Authored on the displayed picture, in fractions of the clip's fitted
/// frame** — the same space the crop rect lives in — so it travels with the
/// clip's placement and a draft renders identically on any device. Applied in
/// the shader as a coverage that multiplies the clip's opacity: outside the
/// window is the background, exactly as a letterbox pixel is, so every
/// transition inherits it for free. Plain values, deliberately not animatable
/// yet: a moving mask is four coupled numbers with their own design.
///
/// [maskCoverage] is the Dart twin of the shader's `maskCoverage` and exists
/// for tests and the canvas outline; if one changes the other must.
library;

import 'dart:math' as math;

/// The window's shape. `none` is the absence of a mask and writes nothing.
/// The window's shape. `none` is the absence of a mask and writes nothing.
///
/// **Append only.** Both sides read the shape as a number — the shader tests
/// `a.x < 1.5` — so inserting a value would turn every saved circle into
/// something else. `roundedRectangle` is last for that reason, not by accident.
enum ClipMaskShape { none, rectangle, circle, linear, roundedRectangle }

/// Least half-extent and feather the maths will accept, so a zero never
/// reaches a division.
const double kMaskMinExtent = 0.001;

class ClipMask {
  const ClipMask({
    this.shape = ClipMaskShape.none,
    this.centerX = 0.5,
    this.centerY = 0.5,
    this.width = 0.6,
    this.height = 0.6,
    this.feather = 0.05,
    this.inverted = false,
    this.cornerRadius = 0.12,
  });

  /// No mask: the whole picture shows.
  static const ClipMask none = ClipMask();

  final ClipMaskShape shape;

  /// The window's centre, as fractions of the fitted frame.
  final double centerX;
  final double centerY;

  /// The window's full extent, as fractions of the fitted frame. For `linear`
  /// only [centerX] and [feather] matter: it keeps the left of the centre and
  /// fades to the right over the feather.
  final double width;
  final double height;

  /// How wide the soft edge is, as a fraction of the frame.
  final double feather;

  /// Corner arc for [ClipMaskShape.roundedRectangle], as a fraction of the
  /// frame like every other extent here. Ignored by the other shapes, and
  /// clamped at use to the largest arc the box can hold — a radius wider than
  /// the box would otherwise fold the shape inside out.
  ///
  /// This is the shape a picture-in-picture actually wants: a plain rectangle
  /// reads as a screenshot pasted on, and a circle crops the corners off a
  /// 16:9 inset.
  final double cornerRadius;

  /// Keep the outside instead of the inside.
  final bool inverted;

  bool get isNone => shape == ClipMaskShape.none;

  ClipMask copyWith({
    ClipMaskShape? shape,
    double? centerX,
    double? centerY,
    double? width,
    double? height,
    double? feather,
    bool? inverted,
    double? cornerRadius,
  }) {
    return ClipMask(
      shape: shape ?? this.shape,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
      width: width ?? this.width,
      height: height ?? this.height,
      feather: feather ?? this.feather,
      inverted: inverted ?? this.inverted,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }

  /// The wire and draft shape. Callers omit it entirely for [none].
  Map<String, dynamic> toJson() => {
        'shape': shape.name,
        'centerX': centerX,
        'centerY': centerY,
        'width': width,
        'height': height,
        'feather': feather,
        'inverted': inverted,
        'cornerRadius': cornerRadius,
      };

  /// Defensive: anything that is not a map with a known shape is [none];
  /// malformed numbers take the defaults, and every number is clamped to the
  /// range the tool can produce.
  static ClipMask fromJson(Object? raw) {
    if (raw is! Map) return none;
    final shape = ClipMaskShape.values.cast<ClipMaskShape?>().firstWhere(
          (s) => s!.name == raw['shape'],
          orElse: () => null,
        );
    if (shape == null || shape == ClipMaskShape.none) return none;
    double read(String key, double fallback, double lo, double hi) {
      final v = raw[key];
      if (v is! num) return fallback;
      return v.toDouble().clamp(lo, hi).toDouble();
    }

    return ClipMask(
      shape: shape,
      centerX: read('centerX', 0.5, 0.0, 1.0),
      centerY: read('centerY', 0.5, 0.0, 1.0),
      width: read('width', 0.6, kMaskMinExtent, 2.0),
      height: read('height', 0.6, kMaskMinExtent, 2.0),
      feather: read('feather', 0.05, 0.0, 0.5),
      inverted: raw['inverted'] == true,
      // Absent in every mask saved before rounded corners existed.
      cornerRadius: read('cornerRadius', 0.12, 0.0, 2.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ClipMask &&
      other.shape == shape &&
      other.centerX == centerX &&
      other.centerY == centerY &&
      other.width == width &&
      other.height == height &&
      other.feather == feather &&
      other.inverted == inverted &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode =>
      Object.hash(shape, centerX, centerY, width, height, feather, inverted,
          cornerRadius);

  @override
  String toString() => isNone
      ? 'ClipMask.none'
      : 'ClipMask(${shape.name} @ $centerX,$centerY ${width}x$height feather $feather${inverted ? ' inverted' : ''})';
}

/// GLSL's `smoothstep`, so the Dart twin and the shader agree edge for edge.
double _smoothstep(double edge0, double edge1, double x) {
  if (edge1 <= edge0) return x < edge0 ? 0.0 : 1.0;
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

/// How much of the picture shows at [x],[y] (fitted-frame fractions): 1 inside
/// the window, 0 outside, a soft ramp across the feather. **The Dart twin of
/// the shader's `maskCoverage`** — the arithmetic here is the arithmetic
/// there, and a test pins the cases that matter.
double maskCoverage(ClipMask mask, double x, double y) {
  if (mask.isNone) return 1.0;
  final feather = math.max(mask.feather, kMaskMinExtent);
  final halfW = math.max(mask.width * 0.5, kMaskMinExtent);
  final halfH = math.max(mask.height * 0.5, kMaskMinExtent);
  final dx = x - mask.centerX;
  final dy = y - mask.centerY;
  double coverage;
  switch (mask.shape) {
    case ClipMaskShape.none:
      return 1.0;
    case ClipMaskShape.rectangle:
      final outside = math.max(dx.abs() - halfW, dy.abs() - halfH);
      coverage = 1.0 - _smoothstep(0.0, feather, outside);
    case ClipMaskShape.circle:
      final r = math.sqrt((dx / halfW) * (dx / halfW) + (dy / halfH) * (dy / halfH));
      coverage = 1.0 - _smoothstep(1.0, 1.0 + feather / math.max(halfW, halfH), r);
    case ClipMaskShape.roundedRectangle:
      // The distance field of a rounded box: push the box in by the radius,
      // measure to that smaller box, then subtract the radius back. Inside the
      // straight edges this is identical to the plain rectangle; near a corner
      // it becomes the distance to the arc's centre, which is what rounds it.
      final r = math.min(mask.cornerRadius, math.min(halfW, halfH))
          .clamp(0.0, double.infinity)
          .toDouble();
      final qx = dx.abs() - (halfW - r);
      final qy = dy.abs() - (halfH - r);
      final outside = math.sqrt(
            math.pow(math.max(qx, 0.0), 2) + math.pow(math.max(qy, 0.0), 2),
          ) +
          math.min(math.max(qx, qy), 0.0) -
          r;
      coverage = 1.0 - _smoothstep(0.0, feather, outside);
    case ClipMaskShape.linear:
      coverage = 1.0 - _smoothstep(mask.centerX - feather, mask.centerX + feather, x);
  }
  return mask.inverted ? 1.0 - coverage : coverage;
}

/// The two `vec4`s the shader reads per lane: `(shape, centerX, centerY,
/// feather)` and `(width, height, inverted, 0)`. Kotlin's
/// `NativeTimelineClip.maskUniforms` encodes the same order from the wire, and
/// a fixture-style test on each side pins it.
List<double> maskUniforms(ClipMask mask) => [
      mask.shape.index.toDouble(),
      mask.centerX,
      mask.centerY,
      mask.feather,
      mask.width,
      mask.height,
      mask.inverted ? 1.0 : 0.0,
      // The slot was reserved and unused; the rounded rectangle is what it was
      // waiting for. Zero for every other shape, which is what they always sent.
      mask.shape == ClipMaskShape.roundedRectangle ? mask.cornerRadius : 0.0,
    ];

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
/// A window can be **tilted** ([ClipMask.angle]) — CapCut turns its mask with
/// a two-finger twist, and the car-crash edit leans a line mask so the car
/// passes behind it. The turn is rigid on the picture: it happens in an
/// aspect-true space, or a tilted circle on a 9:16 frame would come out an
/// ellipse.
///
/// [maskCoverage] is the Dart twin of the shader's `maskCoverage` and exists
/// for tests and the canvas outline; if one changes the other must.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../models/media_asset.dart' show normaliseDegrees;

/// The window's shape. `none` is the absence of a mask and writes nothing.
///
/// **Append only.** Both sides read the shape as a number — the shader tests
/// `a.x < 1.5` — so inserting a value would turn every saved circle into
/// something else. `roundedRectangle` and `mirror` come last for that reason,
/// not by accident: the panel orders its chips itself.
///
/// `mirror` is CapCut's: a band between two parallel lines, horizontal until
/// it is tilted, whose thickness is the window's height.
enum ClipMaskShape { none, rectangle, circle, linear, roundedRectangle, mirror }

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
    this.angle = 0.0,
  });

  /// No mask: the whole picture shows.
  static const ClipMask none = ClipMask();

  final ClipMaskShape shape;

  /// The window's centre, as fractions of the fitted frame.
  final double centerX;
  final double centerY;

  /// The window's full extent, as fractions of the fitted frame. For `linear`
  /// only the centre and [feather] matter: it keeps the left of a line
  /// through the centre and fades to the right over the feather — "left" in
  /// the window's own axes, so a tilt turns the line with it. For `mirror`
  /// the height is the band's thickness and the width plays no part: the band
  /// runs edge to edge.
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

  /// The window's tilt in degrees, **clockwise** — the way the fingers turn
  /// it and the way every rotation in the editor reads — in `(-180, 180]`.
  /// It turns about the window's centre, rigidly on the picture.
  ///
  /// Written to a draft and the wire only when not zero, so every mask that
  /// was never twisted reads and sends exactly what it always did.
  final double angle;

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
    double? angle,
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
      angle: angle ?? this.angle,
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
        if (angle != 0.0) 'angle': angle,
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
      // Absent in every mask never tilted.
      angle: raw['angle'] is num
          ? normaliseDegrees((raw['angle'] as num).toDouble())
          : 0.0,
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
      other.cornerRadius == cornerRadius &&
      other.angle == angle;

  @override
  int get hashCode =>
      Object.hash(shape, centerX, centerY, width, height, feather, inverted,
          cornerRadius, angle);

  @override
  String toString() => isNone
      ? 'ClipMask.none'
      : 'ClipMask(${shape.name} @ $centerX,$centerY ${width}x$height feather $feather${inverted ? ' inverted' : ''}${angle != 0.0 ? ' $angle°' : ''})';
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
///
/// [aspect] is the frame's width over its height in pixels. Only a tilt reads
/// it: turning the window rigidly on the picture means turning in a space
/// where a unit of x is a unit of y, so x is scaled up by the aspect, turned,
/// and scaled back — `rotateCanvas`' rule for a clip, applied to its window.
double maskCoverage(ClipMask mask, double x, double y, {double aspect = 1.0}) {
  if (mask.isNone) return 1.0;
  final feather = math.max(mask.feather, kMaskMinExtent);
  final halfW = math.max(mask.width * 0.5, kMaskMinExtent);
  final halfH = math.max(mask.height * 0.5, kMaskMinExtent);
  var dx = x - mask.centerX;
  var dy = y - mask.centerY;
  if (mask.angle != 0.0) {
    // Into the window's own axes: undo its clockwise turn. y runs down, so the
    // inverse of a clockwise turn is (c, s; -s, c).
    final t = mask.angle * math.pi / 180.0;
    final c = math.cos(t);
    final s = math.sin(t);
    final a = aspect > 0 ? aspect : 1.0;
    final px = dx * a;
    final py = dy;
    dx = (c * px + s * py) / a;
    dy = -s * px + c * py;
  }
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
      coverage = 1.0 - _smoothstep(-feather, feather, dx);
    case ClipMaskShape.mirror:
      // A band: within half its height of the centre line, edge to edge.
      coverage = 1.0 - _smoothstep(0.0, feather, dy.abs() - halfH);
  }
  return mask.inverted ? 1.0 - coverage : coverage;
}

/// The three `vec4`s the shader reads per lane: `(shape, centerX, centerY,
/// feather)`, `(width, height, inverted, radius)` and `(cos, sin, 0, 0)` of
/// the tilt. Kotlin's `NativeTimelineClip.parseMask` encodes the same order
/// from the wire, and a test on each side pins it.
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
      // The tilt as the cosine and sine the shader turns by, worked out once
      // here rather than once per pixel.
      math.cos(mask.angle * math.pi / 180.0),
      math.sin(mask.angle * math.pi / 180.0),
      0.0,
      0.0,
    ];

/// How far two fingers must turn before a gesture reads as a twist and the
/// canvas shows the angle. A pinch's fingers wobble a degree or so; that alone
/// does not bring the readout up.
const double kMaskTwistRadians = 2 * math.pi / 180;

/// How close to a right angle a twist must come to land on it — the text
/// frame's snap, so straightening a mask feels the same as straightening text.
const double kMaskAngleSnapDegrees = 3.0;

/// [degrees] folded into `(-180, 180]`, landing exactly on a right angle when
/// within [kMaskAngleSnapDegrees] of one. A window leaned by an unsteady hand
/// should still be able to stand straight.
double snapMaskAngle(double degrees) {
  final d = normaliseDegrees(degrees);
  final nearest = (d / 90.0).round() * 90.0;
  if ((d - nearest).abs() > kMaskAngleSnapDegrees) return d;
  // `+ 0.0` turns a -0.0 into 0.0, which a draft then omits like any zero.
  return normaliseDegrees(nearest) + 0.0;
}

/// The window after one frame of the canvas gesture, from the window the
/// gesture began on: [pan] in frame fractions, [scale] the pinch, and
/// [rotationRadians] the twist, clockwise, all accumulated since the fingers
/// landed — anchor-based like every drag here, never a running sum.
///
/// The centre stays on the picture and the size inside what the tool makes.
/// A gesture with no twist leaves the angle exactly as it was: snapping it
/// would straighten a window the user only moved.
ClipMask maskAfterGesture(
  ClipMask start, {
  Offset pan = Offset.zero,
  double scale = 1.0,
  double rotationRadians = 0.0,
}) {
  return start.copyWith(
    centerX: (start.centerX + pan.dx).clamp(0.0, 1.0).toDouble(),
    centerY: (start.centerY + pan.dy).clamp(0.0, 1.0).toDouble(),
    width: (start.width * scale).clamp(kMaskMinExtent, 2.0).toDouble(),
    height: (start.height * scale).clamp(kMaskMinExtent, 2.0).toDouble(),
    angle: rotationRadians == 0.0
        ? start.angle
        : snapMaskAngle(start.angle + rotationRadians * 180.0 / math.pi),
  );
}

/// What the canvas shows while a window is being twisted: whole degrees, as
/// CapCut shows its mask's angle.
String maskAngleLabel(double degrees) => '${degrees.round()}°';

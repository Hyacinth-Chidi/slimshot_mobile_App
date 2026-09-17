import 'dart:math' as math;

/// One point of a [SpeedCurve]: the clip plays at [speed] when it is at
/// source fraction [x] of its own range.
class SpeedPoint {
  const SpeedPoint(this.x, this.speed);

  /// 0..1 across the clip's **source** range, in play order.
  final double x;

  /// Playback rate at that point of the footage. 1 is natural speed.
  final double speed;

  @override
  bool operator ==(Object other) =>
      other is SpeedPoint && other.x == x && other.speed == speed;

  @override
  int get hashCode => Object.hash(x, speed);

  @override
  String toString() => 'SpeedPoint($x, ${speed}x)';
}

/// Speed as a function of *where in the footage* the clip is.
///
/// A scalar speed cannot ramp. Nor can a keyframed one: every other clip
/// property is read *at* a progress, while speed decides what progress means —
/// `duration` divides by it and `clipProgressAt` divides by `duration`, so a
/// keyframed speed makes progress a function of itself. A ramp needs source
/// time to be the **integral** of a speed curve, which is this model.
///
/// The curve is parametrised over the **source**, CapCut-style, so a point
/// placed on a moment of the footage stays on that moment however the curve
/// around it is shaped. Speed interpolates linearly between points, which
/// keeps both directions closed-form over each segment:
///
/// - reaching source fraction `x` takes `∫₀ˣ dx' / v(x')` of timeline — a
///   logarithm where the speed ramps, a division where it is flat
///   ([timeToSource]); the whole clip's timeline length is the source span
///   times [durationFactor];
/// - which source frame is due at a timeline instant is that integral's
///   inverse — an exponential ([sourceAtTime]).
///
/// Playback, the filmstrip, the scrub and export all resolve source position
/// through the second, and a Kotlin port carries the same arithmetic for the
/// engine; `test/fixtures/speed_curve_fixture.json` pins the two together.
class SpeedCurve {
  const SpeedCurve._(this.points, this.presetId);

  /// A curve through [raw], cleaned: non-finite points dropped, `x` clamped
  /// to 0..1 and speeds to the range, sorted, and held flat out to both ends
  /// if the list does not reach them. Fewer than two usable points is the
  /// flat 1× curve, never a throw.
  factory SpeedCurve(Iterable<SpeedPoint> raw, {String? presetId}) {
    final pts = _sanitize(raw) ?? _flat;
    return SpeedCurve._(pts, presetId);
  }

  /// The scalar speed it replaces, as a curve.
  factory SpeedCurve.constant(double speed) =>
      SpeedCurve([SpeedPoint(0, speed), SpeedPoint(1, speed)]);

  static const double kMinSpeed = 0.1;
  static const double kMaxSpeed = 10.0;

  /// Below this a segment's speed change is treated as none. Practically only
  /// two equal speeds reach it, and the division that replaces the logarithm
  /// there is exact rather than a `log(1 + ε) / ε` losing digits.
  static const double _kFlatSpeedDelta = 1e-9;

  static const List<SpeedPoint> _flat = [SpeedPoint(0, 1), SpeedPoint(1, 1)];

  /// Sorted by [SpeedPoint.x], first at 0, last at 1, at least two.
  final List<SpeedPoint> points;

  /// The preset this curve is, or null once a point has been touched.
  final String? presetId;

  static List<SpeedPoint>? _sanitize(Iterable<SpeedPoint> raw) {
    final pts = <SpeedPoint>[
      for (final p in raw)
        if (p.x.isFinite && p.speed.isFinite)
          SpeedPoint(
            p.x.clamp(0.0, 1.0).toDouble(),
            p.speed.clamp(kMinSpeed, kMaxSpeed).toDouble(),
          ),
    ];
    if (pts.length < 2) return null;
    pts.sort((a, b) => a.x.compareTo(b.x));
    if (pts.first.x > 0) pts.insert(0, SpeedPoint(0, pts.first.speed));
    if (pts.last.x < 1) pts.add(SpeedPoint(1, pts.last.speed));
    return List.unmodifiable(pts);
  }

  /// Playback rate at source fraction [x].
  double speedAtSource(double x) {
    final xc = x.clamp(0.0, 1.0).toDouble();
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      if (xc <= b.x) {
        final w = b.x - a.x;
        if (w <= 0) return b.speed;
        return a.speed + (b.speed - a.speed) * ((xc - a.x) / w);
      }
    }
    return points.last.speed;
  }

  /// Timeline needed to travel [dx] into the segment from [a] to [b] of
  /// source width [w]: `∫ dx / (a.speed + slope·x)`.
  static double _segmentTime(SpeedPoint a, SpeedPoint b, double w, double dx) {
    if ((b.speed - a.speed).abs() < _kFlatSpeedDelta) return dx / a.speed;
    final slope = (b.speed - a.speed) / w;
    return math.log((a.speed + slope * dx) / a.speed) / slope;
  }

  /// Source travelled in [t] of timeline from [a] toward [b]: the inverse of
  /// [_segmentTime].
  static double _segmentSource(SpeedPoint a, SpeedPoint b, double w, double t) {
    if ((b.speed - a.speed).abs() < _kFlatSpeedDelta) return t * a.speed;
    final slope = (b.speed - a.speed) / w;
    return a.speed * (math.exp(slope * t) - 1) / slope;
  }

  /// Timeline elapsed, **per second of source span**, when the clip reaches
  /// source fraction [x]. Multiply by the clip's source length for seconds.
  double timeToSource(double x) {
    final xc = x.clamp(0.0, 1.0).toDouble();
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      if (xc <= a.x) break;
      final w = b.x - a.x;
      if (w <= 0) continue;
      total += _segmentTime(a, b, w, math.min(xc, b.x) - a.x);
      if (xc <= b.x) break;
    }
    return total;
  }

  /// The clip's timeline length as a multiple of its source length. 1 for a
  /// flat 1× curve, 0.5 for a flat 2×.
  double get durationFactor => timeToSource(1.0);

  /// Source fraction reached after [u] of timeline per second of source span
  /// — the inverse of [timeToSource]. Clamped to the clip at both ends.
  double sourceAtTime(double u) {
    if (u <= 0) return 0.0;
    var remaining = u;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1];
      final b = points[i];
      final w = b.x - a.x;
      if (w <= 0) continue;
      final segTime = _segmentTime(a, b, w, w);
      if (remaining <= segTime) {
        return (a.x + _segmentSource(a, b, w, remaining))
            .clamp(a.x, b.x)
            .toDouble();
      }
      remaining -= segTime;
    }
    return 1.0;
  }

  /// This curve with point [index] at [speed], clamped. No longer a preset.
  SpeedCurve withPointSpeed(int index, double speed) {
    if (index < 0 || index >= points.length) return this;
    final pts = [...points];
    pts[index] = SpeedPoint(pts[index].x, speed.clamp(kMinSpeed, kMaxSpeed).toDouble());
    return SpeedCurve(pts);
  }

  /// A point added **on** the curve at [x], so adding one changes nothing
  /// about the picture. No longer a preset.
  SpeedCurve addPoint(double x) {
    final xc = x.clamp(0.0, 1.0).toDouble();
    return SpeedCurve([...points, SpeedPoint(xc, speedAtSource(xc))]);
  }

  /// Without point [index]. The endpoints stay: a curve must span its clip.
  SpeedCurve removePoint(int index) {
    if (index <= 0 || index >= points.length - 1) return this;
    return SpeedCurve([...points]..removeAt(index));
  }

  /// The curve cut at source fraction [x], each half rescaled to its own
  /// 0..1 and both reading this curve's speed at the seam — so a split clip
  /// keeps its whole length and plays through the cut unchanged.
  ({SpeedCurve left, SpeedCurve right}) splitAt(double x) {
    final xc = x.clamp(1e-6, 1 - 1e-6).toDouble();
    final seam = speedAtSource(xc);
    final left = SpeedCurve([
      for (final p in points)
        if (p.x < xc) SpeedPoint(p.x / xc, p.speed),
      SpeedPoint(1, seam),
    ]);
    final right = SpeedCurve([
      SpeedPoint(0, seam),
      for (final p in points)
        if (p.x > xc) SpeedPoint((p.x - xc) / (1 - xc), p.speed),
    ]);
    return (left: left, right: right);
  }

  Map<String, dynamic> toJson() => {
        'points': [
          for (final p in points) {'x': p.x, 'speed': p.speed},
        ],
        if (presetId != null) 'preset': presetId,
      };

  /// A curve from its JSON, or null for anything that is not one — absent,
  /// junk, fewer than two points. A malformed curve costs the clip its ramp,
  /// never the project.
  static SpeedCurve? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final list = raw['points'];
    if (list is! List) return null;
    final pts = <SpeedPoint>[];
    for (final e in list) {
      if (e is! Map) continue;
      final x = e['x'];
      final v = e['speed'];
      if (x is! num || v is! num) continue;
      pts.add(SpeedPoint(x.toDouble(), v.toDouble()));
    }
    final clean = _sanitize(pts);
    if (clean == null) return null;
    final preset = raw['preset'];
    return SpeedCurve._(clean, preset is String ? preset : null);
  }

  @override
  bool operator ==(Object other) =>
      other is SpeedCurve &&
      other.presetId == presetId &&
      _samePoints(other.points, points);

  static bool _samePoints(List<SpeedPoint> a, List<SpeedPoint> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(presetId, Object.hashAll(points));

  @override
  String toString() => 'SpeedCurve(${presetId ?? 'custom'}, $points)';
}

/// A named curve the sheet offers.
class SpeedCurvePreset {
  const SpeedCurvePreset({required this.id, required this.label, required this.curve});
  final String id;
  final String label;
  final SpeedCurve curve;
}

/// The sheet's presets, in display order. **Custom** is flat 1× so choosing it
/// changes nothing until a point is dragged; it exists to give the editor
/// five handles to start from.
const List<SpeedCurvePreset> kSpeedCurvePresets = [
  SpeedCurvePreset(
    id: 'montage',
    label: 'Montage',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 1),
        SpeedPoint(0.25, 0.5),
        SpeedPoint(0.5, 2),
        SpeedPoint(0.75, 0.5),
        SpeedPoint(1, 1),
      ],
      'montage',
    ),
  ),
  SpeedCurvePreset(
    id: 'hero',
    label: 'Hero',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 2),
        SpeedPoint(0.35, 2),
        SpeedPoint(0.5, 0.4),
        SpeedPoint(0.65, 2),
        SpeedPoint(1, 2),
      ],
      'hero',
    ),
  ),
  SpeedCurvePreset(
    id: 'bullet',
    label: 'Bullet',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 1),
        SpeedPoint(0.3, 3),
        SpeedPoint(0.5, 0.3),
        SpeedPoint(0.7, 3),
        SpeedPoint(1, 1),
      ],
      'bullet',
    ),
  ),
  SpeedCurvePreset(
    id: 'jump_cut',
    label: 'Jump cut',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 1),
        SpeedPoint(0.3, 1),
        SpeedPoint(0.35, 4),
        SpeedPoint(0.65, 4),
        SpeedPoint(0.7, 1),
        SpeedPoint(1, 1),
      ],
      'jump_cut',
    ),
  ),
  SpeedCurvePreset(
    id: 'flash_in',
    label: 'Flash in',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 4),
        SpeedPoint(0.3, 4),
        SpeedPoint(0.5, 1),
        SpeedPoint(1, 1),
      ],
      'flash_in',
    ),
  ),
  SpeedCurvePreset(
    id: 'flash_out',
    label: 'Flash out',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 1),
        SpeedPoint(0.5, 1),
        SpeedPoint(0.7, 4),
        SpeedPoint(1, 4),
      ],
      'flash_out',
    ),
  ),
  SpeedCurvePreset(
    id: 'custom',
    label: 'Custom',
    curve: SpeedCurve._(
      [
        SpeedPoint(0, 1),
        SpeedPoint(0.25, 1),
        SpeedPoint(0.5, 1),
        SpeedPoint(0.75, 1),
        SpeedPoint(1, 1),
      ],
      'custom',
    ),
  ),
];

SpeedCurvePreset? speedCurvePresetById(String? id) {
  if (id == null) return null;
  for (final p in kSpeedCurvePresets) {
    if (p.id == id) return p;
  }
  return null;
}

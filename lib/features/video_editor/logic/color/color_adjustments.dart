/// Adjust — brightness, contrast, saturation and temperature — as one 4×5
/// colour matrix, so it rides the grade pipeline that already exists.
///
/// The matrix is in Flutter's `ColorFilter.matrix` layout: **row-major 4×5,
/// offsets on the 0–255 scale**, the same shape a `FilterPreset` is. A clip's
/// adjustments compose into its own `colorMatrix` after its filter and travel
/// as the one matrix the clip already sends; the project's compose into the
/// canvas look. Nothing in Kotlin changed for this: `gradeClip` and
/// `outputColor` already apply a 4×5 matrix at each level.
///
/// Unlike filters, the two levels **may coexist**. A filter applied twice is a
/// mistake (which is why `filterAppliesToAll` keeps those mutually exclusive);
/// an adjustment applied at both levels is the user's intent — a warm project
/// with one clip pulled cooler.
library;

/// The four adjustable parameters, each in -1..1 with 0 as untouched.
enum AdjustParameter { brightness, contrast, saturation, temperature }

/// Offset, in 0–255 units, that brightness +1 adds to every colour channel.
const double kBrightnessRange = 100.0;

/// Fraction by which temperature +1 lifts red and lowers blue.
const double kTemperatureRange = 0.2;

/// Rec. 709 luma weights, which is what a desaturated colour collapses to.
const double _kLumaR = 0.2126;
const double _kLumaG = 0.7152;
const double _kLumaB = 0.0722;

/// Contrast pivots about mid grey, so mid grey never moves.
const double _kMidGrey = 127.5;

/// The identity matrix in the 4×5 layout. Defined here rather than borrowed so
/// this file depends on nothing but arithmetic.
const List<double> kIdentityColorMatrix = [
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// A set of colour adjustments. Immutable; equal when every parameter is.
class ColorAdjustments {
  const ColorAdjustments({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.temperature = 0.0,
  });

  /// Nothing adjusted — the identity, and what every clip and project starts
  /// as.
  static const ColorAdjustments none = ColorAdjustments();

  final double brightness;
  final double contrast;
  final double saturation;
  final double temperature;

  bool get isIdentity =>
      brightness == 0.0 && contrast == 0.0 && saturation == 0.0 && temperature == 0.0;

  double valueOf(AdjustParameter p) => switch (p) {
        AdjustParameter.brightness => brightness,
        AdjustParameter.contrast => contrast,
        AdjustParameter.saturation => saturation,
        AdjustParameter.temperature => temperature,
      };

  ColorAdjustments withValue(AdjustParameter p, double value) {
    final v = value.clamp(-1.0, 1.0).toDouble();
    return switch (p) {
      AdjustParameter.brightness => copyWith(brightness: v),
      AdjustParameter.contrast => copyWith(contrast: v),
      AdjustParameter.saturation => copyWith(saturation: v),
      AdjustParameter.temperature => copyWith(temperature: v),
    };
  }

  ColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
  }) {
    return ColorAdjustments(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
    );
  }

  /// The combined matrix. **Applied to a pixel in this order:** contrast,
  /// saturation, temperature, brightness — so brightness is an offset on the
  /// finished colour rather than something contrast then stretches. The order
  /// is a convention, not a law; what matters is that it is one order, here.
  List<double> get matrix {
    if (isIdentity) return kIdentityColorMatrix;
    var m = _contrastMatrix(contrast);
    m = composeColorMatrices(_saturationMatrix(saturation), m);
    m = composeColorMatrices(_temperatureMatrix(temperature), m);
    m = composeColorMatrices(_brightnessMatrix(brightness), m);
    return m;
  }

  Map<String, dynamic> toJson() => {
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'temperature': temperature,
      };

  /// Defensive: a missing or malformed field is untouched, a value past the
  /// slider's range is clamped to it. Anything that is not a map is [none].
  static ColorAdjustments fromJson(Object? raw) {
    if (raw is! Map) return none;
    double read(String key) {
      final v = raw[key];
      if (v is! num) return 0.0;
      return v.toDouble().clamp(-1.0, 1.0).toDouble();
    }

    return ColorAdjustments(
      brightness: read('brightness'),
      contrast: read('contrast'),
      saturation: read('saturation'),
      temperature: read('temperature'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ColorAdjustments &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.temperature == temperature;

  @override
  int get hashCode => Object.hash(brightness, contrast, saturation, temperature);

  @override
  String toString() =>
      'ColorAdjustments(b: $brightness, c: $contrast, s: $saturation, t: $temperature)';
}

List<double> _brightnessMatrix(double b) {
  final offset = b * kBrightnessRange;
  return [
    1, 0, 0, 0, offset,
    0, 1, 0, 0, offset,
    0, 0, 1, 0, offset,
    0, 0, 0, 1, 0,
  ];
}

List<double> _contrastMatrix(double c) {
  // -1 → 0 (flat mid grey), 0 → 1, +1 → 2.
  final s = (1.0 + c).clamp(0.0, 2.0).toDouble();
  final offset = _kMidGrey * (1.0 - s);
  return [
    s, 0, 0, 0, offset,
    0, s, 0, 0, offset,
    0, 0, s, 0, offset,
    0, 0, 0, 1, 0,
  ];
}

List<double> _saturationMatrix(double sat) {
  // -1 → luma grey, 0 → unchanged, +1 → twice the distance from grey.
  final s = (1.0 + sat).clamp(0.0, 2.0).toDouble();
  final inv = 1.0 - s;
  return [
    _kLumaR * inv + s, _kLumaG * inv, _kLumaB * inv, 0, 0,
    _kLumaR * inv, _kLumaG * inv + s, _kLumaB * inv, 0, 0,
    _kLumaR * inv, _kLumaG * inv, _kLumaB * inv + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> _temperatureMatrix(double t) {
  final r = 1.0 + kTemperatureRange * t;
  final b = 1.0 - kTemperatureRange * t;
  return [
    r, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, b, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// `outer ∘ inner`: the matrix that applies [inner] to a pixel first, then
/// [outer]. For the 4×5 affine layout that is `A·B` for the linear part and
/// `A·b + a` for the offsets.
List<double> composeColorMatrices(List<double> outer, List<double> inner) {
  assert(outer.length == 20 && inner.length == 20);
  final out = List<double>.filled(20, 0.0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 4; col++) {
      var sum = 0.0;
      for (var k = 0; k < 4; k++) {
        sum += outer[row * 5 + k] * inner[k * 5 + col];
      }
      out[row * 5 + col] = sum;
    }
    var offset = outer[row * 5 + 4];
    for (var k = 0; k < 4; k++) {
      offset += outer[row * 5 + k] * inner[k * 5 + 4];
    }
    out[row * 5 + 4] = offset;
  }
  return out;
}

/// Applies a 4×5 matrix to an `[r, g, b, a]` on the 0–255 scale, unclamped —
/// the GPU clamps; tests want to see the raw arithmetic.
List<double> applyColorMatrix(List<double> m, List<double> rgba) {
  assert(m.length == 20 && rgba.length == 4);
  return List<double>.generate(4, (row) {
    var v = m[row * 5 + 4];
    for (var k = 0; k < 4; k++) {
      v += m[row * 5 + k] * rgba[k];
    }
    return v;
  });
}

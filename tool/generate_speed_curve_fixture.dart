/// Generates the shared fixture that pins `SpeedCurve` and its Kotlin port
/// together.
///
/// A curved clip's source position is resolved in Dart for the filmstrip and
/// the scrub, and in `SpeedCurve.kt` for playback and export, so the integral
/// and its inverse exist twice. Nothing in either type system makes the two
/// agree — a mistranslated logarithm is a file whose clip lands on different
/// frames than the canvas showed, with nothing on screen explaining it. This
/// table of sampled values is what turns that into a test failure.
///
/// Run after any deliberate change to `speed_curve.dart`:
///
/// ```
/// dart run tool/generate_speed_curve_fixture.dart
/// ```
///
/// and then re-run **both** sides:
///
/// ```
/// flutter test test/features/video_editor/logic/speed/speed_curve_fixture_test.dart
/// .\android\gradlew.bat -p android :app:testDebugUnitTest --tests "*SpeedCurveTest*"
/// ```
///
/// Same mechanism, same shape and same caveat as the animation fixtures: the
/// Dart pin passes by construction, so only the Kotlin run says whether the
/// port followed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';

const List<String> _outputPaths = [
  'test/fixtures/speed_curve_fixture.json',
  'android/app/src/test/resources/speed_curve_fixture.json',
];

/// Source fractions sampled for speed and elapsed time. Dense enough to land
/// inside every preset's segments, including the short 5% ramps of `jump_cut`.
const List<double> _xSamples = [0.0, 0.05, 0.1, 0.25, 0.33, 0.5, 0.66, 0.75, 0.9, 1.0];

/// Fractions of the whole duration sampled for the inverse.
const List<double> _uFractions = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];

/// Raw point lists that exercise the parser's cleaning, not just the presets:
/// an unsorted list that does not reach the ends, and a step made of two
/// points sharing an `x`.
final Map<String, List<Map<String, double>>> _rawCases = {
  'thin_unsorted': [
    {'x': 0.8, 'speed': 2.0},
    {'x': 0.2, 'speed': 1.0},
  ],
  'step': [
    {'x': 0.0, 'speed': 1.0},
    {'x': 0.5, 'speed': 1.0},
    {'x': 0.5, 'speed': 3.0},
    {'x': 1.0, 'speed': 3.0},
  ],
  'ramp': [
    {'x': 0.0, 'speed': 1.0},
    {'x': 1.0, 'speed': 3.0},
  ],
};

void main() {
  final curves = <Map<String, dynamic>>[];

  void add(String id, List<Map<String, double>> rawPoints) {
    final curve = SpeedCurve.fromJson({'points': rawPoints})!;
    final factor = curve.durationFactor;
    curves.add({
      'id': id,
      'points': rawPoints,
      'durationFactor': factor,
      'samples': [
        for (final x in _xSamples)
          {
            'x': x,
            'speed': curve.speedAtSource(x),
            'time': curve.timeToSource(x),
          },
      ],
      'inverse': [
        for (final f in _uFractions)
          {'u': f * factor, 'x': curve.sourceAtTime(f * factor)},
      ],
    });
  }

  for (final p in kSpeedCurvePresets) {
    add(p.id, [
      for (final pt in p.curve.points) {'x': pt.x, 'speed': pt.speed},
    ]);
  }
  _rawCases.forEach(add);

  final json = const JsonEncoder.withIndent('  ').convert({
    'generatedBy': 'tool/generate_speed_curve_fixture.dart',
    'curves': curves,
  });
  for (final path in _outputPaths) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync('$json\n');
    stdout.writeln('wrote $path');
  }
}

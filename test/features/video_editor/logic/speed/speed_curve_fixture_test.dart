import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';

/// The fixture is the contract the Kotlin port is held to. If the integral or
/// its inverse changes deliberately, regenerate it with
/// `dart run tool/generate_speed_curve_fixture.dart` **and** re-run the Kotlin
/// test, or preview and export will quietly land on different frames.
///
/// As with the animation fixtures: this file is generated from the code it
/// checks, so on its own it pins **future drift**, not correctness today. The
/// shape of the arithmetic is pinned by `speed_curve_test.dart` against a
/// numeric integral; the comparison that can fail for a real reason is
/// `SpeedCurveTest.kt` reading the same numbers.
const String _fixturePath = 'test/fixtures/speed_curve_fixture.json';
const String _androidFixturePath =
    'android/app/src/test/resources/speed_curve_fixture.json';

Map<String, dynamic> _load() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

void main() {
  test('the Android copy is byte-identical to the repo-root fixture', () {
    expect(
      File(_androidFixturePath).readAsStringSync(),
      File(_fixturePath).readAsStringSync(),
      reason: 'regenerate: dart run tool/generate_speed_curve_fixture.dart',
    );
  });

  test('every curve still matches the committed fixture', () {
    final rows = (_load()['curves'] as List).cast<Map<String, dynamic>>();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      final id = row['id'] as String;
      final curve = SpeedCurve.fromJson({'points': row['points']})!;
      expect(curve.durationFactor,
          closeTo((row['durationFactor'] as num).toDouble(), 1e-9),
          reason: '$id durationFactor');
      for (final s in (row['samples'] as List).cast<Map<String, dynamic>>()) {
        final x = (s['x'] as num).toDouble();
        expect(curve.speedAtSource(x),
            closeTo((s['speed'] as num).toDouble(), 1e-9),
            reason: '$id speed @ $x');
        expect(curve.timeToSource(x),
            closeTo((s['time'] as num).toDouble(), 1e-9),
            reason: '$id time @ $x');
      }
      for (final s in (row['inverse'] as List).cast<Map<String, dynamic>>()) {
        final u = (s['u'] as num).toDouble();
        expect(curve.sourceAtTime(u), closeTo((s['x'] as num).toDouble(), 1e-9),
            reason: '$id inverse @ $u');
      }
    }
  });

  test('the fixture covers every preset this build knows', () {
    final ids = {
      for (final row in (_load()['curves'] as List).cast<Map<String, dynamic>>())
        row['id'] as String,
    };
    for (final p in kSpeedCurvePresets) {
      expect(ids, contains(p.id));
    }
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';

/// The fixture is the contract the Kotlin port is held to. If an envelope or the
/// evaluator changes deliberately, regenerate it with
/// `dart run tool/generate_envelope_fixture.dart` **and** re-run the Kotlin
/// test, or preview and export will quietly disagree.
///
/// Be honest about what this file proves: the fixture is generated from the same
/// code it checks, so on its own it only pins **future drift** — it cannot tell
/// you the envelopes are right today. The value is on the other side:
/// `AnimatableDoubleTest` asserts an independently written Kotlin translation
/// against the same numbers, and that comparison is the one that can actually
/// fail for a real reason. The *shape* of the curves is pinned separately, by
/// the property assertions in `animatable_double_test.dart`.
const String _fixturePath = 'test/fixtures/animatable_fixture.json';

/// The Android copy. Gradle unit tests cannot read the repo-root fixture, so the
/// generator writes two files — and two files can fall out of step, which would
/// leave the Kotlin test passing against a stale table while the Dart test
/// passed against a fresh one. Pinning them byte-for-byte here is the cheapest
/// way to make a half-finished regeneration fail loudly.
const String _androidFixturePath =
    'android/app/src/test/resources/animatable_fixture.json';

Map<String, dynamic> _loadFixture() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

/// Progress travels as a number, except NaN, which JSON cannot spell — the
/// generator writes the string `"nan"` for it. Reading it back rather than
/// skipping the row is what keeps the `_clamp01` NaN arm — which exists because
/// a caller dividing seconds by a zero-length clip hands one over — under test
/// on both sides.
double _progress(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw == 'nan') return double.nan;
  throw ArgumentError('unreadable progress $raw');
}

String _show(double p) => p.isNaN ? 'nan' : '$p';

void main() {
  test('the Android copy of the fixture is identical', () {
    expect(
      File(_androidFixturePath).readAsStringSync(),
      File(_fixturePath).readAsStringSync(),
      reason: 'the two fixture copies have diverged — re-run '
          '`dart run tool/generate_envelope_fixture.dart`',
    );
  });

  test('every envelope still matches the committed fixture', () {
    final rows = _loadFixture()['envelopes'] as List;
    expect(rows, isNotEmpty);

    for (final entry in rows.cast<Map<String, dynamic>>()) {
      final name = entry['envelope'] as String;
      final p = (entry['p'] as num).toDouble();
      expect(
        resolveEnvelope(name, p),
        closeTo((entry['value'] as num).toDouble(), 1e-5),
        reason: "envelope '$name' at p=$p",
      );
    }
  });

  test('the fixture covers every envelope in the catalog', () {
    // The generator walks `kEnvelopeNames`, so this cannot fail against a
    // freshly generated fixture — it fails against a *stale* one, which is
    // exactly the case where a new envelope has been added, never sampled, and
    // therefore never held to its Kotlin port.
    final rows = (_loadFixture()['envelopes'] as List)
        .cast<Map<String, dynamic>>();
    final sampled = rows.map((e) => e['envelope'] as String).toSet();
    expect(
      sampled,
      containsAll(kEnvelopeNames),
      reason: 'an envelope has no fixture rows — re-run '
          '`dart run tool/generate_envelope_fixture.dart`',
    );
  });

  test('unknown envelope names still rest at the base value', () {
    final rows = _loadFixture()['unknownEnvelopes'] as List;
    expect(rows, isNotEmpty);

    for (final entry in rows.cast<Map<String, dynamic>>()) {
      final name = entry['envelope'] as String;
      final p = (entry['p'] as num).toDouble();
      final actual = resolveEnvelope(name, p);
      expect(
        actual,
        closeTo((entry['value'] as num).toDouble(), 1e-5),
        reason: "unknown envelope '$name' at p=$p",
      );
      expect(actual, 1.0, reason: "unknown envelope '$name' at p=$p");
    }
  });

  test('out-of-range progress is still clamped the same way', () {
    final rows = _loadFixture()['clampedEnvelopes'] as List;
    expect(rows, isNotEmpty);

    for (final entry in rows.cast<Map<String, dynamic>>()) {
      final name = entry['envelope'] as String;
      final p = _progress(entry['p']);
      expect(
        resolveEnvelope(name, p),
        closeTo((entry['value'] as num).toDouble(), 1e-5),
        reason: "envelope '$name' at clamped p=${_show(p)}",
      );
    }
  });

  test('every keyframe case still matches the committed fixture', () {
    final cases = _loadFixture()['keyframeCases'] as List;
    expect(cases, isNotEmpty);

    for (final entry in cases.cast<Map<String, dynamic>>()) {
      final name = entry['name'] as String;
      // Rebuilt from the fixture's own record of the parameter, exactly as the
      // Kotlin test rebuilds it — so if the two sides read the recorded shape
      // differently, that shows up here rather than as a mysterious value
      // mismatch. Not sorted: the fixture records the order the parameter
      // actually holds, and `resolveAt` must be independent of it.
      final parameter = AnimatableDouble(
        baseValue: (entry['baseValue'] as num).toDouble(),
        envelope: entry['envelope'] as String?,
        keyframes: [
          for (final k in (entry['keyframes'] as List).cast<Map<String, dynamic>>())
            Keyframe(
              progress: (k['progress'] as num).toDouble(),
              value: (k['value'] as num).toDouble(),
              interpolation: KeyframeInterpolation.values.firstWhere(
                (v) => v.name == k['interpolation'],
              ),
            ),
        ],
      );

      expect(
        parameter.isAnimated,
        entry['isAnimated'] as bool,
        reason: "isAnimated for case '$name'",
      );

      for (final sample in (entry['samples'] as List).cast<Map<String, dynamic>>()) {
        final p = _progress(sample['p']);
        expect(
          parameter.resolveAt(p),
          closeTo((sample['value'] as num).toDouble(), 1e-5),
          reason: "keyframe case '$name' at p=${_show(p)}",
        );
      }
    }
  });
}

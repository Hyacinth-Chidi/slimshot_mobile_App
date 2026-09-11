import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';

/// The fixture is the contract the Kotlin port is held to. If a curve changes
/// deliberately, regenerate it with
/// `dart run tool/generate_animation_fixture.dart` **and** re-run the Kotlin
/// test, or preview and export will quietly disagree.
///
/// Be honest about what this file proves: the fixture is generated from the
/// same code it checks, so on its own it only pins **future drift** — it cannot
/// tell you the curves are right today. The value is on the other side:
/// `TextAnimationCurvesTest` asserts an independently written Kotlin
/// translation against the same numbers, and that comparison is the one that
/// can actually fail for a real reason.
const String _fixturePath = 'test/fixtures/text_animation_fixture.json';

/// The Android copy. Gradle unit tests cannot read the repo-root fixture, so
/// the generator writes two files — and two files can fall out of step, which
/// would leave the Kotlin test passing against a stale table while the Dart
/// test passed against a fresh one. Pinning them byte-for-byte here is the
/// cheapest way to make a half-finished regeneration fail loudly.
const String _androidFixturePath =
    'android/app/src/test/resources/text_animation_fixture.json';

Map<String, dynamic> _loadFixture() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

TextAnimationCategory _slot(String name) => switch (name) {
      'in' => TextAnimationCategory.inAnim,
      'out' => TextAnimationCategory.outAnim,
      'loop' => TextAnimationCategory.loop,
      _ => throw ArgumentError('unknown slot $name'),
    };

void main() {
  test('the Android copy of the fixture is identical', () {
    expect(
      File(_androidFixturePath).readAsStringSync(),
      File(_fixturePath).readAsStringSync(),
      reason: 'the two fixture copies have diverged — re-run '
          '`dart run tool/generate_animation_fixture.dart`',
    );
  });

  test('the catalog still matches the committed fixture', () {
    final samples = _loadFixture()['samples'] as List;
    expect(samples, isNotEmpty);

    for (final entry in samples.cast<Map<String, dynamic>>()) {
      final id = entry['id'] as String;
      final anim = textAnimationById(id);
      expect(anim, isNotNull, reason: 'fixture names unknown id $id');
      final s = anim!.stateAt(
        (entry['p'] as num).toDouble(),
        entry['i'] as int,
        entry['n'] as int,
      );
      final where = '$id p=${entry['p']} i=${entry['i']} n=${entry['n']}';
      void check(String field, double actual) {
        expect(
          actual,
          closeTo((entry[field] as num).toDouble(), 1e-5),
          reason: '$where $field',
        );
      }

      check('opacity', s.opacity);
      check('offsetX', s.offsetX);
      check('offsetY', s.offsetY);
      check('scale', s.scale);
      check('rotation', s.rotation);
      check('fillProgress', s.fillProgress);
    }
  });

  test('natural durations still match the committed fixture', () {
    final durations = _loadFixture()['durations'] as List;
    expect(durations, isNotEmpty);

    for (final entry in durations.cast<Map<String, dynamic>>()) {
      final id = entry['id'] as String;
      final anim = textAnimationById(id);
      expect(anim, isNotNull, reason: 'fixture names unknown id $id');
      final count = entry['glyphCount'] as int;
      expect(
        anim!.naturalDuration(count),
        closeTo((entry['seconds'] as num).toDouble(), 1e-5),
        reason: '$id glyphCount=$count',
      );
    }
  });

  test('slot resolution still matches the committed fixture', () {
    final resolution = _loadFixture()['resolution'] as List;
    expect(resolution, isNotEmpty);

    for (final entry in resolution.cast<Map<String, dynamic>>()) {
      final id = entry['id'] as String;
      final slotName = entry['slot'] as String;
      expect(
        resolveTextAnimation(id, _slot(slotName))?.id,
        entry['resolved'] as String?,
        reason: "resolveTextAnimation('$id', $slotName)",
      );
    }
  });

  test('resolved durations still match the committed fixture', () {
    final rows = _loadFixture()['durationResolution'] as List;
    expect(rows, isNotEmpty);

    for (final entry in rows.cast<Map<String, dynamic>>()) {
      final inId = entry['inId'] as String?;
      final outId = entry['outId'] as String?;
      final r = resolveTextAnimationDurations(
        spanSeconds: (entry['spanSeconds'] as num).toDouble(),
        inAnim: inId == null
            ? null
            : resolveTextAnimation(inId, TextAnimationCategory.inAnim),
        outAnim: outId == null
            ? null
            : resolveTextAnimation(outId, TextAnimationCategory.outAnim),
        glyphCount: entry['glyphCount'] as int,
        speed: (entry['speed'] as num).toDouble(),
      );
      final where = 'span=${entry['spanSeconds']} speed=${entry['speed']} '
          'glyphCount=${entry['glyphCount']} in=$inId out=$outId';
      expect(
        r.inSeconds,
        closeTo((entry['inSeconds'] as num).toDouble(), 1e-5),
        reason: '$where inSeconds',
      );
      expect(
        r.outSeconds,
        closeTo((entry['outSeconds'] as num).toDouble(), 1e-5),
        reason: '$where outSeconds',
      );
    }
  });
}

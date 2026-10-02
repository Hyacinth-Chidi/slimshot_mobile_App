import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight_catalog.dart';

/// The fixture is the contract the Kotlin port (`CaptionHighlightCurves.kt`)
/// is held to. It is generated from the code it checks, so on its own it pins
/// only future drift; the Kotlin test asserting an independent translation
/// against the same numbers is the comparison that can fail for a real reason.
///
/// After a deliberate change: `dart run tool/generate_caption_highlight_fixture.dart`,
/// then re-run the Kotlin test.
const String _fixturePath = 'test/fixtures/caption_highlight_fixture.json';
const String _androidFixturePath =
    'android/app/src/test/resources/caption_highlight_fixture.json';

void main() {
  test('the Android copy of the fixture is identical', () {
    expect(
      File(_androidFixturePath).readAsStringSync(),
      File(_fixturePath).readAsStringSync(),
      reason: 're-run `dart run tool/generate_caption_highlight_fixture.dart`',
    );
  });

  test('the catalog still matches the committed fixture', () {
    final fixture =
        jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;
    final sets = [
      for (final s in (fixture['sets'] as List).cast<Map<String, dynamic>>())
        (
          span: (s['span'] as num).toDouble(),
          words: [
            for (final w in (s['words'] as List).cast<Map<String, dynamic>>())
              WordSpan((w['start'] as num).toDouble(), (w['end'] as num).toDouble()),
          ],
        ),
    ];
    final samples = (fixture['samples'] as List).cast<Map<String, dynamic>>();
    expect(samples, isNotEmpty);

    for (final row in samples) {
      final style = CaptionHighlightStyle.values.byName(row['style'] as String);
      final set = sets[row['set'] as int];
      final t = (row['t'] as num).toDouble();
      final i = row['i'] as int;
      final s = wordHighlightStateAt(
        style: style,
        t: t,
        words: set.words,
        index: i,
        spanSeconds: set.span,
      );
      final where = '${style.name} set=${row['set']} t=$t i=$i';
      expect(s.highlighted, row['highlighted'], reason: '$where highlighted');
      for (final (name, value) in [
        ('fill', s.fill),
        ('scale', s.scale),
        ('opacity', s.opacity),
        ('pill', s.pill),
      ]) {
        expect(value, closeTo((row[name] as num).toDouble(), 1e-5),
            reason: '$where $name');
      }
    }
  });
}

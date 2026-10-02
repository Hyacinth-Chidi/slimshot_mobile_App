/// Generates the shared fixture that pins the caption highlight catalog and
/// its Kotlin port together.
///
/// Every highlight exists twice: in `caption_highlight_catalog.dart` for the
/// preview, and in `CaptionHighlightCurves.kt` for the export. This table of
/// sampled states turns a divergence between them into a test failure.
///
/// Run after any deliberate change to a highlight:
///
/// ```
/// dart run tool/generate_caption_highlight_fixture.dart
/// ```
///
/// and then re-run **both** sides:
///
/// ```
/// flutter test test/features/video_editor/logic/captions/caption_highlight_fixture_test.dart
/// .\android\gradlew.bat -p android :app:testDebugUnitTest --tests "*CaptionHighlightCurvesTest*"
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight_catalog.dart';

const List<String> _outputPaths = [
  'test/fixtures/caption_highlight_fixture.json',
  'android/app/src/test/resources/caption_highlight_fixture.json',
];

/// Word sets, each a caption's words and its span.
///
/// The second has a last word timed past the caption (the next caption's lead
/// took that room); the third a word of no length.
const List<({double span, List<WordSpan> words})> kHighlightFixtureSets = [
  (
    span: 1.5,
    words: [WordSpan(0.1, 0.4), WordSpan(0.5, 0.8), WordSpan(0.9, 1.2)],
  ),
  (span: 1.5, words: [WordSpan(0.1, 0.4), WordSpan(1.4, 2.0)]),
  (span: 1.0, words: [WordSpan(0.5, 0.5)]),
];

/// Instants, chosen to land before, on and inside every edge and ramp.
const List<double> kHighlightFixtureTimes = [
  0.0, 0.05, 0.1, 0.13, 0.14, 0.2, 0.225, 0.25, 0.3, 0.35, 0.4, 0.45, //
  0.5, 0.54, 0.6, 0.7, 0.9, 1.0, 1.2, 1.3, 1.4, 1.45, 1.49, 1.5, 2.0,
];

num _round(double v) {
  final r = double.parse(v.toStringAsFixed(6));
  return r == 0 ? 0.0 : r;
}

/// Every sampled state, as the fixture stores it.
List<Map<String, dynamic>> highlightFixtureSamples() => [
      for (var s = 0; s < kHighlightFixtureSets.length; s++)
        for (final style in CaptionHighlightStyle.values)
          for (final t in kHighlightFixtureTimes)
            for (var i = -1; i <= kHighlightFixtureSets[s].words.length; i++)
              _sample(style, s, t, i),
    ];

Map<String, dynamic> _sample(CaptionHighlightStyle style, int set, double t, int i) {
  final state = wordHighlightStateAt(
    style: style,
    t: t,
    words: kHighlightFixtureSets[set].words,
    index: i,
    spanSeconds: kHighlightFixtureSets[set].span,
  );
  return {
    'style': style.name,
    'set': set,
    't': t,
    'i': i,
    'highlighted': state.highlighted,
    'fill': _round(state.fill),
    'scale': _round(state.scale),
    'opacity': _round(state.opacity),
    'pill': _round(state.pill),
  };
}

void main() {
  final fixture = {
    'sets': [
      for (final set in kHighlightFixtureSets)
        {
          'span': set.span,
          'words': [
            for (final w in set.words) {'start': w.start, 'end': w.end},
          ],
        },
    ],
    'samples': highlightFixtureSamples(),
  };
  final json = '${const JsonEncoder.withIndent('  ').convert(fixture)}\n';
  for (final path in _outputPaths) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(json);
    stdout.writeln('wrote $path');
  }
}

/// Generates the shared curve fixture that pins the Dart catalog and its
/// Kotlin port together.
///
/// The export renders text natively, so every curve in
/// `text_animation_catalog.dart` exists twice: once in Dart for the preview and
/// once in `TextAnimationCurves.kt` for the encoder. Nothing in the type system
/// makes the two agree — a changed constant on one side is a file that animates
/// differently from the preview, with nothing on screen explaining it. This
/// table of sampled values is what turns that into a test failure.
///
/// Run after any deliberate curve change:
///
/// ```
/// dart run tool/generate_animation_fixture.dart
/// ```
///
/// and then re-run **both** sides:
///
/// ```
/// flutter test test/features/video_editor/logic/text_animation_fixture_test.dart
/// .\android\gradlew.bat -p android testDebugUnitTest --tests "*TextAnimationCurvesTest*"
/// ```
///
/// Regenerating without running the Kotlin test moves the goalposts silently:
/// the Dart pin passes by construction (it is generated from the code it
/// checks), so only the Kotlin run tells you whether the port followed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:slimshotai/features/video_editor/logic/text_animation_catalog.dart';

/// Where the fixture is written. Two copies, because Dart tests read from the
/// repo root and Gradle unit tests read from the Android module's test
/// resources; neither build system can reach across to the other's tree.
const List<String> _outputPaths = [
  'test/fixtures/text_animation_fixture.json',
  'android/app/src/test/resources/text_animation_fixture.json',
];

/// Progress samples.
///
/// The brief's five (0, .25, .5, .75, 1) plus the four eighths. The extra
/// points are nearly free and land inside curve segments the quarters step
/// straight over: `_easeOutBounce` is piecewise with breakpoints at
/// 1/2.75, 2/2.75 and 2.5/2.75, and `_colourCycleLoop`'s triangle turns at
/// its half. A port that fumbled one branch of either would pass on the
/// quarters alone.
const List<double> _progressSamples = [
  0.0,
  0.125,
  0.25,
  0.375,
  0.5,
  0.625,
  0.75,
  0.875,
  1.0,
];

/// Glyph positions, as `(i, n)`.
///
/// The brief's four plus `(1, 2)` and `(7, 8)`. `(0, 1)` is the
/// divide-by-zero guard in `_stagger`; `(1, 2)` is the smallest `n` where the
/// stagger arithmetic actually runs; `(0, 5)`, `(2, 5)`, `(4, 5)` walk a word
/// from first to last glyph; `(7, 8)` gives the hash a larger index and a
/// different `i / n` phase for the loops.
const List<List<int>> _glyphSamples = [
  [0, 1],
  [1, 2],
  [0, 5],
  [2, 5],
  [4, 5],
  [7, 8],
];

/// Glyph counts the duration table is sampled at.
const List<int> _durationGlyphCounts = [1, 2, 5, 40, 120];

/// Speeds the duration table is sampled at, including the guarded
/// non-positive values.
const List<double> _durationSpeeds = [0.0, -1.0, 0.5, 1.0, 2.0];

/// Spans the duration table is sampled at, including the ones that force the
/// proportional squeeze and the degenerate non-positive cases.
const List<double> _durationSpans = [0.0, -2.0, 0.3, 1.0, 5.0];

/// Six decimal places: far below the `1e-5` the tests compare at, but coarse
/// enough that the last bits of a `double` cannot make a regenerated fixture
/// churn in the diff for no reason.
num _round(double v) {
  final r = double.parse(v.toStringAsFixed(6));
  // Normalise `-0.0` to `0.0`. They compare equal numerically, but they print
  // differently, so leaving it would make the JSON depend on which side of
  // zero an intermediate happened to land on.
  return r == 0 ? 0.0 : r;
}

Map<String, dynamic> _sample(TextAnimation anim, double p, int i, int n) {
  final s = anim.stateAt(p, i, n);
  return {
    'id': anim.id,
    'p': p,
    'i': i,
    'n': n,
    'opacity': _round(s.opacity),
    'offsetX': _round(s.offsetX),
    'offsetY': _round(s.offsetY),
    'scale': _round(s.scale),
    'rotation': _round(s.rotation),
    'fillProgress': _round(s.fillProgress),
  };
}

String _slotName(TextAnimationCategory slot) => switch (slot) {
      TextAnimationCategory.inAnim => 'in',
      TextAnimationCategory.outAnim => 'out',
      TextAnimationCategory.loop => 'loop',
    };

void main() {
  final samples = <Map<String, dynamic>>[];
  for (final anim in kTextAnimations) {
    for (final p in _progressSamples) {
      for (final g in _glyphSamples) {
        samples.add(_sample(anim, p, g[0], g[1]));
      }
    }
  }

  // `naturalDuration` is part of the contract too: the Kotlin side decides how
  // long a window runs, so a divergence here shifts every glyph's `p` even
  // with identical curves.
  final durations = <Map<String, dynamic>>[
    for (final anim in kTextAnimations)
      for (final count in _durationGlyphCounts)
        {
          'id': anim.id,
          'glyphCount': count,
          'seconds': _round(anim.naturalDuration(count)),
        },
  ];

  // Slot resolution. `'fade'` meant fade-in in the in-slot and fade-out in the
  // out-slot, and a bare in-only id in the out-slot resolved to nothing; both
  // rules are bug-for-bug fidelity to saved drafts, so both are pinned.
  final resolutionIds = <String>{
    'fade',
    'scale',
    'none',
    '',
    'not_a_real_id',
    'circleOpen',
    for (final a in kTextAnimations) a.id,
  }.toList()
    ..sort();

  final resolution = <Map<String, dynamic>>[
    for (final id in resolutionIds)
      for (final slot in TextAnimationCategory.values)
        {
          'id': id,
          'slot': _slotName(slot),
          'resolved': resolveTextAnimation(id, slot)?.id,
        },
  ];

  // Speed scaling and the proportional compression rule.
  final durationResolution = <Map<String, dynamic>>[];
  for (final span in _durationSpans) {
    for (final speed in _durationSpeeds) {
      for (final count in _durationGlyphCounts) {
        for (final pair in const [
          ['typing', 'fade_out'],
          ['bounce_in', 'sink_out'],
          ['fade_in', null],
          [null, 'untyping'],
          [null, null],
        ]) {
          final inId = pair[0];
          final outId = pair[1];
          final r = resolveTextAnimationDurations(
            spanSeconds: span,
            inAnim: inId == null
                ? null
                : resolveTextAnimation(inId, TextAnimationCategory.inAnim),
            outAnim: outId == null
                ? null
                : resolveTextAnimation(outId, TextAnimationCategory.outAnim),
            glyphCount: count,
            speed: speed,
          );
          durationResolution.add({
            'spanSeconds': span,
            'speed': speed,
            'glyphCount': count,
            'inId': inId,
            'outId': outId,
            'inSeconds': _round(r.inSeconds),
            'outSeconds': _round(r.outSeconds),
          });
        }
      }
    }
  }

  final payload = <String, dynamic>{
    'samples': samples,
    'durations': durations,
    'resolution': resolution,
    'durationResolution': durationResolution,
  };

  final json = const JsonEncoder.withIndent('  ').convert(payload);
  for (final path in _outputPaths) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$json\n');
  }

  stdout
    ..writeln('animations:          ${kTextAnimations.length}')
    ..writeln('curve samples:       ${samples.length} '
        '(${kTextAnimations.length} x ${_progressSamples.length} x '
        '${_glyphSamples.length})')
    ..writeln('duration samples:    ${durations.length}')
    ..writeln('resolution samples:  ${resolution.length}')
    ..writeln('duration resolution: ${durationResolution.length}');
  for (final path in _outputPaths) {
    stdout.writeln('wrote $path');
  }
}

/// Generates the shared fixture that pins `AnimatableDouble` and its Kotlin
/// port together.
///
/// A parameter's value is resolved in Dart for the preview and in
/// `AnimatableDouble.kt` for the export, so every envelope and the whole
/// keyframe evaluator exist twice. Nothing in either type system makes the two
/// agree — a mistranslated branch is a file whose effect moves differently from
/// the canvas, with nothing on screen explaining it. This table of sampled
/// values is what turns that into a test failure.
///
/// Run after any deliberate change to `animatable_double.dart`:
///
/// ```
/// dart run tool/generate_envelope_fixture.dart
/// ```
///
/// and then re-run **both** sides:
///
/// ```
/// flutter test test/features/video_editor/logic/animation/animatable_fixture_test.dart
/// .\android\gradlew.bat -p android testDebugUnitTest --tests "*AnimatableDoubleTest*"
/// ```
///
/// Regenerating without running the Kotlin test moves the goalposts silently:
/// the Dart pin passes by construction (it is generated from the code it
/// checks), so only the Kotlin run tells you whether the port followed.
///
/// This is deliberately the same mechanism, the same shape and the same caveat
/// as `tool/generate_animation_fixture.dart`. A second pattern for the same job
/// would be one more thing to keep in step by hand.
library;

import 'dart:convert';
import 'dart:io';

import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';

/// Where the fixture is written. Two copies, because Dart tests read from the
/// repo root and Gradle unit tests read from the Android module's test
/// resources; neither build system can reach across to the other's tree.
const List<String> _outputPaths = [
  'test/fixtures/animatable_fixture.json',
  'android/app/src/test/resources/animatable_fixture.json',
];

/// Progress samples.
///
/// The brief's seven. `0` and `1` are the endpoint rule every envelope is
/// written to satisfy; `0.25`, `0.5` and `0.75` walk the middle; and `0.1` and
/// `0.9` land inside the two branches the quarters step straight over —
/// `ramp_out` clears by `1/3` and returns from `0.85`, so `0.9` is the only
/// sample inside its tail and a port that fumbled that arm would pass on the
/// quarters alone.
const List<double> _progressSamples = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];

/// Progress values that are **not** in 0..1, plus NaN.
///
/// `_clamp01` is the first line of `resolveAt` and of `resolveEnvelope`, and
/// its NaN arm exists because a caller dividing seconds by a zero-length clip
/// hands one over. Kotlin's comparison operators treat `NaN` the same way
/// Dart's do — every comparison false — but `Double.NaN < 0` reading `true`
/// through some other spelling of the clamp would paint a black frame, so the
/// guard is pinned rather than assumed.
const List<double> _clampSamples = [-1.0, -0.0001, 1.0001, 2.0, double.nan];

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

/// A keyframe as the Kotlin test rebuilds it. Deliberately the wire shape
/// `Keyframe.toJson` writes, so the fixture doubles as a check that the two
/// sides read the same field names.
Map<String, dynamic> _keyframeJson(Keyframe k) => {
  'progress': k.progress,
  'value': k.value,
  'interpolation': k.interpolation.name,
};

/// One named keyframe configuration, sampled across [_progressSamples].
///
/// The name travels into the fixture and into the Kotlin failure message: a
/// bare "expected 0.5 got 0.7" in a table of hundreds is unusable, and the
/// configuration is what says *which* branch of the evaluator drifted.
class _KeyframeCase {
  const _KeyframeCase(this.name, this.parameter, {this.comment});

  final String name;
  final AnimatableDouble parameter;

  /// Why this case is here, carried into the JSON so the fixture reads as a
  /// document rather than as a number dump.
  final String? comment;
}

/// The keyframe configurations the brief names, plus the two degenerate shapes
/// the evaluator guards against explicitly.
///
/// Every one of these is a distinct arm of `resolveAt`, and a port can get any
/// of them wrong on its own: holding before the first keyframe, holding after
/// the last, the `identical(before, after)` exact-hit case, the `hold` flag
/// belonging to the *outgoing* segment, the zero-span divide guard, and the
/// order-independent bracketing scan.
final List<_KeyframeCase> _keyframeCases = [
  const _KeyframeCase(
    'empty_no_envelope',
    AnimatableDouble(baseValue: 0.75),
    comment: 'nothing animates it: flat base value at every instant',
  ),
  const _KeyframeCase(
    'empty_with_envelope',
    AnimatableDouble(baseValue: 0.8, envelope: 'ramp_in'),
    comment: 'no keyframes, so the envelope scales the base value',
  ),
  const _KeyframeCase(
    'unknown_envelope',
    AnimatableDouble(baseValue: 0.42, envelope: 'not_a_real_envelope'),
    comment:
        'an envelope from a newer build degrades to the base value, '
        'never a throw',
  ),
  const _KeyframeCase(
    'single',
    AnimatableDouble(
      baseValue: 0.5,
      keyframes: [Keyframe(progress: 0.5, value: 0.2)],
    ),
    comment:
        'one keyframe means "this value, for the whole clip" — it holds '
        'in both directions rather than extrapolating',
  ),
  const _KeyframeCase(
    'single_overrides_envelope',
    AnimatableDouble(
      baseValue: 0.5,
      envelope: 'pulse',
      keyframes: [Keyframe(progress: 0.5, value: 0.2)],
    ),
    comment:
        'the rule of the feature: one keyframe and the envelope steps '
        'aside entirely, it does not blend in or scale the result',
  ),
  const _KeyframeCase(
    'two_linear',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(
          progress: 0.2,
          value: 0.1,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 0.8,
          value: 0.9,
          interpolation: KeyframeInterpolation.linear,
        ),
      ],
    ),
    comment: 'a straight line between two points, holding outside them',
  ),
  const _KeyframeCase(
    'two_ease',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(progress: 0.2, value: 0.1),
        Keyframe(progress: 0.8, value: 0.9),
      ],
    ),
    comment:
        'the default ease, which is where `_easeInOut` has to match — '
        'its two cubic arms meet at t == 0.5',
  ),
  const _KeyframeCase(
    'two_hold',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(
          progress: 0.25,
          value: 0.3,
          interpolation: KeyframeInterpolation.hold,
        ),
        Keyframe(progress: 0.75, value: 0.9),
      ],
    ),
    comment:
        'the hold flag belongs to the segment that *starts* at the '
        'keyframe, so the value stays at 0.3 right up to 0.75 and jumps',
  ),
  const _KeyframeCase(
    'three_mixed',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(
          progress: 0.0,
          value: 0.0,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 0.5,
          value: 1.0,
          interpolation: KeyframeInterpolation.hold,
        ),
        Keyframe(progress: 1.0, value: 0.25),
      ],
    ),
    comment:
        'linear into a hold into the end — three segments, each reading '
        'its own outgoing flag',
  ),
  const _KeyframeCase(
    'three_mixed_unsorted',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(progress: 1.0, value: 0.25),
        Keyframe(
          progress: 0.0,
          value: 0.0,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 0.5,
          value: 1.0,
          interpolation: KeyframeInterpolation.hold,
        ),
      ],
    ),
    comment:
        'the same three points through the const constructor in scrambled '
        'order: the evaluator brackets by comparing progress, never by '
        'position, so this must sample identically to three_mixed',
  ),
  _KeyframeCase(
    'unsorted_sorted_factory',
    AnimatableDouble.sorted(
      baseValue: 0.0,
      keyframes: const [
        Keyframe(progress: 1.0, value: 0.25),
        Keyframe(
          progress: 0.0,
          value: 0.0,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 0.5,
          value: 1.0,
          interpolation: KeyframeInterpolation.hold,
        ),
      ],
    ),
    comment:
        'and the same points through the sorting factory — three '
        'identical tables is the point',
  ),
  const _KeyframeCase(
    'duplicate_progress',
    AnimatableDouble(
      baseValue: 0.0,
      keyframes: [
        Keyframe(
          progress: 0.5,
          value: 0.2,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 0.5,
          value: 0.8,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(progress: 1.0, value: 1.0),
      ],
    ),
    comment:
        'two keyframes on one instant — a user can drag one onto another. '
        'The `>=`/`<=` in the bracketing scan makes the last one written win '
        'consistently on both sides of the pair, and the zero-span guard stops '
        'the divide producing NaN',
  ),
  _KeyframeCase(
    'out_of_range_progress',
    AnimatableDouble.sorted(
      baseValue: 0.0,
      keyframes: const [
        Keyframe(progress: 0.0, value: 0.4),
        Keyframe(progress: 1.0, value: 0.6),
      ],
    ),
    comment:
        'keyframes exactly on both ends, so every sample is interpolated '
        'and none of the holding arms can hide a broken ease',
  ),
  const _KeyframeCase(
    'negative_and_large_values',
    AnimatableDouble(
      baseValue: 1.0,
      keyframes: [
        Keyframe(
          progress: 0.0,
          value: -2.5,
          interpolation: KeyframeInterpolation.linear,
        ),
        Keyframe(
          progress: 1.0,
          value: 40.0,
          interpolation: KeyframeInterpolation.linear,
        ),
      ],
    ),
    comment:
        'values are deliberately unclamped — a scale is not a volume — so '
        'a port that clamped to 0..1 somewhere would fail here and nowhere else',
  ),
];

void main() {
  // Every envelope in the catalog, at every progress sample. `kEnvelopeNames`
  // is walked rather than a hand-written list, so a new envelope reaches the
  // fixture — and therefore the Kotlin test — with no edit here.
  final envelopes = <Map<String, dynamic>>[
    for (final name in kEnvelopeNames)
      for (final p in _progressSamples)
        {'envelope': name, 'p': p, 'value': _round(resolveEnvelope(name, p))},
  ];

  // The unknown-name rule, which is what keeps a draft from a newer build
  // openable. It must be 1.0 — the base value, unmodulated — at every instant.
  final unknownEnvelopes = <Map<String, dynamic>>[
    for (final name in const ['', 'not_a_real_envelope', 'Pulse', 'ramp'])
      for (final p in _progressSamples)
        {'envelope': name, 'p': p, 'value': _round(resolveEnvelope(name, p))},
  ];

  // The clamp, pinned separately because out-of-range progress reaches
  // `resolveEnvelope` directly as well as through `resolveAt`.
  final clamped = <Map<String, dynamic>>[
    for (final name in kEnvelopeNames)
      for (final p in _clampSamples)
        {
          'envelope': name,
          // JSON has no NaN literal, so the input travels as a string and each
          // side parses it back. Dropping the NaN row instead would leave the
          // one arm of `_clamp01` that exists for a real crash untested.
          'p': p.isNaN ? 'nan' : p,
          'value': _round(resolveEnvelope(name, p)),
        },
  ];

  final keyframes = <Map<String, dynamic>>[
    for (final c in _keyframeCases)
      {
        'name': c.name,
        if (c.comment != null) 'comment': c.comment,
        'baseValue': c.parameter.baseValue,
        'envelope': c.parameter.envelope,
        'isAnimated': c.parameter.isAnimated,
        // The keyframes are written in the order the parameter actually holds
        // them, not sorted, so `three_mixed_unsorted` genuinely exercises the
        // Kotlin evaluator's order-independence rather than being quietly
        // sorted at the fixture boundary.
        'keyframes': c.parameter.keyframes.map(_keyframeJson).toList(),
        'samples': [
          for (final p in [..._progressSamples, ..._clampSamples])
            {
              'p': p.isNaN ? 'nan' : p,
              'value': _round(c.parameter.resolveAt(p)),
            },
        ],
      },
  ];

  final payload = <String, dynamic>{
    'envelopes': envelopes,
    'unknownEnvelopes': unknownEnvelopes,
    'clampedEnvelopes': clamped,
    'keyframeCases': keyframes,
  };

  final json = const JsonEncoder.withIndent('  ').convert(payload);
  for (final path in _outputPaths) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$json\n');
  }

  final keyframeSamples = keyframes.fold<int>(
    0,
    (n, c) => n + (c['samples'] as List).length,
  );
  stdout
    ..writeln('envelopes:         ${kEnvelopeNames.length}')
    ..writeln(
      'envelope samples:  ${envelopes.length} '
      '(${kEnvelopeNames.length} x ${_progressSamples.length})',
    )
    ..writeln('unknown-name rows: ${unknownEnvelopes.length}')
    ..writeln('clamp rows:        ${clamped.length}')
    ..writeln('keyframe cases:    ${keyframes.length}')
    ..writeln('keyframe samples:  $keyframeSamples');
  for (final path in _outputPaths) {
    stdout.writeln('wrote $path');
  }
}

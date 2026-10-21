import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_stack.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';

/// Pins the effect stack's rules to the engine's.
///
/// `passCosts` is what each effect costs out of the frame's
/// [kMaxEffectPasses]; the Kotlin `EffectPassCostsTest` reads the same file
/// against `EffectPassCosts`, so a budget decided in Dart is the budget the
/// engine draws by. `cases` are bar sets in the timeline's wire form
/// (`EditorTimelineEffect`) with what [effectBarsDrawnAt] draws at a few
/// instants; the Kotlin `EffectStackTest` parses the same bars and must draw
/// the same. Like every fixture here, it catches *divergence
/// tomorrow*, never a wrong number today: a cost is right only when it is the
/// number of passes `EffectShaders.passesFor` actually builds.
///
/// After a deliberate change, regenerate both copies with
///
///     UPDATE_EFFECT_FIXTURE=1 flutter test <this file>
///
/// and run the Kotlin tests again.
void main() {
  const dartPath = 'test/fixtures/effect_stack_fixture.json';
  const kotlinPath = 'android/app/src/test/resources/effect_stack_fixture.json';

  test('the fixture matches the catalog', () {
    final generated =
        const JsonEncoder.withIndent('  ').convert(_fixture()).trim();

    if (Platform.environment['UPDATE_EFFECT_FIXTURE'] == '1') {
      File(dartPath).writeAsStringSync('$generated\n');
      File(kotlinPath).writeAsStringSync('$generated\n');
    }

    String read(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n').trim();
    expect(read(dartPath), generated,
        reason: 'The catalog or the stack rule changed. If that was meant, '
            'regenerate with UPDATE_EFFECT_FIXTURE=1 and re-run the Kotlin '
            'tests.');
    expect(read(kotlinPath), generated,
        reason: 'The Kotlin copy has drifted from the Dart one.');
  });

  test('every catalog effect has the pass cost the fixture records', () {
    final fixture = jsonDecode(File(dartPath).readAsStringSync())
        as Map<String, dynamic>;
    final costs = (fixture['passCosts'] as Map).cast<String, num>();
    expect(costs.keys.toSet(), {for (final e in kVideoEffects) e.id});
    for (final effect in kVideoEffects) {
      expect(effect.passCount, costs[effect.id], reason: effect.id);
    }
  });

  test('the costs the renderer builds', () {
    // `EffectShaders.passesFor`: a gaussian is two draws; the glow is a
    // bright pass, two blur halves and a composite.
    expect(videoEffectById('blur')!.passCount, 2);
    expect(videoEffectById('blur_in')!.passCount, 2);
    expect(videoEffectById('glow')!.passCount, 4);
    expect(videoEffectById('vignette')!.passCount, 1);
    expect(kMaxEffectPasses, 4);
  });
}

Map<String, dynamic> _fixture() => {
      'passCosts': {for (final e in kVideoEffects) e.id: e.passCount},
      'cases': [
        for (final c in _cases)
          {
            'name': c.name,
            'bars': [for (final b in c.bars) _wire(b)],
            'samples': [
              for (final t in c.instants)
                {
                  'seconds': t,
                  'drawn': [
                    for (final a in effectBarsDrawnAt(c.bars, t))
                      {
                        'id': a.bar.id,
                        'intensity': a.intensity,
                        'progress': a.progress,
                        'barSeconds': a.barSeconds,
                      },
                  ],
                },
            ],
          },
      ],
    };

/// A bar as the composer sends it (`EditorTimelineEffect.toJson`).
Map<String, dynamic> _wire(EffectBarModel b) => {
      'id': b.id,
      'effectId': b.effectId,
      'start': b.start,
      'end': b.end,
      'lane': b.laneIndex,
      'intensity': b.intensity.toJson(),
      if (effectIntroSecondsFor(b.effectId) case final intro?) 'introSeconds': intro,
    };

EffectBarModel _bar(
  String id,
  String effect,
  double start,
  double end, {
  int lane = 0,
  AnimatableDouble intensity = const AnimatableDouble(baseValue: 0.7),
}) =>
    EffectBarModel(
      id: id,
      effectId: effect,
      start: start,
      end: end,
      laneIndex: lane,
      intensity: intensity,
    );

const _rising = AnimatableDouble(baseValue: 0.5, keyframes: [
  Keyframe(progress: 0, value: 0),
  Keyframe(progress: 1, value: 1),
]);

final _cases = <({String name, List<EffectBarModel> bars, List<double> instants})>[
  (
    name: 'lane order',
    bars: [_bar('high', 'grain', 0, 5, lane: 2), _bar('low', 'vignette', 0, 5)],
    instants: [2],
  ),
  (
    name: 'half-open at a seam',
    bars: [_bar('a', 'grain', 0, 2), _bar('b', 'vignette', 2, 4)],
    instants: [1.999, 2, 4],
  ),
  (
    name: 'glow is the whole budget',
    bars: [_bar('g', 'glow', 0, 5), _bar('v', 'vignette', 0, 5, lane: 1)],
    instants: [1],
  ),
  (
    name: 'a skipped bar does not stop a later one',
    bars: [
      _bar('b', 'blur', 0, 5),
      _bar('g', 'glow', 0, 5, lane: 1),
      _bar('v', 'vignette', 0, 5, lane: 2),
    ],
    instants: [1],
  ),
  (
    name: 'an unknown effect costs nothing',
    bars: [_bar('x', 'from_the_future', 0, 5), _bar('g', 'glow', 0, 5, lane: 1)],
    instants: [1],
  ),
  (
    name: "keyframed intensity on the bar's clock",
    bars: [_bar('k', 'vignette', 4, 8, intensity: _rising)],
    instants: [4, 6, 7.5, 8],
  ),
  (
    name: 'an envelope across the bar',
    bars: [
      _bar('e', 'blur', 2, 6,
          intensity: const AnimatableDouble(baseValue: 0.8, envelope: 'ramp_out')),
    ],
    instants: [2, 3, 5.9],
  ),
  (
    name: 'a keyframed intro',
    bars: [_bar('z', 'cinema_zoom', 0, 10, intensity: _rising)],
    instants: [0, 0.6, 1.2, 9],
  ),
  (
    name: 'intensity clamped',
    bars: [_bar('c', 'vignette', 0, 4, intensity: const AnimatableDouble(baseValue: 1.7))],
    instants: [1],
  ),
  (
    name: 'the same effect twice',
    bars: [_bar('v1', 'vignette', 0, 5), _bar('v2', 'vignette', 1, 6, lane: 1)],
    instants: [0.5, 3],
  ),
];

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';

/// Pins the effect stack's rules to the engine's.
///
/// `passCosts` is what each effect costs out of the frame's
/// [kMaxEffectPasses]; the Kotlin `EffectPassCostsTest` reads the same file
/// against `EffectPassCosts`, so a budget decided in Dart is the budget the
/// engine draws by. Like every fixture here, it catches *divergence
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
      'cases': <Object>[],
    };

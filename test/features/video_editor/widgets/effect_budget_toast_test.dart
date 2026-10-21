import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_stack.dart';
import 'package:slimshotai/features/video_editor/models/effect_bar_model.dart';

/// A bar the four-pass budget skips is named once, by the edit that first
/// skips it.
void main() {
  EffectBarModel bar(String id, String effect, double start, double end, int lane) =>
      EffectBarModel(id: id, effectId: effect, start: start, end: end, laneIndex: lane);

  test('the line names the effect', () {
    expect(
      effectSkippedMessage(bar('g', 'glow', 0, 2, 1)),
      'Dreamy is skipped: too many effects at once',
    );
    expect(effectSkippedMessage(bar('x', 'from_the_future', 0, 2, 1)),
        'Effect is skipped: too many effects at once');
  });

  test('adding glow over a blur is skipped and named; a later edit says nothing',
      () {
    final before = [bar('b', 'blur', 0, 5, 0)];
    final after = [...before, bar('g', 'glow', 2, 6, 1)];
    expect(newlySkippedEffectBar(before, after)?.id, 'g');
    final unrelated = [
      for (final b in after) b.id == 'b' ? b.copyWith(end: 5.5) : b,
    ];
    expect(newlySkippedEffectBar(after, unrelated), isNull);
  });

  test('the screen listens for it and toasts the line', () {
    final screen = File('lib/screens/video_editor_screen.dart').readAsStringSync();
    expect(screen, contains('newlySkippedEffectBar('));
    expect(screen, contains('effectSkippedMessage('));
  });
}

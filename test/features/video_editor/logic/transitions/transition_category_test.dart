import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_catalog.dart';

void main() {
  test('every transition sits in exactly one category', () {
    final placed = [
      for (final category in TransitionCategory.values)
        ...transitionsIn(category),
    ];
    expect(placed.toSet(), EditorTransition.values.toSet());
    expect(placed.length, EditorTransition.values.length);
  });

  test('a category lists its transitions in catalog order', () {
    for (final category in TransitionCategory.values) {
      final listed = transitionsIn(category);
      final indices = listed.map((t) => t.index).toList();
      expect(indices, [...indices]..sort(), reason: category.name);
    }
  });

  test('the fades and wipes are Basic, the blurs are Blur', () {
    expect(EditorTransition.dissolve.category, TransitionCategory.basic);
    expect(EditorTransition.wipe.category, TransitionCategory.basic);
    expect(EditorTransition.smoothDown.category, TransitionCategory.basic);
    expect(EditorTransition.zoomBlur.category, TransitionCategory.blur);
    expect(EditorTransition.motionBlur.category, TransitionCategory.blur);
    expect(EditorTransition.whipPan.category, TransitionCategory.motion);
    expect(EditorTransition.slideScaleLeft.category, TransitionCategory.motion);
  });

  test('the light, glitch and 3D ports sit in their own pills', () {
    expect(EditorTransition.overexposure.category, TransitionCategory.light);
    expect(EditorTransition.filmBurn.category, TransitionCategory.light);
    expect(EditorTransition.flash.category, TransitionCategory.light);
    for (final t in [
      EditorTransition.glitchMemories,
      EditorTransition.lostSignal,
      EditorTransition.tvStatic,
      EditorTransition.datamosh,
      EditorTransition.glitchDisplace,
      EditorTransition.flicker,
    ]) {
      expect(t.category, TransitionCategory.glitch, reason: t.name);
    }
    for (final t in [
      EditorTransition.revolveLeft,
      EditorTransition.revolveRight,
      EditorTransition.cubeLeft,
      EditorTransition.cubeRight,
    ]) {
      expect(t.category, TransitionCategory.threeD, reason: t.name);
    }
  });

  test('no transition is labelled like a pill', () {
    // A tile reading "Glitch" under a pill reading "Glitch" is two of one word.
    final pills = TransitionCategory.values.map((c) => c.label).toSet();
    for (final t in EditorTransition.values) {
      expect(pills, isNot(contains(t.label)), reason: t.name);
    }
  });

  test('only categories that hold something are offered', () {
    final offered = offeredTransitionCategories();
    expect(offered, isNotEmpty);
    for (final category in offered) {
      expect(transitionsIn(category), isNotEmpty, reason: category.name);
    }
    // Every pill holds something now, in declaration order.
    expect(offered, TransitionCategory.values);
  });

  test('a category with nothing in it is not offered', () {
    expect(
      offeredTransitionCategories(
        from: [EditorTransition.cubeLeft, EditorTransition.dissolve],
      ),
      [TransitionCategory.basic, TransitionCategory.threeD],
    );
  });

  test('the sheet opens on the category of the transition in use', () {
    expect(categoryForTransition(null), TransitionCategory.basic);
    expect(categoryForTransition('defocus'), TransitionCategory.blur);
    expect(categoryForTransition('circleOpen'), TransitionCategory.basic);
  });

  test('every category has a label', () {
    for (final category in TransitionCategory.values) {
      expect(category.label, isNotEmpty);
    }
  });
}

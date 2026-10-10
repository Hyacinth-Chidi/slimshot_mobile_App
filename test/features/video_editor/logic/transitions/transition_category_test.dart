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

  test('only categories that hold something are offered', () {
    final offered = offeredTransitionCategories();
    expect(offered, isNotEmpty);
    for (final category in offered) {
      expect(transitionsIn(category), isNotEmpty, reason: category.name);
    }
    // Light, Glitch and 3D arrive with part 2b.
    expect(offered, isNot(contains(TransitionCategory.glitch)));
    expect(offered.first, TransitionCategory.basic);
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

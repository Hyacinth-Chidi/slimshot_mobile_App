import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/transition_marker.dart';

/// The marker that sits on the seam between two clips.
///
/// Three states, and each has to be legible **over arbitrary footage** — it is
/// drawn on top of the filmstrip, not on a panel, so it cannot rely on the
/// surface behind it being any particular colour.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool hasTransition,
    required bool isSelected,
    VoidCallback? onTap,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TransitionMarker(
              hasTransition: hasTransition,
              isSelected: isSelected,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  BoxDecoration decorationOf(WidgetTester tester) {
    return tester
        .widget<Container>(
          find.descendant(
            of: find.byType(TransitionMarker),
            matching: find.byType(Container),
          ),
        )
        .decoration as BoxDecoration;
  }

  Icon iconOf(WidgetTester tester) => tester.widget<Icon>(
        find.descendant(
          of: find.byType(TransitionMarker),
          matching: find.byType(Icon),
        ),
      );

  group('what it shows', () {
    testWidgets('no transition: an invitation, not a state', (tester) async {
      await pump(tester, hasTransition: false, isSelected: false);
      // A seam with no transition offers to add one, so the icon is the
      // "join these" affordance rather than anything claiming to be active.
      expect(iconOf(tester).icon, LucideIcons.plus);
    });

    testWidgets('a transition is applied: the two-clips mark', (tester) async {
      await pump(tester, hasTransition: true, isSelected: false);
      expect(iconOf(tester).icon, kTransitionIcon);
      expect(iconOf(tester).icon, isNot(LucideIcons.sparkles),
          reason: 'sparkles reads as "effect", not "transition"');
    });

    testWidgets('selected keeps the same icon, changes only emphasis',
        (tester) async {
      await pump(tester, hasTransition: true, isSelected: true);
      // Selection must not swap the glyph: the mark is how the user identifies
      // the thing they just tapped.
      expect(iconOf(tester).icon, kTransitionIcon);
    });
  });

  group('colour comes from the palette', () {
    testWidgets('no hard-coded colours anywhere in the three states',
        (tester) async {
      // CLAUDE.md: colours from `AppColors`, never hard-coded. The first
      // version used Slate (0xFF1E293B / 0xFF0F172A) against the app's Zinc,
      // which is the grey-blue that read as belonging to another app.
      final palette = <Color>{
        AppColors.background,
        AppColors.surface,
        AppColors.surfaceLight,
        AppColors.primaryStart,
        AppColors.primaryEnd,
        AppColors.textPrimary,
        AppColors.textSecondary,
        AppColors.border,
        AppColors.highlight,
        Colors.white,
        Colors.black,
      };

      // A palette colour, an opacity variant of one, or a composite of two of
      // them (`Color.alphaBlend`, which is how a translucent accent is made
      // opaque for drawing over footage). What this rejects is a *foreign hue*
      // — the Slate that made the first version read as another app.
      bool known(Color c) {
        if (palette.any((p) => p.toARGB32() == c.toARGB32())) return true;
        if (palette.any((p) => p.r == c.r && p.g == c.g && p.b == c.b)) {
          return true;
        }
        for (final over in palette) {
          for (final under in palette) {
            final blended = Color.alphaBlend(over, under);
            if (blended.toARGB32() == c.toARGB32()) return true;
          }
        }
        return false;
      }

      for (final (hasTransition, isSelected) in [
        (false, false),
        (true, false),
        (true, true),
      ]) {
        await pump(
          tester,
          hasTransition: hasTransition,
          isSelected: isSelected,
        );
        final d = decorationOf(tester);
        expect(known(d.color!), isTrue,
            reason: 'fill $hasTransition/$isSelected is ${d.color}');
        expect(known((d.border as Border).top.color), isTrue,
            reason: 'border $hasTransition/$isSelected');
        expect(known(iconOf(tester).color!), isTrue,
            reason: 'icon $hasTransition/$isSelected');
      }
    });

    testWidgets('an applied transition is visibly not an empty seam',
        (tester) async {
      await pump(tester, hasTransition: false, isSelected: false);
      final empty = decorationOf(tester);
      final emptyIcon = iconOf(tester).color;

      await pump(tester, hasTransition: true, isSelected: false);
      final applied = decorationOf(tester);

      // The distinction has to survive being 24px over moving footage, so it
      // is carried by the *fill*, not by a border tint alone.
      expect(applied.color, isNot(empty.color));
      expect(iconOf(tester).color, isNot(emptyIcon));
    });

    testWidgets('selection is legible against an applied transition',
        (tester) async {
      await pump(tester, hasTransition: true, isSelected: false);
      final applied = (decorationOf(tester).border as Border).top;

      await pump(tester, hasTransition: true, isSelected: true);
      final selected = (decorationOf(tester).border as Border).top;

      // Selected is the app's selection language: a white ring, thicker.
      expect(selected.color, isNot(applied.color));
      expect(selected.width, greaterThan(applied.width));
    });
  });

  group('the tap', () {
    testWidgets('reports once', (tester) async {
      var taps = 0;
      await pump(
        tester,
        hasTransition: false,
        isSelected: false,
        onTap: () => taps++,
      );
      await tester.tap(find.byType(TransitionMarker));
      expect(taps, 1);
    });

    testWidgets('the target is bigger than the mark', (tester) async {
      // 24px of ink, a 36px target — the same split the diamonds and trim
      // handles make. A seam marker sits between two draggable clips, so a
      // target the size of the ink would be nearly unhittable.
      await pump(tester, hasTransition: false, isSelected: false);
      final target = tester.getSize(find.byType(TransitionMarker));
      expect(target.width, greaterThanOrEqualTo(36));
      expect(target.height, greaterThanOrEqualTo(36));
    });
  });
}

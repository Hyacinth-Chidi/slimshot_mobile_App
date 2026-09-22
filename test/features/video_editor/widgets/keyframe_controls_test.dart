import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/widgets/editor_playback_controls.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/keyframe_easing_sheet.dart';

/// The keyframe controls live in the **playback bar**, after the play button
/// and before the time readout — not on any tool panel.
///
/// That placement is the correction this rebuild makes: a keyframe belongs to
/// the clip, so its control belongs where the clip's transport is, not inside
/// whichever feature happened to want keyframes first.
void main() {
  Future<void> pumpControls(
    WidgetTester tester, {
    bool showsKeyframeControls = true,
    bool isOnKeyframe = false,
    bool canEditCurve = true,
    bool canToggleKeyframe = true,
    VoidCallback? onToggleKeyframe,
    VoidCallback? onOpenEasing,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditorPlaybackControls(
            isPlaying: false,
            timelineLabel: '00:02 / 00:10',
            canUndo: false,
            canRedo: false,
            onTogglePreview: () {},
            onUndo: () {},
            onRedo: () {},
            showsKeyframeControls: showsKeyframeControls,
            isOnKeyframe: isOnKeyframe,
            canEditCurve: canEditCurve,
            canToggleKeyframe: canToggleKeyframe,
            onToggleKeyframe: onToggleKeyframe,
            onOpenEasing: onOpenEasing,
          ),
        ),
      ),
    );
  }

  group('the playback bar', () {
    testWidgets('no clip selected, no keyframe controls', (tester) async {
      await pumpControls(tester, showsKeyframeControls: false);
      expect(find.byKey(const Key('keyframe_toggle')), findsNothing);
      expect(find.byKey(const Key('keyframe_easing')), findsNothing);
      // The rest of the bar is untouched.
      expect(find.byIcon(LucideIcons.play), findsOneWidget);
      expect(find.text('00:02 / 00:10'), findsOneWidget);
    });

    testWidgets('the controls sit between the play button and the time',
        (tester) async {
      await pumpControls(tester);

      final play = tester.getCenter(find.byIcon(LucideIcons.play));
      final toggle = tester.getCenter(find.byKey(const Key('keyframe_toggle')));
      final easing = tester.getCenter(find.byKey(const Key('keyframe_easing')));
      final label = tester.getCenter(find.text('00:02 / 00:10'));

      expect(play.dx, lessThan(toggle.dx));
      expect(toggle.dx, lessThan(easing.dx));
      expect(easing.dx, lessThan(label.dx));
    });

    testWidgets('off a diamond the control shows a plus', (tester) async {
      await pumpControls(tester, isOnKeyframe: false);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(find.byIcon(LucideIcons.minus), findsNothing);
      expect(
        tester.widget<KeyframeToggleIcon>(find.byType(KeyframeToggleIcon))
            .isOnKeyframe,
        isFalse,
      );
    });

    testWidgets('on a diamond the control shows a minus', (tester) async {
      await pumpControls(tester, isOnKeyframe: true);
      expect(find.byIcon(LucideIcons.minus), findsOneWidget);
      expect(find.byIcon(LucideIcons.plus), findsNothing);
    });

    testWidgets('tapping the control reports it', (tester) async {
      var taps = 0;
      await pumpControls(tester, onToggleKeyframe: () => taps++);
      await tester.tap(find.byKey(const Key('keyframe_toggle')));
      expect(taps, 1);
    });

    testWidgets('tapping the curve icon opens the easing sheet',
        (tester) async {
      var opened = 0;
      await pumpControls(tester, onOpenEasing: () => opened++);
      await tester.tap(find.byKey(const Key('keyframe_easing')));
      expect(opened, 1);
    });

    testWidgets('with the playhead off the clip the toggle is dim and inert',
        (tester) async {
      // A clip stays selected while the playhead moves onto its neighbour.
      // There is no instant of *this* clip under the playhead then, so there
      // is nothing for a plus to pin — it dims rather than acting on an edge.
      var toggled = 0;
      await pumpControls(
        tester,
        canToggleKeyframe: false,
        onToggleKeyframe: () => toggled++,
      );

      await tester.tap(find.byKey(const Key('keyframe_toggle')));
      expect(toggled, 0);

      expect(find.byKey(const Key('keyframe_toggle')), findsOneWidget);
      final icon =
          tester.widget<KeyframeToggleIcon>(find.byType(KeyframeToggleIcon));
      expect(icon.enabled, isFalse);
    });

    testWidgets('with nothing to ease the curve icon is dim and inert',
        (tester) async {
      // **Disabled, not hidden.** Device-reported: the icon was always live,
      // and tapping it between diamonds silently added one. It is now dim
      // until a curve exists to shape, which also teaches what it wants.
      var opened = 0;
      await pumpControls(
        tester,
        canEditCurve: false,
        onOpenEasing: () => opened++,
      );

      await tester.tap(find.byKey(const Key('keyframe_easing')));
      expect(opened, 0);

      // Still present, so it does not jump in and out of the bar.
      expect(find.byKey(const Key('keyframe_easing')), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const Key('keyframe_easing')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, isNot(AppColors.textSecondary));
    });
  });

  group('the easing sheet', () {
    Future<KeyframeInterpolation?> openSheet(
      WidgetTester tester, {
      KeyframeInterpolation current = KeyframeInterpolation.linear,
    }) async {
      KeyframeInterpolation? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKeyframeEasingSheet(
                  context,
                  current: current,
                  onSelected: (e) => chosen = e,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return chosen;
    }

    testWidgets('shows four families as tabs, one group at a time',
        (tester) async {
      await openSheet(tester);

      // Every family is reachable as a tab...
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Quadratic'), findsOneWidget);
      expect(find.text('Cubic'), findsOneWidget);
      expect(find.text('Bounce'), findsOneWidget);

      // ...but only the open one's four cells are on screen. Sixteen at once
      // is a wall, and the families are alternatives rather than a list to
      // read through.
      expect(find.text('None'), findsOneWidget);
      expect(find.text('Ease in'), findsOneWidget);
      expect(find.text('Ease out'), findsOneWidget);
      expect(find.text('Ease'), findsOneWidget);
    });

    testWidgets('switching tab shows that family', (tester) async {
      KeyframeInterpolation? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKeyframeEasingSheet(
                  context,
                  current: KeyframeInterpolation.linear,
                  onSelected: (e) => chosen = e,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Bounce'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ease out'));
      await tester.pumpAndSettle();

      expect(chosen, KeyframeInterpolation.bounceOut);
    });

    testWidgets('opens on the family the current curve belongs to',
        (tester) async {
      await openSheet(tester, current: KeyframeInterpolation.cubicOut);
      // The highlighted cell has to be visible, not hidden behind a tab the
      // user would have to go looking for.
      await tester.tap(find.text('Ease out'));
      await tester.pumpAndSettle();
      expect(find.text('Cubic'), findsOneWidget);
    });

    testWidgets('choosing a curve applies it immediately', (tester) async {
      // **Applied live, not on confirm.** A sheet that held the choice until ✓
      // would make the user commit to a curve they have not seen move.
      KeyframeInterpolation? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKeyframeEasingSheet(
                  context,
                  current: KeyframeInterpolation.linear,
                  onSelected: (e) => chosen = e,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ease in'));
      await tester.pumpAndSettle();

      expect(chosen, KeyframeInterpolation.sineIn);
      // Still open, so the user can try another without reopening.
      expect(find.text('Default'), findsOneWidget);
    });

    testWidgets('choosing None in any family reports linear', (tester) async {
      KeyframeInterpolation? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showKeyframeEasingSheet(
                  context,
                  current: KeyframeInterpolation.bounceIn,
                  onSelected: (e) => chosen = e,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // There is one way not to ease, so every family's None is the same edit.
      await tester.tap(find.text('Cubic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('None'));
      await tester.pumpAndSettle();
      expect(chosen, KeyframeInterpolation.linear);
    });

    testWidgets('the tick dismisses the sheet', (tester) async {
      await openSheet(tester);
      expect(find.text('Default'), findsOneWidget);
      await tester.tap(find.byKey(const Key('keyframe_easing_done')));
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsNothing);
    });

    testWidgets('each curve is drawn, and None is not a curve', (tester) async {
      // Three graphs plus the crossed circle: "None" drawn as a straight line
      // would read as *linear*, a curve among curves, rather than as the
      // absence of one.
      await openSheet(tester);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(3));
      expect(find.byIcon(LucideIcons.ban), findsOneWidget);
    });
  });
}

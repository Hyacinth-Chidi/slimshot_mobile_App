import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
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

    testWidgets('shows four groups of four', (tester) async {
      await openSheet(tester);

      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Quadratic'), findsOneWidget);
      expect(find.text('Cubic'), findsOneWidget);
      expect(find.text('Bounce'), findsOneWidget);

      expect(find.text('None'), findsNWidgets(4));
      expect(find.text('Ease in'), findsNWidgets(4));
      expect(find.text('Ease out'), findsNWidgets(4));
      expect(find.text('Ease'), findsNWidgets(4));
    });

    testWidgets('choosing a curve reports the right value', (tester) async {
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

      // Bounce is the last group, so its "Ease out" is the last of the four.
      await tester.tap(find.text('Ease out').last);
      await tester.pumpAndSettle();

      expect(chosen, KeyframeInterpolation.bounceOut);
    });

    testWidgets('choosing None in any group reports linear', (tester) async {
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

      // There is one way not to ease, so every group's None is the same edit.
      await tester.tap(find.text('None').at(2));
      await tester.pumpAndSettle();
      expect(chosen, KeyframeInterpolation.linear);
    });

    testWidgets('the sheet closes after a choice', (tester) async {
      await openSheet(tester);
      expect(find.text('Default'), findsOneWidget);
      await tester.tap(find.text('Ease in').first);
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsNothing);
    });

    testWidgets('every curve is drawn, not just named', (tester) async {
      // Sixteen cells, each plotting its own curve from `applyKeyframeEasing`.
      // A text-only chip would make "Quadratic ease out" and "Cubic ease out"
      // indistinguishable until the user tried both.
      await openSheet(tester);
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(16));
    });
  });
}

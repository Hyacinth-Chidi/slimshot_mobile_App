import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/app_motion.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_panel_switcher.dart';

/// The bottom area's tool panels move like the sheets do.
///
/// A panel replacing the toolbar used to nudge up from 40% of its height over
/// 300ms on `easeOutCubic` while the sheets ran Flutter's stock 250ms. Two
/// motions for one family read as two apps. Both now run on [AppMotion]: a
/// panel slides in from fully below on the emphasized-decelerate curve and
/// leaves on emphasized-accelerate, and the container that grows around it
/// takes the same time, so height and slide land together.
void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: EditorPanelSwitcher(child: child),
          ),
        ),
      );

  const toolbar = SizedBox(key: Key('toolbar'), height: 60, width: 300);
  const panel = SizedBox(key: Key('panel'), height: 140, width: 300);

  SlideTransition slideOf(WidgetTester tester, Key key) =>
      tester.widget<SlideTransition>(find
          .ancestor(of: find.byKey(key), matching: find.byType(SlideTransition))
          .first);

  FadeTransition fadeOf(WidgetTester tester, Key key) =>
      tester.widget<FadeTransition>(find
          .ancestor(of: find.byKey(key), matching: find.byType(FadeTransition))
          .first);

  testWidgets('a panel slides up from fully below and fades in', (tester) async {
    await tester.pumpWidget(host(toolbar));
    await tester.pumpAndSettle();

    await tester.pumpWidget(host(panel));
    await tester.pump(); // start the transition
    await tester.pump(const Duration(milliseconds: 1));

    // Below its resting place — from fully below, the way a sheet arrives,
    // not a 40% nudge.
    final early = slideOf(tester, const Key('panel')).position.value.dy;
    expect(early, greaterThan(0.5));
    expect(fadeOf(tester, const Key('panel')).opacity.value, lessThan(0.5));

    await tester.pump(AppMotion.enter);
    expect(slideOf(tester, const Key('panel')).position.value.dy,
        closeTo(0, 1e-6));
    expect(fadeOf(tester, const Key('panel')).opacity.value, closeTo(1, 1e-6));
  });

  testWidgets('the switch and the size both run on the editor\'s motion',
      (tester) async {
    await tester.pumpWidget(host(toolbar));

    final switcher =
        tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
    expect(switcher.duration, AppMotion.enter);
    expect(switcher.reverseDuration, AppMotion.exit);
    expect(switcher.switchInCurve, Easing.emphasizedDecelerate);
    expect(switcher.switchOutCurve, Easing.emphasizedAccelerate);

    // The container grows over the same time the incoming child takes to
    // arrive; a different duration and the height lands before or after the
    // slide, which reads as a stutter.
    final size = tester.widget<AnimatedSize>(find.byType(AnimatedSize));
    expect(size.duration, AppMotion.enter);
    expect(size.curve, Easing.emphasizedDecelerate);
  });

  testWidgets('the old panel leaves faster than the new one arrives',
      (tester) async {
    // Material's rule, and the reason exits feel crisp: leaving takes less
    // time than arriving.
    expect(AppMotion.exit, lessThan(AppMotion.enter));

    await tester.pumpWidget(host(panel));
    await tester.pumpAndSettle();
    await tester.pumpWidget(host(toolbar));
    await tester.pump();
    await tester.pump(AppMotion.exit + const Duration(milliseconds: 16));

    // Gone after the exit duration…
    expect(find.byKey(const Key('panel')), findsNothing);
    // …while the toolbar is still on its way in.
    expect(fadeOf(tester, const Key('toolbar')).opacity.value, lessThan(1.0));
  });
}

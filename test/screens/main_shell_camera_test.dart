import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';
import 'package:slimshotai/core/widgets/nav_camera_button.dart';
import 'package:slimshotai/main.dart';

Future<void> _settle(WidgetTester tester) async {
  // Home has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The camera's door is a circle of its own on the nav's row, right of the
/// bar (the owner's pick of three mockups, 2026-11-07): nothing on a screen
/// is covered, and the bar keeps one shape on every tab.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpShell(WidgetTester tester, {Size size = const Size(1080, 2340), double text = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    initializeAppRouter('/home');
    await tester.pumpWidget(const ProviderScope(child: SlimShotApp(enableShareIntents: false)));
    await _settle(tester);
  }

  List<String> stack() =>
      appRouter.routerDelegate.currentConfiguration.matches.map((m) => m.matchedLocation).toList();

  final camera = find.byKey(kNavCameraKey);

  testWidgets("the camera sits on the nav's row, right of the bar, the bar's height", (tester) async {
    await pumpShell(tester);
    final bar = tester.getRect(find.byType(FloatingNavBar));
    final button = tester.getRect(camera);
    expect(button.left, moreOrLessEquals(bar.right + kNavCameraGap, epsilon: 0.5));
    expect(button.height, moreOrLessEquals(kFloatingNavBarHeight, epsilon: 0.5));
    expect(button.width, moreOrLessEquals(button.height, epsilon: 0.5), reason: 'a circle');
    expect(button.center.dy, moreOrLessEquals(bar.center.dy, epsilon: 0.5));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(screen.width - button.right, moreOrLessEquals(bar.left, epsilon: 0.5),
        reason: 'the row keeps the margin the bar had on both sides');
  });

  testWidgets('it is on every tab, and the bar keeps its shape between them', (tester) async {
    await pumpShell(tester);
    final onHome = tester.getRect(find.byType(FloatingNavBar));
    for (final tab in [1, 2]) {
      await tester.tap(find.byKey(FloatingNavBar.iconKey(tab)));
      await _settle(tester);
      expect(camera, findsOneWidget, reason: 'tab $tab');
      expect(tester.getRect(find.byType(FloatingNavBar)), onHome, reason: 'tab $tab');
    }
  });

  testWidgets('a tap opens the camera', (tester) async {
    await pumpShell(tester);
    await tester.tap(camera);
    await _settle(tester);
    expect(stack(), ['/home', '/camera']);
  });

  testWidgets('it opens the camera from another tab too', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(FloatingNavBar.iconKey(1)));
    await _settle(tester);
    await tester.tap(camera);
    await _settle(tester);
    expect(stack().last, '/camera');
  });

  testWidgets('a screen reader hears a button named Camera', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester);
    expect(tester.getSemantics(camera), isSemantics(label: 'Camera', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('bar and button fit a 320dp phone with large text', (tester) async {
    await pumpShell(tester, size: const Size(960, 1920), text: 1.3);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(camera);
    final bar = tester.getRect(find.byType(FloatingNavBar));
    expect(button.right, lessThanOrEqualTo(320));
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThan(button.left));
  });
}

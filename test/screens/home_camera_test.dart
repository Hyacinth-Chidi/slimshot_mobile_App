import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/home_camera_button.dart';

Future<void> _settle(WidgetTester tester) async {
  // Home has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

DraftProject _draft(int i) => DraftProject(
      id: 'd$i',
      sourceVideoPath: '/v.mp4',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now().subtract(Duration(minutes: i)),
      durationSeconds: 30,
      segments: const [],
      textOverlays: const [],
      imageOverlays: const [],
      videoOverlays: const [],
      audioTracks: const [],
      selectedRatioName: 'ratio9x16',
      customCropRect: const [0, 0, 1, 1],
      videoScale: 1,
      videoPanX: 0,
      videoPanY: 0,
      filterIntensity: 1,
      backgroundType: 'black',
      backgroundColorValue: 0xFF000000,
      backgroundBlurIntensity: 20,
      isMuted: false,
    );

/// The camera's door floats on Home, bottom right, above the nav (the
/// owner's call, 2026-11-09, after living with it beside the bar): a circle
/// of Home's own, so the nav is the three tabs alone again, on every tab.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true}));

  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1080, 2400),
    double ratio = 3,
    double text = 1,
    int drafts = 0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    tester.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      for (var i = 0; i < drafts; i++) {
        await DraftService.saveDraft(_draft(i));
      }
    });
    initializeAppRouter('/home');
    await tester.pumpWidget(const ProviderScope(child: SlimShotApp(enableShareIntents: false)));
    await _settle(tester);
  }

  List<String> stack() =>
      appRouter.routerDelegate.currentConfiguration.matches.map((m) => m.matchedLocation).toList();

  final camera = find.byKey(kHomeCameraKey);
  final bar = find.byType(FloatingNavBar);

  testWidgets('the nav is the three tabs alone again, its old margins both sides', (tester) async {
    await pumpShell(tester);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final nav = tester.getRect(bar);
    expect(nav.left, moreOrLessEquals(kFloatingNavSideMargin, epsilon: 0.5));
    expect(screen.width - nav.right, moreOrLessEquals(kFloatingNavSideMargin, epsilon: 0.5));
    expect(tester.getRect(camera).bottom, lessThan(nav.top), reason: 'not on the nav row');
  });

  testWidgets('it floats bottom right, over the bar, lined up with its right edge', (tester) async {
    await pumpShell(tester);
    final nav = tester.getRect(bar);
    final button = tester.getRect(camera);
    expect(button.right, moreOrLessEquals(nav.right, epsilon: 0.5));
    expect(button.bottom, moreOrLessEquals(nav.top - kHomeCameraGap, epsilon: 0.5));
    expect(button.width, moreOrLessEquals(kHomeCameraSize, epsilon: 0.5));
    expect(button.height, moreOrLessEquals(button.width, epsilon: 0.5), reason: 'a circle');
  });

  testWidgets('on a tablet it still lines up with the bar, not the screen edge', (tester) async {
    await pumpShell(tester, size: const Size(1600, 2560), ratio: 2);
    final nav = tester.getRect(bar);
    expect(nav.width, moreOrLessEquals(kFloatingNavMaxWidth - 2 * kFloatingNavSideMargin, epsilon: 0.5));
    expect(tester.getRect(camera).right, moreOrLessEquals(nav.right, epsilon: 0.5));
  });

  testWidgets('it is on Home only', (tester) async {
    await pumpShell(tester);
    expect(camera, findsOneWidget);
    for (final tab in [1, 2]) {
      await tester.tap(find.byKey(FloatingNavBar.iconKey(tab)));
      await _settle(tester);
      expect(camera.hitTestable(), findsNothing, reason: 'tab $tab');
    }
    await tester.tap(find.byKey(FloatingNavBar.iconKey(0)));
    await _settle(tester);
    expect(camera.hitTestable(), findsOneWidget);
  });

  testWidgets('a tap opens the camera', (tester) async {
    await pumpShell(tester);
    await tester.tap(camera);
    await _settle(tester);
    expect(stack(), ['/home', '/camera']);
  });

  // It sits on the last recent edit's corner, so it must be drawn over the
  // drafts and take the tap there, never pass it to the edit underneath.
  testWidgets('over the recent edits, the tap is the camera\'s', (tester) async {
    await pumpShell(tester, drafts: 6);
    final button = tester.getRect(camera);
    final last = tester.getRect(find.byKey(const ValueKey('recent_draft_d5')));
    expect(button.overlaps(last), isTrue, reason: 'the case this test is about');
    await tester.tapAt(button.center);
    await _settle(tester);
    expect(stack(), ['/home', '/camera']);
  });

  // The owner's call, seen on the device: flat, like the bar.
  testWidgets('the circle casts no shadow', (tester) async {
    await pumpShell(tester);
    final circle = tester.widget<Container>(find.descendant(of: camera, matching: find.byType(Container)).first);
    final decoration = circle.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.boxShadow, anyOf(isNull, isEmpty));
  });

  testWidgets('a screen reader hears a button named Camera', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpShell(tester);
    expect(tester.getSemantics(camera), isSemantics(label: 'Camera', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('it fits a 320dp phone with large text', (tester) async {
    await pumpShell(tester, size: const Size(960, 1920), text: 1.3);
    expect(tester.takeException(), isNull);
    final button = tester.getRect(camera);
    expect(button.right, lessThanOrEqualTo(320));
    expect(button.left, greaterThanOrEqualTo(0));
  });
}

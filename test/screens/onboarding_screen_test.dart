import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/onboarding_screen.dart';

Future<void> _settle(WidgetTester tester) async {
  // Looping light and entrance motion: it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _headline(String text) => find.text(text, findRichText: true);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    Size size = const Size(1080, 2340),
    double ratio = 3,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = ratio;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    initializeAppRouter('/onboarding');
    await tester.pumpWidget(
        const ProviderScope(child: SlimShotApp(enableShareIntents: false)));
    await _settle(tester);
  }

  // The owner's design: the first thing a new user sees is the editor's own
  // timeline, clips with a bar of each kind on it, so the app reads as a
  // real editor at a glance.
  testWidgets('the first page is a timeline with a bar of each kind',
      (tester) async {
    await pumpOnboarding(tester);
    expect(_headline('Edit like a pro'), findsOneWidget);
    final timeline = find.byKey(const Key('onboarding_timeline'));
    expect(timeline, findsOneWidget);
    for (final bar in ['LEVEL UP', 'Glow', 'Photo', 'Whoosh']) {
      expect(find.descendant(of: timeline, matching: find.text(bar)),
          findsOneWidget,
          reason: bar);
    }
    expect(find.byKey(const Key('onboarding_playhead')), findsOneWidget);
    // The playhead stops at the music bar; it does not run into the words.
    final playhead = tester.getRect(find.byKey(const Key('onboarding_playhead')));
    expect(playhead.bottom,
        lessThan(tester.getRect(_headline('Edit like a pro')).top));
  });

  testWidgets('Continue walks three pages; the last says Get started',
      (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(_headline('Clear on WhatsApp Status'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(_headline('Captions in one tap'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('three steps in the progress bar, lit up to the current page',
      (tester) async {
    await pumpOnboarding(tester);
    Color step(int i) => ((tester
                .widget<AnimatedContainer>(
                    find.byKey(Key('onboarding_step_$i')))
                .decoration!) as BoxDecoration)
            .color!;
    expect(find.byKey(const Key('onboarding_step_2')), findsOneWidget);
    expect(step(0), isNot(step(1)));
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(step(1), step(0));
    expect(step(2), isNot(step(1)));
  });

  for (final finish in ['Skip', 'Get started']) {
    testWidgets('$finish ends onboarding for good and opens Home',
        (tester) async {
      await pumpOnboarding(tester);
      if (finish == 'Get started') {
        for (var i = 0; i < 2; i++) {
          await tester.tap(find.text('Continue'));
          await _settle(tester);
        }
      }
      await tester.tap(find.text(finish));
      await _settle(tester);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byKey(const Key('home_new_video')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hasSeenOnboarding'), isTrue);
    });
  }

  for (final (name, size, ratio, scale) in [
    ('a small phone with large text', const Size(960, 1704), 3.0, 1.3),
    ('a tablet', const Size(1600, 2560), 2.0, 1.0),
    ('a tablet on its side', const Size(2560, 1600), 2.0, 1.0),
  ]) {
    testWidgets('every page fits $name', (tester) async {
      await pumpOnboarding(tester, size: size, ratio: ratio, textScale: scale);
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Continue'));
        await _settle(tester);
      }
      // An overflow is reported as an exception the test fails on.
      expect(find.text('Get started'), findsOneWidget);
    });
  }
}

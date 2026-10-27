import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/widgets/launch_splash.dart';
import 'package:slimshotai/main.dart';

/// The splash is the native one, then the app finishing it (the owner's
/// pick, C): the system shows the logo's body dim, without its bars; the
/// app's first frame repeats it exactly, then the body lights and the three
/// bars — the logo's speed lines — streak in from the left one after
/// another, the name rises under the logo, and it all fades into the app.
/// No glow: the owner turned it down.
void main() {
  group('the timeline', () {
    LaunchSplashFrame at(int ms, {bool reduced = false}) =>
        launchSplashFrameAt(Duration(milliseconds: ms), reduced: reduced);

    int firstWhen(bool Function(LaunchSplashFrame) test) {
      for (var ms = 0; ms <= 2000; ms += 5) {
        if (test(at(ms))) return ms;
      }
      return -1;
    }

    test('it opens on exactly what the native splash shows', () {
      for (final reduced in [false, true]) {
        final f = at(0, reduced: reduced);
        expect(f.body, kLaunchLogoRestingOpacity);
        expect(f.bars, everyElement(0.0), reason: 'no bars yet');
        expect(f.name, 0);
        expect(f.lift, 0);
        expect(f.scale, 1);
        expect(f.fade, 1);
      }
    });

    test('the bars arrive one after another, the top one first', () {
      final starts = [
        for (var i = 0; i < 3; i++) firstWhen((f) => f.bars[i] > 0),
      ];
      expect(starts[0], greaterThan(0));
      expect(starts[1], greaterThan(starts[0]));
      expect(starts[2], greaterThan(starts[1]));
      // Caught on the way, each is further in than the one below it.
      final middle = at(starts[2] + 10);
      expect(middle.bars[0], greaterThan(middle.bars[1]));
      expect(middle.bars[1], greaterThan(middle.bars[2]));
    });

    test('the body is lit and every bar in place before the name rises', () {
      final named = firstWhen((f) => f.name > 0);
      expect(named, greaterThan(0));
      final ready = at(named);
      expect(ready.body, 1);
      expect(ready.bars, everyElement(1.0));
    });

    test('the name is up and the logo lifted before anything fades', () {
      final fading = firstWhen((f) => f.fade < 1);
      expect(fading, greaterThan(0));
      final settled = at(fading);
      expect(settled.name, 1);
      expect(settled.lift, 1);
      expect(at(kLaunchSplashDuration.inMilliseconds).fade, 0);
    });

    test('nothing goes backwards', () {
      var previous = at(0);
      for (var ms = 5; ms <= kLaunchSplashDuration.inMilliseconds; ms += 5) {
        final f = at(ms);
        expect(f.body, greaterThanOrEqualTo(previous.body), reason: '$ms');
        for (var i = 0; i < 3; i++) {
          expect(f.bars[i], greaterThanOrEqualTo(previous.bars[i]),
              reason: 'bar $i at $ms');
        }
        expect(f.name, greaterThanOrEqualTo(previous.name), reason: '$ms');
        expect(f.lift, greaterThanOrEqualTo(previous.lift), reason: '$ms');
        expect(f.fade, lessThanOrEqualTo(previous.fade), reason: '$ms');
        previous = f;
      }
    });

    test('with animations turned off it only fades, and quickly', () {
      final middle = at(kLaunchSplashReducedDuration.inMilliseconds ~/ 2,
          reduced: true);
      expect(middle.body, kLaunchLogoRestingOpacity);
      expect(middle.bars, everyElement(0.0));
      expect(middle.name, 0);
      expect(middle.fade, inExclusiveRange(0, 1));
      expect(at(kLaunchSplashReducedDuration.inMilliseconds, reduced: true).fade,
          0);
    });
  });

  group('a bar on its way in', () {
    test('is not drawn before it sets off', () {
      expect(launchBarPose(0).opacity, 0);
    });

    test('streaks from the left, stretched, and shows almost at once', () {
      final early = launchBarPose(0.2);
      expect(early.shift, lessThan(0), reason: 'to the left of its place');
      expect(early.stretch, greaterThan(1), reason: 'drawn out like a streak');
      expect(early.opacity, greaterThan(0.3));
      final later = launchBarPose(0.6);
      expect(later.shift, greaterThan(early.shift));
      expect(later.stretch, lessThan(early.stretch));
    });

    test('lands exactly in place', () {
      final landed = launchBarPose(1);
      expect(landed.opacity, 1);
      expect(landed.shift, 0);
      expect(landed.stretch, 1);
    });
  });

  group('on screen', () {
    Future<LaunchSplashArt> loadArt(WidgetTester tester) async =>
        (await tester.runAsync(LaunchSplashArt.load))!;

    Widget host(LaunchSplashArt? art, {VoidCallback? onTap}) => MaterialApp(
          builder: (context, child) => LaunchSplash(art: art, child: child!),
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: onTap,
                child: const Text('Inside'),
              ),
            ),
          ),
        );

    final paint = find.byKey(const Key('launch_splash_paint'));

    LaunchSplashPainter painter(WidgetTester tester) =>
        tester.widget<CustomPaint>(paint).painter! as LaunchSplashPainter;

    // A phone whose navigation bar sits below the app: the view is shorter
    // than the display. The native splash is centred on the whole display,
    // so the first frame must be too, or the logo jumps at the hand-over.
    testWidgets('the first frame repeats the native splash: the body dim, its '
        'size, at the centre of the display', (tester) async {
      tester.view.physicalSize = const Size(1080, 2208);
      tester.view.devicePixelRatio = 3;
      tester.view.display.size = const Size(1080, 2340);
      addTearDown(tester.view.reset);
      addTearDown(tester.view.display.reset);
      final art = await loadArt(tester);

      await tester.pumpWidget(host(art));

      final p = painter(tester);
      expect(p.frame.body, kLaunchLogoRestingOpacity);
      expect(p.logoRect.size, kLaunchLogoSize);
      expect(p.logoRect.center, const Offset(180, 390));
      final name = tester.widget<Opacity>(
        find.byKey(const Key('launch_splash_name')),
      );
      expect(name.opacity, 0);
    });

    // The native picture is the body alone; anything more on the first
    // frame — a bar, a glow — would appear in a flash at the hand-over.
    testWidgets('the first frame draws the body and nothing else',
        (tester) async {
      final art = await loadArt(tester);
      await tester.pumpWidget(host(art));
      expect(tester.renderObject(paint),
          paintsExactlyCountTimes(#drawImageRect, 1));
      expect(tester.renderObject(paint), isNot(paints..circle()));
    });

    testWidgets('once the bars are in, it draws the body and three bars, and '
        'still no glow', (tester) async {
      final art = await loadArt(tester);
      await tester.pumpWidget(host(art));
      await tester.pump(const Duration(milliseconds: 540));
      expect(painter(tester).frame.bars, everyElement(1.0));
      expect(tester.renderObject(paint),
          paintsExactlyCountTimes(#drawImageRect, 4));
      expect(tester.renderObject(paint), isNot(paints..circle()));
    });

    testWidgets('it covers the app and keeps its touches, then hands it over',
        (tester) async {
      final art = await loadArt(tester);
      var taps = 0;
      await tester.pumpWidget(host(art, onTap: () => taps++));

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Inside'), warnIfMissed: false);
      expect(taps, 0, reason: 'a tap on an app nobody can see yet');

      await tester.pump(kLaunchSplashDuration);
      expect(find.byKey(const Key('launch_splash')), findsNothing);
      await tester.tap(find.text('Inside'));
      expect(taps, 1);
    });

    testWidgets('the name under the logo is the home header\'s wordmark',
        (tester) async {
      final art = await loadArt(tester);
      await tester.pumpWidget(host(art));
      final text = tester.widget<Text>(find.descendant(
        of: find.byKey(const Key('launch_splash_name')),
        matching: find.text('SlimShot AI'),
      ));
      expect(text.style!.fontWeight, FontWeight.w800);
      expect(text.style!.decoration, TextDecoration.none);
    });

    testWidgets('its pictures are let go when it ends', (tester) async {
      final art = await loadArt(tester);
      await tester.pumpWidget(host(art));
      expect(art.body.debugDisposed, isFalse);
      await tester.pump(kLaunchSplashDuration + const Duration(milliseconds: 50));
      expect(art.body.debugDisposed, isTrue);
      expect(art.bars.map((b) => b.debugDisposed), everyElement(isTrue));
    });

    testWidgets('with animations turned off it is gone in a moment',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final art = await loadArt(tester);
      await tester.pumpWidget(host(art));

      await tester.pump(kLaunchSplashReducedDuration ~/ 2);
      expect(painter(tester).frame.bars, everyElement(0.0));
      await tester.pump(kLaunchSplashReducedDuration);
      expect(find.byKey(const Key('launch_splash')), findsNothing);
    });

    // Its art failed to load: the app still opens, straight to itself.
    testWidgets('without its pictures there is no splash', (tester) async {
      await tester.pumpWidget(host(null));
      expect(find.byKey(const Key('launch_splash')), findsNothing);
      expect(find.text('Inside'), findsOneWidget);
    });

    testWidgets('the app opens on the splash and fades into Home',
        (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true});
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final art = await loadArt(tester);
      initializeAppRouter('/home');

      await tester.pumpWidget(ProviderScope(
        child: SlimShotApp(enableShareIntents: false, launchArt: art),
      ));
      expect(find.byKey(const Key('launch_splash')), findsOneWidget);
      // Home builds underneath from the first frame, ready for the fade.
      expect(find.byKey(const Key('home_new_video')), findsOneWidget);

      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const Key('launch_splash')), findsNothing);
      expect(find.byKey(const Key('home_new_video')), findsOneWidget);
    });
  });

  test('the art the app draws is the logo in four layers', () {
    expect(kLaunchSplashLayers, [
      'assets/splash/body.png',
      'assets/splash/bar_0.png',
      'assets/splash/bar_1.png',
      'assets/splash/bar_2.png',
    ]);
  });
}

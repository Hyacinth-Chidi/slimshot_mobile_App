import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/widgets/launch_splash.dart';
import 'package:slimshotai/main.dart';

/// The splash is the native one, then the app lighting it up (the owner's
/// pick, B): the system shows the logo dim; the app's first frame repeats it
/// exactly, then a glow blooms, the three bars light one by one, the name
/// rises under the logo, and it all fades into the app.
void main() {
  group('the timeline', () {
    LaunchSplashFrame at(int ms, {bool reduced = false}) =>
        launchSplashFrameAt(Duration(milliseconds: ms), reduced: reduced);

    test('it opens on exactly what the native splash shows', () {
      for (final reduced in [false, true]) {
        final f = at(0, reduced: reduced);
        expect(f.body, kLaunchLogoRestingOpacity);
        expect(f.bars, everyElement(kLaunchLogoRestingOpacity));
        expect(f.glow, 0);
        expect(f.name, 0);
        expect(f.lift, 0);
        expect(f.scale, 1);
        expect(f.fade, 1);
      }
    });

    test('the bars light one after another, the top one first', () {
      int firstLit(int bar) {
        for (var ms = 0; ms <= 1000; ms += 5) {
          if (at(ms).bars[bar] > kLaunchLogoRestingOpacity + 0.01) return ms;
        }
        return -1;
      }

      expect(firstLit(0), greaterThan(0));
      expect(firstLit(1), greaterThan(firstLit(0)));
      expect(firstLit(2), greaterThan(firstLit(1)));
      // Caught mid-way, each is ahead of the one below it.
      final middle = at(firstLit(1) + 20);
      expect(middle.bars[0], greaterThan(middle.bars[1]));
      expect(middle.bars[1], greaterThan(middle.bars[2]));
    });

    test('the logo is fully lit before the name rises under it', () {
      int firstNamed() {
        for (var ms = 0; ms <= 1000; ms += 5) {
          if (at(ms).name > 0) return ms;
        }
        return -1;
      }

      final named = firstNamed();
      expect(named, greaterThan(0));
      final lit = at(named);
      expect(lit.body, 1);
      expect(lit.bars, everyElement(1.0));
      expect(lit.glow, 1);
    });

    test('the name is up and the logo lifted before anything fades', () {
      int firstFading() {
        for (var ms = 0; ms <= 1000; ms += 5) {
          if (at(ms).fade < 1) return ms;
        }
        return -1;
      }

      final fading = firstFading();
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
        expect(f.glow, greaterThanOrEqualTo(previous.glow), reason: '$ms');
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
      expect(middle.glow, 0);
      expect(middle.body, kLaunchLogoRestingOpacity);
      expect(middle.bars, everyElement(kLaunchLogoRestingOpacity));
      expect(middle.name, 0);
      expect(middle.fade, inExclusiveRange(0, 1));
      expect(at(kLaunchSplashReducedDuration.inMilliseconds, reduced: true).fade,
          0);
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

    LaunchSplashPainter painter(WidgetTester tester) =>
        tester
                .widget<CustomPaint>(find.byKey(const Key('launch_splash_paint')))
                .painter!
            as LaunchSplashPainter;

    // A phone whose navigation bar sits below the app: the view is shorter
    // than the display. The native splash is centred on the whole display,
    // so the first frame must be too, or the logo jumps at the hand-over.
    testWidgets('the first frame repeats the native splash: the logo dim, its '
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
      expect(p.frame.bars, everyElement(kLaunchLogoRestingOpacity));
      expect(p.frame.glow, 0);
      expect(p.logoRect.size, kLaunchLogoSize);
      expect(p.logoRect.center, const Offset(180, 390));
      final name = tester.widget<Opacity>(
        find.byKey(const Key('launch_splash_name')),
      );
      expect(name.opacity, 0);
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
      expect(painter(tester).frame.glow, 0);
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/features/video_editor/logic/captions/caption_highlight.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_catalog.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/onboarding_screen.dart';
import 'package:slimshotai/screens/onboarding_showreel.dart';

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

  testWidgets('Continue walks four pages; the last says Get started',
      (tester) async {
    await pumpOnboarding(tester);
    expect(find.text('Skip'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(_headline('Clear on WhatsApp Status'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(_headline('Transitions that wow'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await _settle(tester);
    expect(_headline('Captions in one tap'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('four steps in the progress bar, lit up to the current page',
      (tester) async {
    await pumpOnboarding(tester);
    Color step(int i) => ((tester
                .widget<AnimatedContainer>(
                    find.byKey(Key('onboarding_step_$i')))
                .decoration!) as BoxDecoration)
            .color!;
    expect(find.byKey(const Key('onboarding_step_3')), findsOneWidget);
    expect(find.byKey(const Key('onboarding_step_4')), findsNothing);
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
        for (var i = 0; i < 3; i++) {
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
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Continue'));
        await _settle(tester);
      }
      // An overflow is reported as an exception the test fails on.
      expect(find.text('Get started'), findsOneWidget);
    });
  }

  // On a tablet the picture grows with the room it has, up to 1.6x; on a
  // phone it is the size it was laid out at.
  testWidgets('the timeline grows on a tablet and stays put on a phone',
      (tester) async {
    await pumpOnboarding(tester);
    // On screen, after the picture's scale.
    final phone = tester.getRect(find.byKey(const Key('onboarding_timeline')));
    await pumpOnboarding(tester, size: const Size(1600, 2560), ratio: 2);
    final tablet = tester.getRect(find.byKey(const Key('onboarding_timeline')));
    expect(tablet.width, greaterThan(phone.width * 1.3));
    expect(tablet.width, lessThanOrEqualTo(360 * 1.6 + 0.5));
  });

  Future<void> toTransitionsPage(WidgetTester tester) async {
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }
  }

  List<String> chipLabels(WidgetTester tester) => [
        for (var i = 0; tester.any(find.byKey(Key('onboarding_move_$i'))); i++)
          tester
              .widget<Text>(find.descendant(
                of: find.byKey(Key('onboarding_move_$i')),
                matching: find.byType(Text),
              ))
              .data!,
      ];

  String litChip(WidgetTester tester) {
    final labels = chipLabels(tester);
    final lit = [
      for (var i = 0; i < labels.length; i++)
        if (((tester
                        .widget<AnimatedContainer>(
                            find.byKey(Key('onboarding_move_$i')))
                        .decoration!) as BoxDecoration)
                .color ==
            AppColors.primaryStart)
          labels[i],
    ];
    expect(lit, hasLength(1), reason: 'one chip lit at a time');
    return lit.single;
  }

  // The owner's pick (A, Zoom Blur first, then the glitch): a framed clip
  // plays the app's own moves between three photos, the chip under it lit
  // for the one playing or about to.
  testWidgets('the transitions page plays Zoom Blur, Glitch and Cube in '
      'turn, lighting each', (tester) async {
    await pumpOnboarding(tester);
    await toTransitionsPage(tester);
    expect(_headline('Transitions that wow'), findsOneWidget);
    expect(find.byKey(const Key('onboarding_showreel')), findsOneWidget);
    expect(chipLabels(tester), [
      'Zoom Blur',
      'Glitch',
      'Cube',
      EditorTransition.swirl.label,
      '+${EditorTransition.values.length - 4}',
    ]);
    final order = <String>[];
    for (var i = 0; i < 70; i++) {
      final lit = litChip(tester);
      if (order.isEmpty || order.last != lit) order.add(lit);
      await tester.pump(const Duration(milliseconds: 100));
    }
    const moves = ['Zoom Blur', 'Glitch', 'Cube'];
    expect(order.toSet(), moves.toSet());
    for (var i = 1; i < order.length; i++) {
      expect(moves.indexOf(order[i]),
          (moves.indexOf(order[i - 1]) + 1) % moves.length,
          reason: order.join(' '));
    }
  });

  // The counts are the catalogs', so the line cannot fall behind them; the
  // owner struck "smooth on any phone" from it.
  testWidgets('its line counts the transitions and effects the app holds',
      (tester) async {
    await pumpOnboarding(tester);
    await toTransitionsPage(tester);
    expect(
        find.text('${EditorTransition.values.length} transitions and '
            '${kVideoEffects.length} effects.'),
        findsOneWidget);
    expect(find.textContaining('smooth'), findsNothing);
  });

  testWidgets('with animations turned off the transitions page holds on its '
      'first photo, Zoom Blur lit', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpOnboarding(tester);
    await toTransitionsPage(tester);
    expect(litChip(tester), 'Zoom Blur');
    await tester.pump(kShowreelLoop ~/ 2);
    expect(litChip(tester), 'Zoom Blur');
  });

  Future<void> toLastPage(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Continue'));
      await _settle(tester);
    }
  }

  final finalePhoto = find.byKey(const Key('onboarding_finale_photo'));
  final finaleCaption = find.byKey(const Key('onboarding_finale_caption'));

  // The owner's pick (A of four): the last page is the finished video — a
  // photo edge to edge from the top of the screen, fading into the black
  // where the words are — not a picture in a frame.
  for (final (name, size, ratio) in [
    ('a phone', const Size(1080, 2340), 3.0),
    ('a tablet', const Size(1600, 2560), 2.0),
  ]) {
    testWidgets("the last page's photo runs edge to edge from the top of the "
        'screen on $name', (tester) async {
      await pumpOnboarding(tester, size: size, ratio: ratio);
      await toLastPage(tester);
      final screen = size / ratio;
      final photo = tester.getRect(finalePhoto);
      expect(photo.left, 0);
      expect(photo.top, 0, reason: 'under the status bar and the step bar');
      expect(photo.width, screen.width, reason: 'wider than the words');
      expect(photo.height, greaterThan(screen.height * 0.5));
      final headline = tester.getRect(_headline('Captions in one tap'));
      expect(photo.bottom, lessThanOrEqualTo(headline.top + 0.5));
    });
  }

  // The owner's line, lit word by word in the app's own Bubble style.
  testWidgets('its caption plays word by word: EDIT YOUR VIDEOS WITH PASSION',
      (tester) async {
    await pumpOnboarding(tester);
    await toLastPage(tester);
    expect(kOnboardingCaptionWords,
        ['EDIT', 'YOUR', 'VIDEOS', 'WITH', 'PASSION']);
    for (final word in kOnboardingCaptionWords) {
      expect(find.descendant(of: finaleCaption, matching: find.text(word)),
          findsOneWidget);
    }
    String lit() => tester
        .widget<Text>(find.descendant(
          of: find.byKey(const Key('onboarding_caption_lit')),
          matching: find.byType(Text),
        ))
        .data!;
    final order = <String>[];
    for (var i = 0; i < 40; i++) {
      final word = lit();
      if (order.isEmpty || order.last != word) order.add(word);
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Every word lights in turn, in order, round and round.
    expect(order.toSet(), kOnboardingCaptionWords.toSet());
    for (var i = 1; i < order.length; i++) {
      final before = kOnboardingCaptionWords.indexOf(order[i - 1]);
      expect(kOnboardingCaptionWords.indexOf(order[i]),
          (before + 1) % kOnboardingCaptionWords.length,
          reason: order.join(' '));
    }
  });

  // Where a real caption sits — low on the picture, where it has faded
  // dark enough for white words — and never on the headline.
  testWidgets('the caption sits on the photo and clear of the words, even on '
      'a small phone with large text', (tester) async {
    await pumpOnboarding(tester,
        size: const Size(960, 1704), ratio: 3, textScale: 1.3);
    await toLastPage(tester);
    final photo = tester.getRect(finalePhoto);
    final caption = tester.getRect(finaleCaption);
    expect(caption.top, greaterThanOrEqualTo(photo.top));
    expect(caption.bottom, lessThanOrEqualTo(photo.bottom));
    expect(caption.center.dy, greaterThan(photo.center.dy),
        reason: 'low on the picture, where captions go');
    expect(caption.bottom,
        lessThan(tester.getRect(_headline('Captions in one tap')).top));
  });

  // The pages now run the whole screen under the step bar and the button;
  // a swipe in between must still reach them.
  testWidgets('a swipe across the middle of the screen turns the page',
      (tester) async {
    await pumpOnboarding(tester);
    await tester.fling(find.byType(PageView), const Offset(-300, 0), 1200);
    await _settle(tester);
    expect(_headline('Clear on WhatsApp Status'), findsOneWidget);
  });

  testWidgets('with animations turned off the caption holds still',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpOnboarding(tester);
    await toLastPage(tester);
    String lit() => tester
        .widget<Text>(find.descendant(
          of: find.byKey(const Key('onboarding_caption_lit')),
          matching: find.byType(Text),
        ))
        .data!;
    final first = lit();
    await tester.pump(const Duration(milliseconds: 1500));
    expect(lit(), first);
  });

  // A picture of a caption on a video: like the app's own captions it does
  // not grow with the phone's text size, and it wraps rather than shrinks.
  testWidgets('the caption keeps its size with large text, on two lines',
      (tester) async {
    await pumpOnboarding(tester);
    await toLastPage(tester);
    final normal = tester.getSize(finaleCaption);
    final word = tester.getSize(find.text('PASSION'));
    // A fresh start, at large text.
    await tester.pumpWidget(const SizedBox());
    await pumpOnboarding(tester, textScale: 1.3);
    await toLastPage(tester);
    expect(tester.getSize(find.text('PASSION')), word);
    expect(tester.getSize(finaleCaption), normal);
    expect(tester.getRect(find.text('PASSION')).top,
        greaterThan(tester.getRect(find.text('EDIT')).bottom),
        reason: 'EDIT YOUR VIDEOS / WITH PASSION');
  });

  // The owner's call: the spoken word on a pink pill — the caption
  // highlight row's own pink, so it is a look the app offers.
  testWidgets('the spoken word sits on a pink pill', (tester) async {
    await pumpOnboarding(tester);
    await toLastPage(tester);
    final pill = tester.widget<Container>(
      find.byKey(const Key('onboarding_caption_lit')),
    );
    expect((pill.decoration! as BoxDecoration).color, kCaptionHighlightPink);
    expect(kCaptionHighlightColors, contains(kCaptionHighlightPink));
  });
}


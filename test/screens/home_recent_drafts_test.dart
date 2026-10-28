import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/core/theme/app_fonts.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/home_screen.dart';

const _tall = Size(412, 915);
const _short = Size(360, 720);
const _sideways = Size(915, 412);

DraftProject _draft(int i) => DraftProject(
      id: 'd$i',
      sourceVideoPath: '/v.mp4',
      createdAt: DateTime.now(),
      // d0 is the newest.
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

Finder _card(int i) => find.byKey(ValueKey('recent_draft_d$i'));

ScrollPosition _scroll(WidgetTester tester, Key key) => tester
    .state<ScrollableState>(
      find.descendant(of: find.byKey(key), matching: find.byType(Scrollable)).first,
    )
    .position;

Future<void> _settle(WidgetTester tester) async {
  // Home has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Home's recent drafts: up to six, filling the room down to the nav. Where
/// they run under the nav they pass under a blur, never a hard edge, and
/// they scroll up out from under it inside their own box — the rest of Home
/// stays put.
void main() {
  // Home's own face, so text measures as it does on a phone: the test font
  // draws every letter a full em wide, and at 110% text "Compress" no longer
  // fits its card.
  setUpAll(() async {
    final loader = FontLoader(kInterfaceFontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true}));

  Future<void> pumpHome(
    WidgetTester tester,
    Size size, {
    int drafts = 0,
    double pixelRatio = 1,
    FakeViewPadding padding = FakeViewPadding.zero,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.runAsync(() async {
      for (var i = 0; i < drafts; i++) {
        await DraftService.saveDraft(_draft(i));
      }
    });
    initializeAppRouter('/home');
    await tester.pumpWidget(
      const ProviderScope(child: SlimShotApp(enableShareIntents: false)),
    );
    await _settle(tester);
  }

  group('draftRowHeight', () {
    test('one row never gives up height', () {
      expect(draftRowHeight(drafts: 3, room: 100), 140);
    });
    test('two rows with room to spare keep their full height', () {
      expect(draftRowHeight(drafts: 6, room: 400), 140);
    });
    test('two rows give up what they must to sit above the nav', () {
      // A Note 10: 288dp between the title and the nav.
      expect(draftRowHeight(drafts: 6, room: 288), 134);
      expect(draftRowHeight(drafts: 4, room: 288), 134);
    });
    test('never below 120: where that will not fit, full height and scroll', () {
      // Two 120dp rows, the 12dp between them and 8dp above the nav: 260.
      expect(draftRowHeight(drafts: 6, room: 260), 120);
      expect(draftRowHeight(drafts: 6, room: 259), 140);
    });
  });

  testWidgets('Home shows the six latest drafts', (tester) async {
    await pumpHome(tester, _tall, drafts: 7);
    for (var i = 0; i < 6; i++) {
      expect(_card(i), findsOneWidget, reason: 'd$i');
    }
    expect(_card(6), findsNothing);
  });

  testWidgets('on a tall phone all six sit above the nav, and nothing scrolls',
      (tester) async {
    await pumpHome(tester, _tall, drafts: 6);
    final nav = tester.getRect(find.byType(FloatingNavBar));
    expect(tester.getRect(_card(5)).bottom, lessThanOrEqualTo(nav.top));
    expect(_scroll(tester, const ValueKey('recent_drafts')).maxScrollExtent, 0);
    expect(_scroll(tester, const ValueKey('home_page')).maxScrollExtent, 0);
  });

  // The owner's Galaxy Note 10, measured over adb: 1080 x 2280 at 420 dpi,
  // a 90 px status bar, a 126 px three-button bar, text at 110%.
  testWidgets('on a Galaxy Note 10 the six fit above the nav, the cards giving '
      'up a little height, and nothing scrolls', (tester) async {
    await pumpHome(
      tester,
      const Size(1080, 2280),
      drafts: 6,
      pixelRatio: 2.625,
      padding: const FakeViewPadding(top: 90, bottom: 126),
      textScale: 1.1,
    );
    final nav = tester.getRect(find.byType(FloatingNavBar));
    final last = tester.getRect(_card(5));
    expect(last.bottom, lessThanOrEqualTo(nav.top));
    expect(last.height, inInclusiveRange(120, 139));
    expect(_scroll(tester, const ValueKey('recent_drafts')).maxScrollExtent, 0);
    expect(_scroll(tester, const ValueKey('home_page')).maxScrollExtent, 0);
  });

  testWidgets('on a tall phone the cards keep their full height',
      (tester) async {
    await pumpHome(tester, _tall, drafts: 6);
    expect(tester.getRect(_card(5)).height, 140);
  });

  testWidgets('on a shorter phone the second row runs on under the nav, and '
      'the drafts scroll up out from under it while the page stays put',
      (tester) async {
    await pumpHome(tester, _short, drafts: 6);
    final nav = tester.getRect(find.byType(FloatingNavBar));
    final last = tester.getRect(_card(5));
    expect(last.top, lessThan(nav.top));
    expect(last.bottom, greaterThan(nav.top), reason: 'not cut off above the nav');
    expect(last.height, 140, reason: 'laid out whole');

    final header = tester.getRect(find.text('SlimShot AI'));
    await tester.drag(_card(0), const Offset(0, -400));
    await _settle(tester);
    expect(tester.getRect(_card(5)).bottom, lessThanOrEqualTo(nav.top));
    expect(tester.getRect(find.text('SlimShot AI')), header);
    expect(_scroll(tester, const ValueKey('home_page')).maxScrollExtent, 0);
  });

  testWidgets('what passes under the nav is blurred across the full width',
      (tester) async {
    await pumpHome(tester, _short, drafts: 6);
    final nav = tester.getRect(find.byType(FloatingNavBar));
    final blur = find.byKey(const ValueKey('recent_drafts_blur'));
    expect(
      find.descendant(of: blur, matching: find.byType(BackdropFilter)),
      findsOneWidget,
    );
    final band = tester.getRect(blur);
    expect(band.top, lessThanOrEqualTo(nav.top));
    expect(band.bottom, _short.height);
    expect(band.width, _short.width);
  });

  testWidgets('with no drafts the placeholder keeps its size, and nothing blurs',
      (tester) async {
    await pumpHome(tester, _tall);
    final placeholder = find.ancestor(
      of: find.text('Your recent video drafts will appear here'),
      matching: find.byType(SizedBox),
    );
    expect(tester.getSize(placeholder.first).height, 120);
    expect(find.byKey(const ValueKey('recent_drafts_blur')), findsNothing);
  });

  testWidgets('a phone on its side still lays Home out, the page scrolling '
      'where the drafts have no room', (tester) async {
    await pumpHome(tester, _sideways, drafts: 6);
    expect(tester.takeException(), isNull);
    expect(_scroll(tester, const ValueKey('home_page')).maxScrollExtent,
        greaterThan(0));
  });
}

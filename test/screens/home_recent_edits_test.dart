import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_refresh_notifier.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/core/theme/app_colors.dart';
import 'package:slimshotai/core/theme/app_fonts.dart';
import 'package:slimshotai/core/widgets/dashed_frame_painter.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';
import 'package:slimshotai/core/widgets/frosted_glass.dart';
import 'package:slimshotai/main.dart';
import 'package:slimshotai/screens/home_layout.dart';

/// A phone as Home meets it: its screen in dp, the system's bars above and
/// below, the text size its owner chose and its pixel density.
class _Phone {
  const _Phone(
    this.width,
    this.height, {
    this.top = 24,
    this.bottom = 48,
    this.text = 1,
    this.ratio = 1,
  });

  final double width;
  final double height;
  final double top;
  final double bottom;
  final double text;
  final double ratio;

  @override
  String toString() => '${width.toInt()} × ${height.toInt()}dp phone '
      '(bars ${top.toInt()}/${bottom.toInt()}, text ×$text)';
}

/// Every common shape from the shortest 18:9 up, with three-button and
/// gesture navigation, larger text and several densities. Nothing here is
/// one phone: a layout tuned to any one of them would fail another.
const _phonesWithRoomForSix = [
  _Phone(360, 720),
  _Phone(360, 720, bottom: 16),
  _Phone(360, 760, top: 36),
  _Phone(360, 800, top: 36, text: 1.3),
  _Phone(360, 806, top: 36, ratio: 2),
  _Phone(384, 854, text: 1.15),
  _Phone(393, 852, bottom: 16, ratio: 2.75),
  _Phone(411, 869, top: 34, text: 1.1, ratio: 2.625),
  _Phone(412, 915),
  _Phone(480, 1067, ratio: 2.25),
  _Phone(600, 960, ratio: 2),
];

/// A 16:9 phone: too short for both rows above the nav, even at the least.
const _short = _Phone(360, 640);
const _tall = _Phone(412, 915);

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

/// What Home shows in the drafts' place before any edit.
final _emptyCard = find.byKey(const ValueKey('recent_drafts_empty'));

ScrollPosition _scroll(WidgetTester tester, String key) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<void> _settle(WidgetTester tester) async {
  // Home has looping animations, so it never settles by itself.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Home's recent edits: up to six, filling the room down to the nav, and
/// every part of Home sized from the height the phone gives it. Where both
/// rows cannot sit above the nav, the second runs on under it through a
/// blur and scrolls up from under it inside the drafts' own box — the rest
/// of Home stays put.
void main() {
  // Home's own face, so text measures as it does on a phone: the test font
  // draws every letter a full em wide.
  setUpAll(() async {
    final loader = FontLoader(kInterfaceFontFamily);
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      loader.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
    }
    await loader.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true}));

  Future<void> pumpHome(WidgetTester tester, _Phone phone, {int drafts = 0}) async {
    tester.view.physicalSize =
        Size(phone.width * phone.ratio, phone.height * phone.ratio);
    tester.view.devicePixelRatio = phone.ratio;
    final bars = FakeViewPadding(
      top: phone.top * phone.ratio,
      bottom: phone.bottom * phone.ratio,
    );
    tester.view.padding = bars;
    tester.view.viewPadding = bars;
    tester.platformDispatcher.textScaleFactorTestValue = phone.text;
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

  testWidgets('the section is "Recent Edits"', (tester) async {
    await pumpHome(tester, _tall, drafts: 1);
    expect(find.text('Recent Edits'), findsOneWidget);
    expect(find.text('Recent Drafts'), findsNothing);
  });

  testWidgets('Home shows the six latest edits', (tester) async {
    await pumpHome(tester, _tall, drafts: 7);
    for (var i = 0; i < 6; i++) {
      expect(_card(i), findsOneWidget, reason: 'd$i');
    }
    expect(_card(6), findsNothing);
  });

  for (final phone in _phonesWithRoomForSix) {
    testWidgets('on a $phone all six sit above the nav, and nothing scrolls',
        (tester) async {
      await pumpHome(tester, phone, drafts: 6);
      expect(tester.takeException(), isNull);
      final nav = tester.getRect(find.byType(FloatingNavBar));
      for (var i = 0; i < 6; i++) {
        final card = tester.getRect(_card(i));
        expect(card.bottom, lessThanOrEqualTo(nav.top + 1e-3), reason: 'd$i');
        expect(
          card.height,
          inInclusiveRange(kHomeDraftRowHeight.least - 1e-3,
              kHomeDraftRowHeight.full + 1e-3),
          reason: 'd$i',
        );
      }
      expect(_scroll(tester, 'recent_drafts').maxScrollExtent, closeTo(0, 1e-3));
      expect(_scroll(tester, 'home_page').maxScrollExtent, closeTo(0, 1e-3));
      // Where the cards gave up height, the room went to them: the second
      // row ends at the gap above the nav, give or take the rounding.
      final last = tester.getRect(_card(5));
      if (last.height < kHomeDraftRowHeight.full) {
        expect(nav.top - last.bottom, lessThan(kHomeDraftNavGap + 2 + 1e-3));
      }
    });
  }

  testWidgets('on a tall phone everything is at its full size', (tester) async {
    await pumpHome(tester, _tall, drafts: 6);
    expect(tester.getSize(find.byKey(const Key('home_new_video'))).height,
        kHomeHeroHeight.full);
    expect(tester.getSize(find.byKey(const ValueKey('home_compress_video'))).height,
        kHomeToolsHeight.full);
    expect(tester.getRect(_card(5)).height, kHomeDraftRowHeight.full);
  });

  testWidgets('a shorter phone shows the same page smaller: New Video and the '
      'tool cards give up the same share of what they can', (tester) async {
    await pumpHome(tester, const _Phone(360, 720), drafts: 6);
    final hero = tester.getSize(find.byKey(const Key('home_new_video'))).height;
    final tools =
        tester.getSize(find.byKey(const ValueKey('home_compress_video'))).height;
    expect(hero, inExclusiveRange(kHomeHeroHeight.least, kHomeHeroHeight.full));
    expect(tools, inExclusiveRange(kHomeToolsHeight.least, kHomeToolsHeight.full));
    double share(double size, HomeGive give) =>
        (size - give.least) / (give.full - give.least);
    expect(share(hero, kHomeHeroHeight),
        closeTo(share(tools, kHomeToolsHeight), 1e-6));
    expect(tester.getRect(_card(5)).height, lessThan(kHomeDraftRowHeight.full));
  });

  testWidgets('on a 16:9 phone the second row runs on under the nav at the '
      'cards\' least, and the drafts scroll it up while the page stays put',
      (tester) async {
    await pumpHome(tester, _short, drafts: 6);
    final nav = tester.getRect(find.byType(FloatingNavBar));
    expect(tester.getRect(_card(2)).bottom, lessThanOrEqualTo(nav.top),
        reason: 'the first row above the nav');
    final last = tester.getRect(_card(5));
    expect(last.top, lessThan(nav.top));
    expect(last.bottom, greaterThan(nav.top), reason: 'not cut off above the nav');
    expect(last.height, kHomeDraftRowHeight.least, reason: 'laid out whole');

    final header = tester.getRect(find.text('SlimShot AI'));
    await tester.drag(_card(0), const Offset(0, -400));
    await _settle(tester);
    expect(tester.getRect(_card(5)).bottom, lessThanOrEqualTo(nav.top));
    expect(tester.getRect(find.text('SlimShot AI')), header);
    expect(_scroll(tester, 'home_page').maxScrollExtent, closeTo(0, 1e-3));
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

  for (final phone in [_tall, const _Phone(360, 806, top: 36), const _Phone(360, 720)]) {
    testWidgets('on a $phone, before any edit, the card standing in takes '
        'the six\'s place, keeping more room above the nav than they do, and '
        'nothing blurs', (tester) async {
      await pumpHome(tester, phone);
      final nav = tester.getRect(find.byType(FloatingNavBar));
      final empty = tester.getRect(_emptyCard);
      expect(find.byKey(const ValueKey('recent_drafts_blur')), findsNothing);
      expect(empty.bottom,
          lessThanOrEqualTo(nav.top - kHomeEmptyCardNavGap + 1e-3));

      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          await DraftService.saveDraft(_draft(i));
        }
      });
      DraftRefreshNotifier.instance.refresh();
      await _settle(tester);
      expect(_emptyCard, findsNothing);
      final first = tester.getRect(_card(0));
      final last = tester.getRect(_card(5));
      expect(first.top, closeTo(empty.top, 1e-3));
      expect(first.left, closeTo(empty.left, 1e-3));
      expect(last.right, closeTo(empty.right, 1e-3));
      // Down to the second row's foot, or its own room above the nav,
      // whichever comes first.
      expect(empty.bottom,
          closeTo(math.min(last.bottom, nav.top - kHomeEmptyCardNavGap), 1e-3));
    });
  }

  testWidgets('the card standing in for no edits is a dashed frame, the home '
      'screen widget\'s, not glass', (tester) async {
    await pumpHome(tester, _tall);
    final frames = tester
        .widgetList<CustomPaint>(
          find.descendant(of: _emptyCard, matching: find.byType(CustomPaint)),
        )
        .map((p) => p.foregroundPainter)
        .whereType<DashedFramePainter>();
    expect(frames, hasLength(1));
    expect(frames.single.colour, AppColors.lilac.withValues(alpha: 0.45));
    expect(find.descendant(of: _emptyCard, matching: find.byType(FrostedGlass)),
        findsNothing);
    expect(
      find.descendant(
        of: _emptyCard,
        matching: find.text('Your recent edits will appear here'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('on a 16:9 phone the card standing in stops above the nav',
      (tester) async {
    await pumpHome(tester, _short);
    final nav = tester.getRect(find.byType(FloatingNavBar));
    final empty = tester.getRect(_emptyCard);
    expect(empty.bottom,
        lessThanOrEqualTo(nav.top - kHomeEmptyCardNavGap + 1e-3));
    expect(empty.height, greaterThanOrEqualTo(kHomeEmptyCardLeast - 1e-3));
  });

  for (final (what, phone) in [
    ('a phone on its side', const _Phone(915, 412, top: 24, bottom: 0)),
    ('a 320 × 568dp phone', const _Phone(320, 568, top: 20)),
    ('a 16:9 phone at twice the text size', const _Phone(360, 640, text: 2)),
  ]) {
    testWidgets('$what still lays Home out, the page scrolling where the '
        'drafts have no room', (tester) async {
      await pumpHome(tester, phone, drafts: 6);
      expect(tester.takeException(), isNull);
      // The first row can always be brought up clear of the nav.
      await tester.drag(find.text('SlimShot AI'), const Offset(0, -2000));
      await _settle(tester);
      final nav = tester.getRect(find.byType(FloatingNavBar));
      expect(tester.getRect(_card(0)).bottom, lessThanOrEqualTo(nav.top + 1e-3));
    });
  }
}

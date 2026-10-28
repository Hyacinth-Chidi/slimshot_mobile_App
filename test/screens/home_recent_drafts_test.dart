import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/core/services/draft_service.dart';
import 'package:slimshotai/core/widgets/floating_nav_bar.dart';
import 'package:slimshotai/main.dart';

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
  setUp(() => SharedPreferences.setMockInitialValues({'hasSeenOnboarding': true}));

  Future<void> pumpHome(WidgetTester tester, Size size, {int drafts = 0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

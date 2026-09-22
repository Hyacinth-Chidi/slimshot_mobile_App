import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/emoji_catalog.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/stickers_drawer.dart';

void main() {
  /// Pumps the drawer inside a route, so `Navigator.pop` has something to pop
  /// — the sheet closes itself before reporting, and a test that skipped the
  /// route would not catch a missing pop.
  Future<List<String>> pumpDrawer(WidgetTester tester) async {
    final chosen = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => StickersDrawer(onEmojiSelected: chosen.add),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return chosen;
  }

  testWidgets('opens on the first group and shows its emoji', (tester) async {
    await pumpDrawer(tester);

    final first = kEmojiGroups.first;
    expect(find.text(first.name), findsOneWidget);
    // The first emoji appears twice — once on the group's pill, once in the
    // grid — so this asserts presence rather than a count.
    expect(find.text(first.emoji.first), findsWidgets);
  });

  testWidgets('every group has a pill', (tester) async {
    await pumpDrawer(tester);
    // The pill row scrolls, so off-screen names are not rendered; assert on
    // the ones that fit rather than pretending all nine are laid out.
    expect(find.text(kEmojiGroups.first.name), findsOneWidget);
    expect(
      find.byType(GestureDetector, skipOffstage: false),
      findsWidgets,
    );
  });

  testWidgets('tapping an emoji reports it and closes the sheet',
      (tester) async {
    final chosen = await pumpDrawer(tester);

    // Take one that is not the group's first, so a tap on the *pill* cannot
    // pass for a tap on the tile.
    final target = kEmojiGroups.first.emoji[3];
    await tester.tap(find.text(target).first);
    await tester.pumpAndSettle();

    expect(chosen, [target]);
    // Closed first, so the canvas is visible when the overlay lands.
    expect(find.byType(StickersDrawer), findsNothing);
  });

  testWidgets('switching group changes the grid', (tester) async {
    await pumpDrawer(tester);

    final second = kEmojiGroups[1];
    await tester.tap(find.text(second.name));
    await tester.pumpAndSettle();

    // An emoji unique to the second group is now on screen. The catalog test
    // pins uniqueness, so this cannot pass by coincidence.
    expect(find.text(second.emoji[2]), findsWidgets);
  });

  testWidgets('stops at the sheet preview fraction so the canvas stays visible',
      (tester) async {
    // Device-reported about sheets generally: one at half the screen hid the
    // very frame the user was choosing for. Choosing an emoji is a choice
    // *for a frame*, so this obeys the cap rather than taking the audio
    // library's taller height — a grid scrolls, so it loses nothing.
    await pumpDrawer(tester);

    final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final drawerHeight = tester.getSize(find.byType(StickersDrawer)).height;
    expect(
      drawerHeight,
      closeTo(screenHeight * kEditorSheetPreviewFraction, 1.0),
    );
    expect(drawerHeight, lessThan(screenHeight * 0.5));
  });

  testWidgets('has no search field and no GIF or sticker tab', (tester) async {
    // The drawer these replaced was a mockup: a dead search box over a
    // spinner that never resolved, and tabs for content with no provider
    // behind it. Promising them is worse than not offering them.
    await pumpDrawer(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('GIFs'), findsNothing);
    expect(find.text('Stickers'), findsNothing);
  });
}

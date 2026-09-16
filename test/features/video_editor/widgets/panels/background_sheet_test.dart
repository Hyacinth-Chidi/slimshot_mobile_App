import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/background_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/crop_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/editor_sheet.dart';

/// The background picker is a sheet of square colour tiles.
///
/// It was an in-place panel with a "Solid Color" switch over a row of small
/// circles. The switch is gone — black is simply the first tile, so there is
/// nothing left for it to switch — and the circles are tiles the size of the
/// crop panel's, so the two pickers read as one family. A sheet rather than a
/// panel because a background is a choice *about* the picture with no canvas
/// or timeline gesture attached, which is the rule the curve, filters and
/// effects already follow.
void main() {
  VideoEditorNotifier notifierWith({
    EditorBackgroundType type = EditorBackgroundType.black,
    Color colour = Colors.black,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(backgroundType: type, backgroundColor: colour);
  }

  Future<void> pump(
    WidgetTester tester,
    VideoEditorNotifier notifier, {
    Future<String?> Function()? pickImage,
    Size screen = const Size(400, 800),
  }) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: screen),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: BackgroundSheet(pickImage: pickImage),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Finder checkIn(Finder parent) =>
      find.descendant(of: parent, matching: find.byIcon(LucideIcons.check));

  Finder tile(Color colour) => find.byKey(BackgroundSheet.tileKey(colour));

  testWidgets('one square tile per preset, no switch', (tester) async {
    await pump(tester, notifierWith());

    for (final colour in kBackgroundPresets) {
      expect(tile(colour), findsOneWidget, reason: '$colour');
      final size = tester.getSize(tile(colour));
      expect(size.width, BackgroundSheet.kTileSize);
      expect(size.height, BackgroundSheet.kTileSize);
    }
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('a tile is the size of a crop tile', (tester) async {
    // One tile language across the editor's pickers: the crop panel's ratio
    // tiles set the width, and a colour has no label so it is square.
    expect(BackgroundSheet.kTileSize, 64);
    expect(CropPanel.kRowHeight, greaterThanOrEqualTo(BackgroundSheet.kTileSize));
  });

  testWidgets('black is highlighted for a project on the default background',
      (tester) async {
    // The old `black` type is what every draft before this carried; it shows
    // as the black tile being current, not as nothing selected.
    await pump(tester, notifierWith());
    expect(
      find.descendant(
        of: tile(Colors.black),
        matching: find.byIcon(LucideIcons.check),
      ),
      findsOneWidget,
    );
    // And only black: the header's ✓ is a check too, so count within tiles.
    final marked = kBackgroundPresets.where((colour) => find
        .descendant(of: tile(colour), matching: find.byIcon(LucideIcons.check))
        .evaluate()
        .isNotEmpty);
    expect(marked, [Colors.black]);
  });

  testWidgets('tapping a tile applies it live, as one undo step',
      (tester) async {
    final n = notifierWith();
    await pump(tester, n);

    await tester.tap(tile(const Color(0xFF3498DB)));
    await tester.pump();

    expect(n.state.backgroundType, EditorBackgroundType.color);
    expect(n.state.backgroundColor, const Color(0xFF3498DB));
    expect(
      find.descendant(
        of: tile(const Color(0xFF3498DB)),
        matching: find.byIcon(LucideIcons.check),
      ),
      findsOneWidget,
    );

    // Type and colour moved together, so one undo brings both back.
    n.undo();
    expect(n.state.backgroundType, EditorBackgroundType.black);
    expect(n.state.backgroundColor, Colors.black);
  });

  group('the photo tile', () {
    testWidgets('is the first cell of the grid, colours beside it',
        (tester) async {
      // Device-reported: a photo tile alone on its own row above the colours
      // read as a separate section. It is one tile among the tiles — first,
      // with the colours flowing on from it in the same row.
      await pump(tester, notifierWith());
      final photo = tester.getRect(find.byKey(BackgroundSheet.photoTileKey));
      final firstColour = tester.getRect(tile(kBackgroundPresets.first));
      expect(photo.top, firstColour.top);
      expect(photo.right, lessThan(firstColour.left));

      // The same footprint as a colour tile, so the rows stay level — which
      // is why its label sits inside the tile rather than hanging under it.
      expect(photo.width, BackgroundSheet.kTileSize);
      expect(photo.height, BackgroundSheet.kTileSize);
      expect(
        find.descendant(
          of: find.byKey(BackgroundSheet.photoTileKey),
          matching: find.text('Photo'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('with none chosen, a tap asks for a photo', (tester) async {
      var asked = 0;
      final n = notifierWith();
      await pump(tester, n, pickImage: () async {
        asked++;
        return null; // the user backed out of the picker
      });

      await tester.tap(find.byKey(BackgroundSheet.photoTileKey));
      await tester.pump();

      expect(asked, 1);
      expect(n.state.backgroundType, EditorBackgroundType.black);
    });

    testWidgets('with a photo in use, it is current and colours are not',
        (tester) async {
      final n = notifierWith()
        ..state = const VideoEditorState(
          backgroundType: EditorBackgroundType.image,
          backgroundImagePath: '/nowhere/bg.jpg',
        );
      await pump(tester, n);

      expect(checkIn(find.byKey(BackgroundSheet.photoTileKey)), findsOneWidget);
      for (final colour in kBackgroundPresets) {
        expect(checkIn(tile(colour)), findsNothing, reason: '$colour');
      }
    });

    testWidgets('a colour after a photo keeps the photo; tapping it again '
        'uses it without another pick', (tester) async {
      var asked = 0;
      final n = notifierWith()
        ..state = const VideoEditorState(
          backgroundType: EditorBackgroundType.image,
          backgroundImagePath: '/nowhere/bg.jpg',
        );
      await pump(tester, n, pickImage: () async {
        asked++;
        return null;
      });

      await tester.tap(tile(Colors.white));
      await tester.pump();
      expect(n.state.backgroundType, EditorBackgroundType.color);
      expect(n.state.backgroundImagePath, '/nowhere/bg.jpg');

      await tester.tap(find.byKey(BackgroundSheet.photoTileKey));
      await tester.pump();
      expect(n.state.backgroundType, EditorBackgroundType.image);
      expect(asked, 0);
    });
  });

  group('the blur tile', () {
    testWidgets('sits second, after the photo, labelled', (tester) async {
      await pump(tester, notifierWith());
      final blur = tester.getRect(find.byKey(BackgroundSheet.blurTileKey));
      final photo = tester.getRect(find.byKey(BackgroundSheet.photoTileKey));
      final firstColour = tester.getRect(tile(kBackgroundPresets.first));
      expect(blur.top, photo.top);
      expect(blur.left, greaterThan(photo.right));
      expect(blur.right, lessThan(firstColour.left));
      expect(
        find.descendant(
          of: find.byKey(BackgroundSheet.blurTileKey),
          matching: find.text('Blur'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tapping it blurs the clip behind itself, one undo step',
        (tester) async {
      final n = notifierWith();
      await pump(tester, n);
      await tester.tap(find.byKey(BackgroundSheet.blurTileKey));
      await tester.pump();

      expect(n.state.backgroundType, EditorBackgroundType.blur);
      expect(checkIn(find.byKey(BackgroundSheet.blurTileKey)), findsOneWidget);
      for (final colour in kBackgroundPresets) {
        expect(checkIn(tile(colour)), findsNothing, reason: '$colour');
      }

      n.undo();
      expect(n.state.backgroundType, EditorBackgroundType.black);
    });
  });

  testWidgets('the sheet stops at 45% of the screen and scrolls', (tester) async {
    // The point of a sheet over a clear canvas is watching the picture change;
    // a sheet that climbs to half the screen hides the picture it is about.
    // A real 400×600 view — not just a reported size — so the grid wraps at
    // phone width and outgrows the cap; on a wide, tall surface the whole
    // grid fits under 45% and the sheet simply takes its content.
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester, notifierWith(), screen: const Size(400, 600));
    final sheet = tester.getSize(find.byType(BackgroundSheet));
    expect(sheet.height, closeTo(600 * kEditorSheetPreviewFraction, 0.5));
    expect(
      find.descendant(
        of: find.byType(BackgroundSheet),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the tick dismisses the sheet', (tester) async {
    final n = notifierWith();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const BackgroundSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('background_done')));
    await tester.pumpAndSettle();
    expect(find.byType(BackgroundSheet), findsNothing);
  });
}

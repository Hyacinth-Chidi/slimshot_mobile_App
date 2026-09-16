import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/background_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/crop_panel.dart';

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

  Future<void> pump(WidgetTester tester, VideoEditorNotifier notifier) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(home: Scaffold(body: BackgroundSheet())),
      ),
    );
  }

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

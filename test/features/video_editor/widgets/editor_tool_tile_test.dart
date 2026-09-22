import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/theme/lucide_icons.dart';
import 'package:slimshotai/features/video_editor/widgets/editor_tool_tile.dart';

/// A toolbar tool shows its whole name.
///
/// Device-reported: "Background" came out as "Backgro…". Every tool sat in a
/// fixed 56px box with an ellipsis, so any name longer than about eight
/// letters at 10pt was cut — and a tool the user cannot read is a tool they
/// will not find. The tile now takes the width its label needs, with 56 as a
/// floor so short names keep the rhythm of the row.
void main() {
  Future<Size> pumpTile(WidgetTester tester, String label) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [EditorToolTile(icon: LucideIcons.image, label: label)],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return tester.getSize(find.byType(EditorToolTile));
  }

  testWidgets('a long name is shown whole, never cut to an ellipsis',
      (tester) async {
    final tile = await pumpTile(tester, 'Background');
    final text = tester.widget<Text>(find.text('Background'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
    expect(text.maxLines, 1);
    // The label fits inside the tile with the tile's own padding to spare.
    expect(tester.getSize(find.text('Background')).width,
        lessThanOrEqualTo(tile.width - 2 * EditorToolTile.kHorizontalPadding));
  });

  testWidgets('a short name keeps the row\'s rhythm at the minimum width',
      (tester) async {
    final tile = await pumpTile(tester, 'Zoom');
    expect(tile.width, EditorToolTile.kMinWidth + EditorToolTile.kGap);
  });

  testWidgets('a long name widens the tile rather than the tile cutting it',
      (tester) async {
    final short = await pumpTile(tester, 'Zoom');
    final long = await pumpTile(tester, 'Background');
    expect(long.width, greaterThan(short.width));
  });
}

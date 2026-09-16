import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/crop_panel.dart';

/// A tool panel takes the height its content needs, not a fixed 160.
///
/// Device-reported: the crop panel opened as a 160px box holding one row of
/// ratio tiles, and the empty rest read as a gap between the panel and the
/// timeline. The panel now sizes to its content, which means every panel body
/// has to lay out under an **unbounded** height — a horizontal list or an
/// `Expanded` inside one throws the moment the fixed box is gone. This pumps
/// a body the way the panel now does and pins that it neither throws nor
/// sprawls. (The background picker, which needed the same care, has since
/// become a sheet; see `background_sheet_test.dart`.)
void main() {
  Future<Size> pumpUnbounded(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 360,
                child: KeyedSubtree(key: const Key('body'), child: body),
              ),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    return tester.getSize(find.byKey(const Key('body')));
  }

  testWidgets('the crop panel sizes itself to one row of tiles, at full height',
      (tester) async {
    // Device-reported after the panel began sizing to its body: the ratio
    // tiles came out squat, because the row had been pinned at 64 where the
    // old fixed panel stretched them to 80. The row is the tile's height, and
    // the tile is tall enough to carry its glyph and label with air around
    // them — the same 80 the tiles always had, now owned by the panel body
    // instead of falling out of the box around it.
    final size = await pumpUnbounded(
      tester,
      CropPanel(
        selectedRatio: EditorCropRatio.ratio9x16,
        onRatioSelected: (_) {},
      ),
    );
    expect(size.height, CropPanel.kRowHeight);
    expect(CropPanel.kRowHeight, 80);

    // Every tile stands the full row, so a row of them reads as one band.
    for (final tile in find.byType(GestureDetector).evaluate()) {
      expect(tester.getSize(find.byWidget(tile.widget)).height,
          CropPanel.kRowHeight);
    }
  });
}

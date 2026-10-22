import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/fonts/font_registry.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_overlay_painter.dart';
import 'package:slimshotai/features/video_editor/widgets/text_overlay/text_preview_tile.dart';

/// A font downloaded while a tile is on screen: the tile measures and paints
/// again in it, rather than keeping the System face it fell back to.
void main() {
  // A real font file, so the real engine registers it; each test registers
  // under a name of its own, since a registration lasts the whole session.
  const fontFile = 'assets/fonts/Poppins-Regular.ttf';

  TextOverlayModel words(String family) => TextOverlayModel(
        id: 't',
        text: 'Title',
        fontFamily: family,
        referenceCanvasSize: kTextPreviewCanvas,
        endTime: const Duration(seconds: 1),
      );

  final painterFinder =
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is TextOverlayPainter);

  testWidgets('a preview tile redraws when a font registers', (tester) async {
    const family = 'Preview Tile Late Font';
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 110,
          height: 100,
          child: TextPreviewTile(
            overlay: words(family),
            spanSeconds: 1,
            label: 'x',
            isSelected: false,
            onTap: () {},
          ),
        ),
      ),
    ));
    final before = tester.widget<CustomPaint>(painterFinder).painter;
    final registered = await tester.runAsync(() => FontRegistry.instance.registerFile(family, fontFile));
    expect(registered, isTrue);
    await tester.pump();
    expect(identical(tester.widget<CustomPaint>(painterFinder).painter, before), isFalse);
  });

  test('a text painter repaints when a font registers', () async {
    final painter = TextOverlayPainter(
      overlay: words('Roboto'),
      layout: TextOverlayLayout.measure(words('Roboto'), kTextPreviewCanvas),
      canvasSize: kTextPreviewCanvas,
      positionSeconds: 0,
    );
    var asked = 0;
    void listener() => asked++;
    painter.addListener(listener);
    addTearDown(() => painter.removeListener(listener));
    expect(await FontRegistry.instance.registerFile('Painter Late Font', fontFile), isTrue);
    expect(asked, 1);
  });
}

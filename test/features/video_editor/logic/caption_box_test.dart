import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/text_overlay_geometry.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';

import '../../../support/test_fonts.dart';

/// A boxed caption's box hugs its words.
///
/// A caption carries its set's wrap width — one the user never chose — so a
/// background spanning it drew a band most of the canvas wide behind a single
/// "Hi". The box the user grabs keeps that width; only the background hugs.
void main() {
  const canvas = Size(400, 700);

  TextOverlayModel boxed(String words, {String? setId, String align = 'center'}) =>
      TextOverlayModel(
        id: 't',
        text: words,
        fontFamily: kTestFontFamily,
        referenceCanvasSize: canvas,
        boxWidth: 340,
        backgroundColor: Colors.black,
        backgroundPadding: 12,
        textAlign: align,
        captionSetId: setId,
      );

  test("a caption's background hugs its words, centred", () {
    final layout = TextOverlayLayout.measure(boxed('Hi', setId: 's'), canvas);
    final bg = layout.backgroundRect;
    final words = layout.textOrigin.dx + layout.textWidth / 2;
    // Far narrower than the box, wide enough for the word and its padding.
    expect(bg.width, lessThan(layout.boxSize.width / 2));
    expect(bg.width, greaterThan(layout.backgroundPaddingH * 2));
    expect(bg.center.dx, closeTo(words, 0.5));
    // The box itself — what the user grabs — keeps the set's width.
    expect(
      layout.boxSize.width,
      TextOverlayLayout.measure(boxed('Hi'), canvas).boxSize.width,
    );
  });

  test('it hugs the longest line of a caption that wraps', () {
    final layout = TextOverlayLayout.measure(
      boxed('one two three four five six seven eight nine ten', setId: 's'),
      canvas,
    );
    final bg = layout.backgroundRect;
    expect(bg.width, lessThanOrEqualTo(layout.boxSize.width - layout.outerPadding * 2 + 0.01));
    expect(layout.textHeight, greaterThan(kTextOverlayFontSize * 1.5));
  });

  test('a left-aligned caption hugs from the left', () {
    final layout = TextOverlayLayout.measure(boxed('Hi', setId: 's', align: 'left'), canvas);
    expect(layout.backgroundRect.left, closeTo(layout.outerPadding, 0.01));
  });

  test('plain text with a width of its own keeps a background as wide as it', () {
    // The user widened that box on purpose; a banner is what they made.
    final layout = TextOverlayLayout.measure(boxed('Hi'), canvas);
    expect(layout.backgroundRect.width, layout.boxSize.width - layout.outerPadding * 2);
  });
}

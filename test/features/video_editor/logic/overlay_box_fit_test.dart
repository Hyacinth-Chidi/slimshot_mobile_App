import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/overlay_box_fit.dart';

/// The selection frame has to be the picture's shape, not the box's.
///
/// Device-reported: once GL drew the overlay, the dotted frame stopped fitting
/// it. The widget that used to size itself from the decoded image had become a
/// fixed square, while the renderer contain-fits the picture *inside* that
/// square — so a 16:9 overlay sat in a frame with empty bands above and below.
void main() {
  test('a wide picture fills the width and is shorter than the box', () {
    final s = fittedOverlayBox(contentAspect: 16 / 9, box: 200);
    expect(s.width, 200);
    expect(s.height, closeTo(112.5, 1e-9));
  });

  test('a tall picture fills the height and is narrower than the box', () {
    final s = fittedOverlayBox(contentAspect: 9 / 16, box: 240);
    expect(s.height, 240);
    expect(s.width, closeTo(135, 1e-9));
  });

  test('a square picture is the box', () {
    expect(fittedOverlayBox(contentAspect: 1, box: 200), const Size(200, 200));
  });

  test('an unknown or junk shape falls back to the whole box', () {
    // Before the picture has been measured the frame is the box: a slightly
    // loose frame for a moment beats no gesture target at all.
    for (final a in [null, 0.0, -2.0, double.nan, double.infinity]) {
      expect(fittedOverlayBox(contentAspect: a, box: 200), const Size(200, 200),
          reason: '$a');
    }
  });
}

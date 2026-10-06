import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/core/widgets/colour_field_backdrop.dart';

void main() {
  for (final size in const [Size(360, 780), Size(1024, 1366)]) {
    testWidgets('fills a ${size.width.toInt()}x${size.height.toInt()} screen '
        'and never takes a touch', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(child: GestureDetector(onTap: () => taps++)),
              const Positioned.fill(child: ColourFieldBackdrop()),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(ColourFieldBackdrop)), size);
      await tester.tapAt(size.center(Offset.zero));
      expect(taps, 1, reason: 'the backdrop must let touches through');
    });
  }

  test('stays dark: a little light, not a colour field', () {
    // Device-reported: the full purple field read as less premium than the
    // old near-black. Light is used sparingly — no blob strong enough to
    // turn the screen purple, and white only as a whisper.
    const glows = ColourFieldBackdrop.homeGlows;
    expect(glows, isNotEmpty);
    for (final g in glows) {
      expect(g.opacity, lessThanOrEqualTo(0.30), reason: '${g.color}');
    }
    final whiteLight = glows
        .where((g) => g.color.r > 0.9 && g.color.g > 0.9 && g.color.b > 0.9)
        .fold<double>(0, (sum, g) => sum + g.opacity);
    expect(whiteLight, lessThanOrEqualTo(0.06));
  });
}

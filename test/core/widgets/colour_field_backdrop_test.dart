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
}
